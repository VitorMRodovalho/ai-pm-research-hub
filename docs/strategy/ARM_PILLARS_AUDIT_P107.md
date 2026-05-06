# ARM — Aquisição de Recursos: Auditoria de Pilares e Maturidade (p107)

**Sessão:** p107 — 2026-05-06
**Mandato (PM Vitor):** estruturar pilares de trabalho dentro do domínio PMBOK "Aquisição de Recursos" antes de descer em features. Cada pilar com estado atual + boa prática + gaps + maturidade, para destravar análise focada por pilar nas sessões seguintes.
**Método:** 5 lentes paralelas (data-architect, product-leader, ux-leader, ai-engineer, security-engineer) + re-auditoria do subsistema de IA ativo na seleção. Total ~6 mil palavras de findings sintetizadas em 12 pilares.
**Status:** consultivo — nenhuma alteração de código nesta sessão. Onda 1 (compliance/hotfix) abre issues priority:high para fila autonomous-shippable; ondas 2-5 dependem de PM trigger.

---

## TL;DR

1. **Plataforma é forte em ARM-8 (Compliance/Audit, maturidade 3)**, **funcional em ARM-2/3/4/6/7/10/11/12 (maturidade 2)**, e **embrionária em ARM-1/5/9 (maturidade 1)**. Maturidade média ponderada **≈ 1.92** — funcional em early-stage, pronta para escalar com hotfix de compliance + visibilidade.
2. **Achado crítico não-óbvio:** RLS de `selection_applications` provavelmente não está explícita (security-engineer flagged) — possível leak de email/telefone/CV de candidatos para qualquer usuário autenticado, incluindo ghost. Verificação imediata é **ship gate** antes do Cycle 4.
3. **Reframe IA:** existe pipeline IA ativo (`pmi-ai-analyze` EF + `ai_analysis_runs` table + Gemini 2.5 Flash + cron retry + consent gate dedicado + purga LGPD em 90/180d). O gap reportado pelo PM ("tab à parte") é **UX inline vs tab**, não inexistência. ARM-11 maturidade ajustada 1→2.

---

## Os 12 Pilares ARM — Matriz de Maturidade

Maturidade: **1** = embrionário · **2** = funcional com gaps · **3** = otimizado · **4** = excelência (literatura/benchmark de comunidades técnicas: Mozilla Reps, Apache Foundation, GitHub Sponsors, GovTech UK Talent).

| ID | Pilar | Definição | Maturidade | Top P0 desbloqueador |
|----|-------|-----------|------------|---------------------|
| ARM-1 | Captação & Awareness | Gerar demanda qualificada de candidatos antes da janela de inscrições | 1 | Adicionar `referral_source` + UTM em `selection_applications`; landing `/volunteer` |
| ARM-2 | Application (jornada candidato) | Submission → confirmação → status real-time | 2 | Lançar `/me/status` (RPC `get_my_application_status` já existe) |
| ARM-3 | Triage & Initial Filter | Reduzir pool via filtros e scoring inicial | 2 | Decisão PM: `analyze_application` LLM W4 (LGPD + budget) |
| ARM-4 | Evaluation Pipeline | Atribuição, formulário, calibração, dashboards de avaliador | 2 | Coluna `my_eval_status`/`my_eval_score` em `get_selection_dashboard` |
| ARM-5 | Interview Layer | Agendamento, condução, notas, normalização | 1 | Reusar `meeting_notes` + Form estruturado; resolver `#92`/`#116` Calendar |
| ARM-6 | Decision & Communication | Comitê, audit, dispatch de decisão e feedback | 2 | Fix `send-notification-email` drain cron 10min window |
| ARM-7 | Onboarding | Termo, welcome, atribuição de tribo, treinamento | 2 | Migrar `localStorage` → RPC `upsert_onboarding_progress` |
| ARM-8 | Compliance & Audit | LGPD, audit log, approval chains, versionamento | **3** | RLS `selection_applications` + `admin_audit_log` DENY DELETE |
| ARM-9 | Offboarding | Trigger, handoff, anonimização, re-engagement | 1 | `member_status` enum (active/alumni/inactive/withdrawn) + alumni path |
| ARM-10 | Communication Layer (cross-cutting) | Resend, templates, multi-language | 2 | drain cron fix + bulk imports dispatching welcome |
| ARM-11 | AI Layer (cross-cutting) | Pre-screen, suggestion, calibração, drift | 2 | UX inline AI (não tab); calibration metrics |
| ARM-12 | Observability (cross-cutting) | Dashboards, cron health, funnel analytics | 2 | `get_selection_health` RPC (padrão W7/W8/W9) |

**Maturidade média ponderada ≈ 1.92.** Justificativa por pilar nas seções abaixo.

---

## Achados Convergentes (15) — Onde Múltiplas Lentes Concordam

