# PMI Journey v4 — Architectural Review (p81)

**Author:** Claude Code (autonomous review per PM mandate p81)
**Date:** 2026-04-28
**Spec source:** `/home/vitormrodovalho/.claude/projects/-home-vitormrodovalho-projects-ai-pm-research-hub/specs/p81-pmi-vep-journey/` (14 files, 4 anexed by PM at end of p80)
**Scope:** validate spec architecturally + identify ajustes BEFORE PM approves implementation

---

## EXECUTION LOG (2026-04-28, post PM approval)

PM aprovou os 3 blockers + 8 recomendações em 2026-04-28. Execução autônoma das phases 0-3:

### Phase 0 — pre-flight findings + COURSE CORRECTION

**🚨 B2 corrigido durante execução**: a recomendação original era "DELETE older duplicate rows + add UNIQUE on `vep_application_id`". Phase 0 examinou as 5 supostas duplicatas e descobriu:

- São rows **legítimas** do dual-track `triaged_to_leader` selection pattern (Marcos Klemz, Adalberto Neris, Rodolfo Santana, Ana Cavalcante, Hayala Curto)
- Cada par tem `linked_application_id` cross-ref + `promotion_path='triaged_to_leader'` + DIFFERENT `vep_opportunity_id` (64966 leader / 64967 researcher) + DIFFERENT scores
- `(vep_application_id, vep_opportunity_id)` JÁ É unique em todos os 81 rows com ambos populated

**Original plan would have destroyed dual-track data**. Corrigido para PARTIAL COMPOUND UNIQUE:

```sql
CREATE UNIQUE INDEX uq_selection_applications_vep_app_opp
  ON public.selection_applications(vep_application_id, vep_opportunity_id)
  WHERE vep_application_id IS NOT NULL AND vep_opportunity_id IS NOT NULL;
```

**Zero DELETEs executados. Todos os 82 rows preservados.**

### Phase 2 — migration applied

Migration consolidated `20260516200000_phase_b_pmi_journey_v4.sql` aplicada via Supabase MCP `apply_migration`:
- 4 tables (selection_evaluation_ai_suggestions, pmi_video_screenings, onboarding_tokens, cron_run_log)
- 12 RLS policies (`rpc_only_deny_all` + `_v4_org_scope` RESTRICTIVE per nova tabela)
- 8 indexes (incluindo B2 partial compound UNIQUE)
- 2 trigger functions + 3 triggers (R6 rename `trg_supersede_ai_suggestions_on_consent_revoke`)
- 2 views (`v_cron_last_success`, `v_ai_human_concordance`)
- 10 functions:
  - 1 helper (`set_updated_at_v4`)
  - 6 spec RPCs (get_ai_suggestion, consume_onboarding_token w/ R2+R5, register_video_screening, log_cron_run_start/complete)
  - 1 wrapper (`campaign_send_one_off` para B3)
  - 1 extended fn (`submit_evaluation` arity 4→5 com R7 `p_ai_suggestion_id`)
  - 1 token-auth wrapper (`update_pmi_onboarding_step` para R8)
- B1: ALTER `selection_applications.role_applied` CHECK → adiciona `'manager'`

Timestamp ajustado de auto-gerado `20260429025919` para slot `20260516200000` em série (rpc-v4-auth contract scan ordering).

### Phase 3 — verification results

| Check | Result |
|---|---|
| All 4 tables created | ✅ |
| All 10 functions created | ✅ |
| Both views created | ✅ |
| All 3 triggers active | ✅ |
| 5 indexes (incl. B2 UNIQUE) | ✅ |
| `submit_evaluation` arity = 5 (R7) | ✅ |
| `check_schema_invariants()` | ✅ 11/11 — 0 violations |
| Smoke: invalid token → reject | ✅ raised `invalid_authorization_specification` |
| Smoke: insert without consent → reject | ✅ raised `check_violation` |
| B1: 'manager' in role_applied CHECK | ✅ confirmed |
| B2: UNIQUE allows dual-track | ✅ all 81 valid rows preserved |
| `npm test` (DB-aware) | ✅ 1418 tests / 1383 pass / 0 fail / 35 skip (baseline preserved) |
| `supabase migration list` local↔remote sync | ✅ both at 20260516200000 |

### Status — what's done vs PM-pending

**DONE (DB layer):**
- Migration aplicada + sincronizada
- Review doc atualizado (este arquivo)
- Files prontos para commit (2 untracked: review + migration)

**PM-PENDING (deploy/operacional):**
- Worker code creation em `cloudflare-workers/pmi-vep-sync/` no repo (atualmente só no memory dir spec source) — adapt files com B3 wrapper call (`p_template_slug`) + B2 compound key on upsert
- PMI VEP OAuth grant type confirmation + secrets via `wrangler secret put`
- Seed `campaign_templates` row para `slug = 'pmi_welcome_with_token'` com placeholders + body
- Wrangler staging deploy + smoke test 1 candidato
- Production deploy
- ADR-0066 documentando ship + memory entry handoff_p82

