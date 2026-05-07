# ADR Index

Este diretório separa decisões técnicas duráveis das notas de governança geral.

## Como usar

- Cada ADR deve focar em uma decisão arquitetural específica.
- O formato é curto: contexto, decisão, consequências.
- Quando a decisão mudar, criar um novo ADR que substitui o anterior (não reescrever histórico).

## ADRs ativos

- `ADR-0001-source-of-truth-and-cycle-history.md` — Hub como fonte única de verdade + separação snapshot/histórico.
- `ADR-0002-role-model-v3-operational-role-and-designations.md` — Modelo v3 (substituído por ADR-0007).
- `ADR-0003-admin-analytics-internal-readonly-surface.md` — `/admin/analytics` como leitura interna sem abrir trilhas de escrita.
- `ADR-0010-wiki-scope-narrative-knowledge-only.md` — Fronteira wiki vs SQL: wiki só para conhecimento narrativo (ADRs, governança), dados operacionais ficam em SQL.
- `ADR-0011-v4-auth-pattern-rpcs-mcp.md` — `can()` / `can_by_member()` é a única fonte de verdade de autoridade em todas as camadas (RPC, MCP, RLS). Padrão canônico pós-V4, substitui role list hardcoded.
- `ADR-0012-schema-consolidation-principles.md` — Single source of truth por conceito + cache columns com trigger de sync explícito. Elimina drift silencioso como o caso Wellington 16/Abr (3 colunas para o mesmo status).
- `ADR-0013-log-table-taxonomy.md` — Taxonomia em 5 categorias (Admin Audit / Domain Lifecycle / High-Volume / Distinct Retention / External Ingestion) para decidir quando uma tabela log consolida em `admin_audit_log` vs existe separada. Fecha a questão deixada aberta por ADR-0012 P5 + B8.
- `ADR-0014-log-retention-policy.md` — Janelas de retenção (archive/purge) por categoria do ADR-0013: Cat A 5y→archive+7y→drop; Cat B indefinido; Cat C 90-180d drop; Cat D 5y anonymize+6y drop (LGPD Art. 37); Cat E 180d-2y drop. RPC `purge_expired_logs` + pg_cron mensal.
- `ADR-0015-tribes-bridge-consolidation.md` — Deprecação do `tribe_id` legacy em 11 tabelas droppable (C3: events, announcements, webinars, etc.), mantendo 7 bridge-locked (C2: tribe_deliverables, member_cycle_history) + `tribes` table + `members.tribe_id` (C4 deferred). Plano em 5 fases multi-sessão.
- `ADR-0016-ip-ratification-governance-model.md` — Modelo de ratificação multi-gate de documentos de governança: gates como data + autoridade em camadas + assinatura externa + imutabilidade de versões. Fundamenta o subsistema CR-050 / IP Policy.
- `ADR-0017-schema-code-contract-audit-methodology.md` — Checklist obrigatório pré-`DROP COLUMN`: audit pg_proc.prosrc + views + policies + triggers + EFs + frontend. Padroniza dimensões de busca para evitar falsos-negativos (origens das issues #79/#80). **Status: Accepted (2026-04-24 p43) — ratificada pela prática: sessões p40-p43 seguiram a metodologia sem regressão tipo #79/#80.**
- `ADR-0018-mcp-threat-model.md` — Análise de risco do `nucleo-mcp` (EF + Cloudflare proxy) contra vulnerabilidade MCP reportada em abril/2026. Vetores aplicáveis vs não-aplicáveis, mitigações canônicas (OAuth 2.1, CSRF middleware, canV4 gate). **Status: Accepted (2026-04-24 p44 R+T+W3+S) — todas as mitigações shipped**: **W1 confirmation step (MCP v2.24.0, Track R)** (5 destructive tools default to preview); **W2 rate limit no Cloudflare Worker (`src/lib/mcp-rate-limit.ts` + `src/pages/mcp.ts`, Track S)** (100/min general + 10/min destructive, KV counters, caveat eventual consistency); **W3 anomaly detection cron (migration `20260511020000`, pg_cron `mcp-anomaly-detection-15min`, Track W3)** (4 patterns, alerts em admin_audit_log).
- `ADR-0019-portfolio-as-projection-principle.md` — Portfólio executivo é VIEW agregada sobre `board_items.is_portfolio_item=true`, NÃO entidade com lifecycle próprio. Não existe workflow formal de "portfolio request/approval" — governance via board tier + audit log. **Status: Accepted (2026-04-24 p43) — D1 enforcement presente em `update_board_item`, D3 6 event types ativos em `board_lifecycle_events`, D6 tools expostas. D5 cron e D7 coluna opcional continuam explicitamente opt-in.**
- `ADR-0020-publication-pipeline.md` — Pipeline unificado de publicação: `publication_ideas` + `publication_series` como primitivos. Consolida 5 flows paralelos (hub_resources, wiki, submissions, publications, newsletter). Inspirado em padrões de 10 cases de mercado. **Status: Proposed.**
- `ADR-0021-newsletter-frontiers-governance.md` — Addendum operacional ao Pipeline (ADR-0020) para Newsletter "Frontiers in AI & Project Mgmt". Decisões editoriais + operacionais + licensing + cadência biweekly + trilíngue. **Status: Partially Accepted, pending Termo R3.**
- `ADR-0022-communication-batching-weekly-digest-default.md` — Weekly digest é default; transactional email é exceção. Governa integrações de notificação (issues #97, #98, #88, #91). **Status: Proposed.**
- `ADR-0023-sync-operational-role-cache-trigger-contract.md` — Contrato formal do `sync_operational_role_cache()` trigger: priority ladder canônica, paridade mandatória com invariant A3, fast-path usages (Amendment A de ADR-0011), regras de amendment.
- `ADR-0024-public-members-view-accepted-risk.md` — `public_members` view: aceitação formal do risco advisor (SECURITY DEFINER VIEW) + path slim futuro.
- `ADR-0025-manage-finance-v4-action.md` — Nova V4 action `manage_finance` (Phase B'' conversion).
- `ADR-0026-manage-comms-v4-action.md` — Nova V4 action `manage_comms` (Phase B'' conversion).
- `ADR-0027-governance-readers-v4-conversion.md` — 3 governance readers V3→V4 (Phase B'').
- `ADR-0028-service-role-bypass-adapter-pattern.md` — Padrão canônico V4 para fns chamáveis via cron/EF (service_role) E por usuários admin. Adapter pattern: `IF auth.role()='service_role' THEN bypass; ELSE can_by_member(...)`. Enforcement em 4 camadas (allowlist + size guard + COMMENT sentinel + invariant G novo). Conceitualmente "ADR-0011 Amendment C" mas standalone para discoverability. **Status: Accepted (ratified 2026-04-26 p64 via Opção A council-validated).** Scope amended Pacote M: 5 fns OK convertidas (admin_capture_data_quality_snapshot, admin_check_ingestion_source_timeout, admin_set_ingestion_source_sla, admin_set_release_readiness_policy, admin_get_ingestion_source_policy). 32 dead-code fns dropadas via ADR-0029.
- `ADR-0029-ingestion-subsystem-retroactive-retirement.md` — Retroactive retirement record do ingestion/release-readiness/governance-bundle subsystem (14 substrate tables + 32 dead-code SECDEF functions). DDL drift acidental confirmado via P4 council investigation (security-engineer + accountability-advisor). Zero telemetria operacional 90 dias. Acknowledgment formal do governance gap (drops historicos via Dashboard/execute_sql fora da disciplina apply_migration). Forensic preservation via migration files + git log. **Status: Accepted (PM-ratified 2026-04-26 p64, retroactive).**
- `ADR-0030-view-internal-analytics-v4-action.md` — Nova V4 action `view_internal_analytics` (Phase B'').
- `ADR-0031-admin-list-members-v4-conversion.md` — `admin_list_members` V3→V4 reuse `view_internal_analytics` (Opção B).
- `ADR-0032-board-admin-v4-conversion.md` — Board admin fns V4: nova action `manage_board_admin` + reuse `view_internal_analytics`.
- `ADR-0033-partner-subsystem-v4-conversion.md` — Partner subsystem V4 Phase 1 reuse `manage_partner`; Phase 2 deferred.
- `ADR-0034-partner-attachments-v4-conversion.md` — Partner attachments V4 Phase 2 + drift signals #5 #6 closure.
- `ADR-0035-analytics-dashboards-and-no-gate-hardening.md` — Analytics dashboards V4 + no-gate hardening (`view_internal_analytics`).
- `ADR-0036-get-member-detail-v4-conversion.md` — `get_member_detail` V4 Opção B reuse `view_internal_analytics`.
- `ADR-0037-chapter-needs-and-org-chart-v4-conversion.md` — Chapter needs + org chart V4 + Path Y chapter_board preservation.
- `ADR-0038-p68-cleanup-batch-and-security-fixes.md` — p68 cleanup: 1 V3→V4 zero-drift convert + 2 security drift corrections.
- `ADR-0039-volunteer-agreement-countersign-subsystem-and-attendance-batch-fix.md` — Countersign subsystem 100% V4 (Path Y precedent) + `register_attendance_batch` security drift fix.
- `ADR-0040-p70-cleanup-helper-batch.md` — p70 cleanup: DROP dead helper + REVOKE-from-anon em 3 internal helpers.
- `ADR-0041-participate-in-governance-review-action.md` — Nova V4 action `participate_in_governance_review` (curation cluster, 9 fns).
- `ADR-0042-view-chapter-dashboards-action.md` — Nova V4 action `view_chapter_dashboards` (sponsor + chapter_board) + `_can_manage_event` helper conversion.
- `ADR-0043-finance-v4-and-sponsor-notification-safeguard.md` — `create_cost_entry` + `create_revenue_entry` V3→V4 + sponsor finance notification safeguard.
- `ADR-0044-manual-version-2-of-n-approval.md` — `generate_manual_version` V3→V4 + 2-of-N approval pattern.
- `ADR-0045-meeting-board-traceability-schema-hardening.md` — Meeting↔Board traceability schema hardening (#84 Onda 1).
- `ADR-0046-action-item-lifecycle-rpcs.md` — Action item lifecycle RPCs (#84 Onda 2 partial).
- `ADR-0047-card-history-action-conversion-decisions.md` — Card history + action conversion + decisions (#84 Onda 2 cont.).
- `ADR-0048-get-meeting-preparation.md` — `get_meeting_preparation` RPC (#84 Onda 2 cont., 7/10).
- `ADR-0049-meeting-board-traceability-onda-2-closure.md` — Meeting↔Board traceability Onda 2 closure (4/4 RPCs final).
- `ADR-0050-gamification-leaderboard-v2-and-opt-out.md` — `gamification_leaderboard` v2 + member opt-out.
- `ADR-0051-gamification-leaderboard-scope-filter.md` — `gamification_leaderboard` v3: scope filter (chapter/tribe).
- `ADR-0052-drop-duplicate-indexes-perf-cleanup.md` — DROP 12 duplicate indexes — perf cleanup.
- `ADR-0053-auth-rls-initplan-batch-1.md` — `auth_rls_initplan` perf fix batch 1 (#82 P1 deferred).
- `ADR-0054-auth-rls-initplan-batch-2.md` — `auth_rls_initplan` perf fix batch 2 (#82 P1).
- `ADR-0055-auth-rls-initplan-batch-3.md` — `auth_rls_initplan` perf fix batch 3 (Class D superadmin EXISTS).
- `ADR-0056-auth-rls-initplan-batch-4.md` — `auth_rls_initplan` perf fix batch 4 (Class E `can_by_member` subquery).
- `ADR-0057-auth-rls-initplan-batch-5-final.md` — `auth_rls_initplan` perf fix batch 5 FINAL (fecha 100% de #82 P1).
- `ADR-0058-multiple-permissive-policies-cleanup.md` — `multiple_permissive_policies` cleanup (P2 RLS perf class).
- `ADR-0059-selection-phase-blind-review-anti-bias.md` — Selection cycle phase state machine + blind review enforcement (anti-bias).
- `ADR-0060-g7-engagement-welcome-email-trigger.md` — Welcome email automatizado em engagements INSERT (#97 G7).
- `ADR-0061-initiative-invitations-foundation.md` — Initiative invitation flow + scope-bound permissions (#88 Foundation).
- `ADR-0062-gamification-streak-and-cycle-points.md` — #101 P2 final: gamification streak + cycle points aggregate stats.
- `ADR-0063-whatsapp-mcp-non-use-policy.md` — WhatsApp MCP non-use policy in production. **Status: Accepted (2026-04-28).**
- `ADR-0064-drive-integration-domain-wide-delegation.md` — Drive integration write path: OAuth Refresh Token (Path F amend). **Status: Accepted (2026-04-28), amended same day para Path F.**
- `ADR-0065-drive-phase-4-auto-discovery-atas.md` — Drive Phase 4: auto-discovery atas via cron + filename heuristic. **Status: Accepted (2026-04-28).**
- `ADR-0066-pmi-journey-v4-phase-1.md` — PMI Journey v4 Phase 1: Cloudflare worker + token-auth portal substrate. **Status: Accepted (2026-04-28); Amendment 2026-04-29 (passive ingest pivot); Amendment 2 2026-05-01 (Phase 2 trigger + workflow gate gap surfacing).**
- `ADR-0067-ai-augmented-selection-art20-safeguards.md` — AI-Augmented Selection: LGPD Art. 20 safeguards + human-in-the-loop invariant.
- `ADR-0068-governance-docs-curadoria-redraft-framework.md` — Governance docs curadoria redraft framework (Path A/B + Material/Editorial change). **Status: Proposed (2026-05-01) — aguardando ratificação curadores + revisão advogado humano licenciado.**
- `ADR-0069-artia-bidirectional-sync-pattern.md` — Artia bidirectional sync pattern (PMO PMI-GO portfolio).
- `ADR-0070-external-speaker-artifact-conventions.md` — External speaker artifact conventions (engagement schema hardening).
- `ADR-0071-member-lifecycle-state-machine.md` — Member lifecycle state machine (ARM-9 foundation).
- `ADR-0072-arm1-lead-capture-funnel.md` — ARM-1 lead capture funnel (visitor_leads enrichment).
- `ADR-0073-issue116-calendar-booking-sync-apps-script.md` — #116 calendar booking sync via Apps Script.
- `ADR-0074-onda3-arm-dual-model-ai-architecture.md` — ARM Onda 3 dual-model AI architecture (Sonnet 4.6 triage + Haiku 4.5 briefing + Gemini qualitative legacy).
- `ADR-0075-cv-extraction-pipeline.md` — CV extraction pipeline: Deno + unpdf EF + cron 15min + lazy fallback in pmi-ai-triage. Audit revelou backlog actionable = 0 hoje (todos "órfãos" sem consent); pipeline forward-looking. **Status: Accepted (2026-05-07 — smoke 3 paths PASS, Amendment A documenta evidence).**

## Domain Model V4 — Refatoração Arquitetural (Complete, 2026-04-13)

Pacote coeso que refez o modelo de domínio para habilitar: plataforma nacional, multi-org, governança máxima, LGPD by design, e extensibilidade via configuração. Deve ser lido em ordem.

- `ADR-0004-multi-tenancy-posture.md` — Organizations como entidade first-class.
- `ADR-0005-initiative-as-domain-primitive.md` — Initiative substitui Tribe como contêiner raiz.
- `ADR-0006-person-engagement-identity-model.md` — Person + Engagement substituem members catch-all.
- `ADR-0007-authority-as-engagement-grant.md` — Autoridade derivada de engagements ativos (substitui ADR-0002).
- `ADR-0008-per-kind-engagement-lifecycle.md` — Lifecycle e base legal LGPD como config por kind.
- `ADR-0009-config-driven-initiative-kinds.md` — Extensibilidade por configuração, não por código.

**Histórico de execução:** ver `docs/refactor/DOMAIN_MODEL_V4_MASTER.md`. Concluído em 7 fases, 30 migrations, 2026-04-11 → 2026-04-13.

## Processo mínimo

1. Criar novo ADR em `docs/adr/`.
2. Atualizar este índice.
3. Registrar o sprint em `docs/RELEASE_LOG.md` e `docs/GOVERNANCE_CHANGELOG.md`.