| # | Achado | Detectado por | Severidade | Pilar |
|---|--------|---------------|-----------|-------|
| 1 | `selection_applications` provavelmente sem RLS explícita — anon/ghost potencialmente lê PII (email, phone, CV) | security | **CRITICAL — ship gate** | ARM-8/ARM-2 |
| 2 | `admin_audit_log` sem `DENY DELETE` — cadeia de custódia LGPD frágil | security | HIGH | ARM-8 |
| 3 | `admin_reactivate_member` sem guard `anonymized_at IS NULL` (LGPD proíbe des-anonimização) | security | HIGH | ARM-8/ARM-9 |
| 4 | `engagement_kinds.candidate.retention_days_after_end = 1825` (5 anos) excessivo p/ rejeitado sem contrato | security | HIGH | ARM-8 |
| 5 | Drain cron `send-notification-email` janela 10min (perde emails se EF falha) | product-leader (corrobora p34 ai-engineer) | HIGH | ARM-6/ARM-10 |
| 6 | Score caches em `selection_applications` (`objective_score_avg`, `interview_score`, `final_score`) sem trigger sync — divergência silenciosa possível (ADR-0012 violação latente) | data-architect | HIGH | ARM-4 |
| 7 | `detect_onboarding_overdue` tem GRANT mas **sem `cron.schedule`** — SLA invisível operacionalmente | data-architect | HIGH | ARM-7/ARM-12 |
| 8 | Avaliador não vê "já avaliei?" na lista — `peer_eval_count` é agregado, não personal (`admin/selection.astro:659`) | ux-leader | HIGH | ARM-4 |
| 9 | Candidato sem rota `/me/status` — silencioso pós-submissão (RPC `get_my_application_status` existe, falta surface) | ux-leader | HIGH | ARM-2 |
| 10 | Onboarding state em `localStorage` — reset entre dispositivos (`onboarding.astro:249`) | ux-leader | HIGH | ARM-7 |
| 11 | `analyze_application` LLM W4 declarado deferred Q3 2026 (LGPD + budget) — única gate PM em ARM-3 | product + ai + security | DECISION | ARM-3/ARM-11 |
| 12 | Bulk imports bypassam welcome (memory: `feedback_bulk_import_skips_worker_welcome_dispatch`) | product-leader | MEDIUM | ARM-7/ARM-10 |
| 13 | Sem `consent_records` table — impossível provar Art. 7 I + Art. 8 §5 LGPD para política versionada | security | MEDIUM | ARM-8 |
| 14 | Sem `pii_access_log` ao abrir dossiê de candidato (`admin_get_member_details` cobre membros, não applications) | security | MEDIUM | ARM-8 |
| 15 | Blind review de `selection_evaluations` não enforced em RLS — só em fase via ADR-0059 | security | MEDIUM | ARM-4/ARM-8 |

---

## Reframes — O Que Mudou Nesta Auditoria

### R1. IA na Seleção é Real e Robusta (ARM-11 maturidade 1→2)

A primeira passada do ai-engineer concluiu erroneamente "não há IA embedded". Re-auditoria revelou pipeline ativo:

- **EFs:** `supabase/functions/pmi-ai-analyze/index.ts` (317L) + `pmi-ai-analyze-research/index.ts` (263L)
- **Modelo atual:** `gemini-2.5-flash` (sediment: free tier 10 RPM / 32K TPM — cuidado com burst)
- **Tabela observável:** `ai_analysis_runs` (migração `20260516350000_p86_wave5b1b_ai_analysis_runs.sql`) com per-run audit (model_version, tokens, duration, error, status, fields_changed)
- **Triggers:** `consent | enrichment_request | admin_retry | cron_retry`
- **Status state machine:** `running | completed | failed`
- **Cron retry:** `retry_pending_ai_analyses` horário (já agendado em produção)
- **Consent gate dedicado:** `consent_ai_analysis_at` (LGPD Art. 9 §1, separado do consent geral) + revoke trigger purgando `linkedin_relevant_posts/cv_extracted_text/ai_pm_focus_tags/ai_analysis` em 72h
- **RLS:** comitê do ciclo (lead/member) pode ler análises do próprio ciclo
- **Retenção LGPD:** 90d pós-decisão para não-selecionados, 180d para selecionados — purga automática via `cycle_decision_date` clock
- **PII access integration:** documentado nos COMMENT ON COLUMN
- **Diff UI substrate:** `get_application_ai_analysis_runs` (5b-3) + `admin_retry_application_ai_analysis` (p87)
- **W4 deferred:** `analyze_application` (LLM scoring direto) declarado para Q3 2026 — exige decisão PM sobre LGPD + LLM budget

**Gap real reportado por Vitor (UX, não infra):** a "tab Análises IA" no `admin/selection.astro` mostra os campos `raises_the_bar/summary/key_strengths/areas_to_probe` do `ai_analysis_snapshot`. Como tab separada, o avaliador faz context-switch entre "Análises IA" e "Avaliar" — o ideal é injetar esse bloco inline no painel de contexto da avaliação (linhas 1380-1391 do mesmo arquivo). O dado já existe via `get_selection_dashboard.ai_analysis_snapshot`; só falta surface.

### R2. Score Consistency — Invariante Faltante (M)

Os 3 score caches em `selection_applications` (`objective_score_avg`, `interview_score`, `final_score`) são populados por `compute_application_scores()` chamado manualmente e por `submit_evaluation()`. **Nenhum trigger AFTER em `selection_evaluations` chama o RPC**. Se uma evaluation for editada/excluída via service_role sem disparar o RPC, score diverge silenciosamente. Não está coberto pelas 11 invariantes ADR-0012.

**Proposta de invariant 12:**
```sql
-- M_application_score_consistency
SELECT a.id, a.objective_score_avg, AVG(e.score) AS expected_avg
FROM selection_applications a
JOIN selection_evaluations e ON e.application_id = a.id
WHERE e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL
GROUP BY a.id, a.objective_score_avg
HAVING ABS(COALESCE(a.objective_score_avg, 0) - AVG(e.score)) > 0.01;
-- expected: 0 rows
```

### R3. `selection_applications` RLS — Verificação Pendente