**FOLLOW-UP (post-S0, separadas):**
- R1 retention/anonymize cron extension para 4 novas tabelas
- Worker source `db.ts` defensive: trocar `.eq('vep_application_id').maybeSingle()` para `.eq('vep_application_id').eq('vep_opportunity_id').maybeSingle()` para casar com B2 corrigido
- Token TTL config (30→7 dias) é env var no wrangler.toml — PM ajusta no deploy

---

## EXECUTION LOG ROUND 2 (2026-04-28, post worker creation)

PM aprovou continuação autônoma + KV refresh_token plano B + max execução possível desta sessão.

### Migration adicional 20260516210000_phase_b_pmi_journey_v4_consent_rpcs.sql

Spec gap fechado: token tem scope `'consent_giving'` mas spec não tinha RPCs para consumi-lo. Sem isso, candidato no portal não conseguiria dar/revogar consent.

Adicionadas 2 RPCs token-auth:
- `give_consent_via_token(p_token, p_consent_type='ai_analysis')` — sets `consent_ai_analysis_at`, clears `consent_ai_analysis_revoked_at`
- `revoke_consent_via_token(p_token, p_consent_type='ai_analysis')` — sets `consent_ai_analysis_revoked_at`; trigger `trg_supersede_ai_suggestions_on_consent_revoke` automatic supersede non-consumed suggestions

Ambas anon-grantable (token É a credencial, mesma pattern de `consume_onboarding_token` + `register_video_screening` + `update_pmi_onboarding_step`).

### Worker adaptações (Plano B refresh_token KV)

- `src/types.ts`: adicionado `PMI_OAUTH_KV: KVNamespace` ao `Env` + nova interface `PmiOAuthTokens`
- `src/pmi-vep-client.ts`: refatorado completamente — removido `client_credentials`, agora lê tokens do KV `pmi_oauth:tokens`. Refresh automático quando `expires_at < now() + 30s`. Handle 401 retry com 1 refresh. Preserva refresh_token rotation se PMI rotaciona.
- `wrangler.toml`: adicionado `[[kv_namespaces]]` binding (id placeholder — PM preenche após `wrangler kv namespace create`).
- `README.md`: nova seção "PMI OAuth KV Setup" com 4 passos detalhados para PM seedar refresh_token via login interativo.

Worker typecheck: ✅ clean (`tsc --noEmit` zero errors).

### Seeds aplicados via execute_sql

`campaign_templates` rows criadas (idempotent ON CONFLICT slug):
- `pmi_welcome_with_token` (category=`onboarding`) — multilíngue pt-BR/en-US/es-LATAM, placeholders `{{first_name}}`, `{{role_label}}`, `{{chapter}}`, `{{onboarding_url}}`, `{{expires_in_days}}`
- `cron_failure_alert` (category=`operational`) — placeholders `{{worker}}`, `{{failure_count}}`

PM pode customizar body_html depois — ON CONFLICT preserva schema, content é override-able.

### Sanity-check final

- `supabase migration list`: local + remote ambos at 20260516210000 ✅
- `essay_mapping`: opps 64966 leader (4 mapped) ✅, 64967 researcher (4 mapped) ✅, 66470 manager MISSING (esperado per spec README — PM popula quando vier substituto)
- Templates seeded e visíveis em campaign_templates ✅

### Handoff PM (próximas etapas — só 2 grupos)

**Grupo A — One-time browser/terminal setup (Cloudflare CLI)**:
1. `wrangler login` (se ainda não)
2. `cd cloudflare-workers/pmi-vep-sync && npm install` (já feito local — repetir se em outra máquina)
3. `wrangler kv namespace create pmi_oauth_kv` → copiar `id` retornado para wrangler.toml
4. Login interativo PMI VEP → capturar `access_token` + `refresh_token` + `expires_in` do response
5. `wrangler kv key put --binding=PMI_OAUTH_KV pmi_oauth:tokens '<json>'` (formato no README)
6. `wrangler secret put` para 8 secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PMI_VEP_BASE_URL, PMI_VEP_OAUTH_TOKEN_URL, PMI_VEP_OAUTH_CLIENT_ID, PMI_VEP_OAUTH_CLIENT_SECRET, GP_NOTIFICATION_EMAIL, ONBOARDING_BASE_URL
7. `wrangler deploy --env staging` → smoke (cron trigger via dashboard + tail) → `wrangler deploy --env production`

**Grupo B — Frontend portal `/pmi-onboarding/[token]` (próxima sessão Claude Code)**:
- Defer para sessão dedicada — UI não-trivial (consent UI + onboarding step checklist + video upload widget)
- Worker funciona sem portal — candidatos receberão emails mas link irá pra 404 até portal existir
- Recomendação: portal MVP em sessão dedicada (~2h), antes do staging deploy entrar em prod com candidatos reais

---

---

