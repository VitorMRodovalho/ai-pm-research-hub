# Spec p84-wave5 — AI-Augmented Self-Improvement Loop + Interview Reschedule

- **Status:** Spec / Awaiting Council Review
- **Author:** Claude + PM Vitor (2026-04-30 brainstorm)
- **PM approval:** opt-in interview topics + cap 2 re-analyses + hybrid model (AI-shared + committee-secret)
- **Scope:** PMI Journey v4 Phase C extension. Two related but distinct features:
  - **Wave 5b**: Self-improvement loop (candidate enriches application after AI gap detection)
  - **Wave 5d**: Interview slot change / reschedule feature (Thayanne case + future)
- **Council Tier 2 to invoke:** ai-engineer + ux-leader + legal-counsel (parallel)

---

## 1. Problem statement

**Wave 5b — Gap detection without action loop**

Hoje (post-CBGPL launch p82): após consent, gemini-2.5-flash analisa aplicação em ~10s e gera `red_flags` + `areas_to_probe` + `fit_for_role.score`. Esses sinais ficam **invisíveis para o candidato** — só o comitê os vê em `/admin/selection/[id]`. Candidatos com aplicação genérica (ex: Thayanne 2026-04-30: score 1/5, "aplicação extremamente genérica") ficam sem oportunidade de fortalecer **antes** da decisão humana — tornando a IA um *gate* implícito, não um *coach*.

PM mantra: "human-in-the-loop, IA assiste". Aplicação atual viola parcialmente porque o sinal IA não retorna ao candidato. Resultado: aplicações pobres → entrevistas pobres → comitê decide com pouca evidência → candidato sente julgamento sem chance.

**Wave 5d — Calendar booking sem visibilidade na plataforma**

Hoje: candidato agenda via link público Calendar (`gh9WjefjcmisVLoh7`). Apps Script auto-add guests mas **não cria row em `selection_interviews`**. Quando avaliador declina (ex: PM declined Thayanne 2026-04-30 12:38 BRT), Google envia auto-email mas plataforma não fica sabendo + não envia comunicação adicional + candidata não recebe oportunidade clara de re-bookar via plataforma. Silent gap.

## 2. Decisão de produto (PM 2026-04-30)

- ✅ Opt-in para candidato ver "tópicos prováveis na entrevista" (motivo: coerência com framework "AI augments human at all funnel layers"; reduz privilege bias; differentiator publishable)
- ✅ Cap re-analyses por candidato: **2** (motivo: PM "se não tira a chance dos demais" — controle de cost + abuse)
- ✅ Hybrid model: AI-suggested topics shared + committee-secret topics não shared
- ✅ Comitê mantém decisão final (human-in-the-loop não-negociável)
- ✅ Audit log das visualizações para comitê saber se ajustar follow-up
- ✅ Calendar reschedule via plataforma (não disparo manual) — via feature final
- ✅ Anti-abuse: 5 min cooldown entre re-analyses, IP audit, comitê vê histórico completo

## 3. Design — 4 estágios + reschedule flow

### Estágio 1 — Detection (existing, parcial)
- `give_consent_via_token` triggers gemini-2.5-flash via EF `pmi-ai-analyze`
- Response landing em `selection_applications.ai_analysis jsonb` (já hoje)
- **Novo**: helper `_should_offer_enrichment(ai_analysis jsonb) RETURNS boolean` retorna true quando:
  - `fit_for_role.score < 3`, OR
  - `red_flags.length >= 2`, OR
  - missing critical fields detected (ex: empty `motivation_letter` OR `academic_background.length < 50`)

### Estágio 2 — Portal UX `/pmi-onboarding/[token]`

Após consent + AI analysis, se `_should_offer_enrichment == true`, candidato vê 2 cards (additivos, não substituem fluxo existente):

**Card A — Pontos a fortalecer (sempre visível se needs_enrichment)**
```
🤖 Análise inicial concluída
A IA identificou pontos onde sua aplicação pode brilhar mais
ANTES da entrevista com o comitê. Isso aumenta suas chances —
e o comitê analisa a versão final que você enviar.

[Para cada red_flag + areas_to_probe → 1 card editable]

📚 Formação acadêmica
Você mencionou: "Estudando para certificação"
Sugestão IA: "Que certificação? Em que estágio?"
[Textarea editável → field: academic_background]

💼 Experiência relevante
Pendente de detalhamento:
"Quais habilidades específicas relevantes para pesquisa em IA & GP?"
[Textarea → field: non_pmi_experience OR leadership_experience]

🎯 Tema de interesse
[Textarea → field: proposed_theme]

[ Salvar e re-analisar ]
2 tentativas restantes • Cooldown 5 min entre re-análises
```

