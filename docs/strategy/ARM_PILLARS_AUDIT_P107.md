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