## TL;DR

**Verdict:** spec é arquiteturalmente sólida. Padrões V4 (auth_org, RLS rpc_only_deny_all + _v4_org_scope, SECDEF RPCs, organization_id NOT NULL DEFAULT) corretos. ALL referenced columns exist. NEW tables/views/triggers não colidem com objetos existentes.

**3 blockers obrigatórios fix-before-apply**, **8 recomendações**, **6 PM decisions abertas**.

| Severity | Count | Action |
|---|---|---|
| 🔴 Blocker | 3 | Fix migration ou pre-step antes de aplicar |
| 🟡 Recommended | 8 | Aplicar para qualidade — pode ser pós S0 |
| 🟢 Optional | 3 | Cosmético / future-proofing |

---

## Pre-validation matrix (5/5 premises)

| # | Premise | Status |
|---|---|---|
| 1 | `auth_org()` exists | ✅ Confirmed (returns FIXED uuid `2b4f58ab-…`, single-tenant constant — service-role-safe, no NULL risk) |
| 2 | `selection_applications.organization_id` exists | ✅ uuid NOT NULL DEFAULT `auth_org()` |
| 3 | `selection_applications.consent_ai_analysis_at` exists | ✅ timestamptz nullable + `consent_ai_analysis_revoked_at` exists too |
| 4 | `rpc_only_deny_all` is canonical | ✅ Permissive `USING false`. Spec correctly pairs com `_v4_org_scope` (RESTRICTIVE em outros usos confirmados — defesa em profundidade) |
| 5 | `set_updated_at_v4` does NOT exist | ✅ No collision. `set_updated_at` (sem suffix) também não existe em `public` — spec é o primeiro a introduzir |

---

## Schema crosscheck — extra verifications

### selection_applications (target table)

**ALL columns spec uses exist** (verified via `information_schema.columns`):
- ✅ `cycle_id`, `vep_application_id` (text, NULLABLE), `vep_opportunity_id`, `pmi_id`
- ✅ `applicant_name`, `email`, `phone`, `linkedin_url`, `resume_url`
- ✅ `chapter`, `membership_status`, `certifications`
- ✅ `role_applied`, `motivation_letter`, `proposed_theme`, `areas_of_interest`
- ✅ `availability_declared`, `leadership_experience`, `academic_background`
- ✅ `chapter_affiliation`, `non_pmi_experience`, `reason_for_applying`
- ✅ `application_date`, `status`, `imported_at`, `updated_at`
- ✅ `consent_ai_analysis_at`, `consent_ai_analysis_revoked_at`
- ✅ `organization_id`

**CHECK constraints surfaced:**
- `status` allows: submitted, screening, objective_eval, objective_cutoff, interview_pending, interview_scheduled, interview_done, interview_noshow, final_eval, approved, rejected, waitlist, converted, withdrawn, cancelled. Mapper produz: submitted | approved | rejected | cancelled — all valid. ✅
- `role_applied` allows: **researcher | leader | both** — mapper passa-through `opp.role_default` que pode ser `'manager'`. **🔴 BLOCKER B1** — see below.

### Other tables touched

| Table | Status |
|---|---|
| `vep_opportunities` | ✅ existe com `opportunity_id, title, chapter_posted, role_default, essay_mapping (jsonb), vep_url, is_active`. Atualmente: 3 ativas (1 manager + 1 researcher + 1 leader). |
| `selection_cycles` | ✅ tem `cycle_code, title, interview_questions (jsonb), phase, status, open_date, objective_criteria, interview_criteria, leader_extra_criteria, min_evaluators` |
| `selection_committee` | ✅ tem `cycle_id, member_id, role` (default `'evaluator'`). Spec's `get_ai_suggestion` JOIN compatível |
| `selection_evaluations` | ✅ tem `id, application_id, evaluator_id, evaluation_type, scores (jsonb), weighted_subtotal, criterion_notes, submitted_at`. UNIQUE `(application_id, evaluator_id, evaluation_type)` confirmado. `evaluation_type` CHECK = `('objective','interview','leader_extra')` — **EXATO match** com spec's nova `selection_evaluation_ai_suggestions.evaluation_type` CHECK ✅ |
| `onboarding_progress` | ✅ existe (application_id + member_id + step_key) — **NÃO COLIDE** com new `onboarding_tokens` (purposes diferentes: progress tracking vs auth ledger) |

### NEW objects created by spec — collision check

| Object | Status |
|---|---|
| `selection_evaluation_ai_suggestions` (table) | ✅ doesn't exist |
| `pmi_video_screenings` (table) | ✅ doesn't exist |
| `onboarding_tokens` (table) | ✅ doesn't exist |
| `cron_run_log` (table) | ✅ doesn't exist (only `home_schedule` existe; unrelated dashboard widget) |
| `set_updated_at_v4` (fn) | ✅ doesn't exist |
| `check_ai_consent_at_suggestion_insert` (fn) | ✅ doesn't exist |
| `handle_consent_revocation` (fn) | ✅ doesn't exist (nome próximo: `_trg_purge_ai_analysis_on_consent_revocation` — different trigger, different action; **complementar não colide**) |
| `get_ai_suggestion`, `consume_onboarding_token`, `register_video_screening` | ✅ all new |
| `log_cron_run_start`, `log_cron_run_complete` | ✅ all new |
| `v_cron_last_success`, `v_ai_human_concordance` (views) | ✅ all new |