**Card B — Tópicos prováveis na entrevista (opt-in)**
```
═══════════════════════════════════════
🔍 Quer ver tópicos prováveis na sua entrevista?

A IA destacou áreas que o comitê provavelmente vai explorar.
Você pode revisar antes — sem cobrança, sem julgamento.
O comitê pode explorar outros tópicos também.

[ Ver tópicos sugeridos →  ]   [ Pular — prefiro improvisar ]
═══════════════════════════════════════

Se clica "ver":
→ Lista de ai_analysis.areas_to_probe[] visíveis
→ Linguagem positiva: "Pense em exemplos concretos sobre…"
→ Disclaimer: "Comitê pode explorar outros tópicos também."
→ Audit log: timestamp + IP + UA → selection_topic_views table
```

### Estágio 3 — Re-analyze rate-limited

- RPC: `request_application_enrichment(p_token text, p_field_updates jsonb) RETURNS jsonb`
- Validação token + scope `profile_completion` ativo
- Verifica `enrichment_count < 2`
- Verifica cooldown: `last_enrichment_at IS NULL OR last_enrichment_at + interval '5 minutes' < now()`
- Save fields → trigger Gemini re-analysis async (igual ao consent path)
- Histórico append: `ai_analysis_history jsonb[]` array de `{version, analyzed_at, ai_analysis_snapshot, fields_changed}`
- After cap: friendly message "Você usou suas 2 reanálises. Continue revisando — comitê verá sua versão atual."

### Estágio 4 — Comissão visibility (`/admin/selection/[id]`)

Comitê vê painel:
- **Versão original** (timestamp + dados PMI VEP)
- **Versões enriquecidas** (1, 2 — quantas o candidato usou)
- **AI analysis evolution** — score original vs final, red_flags resolvidos
- **Diff visual** — campos novos vs originais (highlight, evita over-padding undetected)
- **Topics-viewed audit** — flag "candidato viu topics da entrevista em [timestamp]" (informational, não penalizing)
- **Decisão final continua humana** (approve/reject/request_more_info/needs_reschedule)

### Estágio 5 — Reschedule flow (Wave 5d)

- **New status enum**: `selection_applications.interview_status` valores: `none | scheduled | needs_reschedule | completed`
- **Trigger paths**:
  1. **Manual** via `/admin/selection/[id]` botão "Mark for reschedule"
  2. **Webhook future** Calendar declined event (deferred; manual trigger é suficiente p/ MVP)
- **Side effects** quando marca needs_reschedule:
  - Notification + email para candidato (template `interview_reschedule_required` 3 langs PT/EN/ES)
  - Email body: "Avaliador identificou conflito de horário. Reagende um novo slot."
  - Email contém: link `/pmi-onboarding/[token]` → ao abrir mostra banner "Reagende sua entrevista" + iframe Calendar booking page (`gh9WjefjcmisVLoh7`)
  - Token reissued se expirou (7-day window pode renovar +7d)
- **Candidato re-bookou**: futuro Calendar webhook OR Apps Script → marca status back to `scheduled`
- **Para Thayanne**: PM marca via /admin → email auto disparado → ela recebe via plataforma (não manual)

## 4. Schema changes (migration)

```sql
-- Migration: p84_wave5_ai_augmented_loop_schema

-- (1) Per-application enrichment tracking
ALTER TABLE selection_applications
  ADD COLUMN ai_analysis_history jsonb[] DEFAULT '{}',
  ADD COLUMN enrichment_count integer DEFAULT 0,
  ADD COLUMN last_enrichment_at timestamptz,
  ADD COLUMN interview_status text DEFAULT 'none' CHECK (interview_status IN ('none','scheduled','needs_reschedule','completed','rescheduled'));

CREATE INDEX idx_selection_apps_interview_status ON selection_applications(interview_status) WHERE interview_status != 'none';

-- (2) Topic view audit (LGPD: candidate self-action, retention 5y per LGPD Art.16 + ADR-0014)
CREATE TABLE selection_topic_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id) ON DELETE CASCADE,
  viewed_at timestamptz NOT NULL DEFAULT now(),
  ip_address inet,
  user_agent text,
  organization_id uuid NOT NULL REFERENCES organizations(id)
);
ALTER TABLE selection_topic_views ENABLE ROW LEVEL SECURITY;
-- RLS: candidato pode insert via token; comitê pode read; ninguém update/delete (audit-immutable)

-- (3) Notification template (engagement_kind catalog extension)
INSERT INTO notification_templates (type, subject_i18n, body_i18n, ...)
VALUES ('interview_reschedule_required', ...);
```

## 5. RPC contract — main