A tabela existe e é a fonte de verdade desde 14/Mar (80 rows ciclo 3). A migration de origem (`20260319100023_w124_selection_pipeline_schema.sql`) chama `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, mas a `migration v4 phase 4 rls_policy_rewrite` (`20260415010000`) **não cria policies SELECT específicas** para a tabela. Se a RESTRICTIVE org_scope não a alcança, RLS habilitado sem policy permissive = full lockdown (impossível ler) ou — se houver policy default permissive em algum sweep — exposição total.

**Verificação necessária (1 query SQL):**
```sql
SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname = 'selection_applications';
SELECT * FROM pg_policies WHERE tablename = 'selection_applications';
```

Resultado define se P0-1 é "verificar e adicionar" ou "verificar e fazer nada". Mas executar a verificação não é opcional.

### R4. Cron de Onboarding Overdue — Função Existe, Schedule Não

`detect_onboarding_overdue()` está com GRANT a `authenticated`, sintaxe válida, mas nenhuma migration encontra `cron.schedule(...detect-onboarding-overdue...)`. Steps com `sla_deadline` ultrapassada nunca são marcados como `overdue` automaticamente. Operacionalmente invisível. ARM-7 + ARM-12 ambos afetados.

---

## Sequência Recomendada — 5 Ondas

### Onda 1 — Compliance & Hotfix Batch (1-2 sessões, autonomous-shippable)

Ship gate de compliance + bug ativo de comunicação. Não exige decisão PM além de aprovar a fila.

| # | Item | Pilar | Esforço | Tipo |
|---|------|-------|---------|------|
| 1 | Verificar e adicionar RLS em `selection_applications` (R3) | ARM-8/ARM-2 | 1-2h | DDL + verify |
| 2 | `admin_audit_log` policy `RESTRICTIVE FOR DELETE USING (false)` | ARM-8 | 30min | DDL |
| 3 | `admin_reactivate_member` guard `anonymized_at IS NULL` | ARM-8/ARM-9 | 30min | RPC patch |
| 4 | `engagement_kinds.retention_days_after_end` candidate: 1825 → 730 | ARM-8 | 15min | UPDATE config |
| 5 | Fix `send-notification-email` drain cron 10min window (DLQ ou remover filtro) | ARM-6/ARM-10 | 1-2h | EF + cron |
| 6 | Agendar cron `detect-onboarding-overdue` (R4) | ARM-7/ARM-12 | 15min | cron.schedule |
| 7 | Adicionar invariant 12 `M_application_score_consistency` (R2) | ARM-4 | 1h | RPC + test |

**Total estimado:** 5-7h em 1-2 sessões. Tudo backend + DDL — autonomous-shippable seguindo pattern p99-p106.

### Onda 2 — Visibility & Observability (1 sessão)

Sem isso, qualquer feature de Onda 3-4 ship em cima de infra cega.

1. RPC `get_selection_health` (padrão W7/W8/W9) — ciclo ativo, candidatos por estágio, tokens não consumidos >48h, último run de cada cron, welcome backlog.
2. Dashboard candidato `/me/status` — surface da `get_my_application_status` (RPC existe, frontend não). Resolve FP-1 ux-leader.
3. Adicionar `my_eval_status`/`my_eval_score` em `get_selection_dashboard` — resolve FP-4 ux-leader.
4. Funnel instrumentation — `referral_source` + UTM em `selection_applications`.
5. `consent_records` table + ligação com `selection_applications.consent_record_id`.

**Total:** 4-5h backend + frontend leve.

### Onda 3 — AI Build (1-2 sessões + decisão PM bloqueante)

1. **Decisão PM** (1h, não código): `analyze_application` LLM W4 — go/no-go LGPD + budget. Definição de retenção (já em substrato via `cycle_decision_date`).
2. **Se go:** decisão arquitetural — manter Gemini 2.5 Flash (custo zero, free tier) ou migrar scoring para Claude Sonnet 4.6 + prompt cache rubrica (custo ~$0.10/ciclo, mais consistente para qualitativo).
3. RPC `get_evaluator_calibration_stats` — Krippendorff alpha ordinal + Cohen's kappa por par de avaliadores. SQL puro sobre `selection_evaluations`. Sem IA generativa.
4. MCP tool `generate_interview_briefing(application_id)` — Haiku 4.5 com payload do candidato gera 3 perguntas personalizadas + pontos de atenção. Curto, baixo custo, anchored to data.
5. `ai_processing_log` table — registra cada chamada a modelo com `application_id + timestamp + hash dos campos enviados` (não conteúdo). Atende LGPD Art. 37 + Art. 20 §1 (revisão humana de decisão automatizada).

### Onda 4 — Evaluator UX (1 sessão browser)

Depende dos RPCs da Onda 2 + 3.

1. Coluna "Minha avaliação" na lista admin — badge verde "Avaliei (X.X)" / cinza "Pendente" / ausente. Resolve FP-4.
2. Form locked exibe scores submetidos (read-only sliders) em vez de banner genérico (`admin/selection.astro:1425`). Resolve FP-5.
3. Inline AI panel (collapsed por default) na tela de avaliação — mostra `raises_the_bar/summary/key_strengths/areas_to_probe` do `ai_analysis_snapshot` (já em `get_selection_dashboard`) sem fetch adicional. Resolve FP-6.
4. Tab "Análises IA" deprecated — conteúdo migra inline.
5. Acessibilidade: `role="dialog"` + `aria-labelledby` + focus trap no modal de candidato; `aria-label` em sliders e checkboxes (ux-leader a11y check).

### Onda 5 — Per-Pillar Deep Dive

Os pilares mais embrionários (1) são ARM-1, ARM-5 e ARM-9. Ordem sugerida:

1. **ARM-9 (Offboarding):** alumni status formal cria base para retenção e re-engagement. Crítico antes da expansão multi-capítulo (5+ capítulos previstos 2026).
2. **ARM-1 (Captação):** sem instrumentação de funil (UTM + referral_source), expansão acontece blind. Quick win na Onda 2 + estratégico aqui.
3. **ARM-5 (Entrevista):** mais embrionário em termos de infra, mas menos urgente — depende de `#92`/`#116` Calendar destrava antes.

Cada um é uma sessão dedicada de 4-6h spec + ship.

---

## Referências de Código (file:line âncoras)