### Existing trigger `_trg_purge_ai_analysis_on_consent_revocation`

`BEFORE UPDATE OF consent_ai_analysis_revoked_at ON selection_applications` — purga `ai_analysis` jsonb da própria row.

Spec adiciona `on_consent_revoke` (`AFTER UPDATE ON selection_applications`) — superseda suggestions na nova tabela.

✅ Não colidem (BEFORE vs AFTER, ações diferentes, tabelas diferentes). **🟡 R6 abaixo**: rename para consistência de prefixo `trg_*`.

---

## Crosscheck contra batches 15-20 (p80 V3→V4 conversions)

Verifiquei os bodies das 7 RPCs convertidas em batches 15-20 que tocam `selection_evaluations`, `selection_interviews`, `selection_applications` e `onboarding_progress`:

### `submit_evaluation` (batch 19)
- Lê `selection_cycles.objective_criteria/interview_criteria/leader_extra_criteria` (jsonb) — **mesma fonte** que spec usa para AI generation inputs ✅
- Calcula `weighted_subtotal` via PERT; insere em `selection_evaluations` com `submitted_at = now()`
- **Integration point com AI suggestions:** quando o evaluator confirma scores que vieram pre-filled da suggestion, o frontend deve atualizar `selection_evaluation_ai_suggestions.used_in_evaluation_id = <new eval id>` + `consumed_at = now()`. **Spec não cria essa RPC** — assume frontend faz UPDATE direto OU adiciona param a `submit_evaluation`. **🟡 R7** — vide ajustes.

### `get_evaluation_form` (batch 20)
- Retorna `application + criteria + draft + committee_role`. **Não retorna AI suggestion** — frontend vai precisar chamar `get_ai_suggestion(p_application_id, p_evaluation_type)` separadamente.
- **Decisão de UX**: chamar separadamente está OK (suggestion é optional / consent-gated). Não bloqueia. ✅

### `get_evaluation_results` (batch 20)
- Retorna `evaluations + consolidated + calibration_alerts`. **Não inclui AI vs human concordance.**
- View `v_ai_human_concordance` (criada pela spec) é separada — pode ser usada por dashboard analytics futuro. ✅ Não conflita.

### `submit_interview_scores` (batch 19)
- Spec mapper menciona "transcrição feed `ai-interview-drafter`" no README mas o **worker em si não consome interview transcripts**.
- `pmi_video_screenings.transcription` armazena texto que (futuramente) workers `gemini-transcribe` + `ai-interview-drafter` vão consumir para gerar `selection_evaluation_ai_suggestions` de tipo `interview`.
- **Integration ponto:** quando `submit_interview_scores` for chamada DEPOIS de uma suggestion existir, mesmo padrão de R7 aplica.
- ✅ Spec não modifica `submit_interview_scores` — esquema funcionalmente compatível.

### `update_onboarding_step` (batch 18)
- Já valida via `application_id` (param) + `step_key` em `onboarding_progress`.
- **Spec não chama essa RPC** — em vez disso `consume_onboarding_token` retorna application context. Frontend portal `/pmi-onboarding/{token}` chamará `update_onboarding_step` ainda autenticado via auth JWT? Ou via token?
- ⚠️ **CONFLITO POTENCIAL DE AUTH**: o portal de PMI candidato ainda **não tem auth Supabase JWT** (token-only). `update_onboarding_step` requires `auth.uid() → members lookup` — vai falhar para PMI candidato pre-member.
- 🟡 **R8** — solução: adicionar wrapper `update_pmi_onboarding_step(p_token text, p_step_key text, ...)` que valida token e chama lógica equivalente sem exigir auth.uid().

### `get_onboarding_dashboard` (batch 20)
- Filtra por `members.is_active AND current_cycle_active`. PMI candidatos pré-member (com onboarding_progress por `application_id` apenas, `member_id IS NULL`) **NÃO aparecem** no dashboard.
- 🟡 **R9** — extension necessária para visibilidade do GP sobre candidatos em onboarding pré-membership.

### `schedule_interview` (batch 18)
- Cria row em `selection_interviews` + atualiza `selection_applications.status = 'interview_scheduled'` + notifica via `create_notification`.
- **Sem interação com novos objetos** spec. ✅ Compatível.

### `finalize_decisions` (batch 17)
- Não tocada pelo spec. ✅

---

## 🔴 BLOCKERS (must fix antes de aplicar)

### B1. `role_applied` CHECK rejeita 'manager'

