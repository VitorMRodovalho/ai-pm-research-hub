# SPEC: Marcos server-side (celebração de marcos persistida) — #766 item 2/4

**Status:** Draft (design + plano de disparo; nenhum código aplicado ainda)
**Priority:** Green / non-blocking (resíduo Wave 5 de #740, rastreado em #766)
**Created:** 2026-06-17
**Author:** Claude (PM/Architect) + Vitor (GP)
**Decisão de escopo (PM, 2026-06-17, AskUserQuestion):** **Framework de marcos (visão J5 ampla)** — não o substituto mínimo 1:1 do localStorage. Multi-PR, começando por este SPEC + plano de disparo.

---

## 1. Contexto & problema

A celebração de "onboarding concluído" (J5, Wave 4) existe hoje **client-side**:

- `src/components/onboarding/OnboardingChecklist.tsx:108-180` mostra o card "🎉 Onboarding concluído!" quando `get_my_onboarding().all_complete === true`.
- O estado "já vi" mora em `localStorage['nia_onboarding_celebrated']` (`OnboardingChecklist.tsx:108,123-124,167`).

**Limitações do localStorage:**
1. **Por dispositivo/navegador** — quem limpa cache ou troca de device revê a celebração.
2. **Servidor não sabe** que o membro foi recebido — nenhum registro auditável, nenhum gancho para e-mail/digest, nenhuma métrica.
3. **Não generaliza** — só cobre 1 marco (onboarding-completo). O J5 do discovery (`PRE_ONBOARDING_JOURNEY_DISCOVERY_2026-06-16.md`, linha 170) pede celebrar **vários** marcos: termo assinado, promoção, 1ª presença, 1ª entrega, perfil 100%.

**Meta:** mover o registro de marcos e o "já celebrei" para o servidor, com um modelo genérico que sirva a múltiplos marcos.

---

## 2. Inventário de fontes server-side (grounded — `execute_sql` 2026-06-17)

Cada marco precisa de um ponto de disparo real no schema. Estado verificado ao vivo:

| Marco | Fonte de verdade no schema | Verificado? | Gancho de disparo proposto |
|-------|----------------------------|-------------|----------------------------|
| `onboarding_complete` | `get_my_onboarding().all_complete` (todos os `onboarding_steps.is_required` em `completed`/`skipped`) | ✅ existe | `complete_onboarding_step` quando resulta em all_complete (ou trigger em `onboarding_progress`) |
| `term_signed` | `certificates` `type='volunteer_agreement' AND status='issued'` (41 certs issued ao vivo) | ✅ existe | trigger `AFTER INSERT/UPDATE ON certificates` — espelha o padrão de `_trg_complete_volunteer_term_on_cert` (mig …018) |
| `first_attendance` | `attendance.present=true` (categoria `attendance` tem 1036 linhas de pontos ao vivo) | ✅ existe | trigger `AFTER INSERT/UPDATE ON attendance WHEN present=true`; UNIQUE garante "primeira" |
| `first_deliverable` | `tribe_deliverables.completed_at` + `assigned_member_id` | ✅ existe | trigger `AFTER UPDATE ON tribe_deliverables` quando `completed_at` é setado |
| `promotion` | `promote_to_leader_track` RPC existe; **não há tabela `role_transitions` dedicada** (confirmado: 0 relations) | ⚠️ parcial | gancho dentro do RPC `promote_to_leader_track` + mudança de `members.operational_role` |
| `profile_complete` (perfil completo) | `members.profile_completed_at` (timestamptz, 23/102 populados), setado pela RPC `update_my_profile` | ✅ existe | trigger `AFTER UPDATE OF profile_completed_at ON members WHEN OLD IS NULL AND NEW IS NOT NULL` |

> ⚠️ **Correção de grounding (investigado 2026-06-17 a pedido do PM):** o marco `profile_complete` É viável (fonte server-side real = `profile_completed_at`), MAS a alegação do discovery "perfil 100% → **+50pts já existe** [pdf]" é **falsa** — não há `gamification_rule` nem `gamification_points` de perfil (as 31 regras vivas não incluem perfil; as linhas de 50pts são todas `cert_pmi_senior`). O que existe é um **badge cosmético client-side** (`gamification.astro:679/1026`, acende com foto+pmi_id+linkedin+phone+credly), que NÃO concede pontos. O marco celebra a conclusão do perfil; **não** prometer/exibir +50pts.

**Infra reutilizável existente:** `notifications` (feed persistido, `is_read`/`read_at`) e `get_my_notifications`; `gamification_points`/`gamification_rules`. O framework de marcos **não** vira notification (decisão na §6) — celebração-única tem semântica distinta de feed.

---

## 3. Modelo de dados proposto

Tabela única (em vez do split `member_milestones` + `member_milestone_acks` esboçado na pergunta de escopo — uma linha por `(member, marco)` com timestamp de ack é mais simples e dá semântica "celebrado uma vez"):

```sql
CREATE TABLE public.member_milestones (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id       uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  milestone_key   text NOT NULL,            -- ver CHECK abaixo
  occurred_at     timestamptz NOT NULL DEFAULT now(),
  source_type     text,                     -- 'certificate' | 'attendance' | 'tribe_deliverable' | 'onboarding' | 'promotion'
  source_id       uuid,                     -- referência informacional SEM FK (fontes heterogêneas; padrão admin_audit_log.target_id) — COMMENT ON COLUMN obrigatório
  metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,
  acknowledged_at timestamptz,              -- substitui o localStorage: NULL = celebração pendente
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT member_milestones_key_chk CHECK (milestone_key IN
    ('onboarding_complete','term_signed','first_attendance','first_deliverable','promotion','profile_complete')),
  UNIQUE (member_id, milestone_key)         -- primeira ocorrência apenas; celebrado 1×
);
```

- **RLS:** membro lê e reconhece (ack) apenas os próprios (`member_id` via `members.auth_id = auth.uid()`). Inserção só via RPCs `SECURITY DEFINER` / triggers (membro nunca insere direto). PII: nenhuma; tabela é por-membro do próprio dado. FK `ON DELETE CASCADE` cobre o apagamento LGPD Art. 18.
- **`organization_id` removido do v1** (projeto single-org/PMI-GO hoje — YAGNI; readicionar com FK + COMMENT quando multi-tenant expandir). Evita coluna "flutuante" sem FK/policy (ADR-0012 P2).
- **`milestone_key`:** validado por `CHECK` enumerado **no schema** (write-time, sem custo de query periódica), não em `check_schema_invariants()`.
- **`UNIQUE(member_id, milestone_key)`:** garante idempotência dos triggers (re-INSERT vira no-op via `ON CONFLICT DO NOTHING`).
- **Marcos `first_*` são lifetime-único por design:** segunda presença / segunda entrega **nunca** re-celebram — comportamento intencional do `ON CONFLICT DO NOTHING`, não bug do trigger. (Documentar para o revisor do PR 3.)
- **Taxonomia:** tabela enquadra-se em **ADR-0013 Categoria B (Domain Lifecycle Events)** — shape semântico próprio; NÃO consolida em `admin_audit_log` nem em `notifications`.

---

## 4. RPCs

| RPC | Assinatura | Papel |
|-----|-----------|-------|
| `get_my_milestones()` | `() → jsonb` | retorna `{ pending: [...marcos com acknowledged_at IS NULL], history: [...] }` para o membro atual. Canônico para a celebração FE. |
| `acknowledge_milestone(p_milestone_key text)` | `(text) → jsonb` | seta `acknowledged_at = now()` no marco do membro atual. Substitui `localStorage.setItem`. Idempotente. |
| `record_milestone(...)` | interno (SECURITY DEFINER) | helper compartilhado pelos triggers/RPCs de disparo: `INSERT ... ON CONFLICT (member_id, milestone_key) DO NOTHING`. |

`get_my_onboarding` mantém `all_complete` (não quebrar consumidores). A celebração FE migra para `get_my_milestones`.

---

## 5. Frontend

- **`OnboardingChecklist.tsx`:** remover `CELEBRATION_SEEN_KEY` / `localStorage`; o gate `dismissed` passa a ler `get_my_milestones().pending` (marco `onboarding_complete`); o dismiss chama `acknowledge_milestone('onboarding_complete')`. Preserva o comportamento "mostra 1×", agora cross-device.
- **Superfície de celebração multi-marco:** card/toast genérico, dirigido por `get_my_milestones().pending`, capaz de celebrar qualquer marco pendente (não só onboarding). Cópia trilíngue no idioma do componente (padrão `CELEBRATE`/`HBLOCK` já no arquivo — i18n inline, não `t()`, ver sedimento Wave 4). Tom "Disney", **zero números** (grounding).
- A UX exata (modal vs card no topo vs toast empilhável) é decisão do slice com `ux-leader`.

---

## 6. Decisões de design (registrar; não re-litigar sem motivo)

1. **Tabela dedicada, não `notifications`.** Celebração é "marco único reconhecido", não item de feed. Reusar `notifications` acoplaria semânticas e contaminaria `is_read`. (Opção C da pergunta de escopo — rejeitada.)
2. **Uma linha por `(member, marco)` com `acknowledged_at`**, não duas tabelas. Mais simples para a semântica "celebrado 1×".
3. **Backfill é silencioso (`acknowledged_at = now()`).** Os 41 membros com cert issued / membros já `all_complete` **não** devem ser bombardeados com celebrações retroativas no primeiro deploy. Backfill marca como já-reconhecido; só marcos **novos** (pós-deploy) celebram. ⚠️ Crítico — confirmar com PM na §8.
   - **Ordem obrigatória na migration (race-safe):** aplicar o **backfill ANTES** de `CREATE TRIGGER`. Senão há janela (banco compartilhado, writes concorrentes) em que o trigger insere uma row sem `acknowledged_at` entre o CREATE TRIGGER e o backfill, e o membro existente celebra indevidamente. Verificar a ordem no padrão de `_trg_complete_volunteer_term_on_cert` (mig …018). Regra vale para **todos** os PRs que instalam trigger + backfill.
4. **`profile_complete` é viável** (fonte confirmada: `members.profile_completed_at` via `update_my_profile`). Entra como marco normal — **mas a celebração não menciona "+50pts"** (esse award não existe; ver correção de grounding §2).
5. **Promoção recorrente NÃO é suportada na v1.** `UNIQUE(member_id,'promotion')` bloqueia uma 2ª celebração (promovido→despromovido→repromovido). Se o requisito surgir, exige nova chave (`promotion_2`) ou mudança do modelo UNIQUE — registrar como decisão, não bug.

---

## 7. Plano de fatiamento (multi-PR)

Cada PR: build verde + suíte + council de domínio + (quando tocar SQL) GC-097 + sync de migração + consideração de invariante.

- **PR 1 — Fundação + paridade com o localStorage atual.**
  Schema `member_milestones` + RLS + `get_my_milestones` + `acknowledge_milestone` + `record_milestone` + backfill silencioso de `onboarding_complete` + gancho `onboarding_complete` + migrar `OnboardingChecklist` para fora do localStorage. **Já entrega o pedido literal do #766** (cross-device) e o esqueleto do framework. Council: `data-architect` (schema/RLS) + `ux-leader` (migração da celebração).
  - **Opção de split** se ficar grande (padrão DB-first → FE, como Wave 3c-i → 3c-ii): **PR 1a** = schema + RLS + 3 RPCs (DB-only); **PR 1b** = backfill `onboarding_complete` + gancho + migração FE.
- **PR 2 — `term_signed`.** Trigger em `certificates` (espelha `_trg_complete_volunteer_term_on_cert`) + backfill silencioso dos 41 (backfill **antes** do CREATE TRIGGER, §6.3) + celebração FE. Bulk em `certificates` (ex.: 33 contra-assinados históricos) dispara o trigger O(rows), mas é idempotente via `ON CONFLICT DO NOTHING`. Council: `data-architect`.
- **PR 3 — `first_attendance` + `first_deliverable`.** Triggers em `attendance` / `tribe_deliverables` + backfill silencioso + celebração. Reforçar a semântica lifetime-único de `first_*` (§3). Council: `data-architect`.
- **PR 4 — `promotion`.** **Avaliar trigger `AFTER UPDATE OF operational_role ON members WHEN (NEW='leader' AND OLD<>'leader')` vs gancho em `promote_to_leader_track`** — o trigger captura QUALQUER path de promoção (inclusive admin direto), o gancho RPC não. ⚠️ Se o trigger tocar `members`, verificar `schema-cache-columns.test.mjs` (gate ADR-0012). Council: `data-architect` + `security-engineer` (toca autoridade).
- **PR 5 — `profile_complete`.** Trigger `AFTER UPDATE OF profile_completed_at ON members WHEN OLD IS NULL AND NEW IS NOT NULL` + backfill silencioso dos 23 + celebração FE. ⚠️ Cópia **sem** "+50pts" (award inexistente, §2). Se o trigger tocar `members`, idem nota de `schema-cache-columns.test.mjs` do PR 4. Council: `data-architect`.

**Invariantes para `check_schema_invariants()`** (avaliar no PR que cria a tabela, com `data-architect`; o CHECK de `milestone_key` fica no DDL, não aqui):
- (forte) `term_signed` sem cert `volunteer_agreement` issued correspondente para o mesmo membro = violação (captura backfill errado ou cert revogado pós-marco). Espelha o padrão do `AA`.
- (média) milestone órfão: `member_milestones.member_id` sem `members.id` atual (o CASCADE cobre em teoria; pega delete via service_role que burle o CASCADE).
Descartadas as candidatas fracas originais ("`acknowledged_at ⟹ occurred_at NOT NULL`" é trivial pelo `NOT NULL`; enum vira CHECK no DDL).

---

## 8. Perguntas abertas para o PM (antes do PR 1)

1. **Conjunto de marcos do v1 do framework** além de `onboarding_complete`: incluir `term_signed` já no PR 1/2, ou só fundação primeiro?
2. **Backfill silencioso (§6.3):** confirmar que membros existentes **não** recebem celebração retroativa (só marcos novos celebram). Recomendação: silencioso.
3. **Superfície de celebração:** card no topo do workspace (como hoje) vs toast vs modal — ou deixar para o `ux-leader` no PR 1?
4. **`profile_complete`:** investigar a fonte agora (gamification) ou cortar do escopo até surgir demanda?

---

## 9. Cross-ref

- #766 (tracking dos resíduos verdes) item 2/4 · #740 (umbrella Wave 1–4, fechada) · J5 do discovery `docs/project-governance/PRE_ONBOARDING_JOURNEY_DISCOVERY_2026-06-16.md:170`
- Celebração atual: `src/components/onboarding/OnboardingChecklist.tsx:80-180`
- Padrão de trigger reutilizável: `_trg_complete_volunteer_term_on_cert` (mig …018), invariante `AA_volunteer_term_complete_when_cert_issued` (PR #770)
- Infra adjacente: `notifications` + `get_my_notifications`; `gamification_points`/`gamification_rules`