### Backend (migrations)
- `supabase/migrations/20260319100023_w124_selection_pipeline_schema.sql` — schema base do funil
- `supabase/migrations/20260514300000_adr_0059_w1_selection_applications_linkedin_ai_analysis_fields.sql` — fields IA + consent gate dedicado + revoke trigger
- `supabase/migrations/20260516350000_p86_wave5b1b_ai_analysis_runs.sql` — observability table + RLS
- `supabase/migrations/20260516360000_p86_wave5b3_get_application_ai_analysis_runs.sql` — diff RPC
- `supabase/migrations/20260516410000_p87_admin_retry_application_ai_analysis.sql` — admin retry
- `supabase/migrations/20260516280000_phase_b_pmi_journey_v4_consent_dispatches_ai_analyze.sql` — pipeline orchestrator
- `supabase/migrations/20260415010000_v4_phase4_rls_policy_rewrite.sql` — RLS sweep V4 (ausência de `selection_applications` é o gap)
- `supabase/migrations/20260413510000_v4_phase5_anonymize_by_kind.sql` — anonymize cron V4
- `supabase/migrations/20260512010000` (offboarding records) + `20260512020000` (replicação invariant L)

### Edge Functions
- `supabase/functions/pmi-ai-analyze/index.ts` (317L) — Gemini 2.5 Flash, `callGeminiAnalyze` em L145
- `supabase/functions/pmi-ai-analyze-research/index.ts` (263L) — variant para research
- `supabase/functions/send-notification-email/` — drain cron com bug 10min window

### Frontend (Astro)
- `src/pages/admin/selection.astro:603` — `renderQuickStats()` (sem dimensão temporal)
- `src/pages/admin/selection.astro:659` — `renderTable()` (sem `my_eval_status`)
- `src/pages/admin/selection.astro:1354` — `loadEvaluationForm()`
- `src/pages/admin/selection.astro:1425` — form locked banner (substituir por sliders read-only)
- `src/pages/admin/selection.astro:1380-1391` — `contextPanel` (alvo do AI inline)
- `src/pages/onboarding.astro:249` — `STORAGE_KEY = 'onboarding_progress'` em localStorage (migrar para RPC)

### MCP Tools (266 total — relevantes)
- `get_my_application_status`, `update_my_application` (candidato)
- `get_selection_dashboard`, `get_selection_pipeline_metrics`, `get_selection_rankings` (comitê/admin)
- `submit_evaluation`, `submit_interview_scores`, `mark_interview_status`, `compute_application_scores` (avaliador)
- `get_my_pending_evaluations`, `get_my_evaluation_feedback` (avaliador self)
- `complete_onboarding_step`, `dismiss_onboarding`, `get_onboarding_*`, `bulk_mark_excused` (onboarding)
- `offboard_member`, `record_offboarding_interview`, `list_offboarding_records`, `get_offboarding_dashboard` (offboarding)
- `get_invitation_health`, `get_lgpd_cron_health`, `get_digest_health` (saturação Pattern 43 health observability — falta `get_selection_health`)

---

## Memory & Decisions Anchored

- `feedback_gemini_free_tier_limits.md` — 10 RPM / 32K TPM. Verbose schemas burst hit 429
- `feedback_round_robin_load_metric_pending_invites.md` — load = submitted + pending invites (sem pending → não rotaciona)
- `feedback_bulk_import_skips_worker_welcome_dispatch.md` — bulk SQL imports bypassam welcome
- `feedback_resend_5rps_bulk_throttle.md` — Resend hard cap 5 req/sec (`pg_sleep(0.3)` em loops bulk)
- `feedback_v4_auth_pattern.md` — ADR-0011 `can_by_member()` source of truth
- `feedback_schema_invariants.md` — ADR-0012 cache columns sync trigger pattern (necessário para R2 invariant 12)
- ADR-0059 W1 — LinkedIn cross-ref + LLM analyze (ativo)
- ADR-0007 — `can()` authority gate (engagement-derived)
- ADR-0012 — schema invariants (proposta de M_application_score_consistency adiciona 12ª)

---

## Próximas Sessões — Disparadores

| Sessão | Trigger | Modo |
|--------|---------|------|
| p108 | "rodar Onda 1 ARM" | Autonomous-shippable, 1-2 sessões |
| p109 | "rodar Onda 2 ARM" | Mix backend + frontend leve |
| Decision | "decidir analyze_application" | 1h PM, não código |
| Browser | "Onda 4 evaluator UX" | 1 sessão browser dedicada |
| Spec | "deep dive ARM-X" (1-12) | Spec session por pilar |

---

**Documento mantido pelo PM. Atualizar ao concluir cada onda. Usar como ground truth de "qual o estado atual do pilar de Aquisição de Recursos" em todo handoff até maturidade média atingir 3.0.**

---

## Onda 1 — Completion Report (2026-05-06)

**Status: 7/7 issues fechadas. 6 migrações aplicadas + 1 false positive.**

| Issue | Resolução | Migration |
|-------|-----------|-----------|
| #134 | Hardening preventivo: RPC-only pattern documentado + REVOKE DML grants over-permissive em 9 tabelas + add `rpc_only_deny_all` em `selection_evaluation_anomalies` | `20260516710000` |
| #135 | RESTRICTIVE policies `audit_log_no_delete` + `audit_log_no_update` + REVOKE DML mutations | `20260516720000` |
| #136 | Guard `anonymized_at IS NULL` em `admin_reactivate_member` + audit log entry de tentativa rejeitada | `20260516730000` |
| #137 | Retenção candidate 1095 → 730d (corrigido: valor real era 1095, não 1825) + audit entry | `20260516740000` |
| #138 | **False positive** — bug já corrigido em commit `dd73031` antes desta sessão; log não atualizado | (nenhuma) |
| #139 | Cron `detect-onboarding-overdue-daily` agendado às 13 UTC + cron-context auth bypass (ADR-0028 pattern) | `20260516750000` |
| #140 | Invariant 12 + AFTER trigger sync + backfill idempotente (8 drift corrigidos em prod) | `20260516760000` |

### Findings que mudaram interpretação dos audit reports