**Problema**: DB `CHECK (role_applied IN ('researcher','leader','both'))`. Spec mapper:
```typescript
role_applied: opp.role_default,  // pode ser 'manager'
```
`vep_opportunities` HOJE tem 1 ativa com `role_default = 'manager'`. `welcome.ts` tem `ROLE_LABEL.manager = 'Gerente de Projeto'` confirmando intenção. Worker insert vai falhar `check_violation` em qualquer manager opportunity processada.

**Fix (adicionar à migration)**:
```sql
ALTER TABLE public.selection_applications
  DROP CONSTRAINT selection_applications_role_applied_check;
ALTER TABLE public.selection_applications
  ADD CONSTRAINT selection_applications_role_applied_check
  CHECK (role_applied = ANY (ARRAY['researcher','leader','both','manager']));
```

**Coordination needed**: rankings/scoring code que assume `role_applied IN ('researcher','leader')` (e.g., `rank_researcher`, `rank_leader` columns) precisa decidir o que fazer com `manager` — provavelmente tratar como `leader` para ranking. Ver `selection_dual_ranking` spec se aplicável.

### B2. `vep_application_id` tem 5 grupos de duplicatas existentes (10 rows)

**Problema**: Spec `upsertSelectionApplication` faz:
```typescript
.eq('vep_application_id', payload.vep_application_id).maybeSingle()
```

`.maybeSingle()` ERRA quando há >1 row matching. **DB hoje** tem 5 grupos duplicados (vep_application_ids: 269580, 269353, 269462, 270846, 272290; cada um com 2 rows).

Worker quebra na primeira execução que tocar qualquer um desses 5 IDs.

**Fix sequencial**:

1. **PM dedup analysis**: examinar cada par para decidir canônico (provavelmente keep latest `imported_at` ou `updated_at`). Query auxiliar:
   ```sql
   SELECT id, vep_application_id, applicant_name, email, status, imported_at, updated_at, cycle_id
   FROM selection_applications
   WHERE vep_application_id IN ('269580','269353','269462','270846','272290')
   ORDER BY vep_application_id, imported_at DESC;
   ```
2. DELETE older duplicates (or merge data into newer)
3. **THEN** add UNIQUE INDEX:
   ```sql
   CREATE UNIQUE INDEX uq_selection_applications_vep_application_id
     ON public.selection_applications(vep_application_id)
     WHERE vep_application_id IS NOT NULL;
   ```

**Defensive worker code (caso PM defira dedup)**: trocar `.maybeSingle()` por:
```typescript
.order('updated_at', { ascending: false }).limit(1).maybeSingle()
```
Mitiga mas não previne race em runs concorrentes (diário é seguro mas worst-case).

### B3. `campaign_send_one_off` RPC não existe

**Problema**: `welcome.ts` chama `db.rpc('campaign_send_one_off' as any, ...)`. RPC inexistente.

**RPCs existentes (campanhas):**
| Nome | Args | Purpose |
|---|---|---|
| `admin_send_campaign` | `p_template_id uuid, p_audience_filter jsonb, p_scheduled_at timestamptz, p_external_contacts jsonb` | broadcast a member audience or external list |
| `admin_preview_campaign` | `p_template_id uuid, p_preview_member_id uuid` | preview render |
| `admin_get_campaign_stats` | `p_send_id uuid` | analytics |
| `get_campaign_analytics` | `p_send_id uuid` | analytics |

**`campaign_templates`** tem coluna `slug` (NOT NULL, single per template) — spec usa `template_key` no welcome.ts (=`'pmi_welcome_with_token'`). **Naming convention drift**.

**Fix (adicionar à migration — wrapper RPC)**:
```sql
CREATE OR REPLACE FUNCTION public.campaign_send_one_off(
  p_template_slug text,
  p_to_email text,
  p_variables jsonb DEFAULT '{}'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_template_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_template_id FROM campaign_templates WHERE slug = p_template_slug;
  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'Template not found: %', p_template_slug
      USING ERRCODE = 'no_data_found';
  END IF;

  RETURN public.admin_send_campaign(
    p_template_id := v_template_id,
    p_audience_filter := '{}'::jsonb,
    p_scheduled_at := NULL,
    p_external_contacts := jsonb_build_array(jsonb_build_object(
      'email', p_to_email,
      'variables', p_variables,
      'metadata', p_metadata
    ))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.campaign_send_one_off(text, text, jsonb, jsonb) TO service_role;
```

**Update welcome.ts**:
```typescript
db.rpc('campaign_send_one_off', {
  p_template_slug: 'pmi_welcome_with_token',  // matches campaign_templates.slug
  p_to_email: opts.email,
  p_variables: variables,
  p_metadata: { source: 'pmi-vep-sync', application_id: opts.application_id }
})
```

**OBS — verify admin_send_campaign signature contract**: spec assumes ele honra `external_contacts` corretamente (vs members audience). Pre-deploy: confirmar com `admin_preview_campaign` test antes de habilitar worker.