```sql
-- request_application_enrichment(p_token text, p_field_updates jsonb)
-- RETURNS jsonb { success, enrichment_count, remaining_attempts, next_allowed_at, ai_analysis_snapshot }
-- Validates: token scope profile_completion + cooldown + cap
-- Updates fields + appends to ai_analysis_history + triggers gemini-2.5-flash via EF

-- log_topic_view(p_token text, p_ip inet, p_ua text)
-- RETURNS void — INSERT into selection_topic_views, idempotent per session

-- request_interview_reschedule(p_application_id uuid, p_reason text)
-- RETURNS jsonb { success, notification_id, email_dispatch_id }
-- Caller: comitê via admin (gated via can_by_member('manage_selection'))
-- Updates interview_status='needs_reschedule' + dispatches email/notification
```

## 6. Frontend changes

- `src/pages/pmi-onboarding/[token].astro` — Estágio 2 cards (sempre + opt-in)
- `src/components/onboarding/EnrichmentCard.tsx` (novo) — render gap items + textarea + save
- `src/components/onboarding/InterviewTopicsOptIn.tsx` (novo) — opt-in card + reveal
- `src/components/onboarding/RescheduleBanner.tsx` (novo) — quando interview_status='needs_reschedule'
- `src/pages/admin/selection/[id].astro` — Estágio 4 painel (history + diff + topics-viewed flag)
- `src/components/admin/selection/EnrichmentHistory.tsx` (novo)
- `src/components/admin/selection/InterviewActions.tsx` (novo) — "Mark for reschedule" button

## 7. i18n keys (3 langs)

~25 novas keys cobrindo: enrichment cards, opt-in interview topics, reschedule banner, admin labels, email subject/body. Detalhe em `src/i18n/`.

## 8. LGPD considerations (legal-counsel review)

- **Candidate self-edit data** → standard data subject right ART. 18 LGPD (rectify own data). OK.
- **AI analysis history retention** — 5 years post-cycle (ADR-0014 retention) consistent. Anonymize cron 5y stays.
- **Topic view audit log** — minimal data (no PII beyond IP + UA), retention 2 years sufficient. PII access log already covers.
- **Right to erasure** — when candidato exerce ART. 16 (forget), `ai_analysis_history[]` deleted with parent application. CASCADE OK.
- **Multiple AI analyses processed** — already consented at first via `consent_ai_analysis_at`. Re-analysis under same consent. **OPEN QUESTION** for legal-counsel: needs new consent per re-analysis OR umbrella consent valid?
- **Audit immutability** — `selection_topic_views` is INSERT-only. RLS prevents UPDATE/DELETE.

## 9. Cost guard / anti-abuse

- **Gemini cost**: ~$0.0001/analysis × 50 candidates × 2 re-analyses = $0.01/cycle. Trivial.
- **Rate limit**: cap 2 re-analyses + 5 min cooldown between
- **Audit**: comitê vê histórico → over-padding detectável visualmente
- **Anti-bot**: token-based, 1 token = 1 candidate, expires 7 days

## 10. Rollout plan

- **Wave 5b-1**: schema migration + RPCs (1 commit)
- **Wave 5b-2**: portal frontend (Estágio 2 cards) + i18n (1 commit)
- **Wave 5b-3**: admin panel (Estágio 4 history + diff) (1 commit)
- **Wave 5d-1**: reschedule flow (status enum + email template + admin button) (1 commit)
- **Wave 5d-2**: portal banner reschedule + Calendar embed (1 commit)
- **Wave 5e (defer)**: Calendar webhook → auto-update DB sync

Total estimate: 8-12h dev across 4-5 sessions.

## 11. Open questions for council

**ai-engineer:**
1. Schema: `ai_analysis_history jsonb[]` array vs separate table `ai_analysis_versions`? Which is better for future analytics queries?
2. Re-analysis trigger pattern — sync (block save until Gemini returns) vs async (save + queue + poll)? Latency UX trade-off.
3. Anti-abuse hardening — should we hash + dedupe near-identical submissions (e.g., 1 word change between v1 and v2)?

**ux-leader:**
1. Card A (gap fill) and Card B (opt-in topics) order — gap fill first, then topics? Or simultaneous? Cognitive load.
2. Mobile UX 375px — textareas + cards stacking. Issues?
3. Friction copy — "2 reanálises restantes" causa anxiety? Better wording?
4. Reschedule banner — full-width vs floating bell?

**legal-counsel:**
1. Multiple AI analyses sob umbrella consent — válido? Ou cada re-analysis precisa nova confirmação granular?
2. Audit log de topic views — retention 2y suficiente vs 5y matching application?
3. LGPD subject right to erasure interaction com `ai_analysis_history` — CASCADE delete OK?
4. PMI Brasil/PMI-GO ownership do candidate enriched data — diferente do submission original?

## 12. Não está em escopo desta wave

- Calendar webhook auto-sync (deferred Wave 5e)
- Video screening fill-the-gap analog (deferred Wave 6 — exige novo Gemini multimodal flow)
- Multi-cycle persistence de candidate profile (return user case)
- Public framework documentation desta feature (Wave de positioning post-CR-050)