1. **R1 corrigido pré-Onda 1:** `selection_applications` estava em full lockdown intencional (RPC-only via SECDEF), não leak. Severidade real: HIGH (defesa em profundidade), não CRITICAL.
2. **R3 corrigido durante #137:** `candidate.retention_days_after_end` real era 1095d (3y), não 1825d (5y) como projetado pelo agent.
3. **R4 confirmado e fechado durante #139:** cron de overdue de fato não existia; agendado.
4. **#138 false positive:** auditoria importou item do issue/gap log sem cross-check git history. Sediment capturado.
5. **Bonus drift detectado em #140:** 8 applications com `research_score` dessincronizado em prod (pré-trigger). Backfill executado.

### Estado pós-Onda 1

- 6 migrações 20260516710000 → 20260516760000 (+1 doc strategic + 1 test contract update)
- 3 commits no `main`: cf78d93 (doc) + 895298f (compliance batch) + 7fed557 (operational batch)
- Invariants **12/12 = 0 violations** (was 11/11)
- ARM-8 maturidade reforçada: 3 → 3+ (aprofundou hardening preventivo)
- Pattern detected: auditorias multi-lente devem cross-checar git log para items "abertos" no issue log

### Próximas ondas

- **Onda 2** (Visibility & Observability) — **COMPLETA p107** (5/5 entregáveis, ver §Onda 2 Completion Report abaixo)
- **Onda 3** (AI Build) ainda pending decisão PM `analyze_application`.
- **Onda 4** (Evaluator UX) ainda pending sessão browser. Backend pieces pode adiantar (calibration metrics).
- **Onda 5** (Per-Pillar Deep Dive) ainda pending — escolher ARM-9 ou ARM-1 ou ARM-4.

---

## Onda 2 — Completion Report (2026-05-06)

**Status: 5/5 entregáveis shipped. 4 migrações + 3 frontend pages + 1 EF deploy.**

| Item | Resolução | Migration / File |
|------|-----------|-----------------|
| 2.1 | `referral_source` + `referrer_member_id` (FK members) + `utm_data` jsonb em selection_applications. Backfill heurístico VEP (100 rows) | `20260516770000` |
| 2.2 | `consent_records` table (LGPD Art. 7 I + Art. 8 §5) com subject polimórfico + RLS rpc-only + FK em selection_applications | `20260516780000` |
| 2.3 | `my_eval_status` + `my_eval_score` + 2 stats rollup em `get_selection_dashboard`. Resolve FP-4 ux-leader | `20260516790000` |
| 2.4 | `get_selection_health` RPC (Pattern 43 W7/W8/W9 + W10) + MCP tool exposure (v2.65.0, 267 tools) | `20260516800000` + EF deploy |
| 2.5 | `/minha-candidatura.astro` + `/en/` + `/es/` redirects + ~50 i18n keys novas. Resolve FP-1 ux-leader | 6 frontend files |

### Estado pós-Onda 2

- Migrations applied: `20260516770000` → `20260516800000` (4 sequenciais)
- MCP `nucleo-mcp` v2.65.0 deployed (267 tools, was 266)
- Cloudflare Worker deployed (frontend live em `nucleoia.vitormr.dev/minha-candidatura`)
- Commits: `55410c3` (visibility/observability backend) + `0588867` (frontend dashboard)
- ARM-2/ARM-4/ARM-12 maturidade reforçada
- ARM-8 maturidade reforçada (consent_records preenche gap LGPD Art. 7 I)

### Próximos triggers já preparados

- Backend autonomous-shippable: pii_access_log dossiê candidato, blind review RLS, calibration metrics RPC
- Decisão PM bloqueante: analyze_application LLM W4 go/no-go
- Sessão browser: inline AI panel evaluator + admin dashboard show selection_health

---

## Pós-Onda 2 P1 batch (2026-05-06 follow-up)

3 P1 items adicionais shipped na mesma sessão:

| Item | Resolução | Commit |
|------|-----------|--------|
| pii_access_log dossiê candidato | Helper `_log_application_pii_access` + 2 RPCs (`get_application_score_breakdown`, `get_evaluation_form`) chamando helper após auth check. Migration `20260516810000` | `d415cb9` |
| get_evaluator_calibration_stats RPC | Cycle summary + per_evaluator (bias_signed/abs + anomaly_count) + pair_divergence top 5. MCP v2.66.0 expose. Migration `20260516820000` | `d415cb9` |
| localStorage onboarding → server-side | Tabela `member_quick_start_progress` + RPCs `get_my_quick_start_progress`/`upsert_my_quick_start_step`. Frontend onboarding.astro com merge offline+online + Wrangler deploy. Migration `20260516830000` | `215eacb` |
| blind review RLS de selection_evaluations | **Verified — already enforced via rpc_only_deny_all + v_blind logic em get_application_score_breakdown.** Defesa em profundidade equivalente. Closed sem migration. | n/a |

### Estado final p107

- **9 commits no main** (cf78d93 → 215eacb)
- **11 migrações** (`20260516710000` → `20260516830000`)
- **MCP v2.66.0** (268 tools, was 266)
- **2 Wrangler deploys** (Onda 2.5 + localStorage→RPC)
- **Invariants 12/12 = 0 violations**
- **5 P1 não-issue resolvidos (Onda 2)** + **3 P1 adicionais (post-Onda 2)** + **7 issues GitHub fechadas**

### Maturidade ARM atualizada

| ID | Pilar | Pré-p107 | Pós-p107 |
|----|-------|----------|----------|
| ARM-1 | Captação | 1 | 1+ (instrumentação UTM/referral_source pronta) |
| ARM-2 | Application | 2 | 2+ (dashboard candidato live) |
| ARM-4 | Evaluation Pipeline | 2 | 2+ (my_eval_status + calibration stats + invariant 12 + sync trigger) |
| ARM-7 | Onboarding | 2 | 2+ (cron overdue + cross-device persistence) |
| ARM-8 | Compliance & Audit | 3 | 3+ (consent_records + RLS hardening + audit_log immutability + pii_access_log dossier) |
| ARM-12 | Observability | 2 | 2+ (get_selection_health Pattern 43) |