---

## 🟡 RECOMMENDED (alta valor — aplicar quase tudo antes de prod)

### R1. Retention/anonymize coverage para novas tabelas

LGPD cron family existente (`anonymize_inactive_members 5y`, `purge_expired_logs`, `_trg_purge_ai_analysis_on_consent_revocation`) **não cobre** novas tabelas. Spec deixa como gap.

**Adicionar (pode ser migration separada pós-S0)**:
- `cron_run_log` purge >90d (operational log retention)
- `onboarding_tokens` cleanup post-`expires_at + 30d` grace
- `pmi_video_screenings` retention align com 5y member anonymize (transcription contém PII proxies — vozes; embora storage_provider 'google_drive' tenha lifecycle Drive-side, transcription text fica no DB)
- `selection_evaluation_ai_suggestions` purge quando `selection_applications` for anonymize (cascade via FK existente já faz isso ✅; mas `consent_snapshot_at` deve ser preserved até purge final para audit)

Estender `admin_run_retention_cleanup()` para orquestrar todos.

### R2. `consume_onboarding_token` PII leak surface

Retorna `email, phone, pmi_id, linkedin_url, interview_questions`. Token é a credencial; quem captura o token vê tudo isso.

**Mitigations**:
- Reduzir TTL de 30 dias → 7 dias para `pmi_application` source (PM decisão)
- Filtrar `interview_questions` da resposta (candidato vê DURANTE entrevista no portal, não com 30d antecedência)
- Hashar token armazenado em `campaign_sends.metadata` (welcome.ts) — usar `metadata.onboarding_token_hash = encode(sha256(token), 'hex')` para troubleshooting sem expor credencial

### R3. `set_updated_at_v4` aplicado em apenas 1 tabela

Trigger só usado em `pmi_video_screenings` (tem `updated_at` column). Outras 3 novas tabelas não têm `updated_at`:
- `selection_evaluation_ai_suggestions` — usa `generated_at` + `consumed_at` ✅
- `onboarding_tokens` — usa `issued_at` + `last_accessed_at` ✅
- `cron_run_log` — usa `started_at` + `completed_at` ✅

✅ Acceptable. Não aplicar trigger em tabelas que não usam `updated_at`. Spec correto.

### R4. `selection_evaluation_ai_suggestions.used_in_evaluation_id` não tem UNIQUE

Múltiplas suggestion rows poderiam reivindicar mesma evaluation. Schema permite, mas é ambíguo (qual suggestion foi de fato usada?).

**Opção restritiva**:
```sql
CREATE UNIQUE INDEX uq_ai_suggestions_used_in_eval
  ON selection_evaluation_ai_suggestions(used_in_evaluation_id)
  WHERE used_in_evaluation_id IS NOT NULL;
```

Defer to PM — pode quebrar workflow de "trocar suggestion após escolher" (UI permitiria revogar associação primeiro).

### R5. `consume_onboarding_token` não retorna `onboarding_progress`

Portal `/pmi-onboarding/{token}` precisa mostrar steps do candidato. Hoje payload inclui `application + cycle + token_metadata` mas não os onboarding_progress rows.

**Add à RPC**:
```sql
'onboarding_progress', (
  SELECT jsonb_agg(jsonb_build_object(
    'step_key', op.step_key,
    'status', op.status,
    'completed_at', op.completed_at,
    'evidence_url', op.evidence_url
  ))
  FROM onboarding_progress op
  WHERE op.application_id = v_app.id
)
```

### R6. Trigger naming convention drift

Spec usa `on_consent_revoke`. Convention existente: `trg_*` prefix (e.g., `trg_purge_ai_analysis_on_consent_revocation`).

**Rename**: `trg_supersede_ai_suggestions_on_consent_revoke` (descriptive, prefixed).

### R7. AI suggestion → human evaluation lineage update

Quando `submit_evaluation` é chamada com scores que vieram de uma AI suggestion pre-filled, lineage não é atualizado automaticamente.

**Opções**:

(a) Frontend-side update (worker ou UI): após submit_evaluation success, chama outro RPC `mark_ai_suggestion_consumed(p_suggestion_id, p_evaluation_id)`. Simples mas frágil.

(b) Estender `submit_evaluation` com `p_ai_suggestion_id uuid DEFAULT NULL`. Quando passado, atualiza `selection_evaluation_ai_suggestions SET used_in_evaluation_id = <new_eval_id>, consumed_at = now()`. Atomic.

(c) Trigger-based: `AFTER INSERT/UPDATE ON selection_evaluations` busca latest non-superseded suggestion para `(application_id, evaluator_id)`-time-window e atualiza. Magic, propenso a heuristic bugs.

**Recommendation: (b) — atomic + explícito + opcional via DEFAULT NULL** preserva backward-compat com chamadas atuais.

Decisão: aplicar como follow-up migration depois do worker estar live. Não bloqueia S0.