ARM média estimada: ≈ 1.92 → ≈ 2.25.

---

## Onda 5 ARM-9 Foundation — Completion Report (2026-05-06 sessão p108)

**Status: G5 + G6 shipped. G1 reframed (não era drift), G7 (`withdrawn`) explicitly NOT added.**

### Reframes durante audit

1. **Substrato 2x mais maduro do que projetado.** ARM-9 reportado em maturidade 1, audit revelou ~2.5: `member_status` text+CHECK com 5 states + 3 triggers ativos + 17 RPCs + 3 crons LGPD + `member_offboarding_records` 19 campos + `offboard_reason_categories` 10 códigos com flags semânticos.
2. **G1 não era drift.** A row `VP Desenvolvimento Profissional (PMI-GO)` é placeholder institucional whitelisted em `check_schema_invariants` — design intencional, não bug.
3. **G6 invariant 13** complementa L (não substitui). L checa existência de offboarding record; N checa `offboarded_at NOT NULL` na própria row de `members` (defense-in-depth).
4. **`withdrawn` rejeitado**: `inactive` + reason `policy_violation` (com `is_volunteer_fault=true` + `preserves_return_eligibility=false`) já comunica caso unilateral.

### Entregáveis

| # | Item | Resolução | Migration |
|---|------|-----------|-----------|
| Foundation.1 | Backfill 14 terminal members com `offboarded_at NULL` | `COALESCE(status_changed_at, updated_at, created_at, now())` preservando whitelist | `20260516840000` |
| Foundation.2 | `validate_status_transition(p_from, p_to)` helper | IMMUTABLE function raises 22023 em (candidate ↔ terminal); self-transition idempotent | `20260516840000` |
| Foundation.3 | `admin_offboard_member` upgrade | Calls validate_status_transition; audit log entry `member.status_transition_blocked` em case de fail | `20260516840000` |
| Foundation.4 | Invariant N (`N_terminal_status_offboarded_at_present`) | Defense-in-depth complement to L. Total 13 invariants (was 12) | `20260516840000` |
| ADR | ADR-0071 Member Lifecycle State Machine | Formaliza state machine + transitions + Features path | `docs/adr/ADR-0071-*.md` |

### Estado pós-Foundation ARM-9

- 1 migration applied (`20260516840000`)
- Invariants **13/13 = 0 violations** (was 12/12)
- 5 alumni members com `offboarded_at` backfilled de NULL para tracked timestamps
- `validate_status_transition` smoke tests PASS (active→alumni allowed; active↔candidate blocked)
- 0 mudança user-facing visible (tighten apenas casos truly invalid)

### ARM-9 maturidade atualizada

| Phase | Maturidade |
|-------|------------|
| Pré-p108 | 2.5 (ajustado do reportado 1 após audit profundo) |
| Pós-Foundation p108 | 2.7 (state machine documentada + invariant + transition validation) |
| Target pós-Features (sessão dedicada) | 3.5 (re-engagement pipeline + alumni badge + inactivity cron) |

### Próxima sessão — ARM-9 Features (G2+G3+G4)

| # | Item | Esforço | Bloqueio |
|---|------|---------|----------|
| G2 | `re_engagement_pipeline` table + RPCs (staged → invited → declined/accepted) + cron quando ciclo abre | 3-4h | Decisão UI (admin curates list before notify alumni) |
| G3 | `certificates.type='alumni_recognition'` + auto-emit em `admin_offboard_member` quando reason preserves_return_eligibility | 2-3h | Decisão visual badge (Credly path?) |
| G4 | `detect_inactive_members` cron 180d configurável via `site_config.inactivity_threshold_days` | 2-3h | Threshold configuration UI |

Total Features: 7-10h. Standalone session recomendada.

### ARM media plataforma atualizada

ARM média ponderada: ≈ 2.25 (pós Onda 1+2+P1) → ≈ 2.30 (pós Foundation ARM-9). Ainda longe de target 3.0; ARM-1 (Captação maturidade 1) e ARM-5 (Interview maturidade 1) ainda dominam o cap.

---

## Onda 5 ARM-9 Features — Completion Report (2026-05-06 sessão p108 cont.)

**Status: G2 + G3 + G4 + Post-G2 shipped. ARM-9 completo. ADR-0071 amended.**

PM ratificou continuação na mesma sessão p108 com "tudo na recomendação". 4 migrations adicionais aplicadas.

### Entregáveis

| # | Item | Migration |
|---|------|-----------|
| G2.1 | ENUM `re_engagement_state` + tabela `re_engagement_pipeline` com state consistency CHECK + partial unique index | `20260516850000` |
| G2.2 | 5 RPCs: stage/list/invite/respond/cancel + trigger `trg_auto_stage_alumni_on_cycle_open` | `20260516850000` |
| G3 | `certificates.type='alumni_recognition'` + auto-emit em `admin_offboard_member` (graceful degradation) | `20260516860000` |
| G4 | `site_config.inactivity_threshold_days=180` + `detect_inactive_members` RPC + cron weekly | `20260516870000` |
| Post-G2 | `validate_status_transition` BLOCKS alumni→active + `admin_reactivate_member` guard (requires accepted pipeline entry) | `20260516880000` |

### Workflow completo alumni (full lifecycle)

```
saída amigável → alumni status (G3 auto badge)
       ↓ ciclo novo abre OU admin manual
staged → invited (notif + email) → accepted | declined
       ↓ accepted
admin_reactivate_member (guard: accepted pipeline) → active
```

### Estado pós-Features ARM-9

- 5 migrations ARM-9 totais (`20260516840000` → `20260516880000`)
- Invariants 13/13 = 0 violations (no regressions)
- 4 novas operações: stage, invite, respond, cancel + 1 cron + 1 trigger
- Tracker em `re_engagement_pipeline` (RLS rpc-only) com state machine enforced via CHECK
- Alumni badge automático em offboard amigável (`preserves_return_eligibility=true`)
- Inactivity detection weekly com manager-in-the-loop (não auto-transitiona)

### ARM-9 maturidade final

| Phase | Maturidade | Ship |
|-------|------------|------|
| Pré-p108 (reportado) | 1 | — |
| Pós-audit profundo | 2.5 | — |
| Pós-Foundation | 2.7 | p108 (Foundation) |
| Pós-Features | **3.5** | p108 (Features) |

### ARM media plataforma final p108

≈ 2.25 → ≈ 2.30 (Foundation) → **≈ 2.40** (Features). ARM-9 entrega +0.15 isolado.

Maturidades remanescentes em 1 ou 1.x:
- **ARM-1 Captação** (próxima sessão p109 conforme plano ABCD)
- **ARM-5 Interview** (depende #92/#116 Calendar — bloqueado)

### Pendentes (não-bloqueantes pós-Features ARM-9)

1. **MCP exposure** 5 RPCs novos (admin) + 1 alumni-self via nucleo-mcp. Esforço ~30min em sessão futura.
2. **Frontend UI** alumni `/me/re-engagement/[id]` + admin `/admin/members?filter=inactive_candidates`. Defer para Onda 4 browser session.
3. **i18n** novos notification types em 3 idiomas. Defer para próxima frontend session.

### Próxima sessão (p109) conforme plano ABCD

- **B) ARM-1 Captação deep dive** — landing `/volunteer` + interest form pré-cycle + UTM dashboard

---

## ARM-1 Captação — Completion Report (2026-05-06 sessão p108 cont.)

**Status: backend shipped + frontend ImpactPageIsland updated. ADR-0072 written.**

PM ratificou continuação direto do ARM-9 Features para ARM-1 na mesma sessão p108. Substrato MUITO mais maduro que projetado — `visitor_leads` table existia + RLS permite anon insert + form em /about já capturava (sem UTM/promote/funnel).

### Reframes durante audit

1. **Substrato parcial existia.** Reportado maturidade 1 baseado em "sem instrumentação UTM" — mas table + RLS + form já existiam. Real maturidade pré-p108 ≈ 1.5.
2. **`/volunteer` page rejected.** Em vez de criar nova rota, surface via `/about` existente que já tinha form. Reduz complexidade UI sem perda de valor.
3. **`get_volunteer_funnel` mention em memory** apontava para função inexistente. Criada nova `get_volunteer_funnel_stats` com nome distinto.

### Entregáveis

| # | Item | Resolução |
|---|------|-----------|
| Schema | ALTER `visitor_leads` + 8 colunas (utm_data, referrer_member_id, promoted/dismissed tracking, dedupe_email_normalized GENERATED) + 4 indexes + status CHECK | Migration `20260516890000` |
| RPC.1 | `capture_visitor_lead(p_payload jsonb)` — public anon-callable, LGPD consent + email format + idempotente | Migration |
| RPC.2 | `list_visitor_leads(p_status, p_chapter, p_limit)` — admin view | Migration |
| RPC.3 | `promote_lead_to_application(p_lead_id, p_cycle_id, p_pmi_id)` — admin promote a selection_application | Migration |
| RPC.4 | `dismiss_visitor_lead(p_lead_id, p_reason)` — admin discard | Migration |
| RPC.5 | `get_volunteer_funnel_stats(p_cycle_id)` — funnel breakdown leads + apps + by_source UTM + by_chapter | Migration |
| Frontend | `ImpactPageIsland.tsx` LeadCaptureForm refactor: direct insert → RPC + URL query UTM/referrer capture | `src/components/islands/ImpactPageIsland.tsx` |
| ADR | ADR-0072 ARM-1 Lead Capture & Funnel | `docs/adr/ADR-0072-*.md` |

### Estado pós-Captação ARM-1

- 1 migration (`20260516890000`)
- 5 RPCs (1 anon + 4 admin)
- 1 frontend file updated
- 4 indexes + 1 CHECK constraint
- Invariants 13/13 = 0 violations (no regressions)
- Build clean, tests baseline

### ARM-1 maturidade atualizada

| Phase | Maturidade |
|-------|------------|
| Pré-p108 (reportado) | 1 |
| Pós-audit (real) | 1.5 |
| Pós-Captação backend + frontend update | **3.0** |

### ARM media plataforma final p108

≈ 2.40 (pós ARM-9) → **≈ 2.55** (pós ARM-1). ARM-1 entrega +0.15 isolado.