### R8. PMI portal auth gap — `update_onboarding_step` requires `auth.uid()`

PMI candidatos pré-member chegam ao portal via token (anon). Mas `update_onboarding_step` (e qualquer RPC que faz `WHERE auth_id = auth.uid()`) vai falhar para anon.

**Solução**: criar família de RPCs token-authenticated:
- `update_pmi_onboarding_step(p_token text, p_step_key text, p_status text, p_evidence_url text)` — valida token + scope `profile_completion`, depois delega para a mesma lógica.
- `register_video_screening` JÁ é token-authenticated (✅ spec correto).

Add à migration ou follow-up.

---

## 🟢 OPTIONAL (cosmético/future-proof)

### O1. `set_updated_at_v4` rename

Sem `_v4` suffix nada colide. Domain Model V4 era foi concluída (per CLAUDE.md "concluído 2026-04-13"). Pode usar `set_updated_at` sem ambiguidade.

Counter: nome com `_v4` sinaliza padrão moderno. Marginal — defer to PM preference.

### O2. `cron_run_log.organization_id` — single-tenant assumption

`auth_org()` retorna constante hoje. Quando multi-tenant chegar, cron logs ficariam grouped por org assumida pelo worker. Workers PMI rodam sem contexto de user → worker já passa `ORG_ID` na env, mas não para o RPC `log_cron_run_start`.

Ajustar `log_cron_run_start` para aceitar `p_organization_id uuid DEFAULT NULL` e overriding default. Future-proof. Defer.

### O3. `cron_run_log` race condition em `log_cron_run_start`

`UPDATE … WHERE status = 'running' AND started_at < now() - interval '30 minutes'` (kill zombies) + `INSERT new row` não é atômico. Dois cron triggers concorrentes podem ambos UPDATE+INSERT. Para cron diário 1x/day, risco zero. Future scale: SELECT FOR UPDATE ou unique partial index `(worker_name) WHERE status='running'`. Defer.

---

## 📋 PM DECISIONS NEEDED

1. **Aprovar B1**: extender `selection_applications.role_applied` CHECK para incluir `'manager'`. (Y/N)
2. **Aprovar B2 dedup strategy**: 5 grupos de duplicatas em `selection_applications`. Qual approach?
   - (a) Manual review row-by-row antes de DELETE
   - (b) Heurística "manter mais recente por `updated_at`, DELETE older"
   - (c) Bloquear worker até dedup feito + adicionar UNIQUE
3. **Aprovar B3 wrapper `campaign_send_one_off`** (slug-based) OU especificar alternativa
4. **Aprovar R2 token TTL** — reduzir 30→7 dias para PMI?
5. **Aprovar R2 `interview_questions` filter** — excluir do consume_onboarding_token payload?
6. **Confirmar R7 estratégia** (a/b/c) para AI suggestion lineage update — pode ficar para post-S0.

Plus os PM-deferred do spec README:
- PMI VEP OAuth grant type (`client_credentials`?)
- Chapter parsing mapping (PMI-PE/SP/RJ outras parceiras?)
- Seed `campaign_templates.slug = 'pmi_welcome_with_token'` body

---

## 🛠 SUGGESTED EXECUTION ORDER

### Phase 0 — pre-flight checks (autonomous, sessão limpa OK)

```sql
-- 0a. Examinar duplicatas para PM dedup decision
SELECT id, vep_application_id, applicant_name, email, status, cycle_id, imported_at, updated_at
FROM selection_applications
WHERE vep_application_id IN ('269580','269353','269462','270846','272290')
ORDER BY vep_application_id, imported_at DESC NULLS LAST;

-- 0b. Verificar nenhuma other ref usa removed rows (cycle id breakdown)
SELECT vep_application_id, cycle_id, COUNT(*) AS n
FROM selection_applications
WHERE vep_application_id IN ('269580','269353','269462','270846','272290')
GROUP BY vep_application_id, cycle_id;

-- 0c. Verificar referrers (selection_evaluations / onboarding_progress)
SELECT 'evals' AS src, application_id, COUNT(*) FROM selection_evaluations
WHERE application_id IN (SELECT id FROM selection_applications
  WHERE vep_application_id IN ('269580','269353','269462','270846','272290'))
GROUP BY application_id
UNION ALL
SELECT 'onb', application_id, COUNT(*) FROM onboarding_progress
WHERE application_id IN (SELECT id FROM selection_applications
  WHERE vep_application_id IN ('269580','269353','269462','270846','272290'))
GROUP BY application_id;
```

### Phase 1 — PM dedup decision + manual cleanup

PM examina output de 0a/0c, escolhe estratégia (likely "keep oldest if no referrers, else keep referenced row"). Output: lista de ids para DELETE.

### Phase 2 — Modified migration apply

Criar migration `20260429_pmi_journey_v4.sql` no repo (timestamp ajustado para next-after-latest:`20260516200000_pmi_journey_v4.sql`):