Maturidades remanescentes em 1 ou 1.x:
- **ARM-5 Interview** (depende #92/#116 Calendar — bloqueado em PM action)

### Pendentes (não-bloqueantes pós ARM-1)

1. **Frontend `/admin/funnel` dashboard** com `get_volunteer_funnel_stats` — Onda 4 browser session
2. **MCP exposure** 5 RPCs ARM-1 + 6 RPCs ARM-9 (~1h batch próxima sessão)
3. **i18n** novos strings se UI futura criada
4. **Auto-promote cron** quando cycle abre (atualmente manual via promote_lead_to_application)

---

## Onda 3 AI Build — Completion Report (2026-05-06 sessão p108 cont. final)

**Status: 4/4 entregáveis shipped. ADR-0074 ratificado. Smoke validado em produção.**

PM ratificou Onda 3 AI Build (decisão 2 confirmada: B = Sonnet 4.6 + prompt cache rubrica). Foundation + Implementation + LGPD reinforcement em uma sessão. ARM-3 maturidade 2 → 3, ARM-11 AI Layer 2 → 3.

### Reframes durante audit

1. **Pipeline Gemini é complementar, não substituível.** Auditoria pré-shipping validou que `pmi-ai-analyze` (Gemini 2.5 Flash, qualitative narrative) tem features dedicadas que Sonnet 4.6 triage NÃO replica (raises_the_bar narrativo, key_strengths array, fields_changed diff). Decisão: dual-model — Gemini para qualitative, Sonnet 4.6 para scoring numérico, Haiku 4.5 para briefing on-demand.
2. **Anthropic structured outputs schema subset é estrito.** `minimum`/`maximum` em integer + `minItems`/`maxItems` em array retornam 400. Validação client-side é load-bearing. Captured em `feedback_anthropic_structured_output_schema_limits.md`.
3. **Cache mínimo Sonnet 4.6 é 2048 tokens.** Rubric atual (~600 tokens) abaixo do limite — não há cache hit. Custo real ~$0.020/call vs $0.0015 esperado com cache. Mitigação: enriquecer rubric ou aceitar pricing sem cache (~$1.60/ciclo n=80).

### Entregáveis

| # | Item | Resolução |
|---|------|-----------|
| 1 | `ai_processing_log` table (LGPD Art. 37 audit) | Migration `20260516930000`. RLS rpc-only. NUNCA conteúdo (só hashes SHA-256 + tokens + duration). 3 indexes. CHECK em status/purpose/model_provider. |
| 2 | `selection_applications` triage cols | +5 cols: `ai_triage_score 0-10` + `ai_triage_reasoning ≤500c` + `ai_triage_confidence high\|medium\|low` + `ai_triage_at` + `ai_triage_model`. CHECK constraints. |
| 3 | EF `pmi-ai-triage` (deployed v1) | Anthropic Sonnet 4.6 + prompt cache rubric. Consent gate respeitado (consent_ai_analysis_at NOT NULL + non revoked). Retry exponencial 429/529/500. Score NON-BINDING per LGPD Art. 20 §1. |
| 4 | MCP nucleo-mcp v2.68.0 (282 tools) | `analyze_application` (admin invoke pmi-ai-triage) + `generate_interview_briefing` (Haiku 4.5 inline ~1-3s sync) + `list_ai_processing_log` (admin observability). |
| ADR | ADR-0074 dual-model AI architecture | Formaliza arquitetura + LGPD Art. 20 §1 garantias + cost analysis. |
| Follow-up | `_trg_purge_ai_analysis_on_consent_revocation` extended | Migration `20260516940000`. Trigger purga `ai_triage_*` em consent revoke. ai_processing_log retained per Art. 16. |

### Smoke validation (2026-05-06 pós-deploy)

| Caso | App | Score | Confidence | Latency | Resultado |
|------|-----|-------|-----------|---------|-----------|
| Rich data | LUIZ RAMOM (5385c motivation, MBAs FGV+CP3P+mestrado, 14a setor público) | **6** | medium | 7.0s | ✓ "sólida, track record moderado" — calibração precisa |
| Thin data | THAYANNE (91c motivation) | **1** | high | 4.3s | ✓ "genérica, sem evidência" — modelo confidence alto na avaliação baixa |

input_tokens 5587, output 185, ai_processing_log row completed. cache_creation/read=0 (rubric < Sonnet 4.6 2048 mínimo). Custo real ~$0.020/call → ~$1.60/ciclo n=80 (dentro estimativa $1-2 ADR).

### Estado pós-Onda 3

- 2 migrations Onda 3 totais (`20260516930000` + `20260516940000`)
- Invariants 13/13 = 0 violations (no regressions)
- 1 EF deployed (pmi-ai-triage v1)
- 1 EF redeployed (nucleo-mcp v2.68.0, 282 tools — was 279)
- ai_processing_log com 2+ rows (LUIZ RAMOM completed + THAYANNE completed + 1 failed pre-fix)
- 2 selection_applications com ai_triage_* populated

### ARM maturidade pós-Onda 3

| ID | Pilar | Pré-Onda 3 | Pós-Onda 3 |
|----|-------|------------|------------|
| ARM-3 | Triage | 2 | **3** (pre-screen scoring funcional + LGPD compliant + observable) |
| ARM-5 | Interview | 1 | **2** (briefing assistivo entregue; agendamento depende #92/#116 PM action) |
| ARM-11 | AI Layer | 2 | **3** (dual-model + cross-purpose audit + LGPD-grade observability) |

### ARM media plataforma final p108

≈ 2.55 (pós ARM-1) → **≈ 2.65** (pós Onda 3). Onda 3 entrega +0.10 isolado. Maturidade média ainda longe de target 3.0; ARM-5 (Interview) ainda em 1.x dependente #92/#116.

### Pendentes (não-bloqueantes pós-Onda 3)

1. **PM action**: setar `ANTHROPIC_API_KEY` Supabase secret ✅ FEITO (smoke confirmou).
2. **PM action**: atualizar Supabase CLI binary 2.95.4 → 2.98.2 (sudo, sistema) — opcional.
3. **Frontend admin/selection inline AI panel** — tab "Análises IA" deprecated em favor de panel inline mostrando triage_score + reasoning + confidence + Gemini qualitative + briefing button (Onda 4 browser session).
4. **i18n notification types em 3 idiomas** — `re_engagement_invitation`, `_accepted`, `_declined`, `arm9_inactivity_alert`, `certificate_issued`. ~24 strings. Defer para próxima frontend session.
5. **Auto-triage cron** quando consent dá cure ou ciclo abre — defer até PM ratificar UX inline.
6. **Calibration delta** — cron weekly comparando `ai_triage_score` vs `final_score` humano para detectar drift e flag manual recalibration.

### Próximas sessões — disparadores

| Sessão | Trigger | Modo |
|--------|---------|------|
| p109 | "Onda 4 evaluator UX inline AI" | Browser session |
| p109 | "i18n batch ARM-9 + AI notifications" | Autonomous |
| p110+ | "Onda 5 ARM-5 deep dive" | Bloqueado por #92/#116 |
| p110+ | "calibration delta cron" | Autonomous backend |