Inclui o spec original PLUS:

```sql
-- B1 fix
ALTER TABLE public.selection_applications
  DROP CONSTRAINT selection_applications_role_applied_check;
ALTER TABLE public.selection_applications
  ADD CONSTRAINT selection_applications_role_applied_check
  CHECK (role_applied = ANY (ARRAY['researcher','leader','both','manager']));

-- B2 fix (after dedup phase 1 completes)
CREATE UNIQUE INDEX uq_selection_applications_vep_application_id
  ON public.selection_applications(vep_application_id)
  WHERE vep_application_id IS NOT NULL;

-- B3 fix
CREATE OR REPLACE FUNCTION public.campaign_send_one_off(
  p_template_slug text, p_to_email text,
  p_variables jsonb DEFAULT '{}'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$ … (per B3 above) $$;

GRANT EXECUTE ON FUNCTION public.campaign_send_one_off(text, text, jsonb, jsonb) TO service_role;

-- R5 fix (consume_onboarding_token + onboarding_progress payload)
-- R6 fix (rename trigger on_consent_revoke → trg_supersede_ai_suggestions_on_consent_revoke)

NOTIFY pgrst, 'reload schema';
```

Apply via `mcp__claude_ai_Supabase__apply_migration` (per `.claude/rules/database.md` — DDL não vai por execute_sql).

### Phase 3 — Worker code modifications

Pre-deploy code edits (in spec source tree):
- `welcome.ts`: trocar args para `p_template_slug` (não `template_key`)
- `db.ts`: adicionar `.order('updated_at', {ascending:false}).limit(1).maybeSingle()` defensivo em `upsertSelectionApplication`
- `mapper.ts`: optional, validar `role_applied` antes de retornar

### Phase 4 — Pre-deploy PM tasks (browser)

- PMI VEP OAuth secrets via Vault/wrangler secret
- Seed `campaign_templates` row para `pmi_welcome_with_token` (slug, subject, body com placeholders, target_audience, category, variables JSONB)
- Confirm `vep_opportunities.essay_mapping` populated nas 3 ativas (manager pendente conforme README)

### Phase 5 — Worker deploy + smoke test

- `cd cloudflare-workers/pmi-vep-sync && npm install && npm run typecheck`
- `wrangler deploy --env staging`
- Smoke: trigger cron via dashboard, `wrangler tail`, verify `cron_run_log` row + at least 1 selection_application upserted + 1 token issued + 1 campaign_send dispatched
- Iterate até clean
- `wrangler deploy --env production`

### Phase 6 — Documentation

- ADR-0066 PMI Journey v4 Phase 1 (similar a Drive Phase 3/4 ADR-0064/0065)
- Atualizar CLAUDE.md p81 marker → p82 com PMI Journey LIVE
- Memory entry session_p81 com decisões e ajustes aplicados
- Backlog: R1 retention cron, R7 lineage atomic update, R8 token-auth onboarding step RPC

---

## Tests/contracts impacted

- `rpc-v4-auth` contract test passa (novas SECDEF RPCs check engagement-derived authority via `selection_committee` JOIN — não usa `is_superadmin` literal). ✅
- `rpc-migration-coverage.test.mjs` — nova migration capturada via apply_migration. ✅
- Possíveis novos contract tests sugeridos:
  - `pmi-journey-v4-rls`: confirma que anon não consegue SELECT direct nas 4 novas tabelas (somente via RPCs)
  - `pmi-journey-v4-consent-gate`: insert em `selection_evaluation_ai_suggestions` falha sem consent ativo
  - `pmi-journey-v4-token-lifecycle`: consume_onboarding_token rejeita expirado + mark consumed corretamente

---

## Closing assessment

**Spec qualidade**: B+ (sólida arquitetura, pequenos gaps recuperáveis em S0 follow-ups).

**Confiança em apply após ajustes B1+B2+B3**: alta. Padrões V4 corretos, schema premises validadas, no-collision com objetos existentes.

**Risco principal pós-deploy**: PMI VEP OAuth grant type unknown (TODO_CLAUDE_CODE no client). Spec depende de informação que PM precisa fornecer — não testável pre-deploy sem credenciais.

**Tempo estimado para ship com ajustes** (estimativa Claude Code autonomous):
- Phase 0-1 (dedup + PM call): ~30min PM browser
- Phase 2 (modified migration): ~45min Claude Code
- Phase 3 (worker mods): ~30min Claude Code
- Phase 4 (PM browser tasks): ~1h PM
- Phase 5 (deploy + smoke): ~1.5h Claude Code + PM watching
- Phase 6 (docs): ~45min Claude Code

**Total**: ~2.5h Claude Code execution + ~1.5h PM browser/decisions, sequencial.

**Recommendation**: PM aprova ajustes B1/B2/B3 para Phase 2 → autorizo execução autônoma das Phases 2/3/5/6 com check-ins ao fim de cada fase. R-items tiered conforme PM prefere.
