# Release Log
## 2026-03-08 — Planning Update (Data Scalability & DB Governance Queue)

### Scope
Consolidate database-focused recommendations into explicit production queue items and architecture governance artifacts.

### Decisions registered
- created roadmap:
  - `docs/migrations/DATA_SCALABILITY_ROADMAP.md`
- backlog queue additions:
  - `S-DB2` Executive MViews
  - `S-DB3` High-volume Index Audit
  - `S-DB4` Vector Index Strategy v2
  - `S-DB5` Embedding Refresh Lifecycle
  - `S-DB6` Audit Trail Schema
  - `S-DB7` Soft-delete Parity
- SQL board alignment:
  - registered DB scalability track items with explicit delivery gate (`migration + audit + rollback + runbook`)
  - linked data roadmap as canonical reference for next DB interventions

## 2026-03-08 — Planning Update (Frontend Hardening & Production Queue)

### Scope
Consolidate technical diagnosis into executable governance items for frontend resiliency, security, and maintainability.

### Decisions registered
- created roadmap:
  - `docs/FRONTEND_HARDENING_ROADMAP.md`
- backlog queue updated with planned sprints:
  - `S-FE1` XSS/DOM safety baseline
  - `S-FE2` admin modularization
  - `S-FE3` auth SSR gate
  - `S-FE4` executive RPC binding
- technical debt register updated:
  - imperative DOM/XSS surface
  - admin monolith complexity
  - client-side auth flicker
- SQL board aligned with execution path:
  - `S-FE4` linked as frontend binding over already delivered SQL models

## 2026-03-08 — Wave 4 Sprint Increment (S-PA2 Executive ROI Dashboards v1 SQL Foundation)

### Scope
Build production-ready SQL architecture for executive product/ROI dashboards in admin.

### Delivered
- migration pack created:
  - `supabase/migrations/20260308102010_exec_roi_dashboards_v1.sql`
  - views:
    - `vw_exec_funnel`
    - `vw_exec_cert_timeline`
    - `vw_exec_skills_radar`
  - RPCs (admin+ gated by `has_min_tier(4)`):
    - `exec_funnel_summary()`
    - `exec_cert_timeline(p_months)`
    - `exec_skills_radar()`
- docs pack created:
  - `docs/migrations/exec-roi-dashboards-v1.sql`
  - `docs/migrations/exec-roi-dashboards-v1-audit.sql`
  - `docs/migrations/exec-roi-dashboards-v1-rollback.sql`
  - `docs/migrations/EXEC_ROI_DASHBOARDS_V1_RUNBOOK.md`

### Pending to close S-PA2
- apply migration in production
- run post-audit and attach evidence
- wire `/admin` executive panel to RPCs (replace client-only aggregation path)

## 2026-03-08 — Wave 5 Sprint Increment (S-KNW8 Friction & Insight Mining v1 Foundation)

### Scope
Start the SQL architecture for friction/insight mining so roadmap prioritization can use structured evidence instead of ad-hoc notes.

### Delivered
- migration pack created:
  - `supabase/migrations/20260308043820_knowledge_insights_v1.sql`
  - table: `knowledge_insights`
  - taxonomy columns (`insight_type`, `taxonomy_area`) and scoring (`impact`, `urgency`, `confidence`)
  - review lifecycle fields (`status`, `reviewed_at`, `reviewed_by`)
  - RLS + ACL policies (`knowledge_insights_read`, `knowledge_insights_manage`)
- analytical RPCs created:
  - `knowledge_insights_overview(status, days)`
  - `knowledge_insights_backlog_candidates(status, limit)`
- docs pack created:
  - `docs/migrations/knowledge-insights-v1.sql`
  - `docs/migrations/knowledge-insights-v1-audit.sql`
  - `docs/migrations/knowledge-insights-v1-rollback.sql`
  - `docs/migrations/KNOWLEDGE_INSIGHTS_V1_RUNBOOK.md`

### Pending to close S-KNW8
- apply migration in production
- run audit SQL in production and attach evidence

### Completion update (same day, ACL hardening)
- production migration applied:
  - `20260308043820_knowledge_insights_v1.sql`
- post-audit evidence captured:
  - table/index/policies/functions present
  - smoke queries running without errors
- ACL hardening added:
  - `supabase/migrations/20260308083610_knowledge_insights_acl_hardening_v1.sql`
  - removes `anon/public` execute from:
    - `knowledge_insights_overview(...)`
    - `knowledge_insights_backlog_candidates(...)`

### Completion update (same day, operational sync v1)
- edge function created:
  - `supabase/functions/sync-knowledge-insights/index.ts`
  - heuristic extraction from `knowledge_chunks` into `knowledge_insights`
  - idempotent insert behavior via dedup key strategy
  - run ledger writes in `knowledge_ingestion_runs` (`source='insights'`)
- scheduler workflow created:
  - `.github/workflows/knowledge-insights-auto-sync.yml`
- runbook created:
  - `docs/migrations/KNOWLEDGE_INSIGHTS_SYNC_RUNBOOK.md`

## 2026-03-08 — Wave 5 Sprint Increment (S-KNW7 Internal Assistant v1)

### Scope
Deliver first internal assistant surface (`/ai-assistant`) using low-cost textual retrieval over ingested knowledge.

### Delivered
- new route:
  - `/ai-assistant` with authenticated gate and citations-first result cards
  - profile drawer shortcut to assistant for signed-in users
- retrieval flow:
  - query form + optional source filter
  - recent source listing via `knowledge_assets_latest(...)`
  - search via `knowledge_search_text(...)`
- SQL pack completed:
  - `supabase/migrations/20260308042540_knowledge_assistant_v1.sql`
  - `docs/migrations/knowledge-assistant-v1.sql`
  - `docs/migrations/knowledge-assistant-v1-audit.sql`
  - `docs/migrations/knowledge-assistant-v1-rollback.sql`

### Pending to close S-KNW7
- apply `knowledge-assistant-v1` migration in production
- run post-audit SQL and attach evidence
- smoke test `/ai-assistant` against production dataset

## 2026-03-08 — Wave 5 Sprint Increment (S-KNW6 Knowledge Ingestion v1 Foundation)

### Scope
Start YouTube-first knowledge ingestion foundation with low-cost architecture guardrails.

### Delivered
- migration pack created:
  - `supabase/migrations/20260308041010_knowledge_ingestion_v1.sql`
  - tables: `knowledge_assets`, `knowledge_chunks`, `knowledge_ingestion_runs`
  - optional `pgvector` enablement (`extensions.vector`)
  - RLS + ACL helper `can_manage_knowledge()`
  - RPCs: `knowledge_assets_latest(...)`, `knowledge_search(...)`
- edge function created:
  - `supabase/functions/sync-knowledge-youtube/index.ts`
  - secret-gated batch ingestion (`SYNC_KNOWLEDGE_INGEST_SECRET`)
  - dry-run support and ingestion run logging
- docs pack created:
  - `docs/migrations/knowledge-ingest-v1.sql`
  - `docs/migrations/knowledge-ingest-v1-audit.sql`
  - `docs/migrations/knowledge-ingest-v1-rollback.sql`
  - `docs/migrations/KNOWLEDGE_INGEST_V1_RUNBOOK.md`

### Pending to close S-KNW6
- apply migration in production
- deploy function in production
- run smoke/audit and attach evidence

### Completion update (same day, production rollout)
- migration applied in production:
  - `supabase/migrations/20260308041010_knowledge_ingestion_v1.sql`
- function deployed in production:
  - `sync-knowledge-youtube` (`--no-verify-jwt`)
- secret configured:
  - `SYNC_KNOWLEDGE_INGEST_SECRET`
- smoke evidence:
  - dry-run `HTTP 200` (`rows_valid: 1`, `rows_invalid: 0`)
  - insert run `HTTP 200` (`rows_upserted: 1`, `rows_chunked: 1`)

## 2026-03-08 — Planning Update (AI Knowledge Hub fit-to-strategy)

### Scope
Evaluate AI ingestion/RAG proposal against current scalability, UX and no-cost constraints, then map it into waves/sprints.

### Decision
- Proposal is **aligned** with platform direction when executed incrementally.
- Guardrails are mandatory:
  - YouTube-first MVP
  - batch ingestion (no realtime LLM in critical UI)
  - explicit budget/usage controls before multi-source scale

### Planning updates applied
- backlog updates:
  - `S-KNW6` AI Knowledge Ingestion MVP
  - `S-KNW7` Internal RAG Assistant
  - `S-KNW8` Friction Insight Mining
  - `S-OPS2` AI Cost Guardrails
- SQL architecture board updated with required data model/RPC work for these items.

## 2026-03-08 — Governance Automation (GitHub Project metadata sync)

### Scope
Automate Project governance metadata updates on `main` merges and manual issue-driven updates.

### Delivered
- workflow added:
  - `.github/workflows/project-governance-sync.yml`
- sync script added:
  - `scripts/sync-project-metadata.sh`
- project governance docs updated:
  - `docs/GITHUB_PROJECT_GOVERNANCE.md`
- project #1 metadata backfill completed:
  - module, work-origin, issue link, commit hash, commit timestamp, last update, delivery mode
  - done/in-progress/backlog items normalized

### Validation captured
- workflow YAML parsed successfully
- project fields and item metadata audited via `gh project item-list`

## 2026-03-08 — Hotfix (Profile actions hardening v2)

### Scope
Fix non-responsive profile actions for secondary email and Credly verification in production.

### Delivered
- `/profile` action handling hardened:
  - event delegation on stable `#profile-content` container
  - profile card controls moved away from fragile inline click paths
  - readiness fallback toasts when session/member context is not yet available
- governance updates:
  - `docs/DEBUG_HOLISTIC_PLAYBOOK.md`
  - `.github/pull_request_template.md` with mandatory regression checklist

### Validation captured
- local `npm run build` passed
- local `npm test` passed

## 2026-03-08 — Wave 4 Sprint Increment (S-COM10 Publish Log Filters & Export v1)

### Scope
Improve comms publish operations with faster audit navigation and pending visibility by channel.

### Delivered
- `/admin/comms/data-entry` publish workflow enhancements:
  - pending summary by `metric_date + source`
  - pending indicators grouped by channel
  - publish log filters by `source`, `from`, `to`
  - CSV export for filtered publish log rows
- i18n parity updates (PT/EN/ES) for new publish-log controls:
  - source/date filters
  - apply filters action
  - export CSV action

### Validation captured
- local `npm run build` passed
- local `npm test` passed

## 2026-03-08 — Wave 4 Sprint Increment (S-COM9 Publish Workflow & Audit v1)

### Scope
Add operational publish workflow for comms batches with explicit audit trail and SQL-backed controls.

### Delivered
- DB workflow migration:
  - `supabase/migrations/20260308012510_comms_metrics_v3_publish_workflow.sql`
  - extends `comms_metrics_daily` with:
    - `published_at`
    - `published_by`
    - `publish_batch_id`
  - creates `comms_metrics_publish_log`
  - adds RPC `publish_comms_metrics_batch(source, metric_date)` with admin-tier guard
- `/admin/comms/data-entry` publish block:
  - pending rows view (`manual_csv` / `manual_admin`)
  - publish action by source/date via RPC
  - recent publish log table
  - status feedback and toast integration
- SQL governance docs added:
  - `docs/migrations/comms-metrics-v3-publish-workflow.sql`
  - `docs/migrations/comms-metrics-v3-publish-workflow-audit.sql`
  - `docs/migrations/comms-metrics-v3-publish-workflow-rollback.sql`
  - `docs/migrations/COMMS_METRICS_V3_RUNBOOK.md`

### Validation captured
- local `npm run build` passed
- local `npm test` passed

## 2026-03-08 — Wave 4 Sprint Increment (S-COM8 CSV Import v1)

### Scope
Add batch ingestion UX for communications metrics with CSV preview and controlled publish.

### Delivered
- extended `/admin/comms/data-entry` with CSV flow:
  - file input (`.csv`)
  - parser for quoted CSV lines and canonical headers
  - preview table for valid rows
  - invalid-row count reporting
  - batch upsert into `comms_metrics_daily` (`source=manual_csv`)
- maintained idempotent behavior:
  - `upsert` by `metric_date + channel + source`
- i18n parity for PT/EN/ES:
  - CSV labels, statuses, and error messages

### Validation captured
- local `npm run build` passed
- local `npm test` passed

## 2026-03-08 — Wave 4 Sprint Increment (S-COM7 Data Entry v1)

### Scope
Start no-code comms operations flow so the communications team can publish daily metrics directly from admin.

### Delivered
- route refactor for comms pages:
  - moved `/admin/comms` file to `src/pages/admin/comms/index.astro` (same URL)
  - added new protected route `/admin/comms/data-entry`
- new `/admin/comms/data-entry` capabilities:
  - ACL gate aligned with admin analytics tier (`admin+`)
  - manual form for `metric_date`, `channel`, `audience`, `reach`, `engagement_rate`, `leads`
  - idempotent `upsert` into `comms_metrics_daily` using `metric_date + channel + source`
  - controlled delete for selected row (`manual_admin` source)
  - quick date actions (today/yesterday) and recent-entry table
- UX linking updates:
  - added `Lançar Dados / Enter Data` button in `/admin/comms`
  - added secondary CTA in `/admin` reports comms card to open data-entry route
- i18n parity:
  - new PT/EN/ES keys for comms data-entry journey and actions

### Validation captured
- local `npm run build` passed
- local `npm test` passed

### Follow up still required
- `S-COM8`: CSV import with preview/validation and batch publish flow
- `S-COM9`: publish workflow + stronger audit trail (who approved batch) in UI

## 2026-03-08 — Wave 4 Sprint Increment (S-COM6 Media Dashboard v1)

### Scope
Start dedicated communications analytics surface for media operations in admin workflows.

### Delivered
- created protected communications route:
  - `/admin/comms`
  - ACL gate aligned to admin analytics access (`admin+`)
- new media card in `/admin` reports panel linking to `/admin/comms`
- dedicated comms dashboard embed with env configuration:
  - `PUBLIC_LOOKER_COMMS_DASHBOARD_URL`
- added missing-config fallback, external-open link, and denied/loading states
- i18n keys added in PT/EN/ES for new reports card and comms route copy

### Validation captured
- local `npm run build` passed
- local `npm test` passed

### Follow up still required
- connect final Looker Studio dashboard with YouTube + LinkedIn/Instagram pipeline
- add KPI summary tiles above iframe (followers growth, reach, engagement, leads)

### Completion update (same day, v2 KPI band)
- added KPI summary band above the comms dashboard iframe in `/admin/comms`:
  - audience
  - reach
  - engagement
  - leads
- KPI loader supports configurable JSON endpoint:
  - `PUBLIC_COMMS_KPI_API_URL`
- added manual refresh action and status line with last-update timestamp
- resilient payload parser accepts common metric key variants (`metrics`/`kpis` roots)
- i18n keys added for KPI copy in PT/EN/ES
- local `npm run build` and `npm test` passed

### Completion update (architecture governance)
- added SQL architecture decision board:
  - `docs/migrations/SQL_ARCH_NEEDS_BOARD.md`
- board now tracks per-feature backend reality (`DB-backed` vs `Frontend/Embed`) and explicit SQL gaps
- established sprint gate: features marked as `Needs SQL` cannot be considered complete without migration/audit/rollback artifacts

### Completion update (same day, v3 DB-backed prep)
- `/admin/comms` KPI band now supports DB-backed fallback:
  - when `PUBLIC_COMMS_KPI_API_URL` is absent, frontend calls `rpc('comms_metrics_latest')`
- delivered full SQL pack for native comms metrics:
  - `docs/migrations/comms-metrics-v1.sql`
  - `docs/migrations/comms-metrics-v1-audit.sql`
  - `docs/migrations/comms-metrics-v1-rollback.sql`
  - `docs/migrations/COMMS_METRICS_V1_RUNBOOK.md`
- i18n updated with KPI source/status copy for DB fallback mode
- local `npm run build` and `npm test` passed

## 2026-03-08 — Wave 4 Sprint Increment (S-AN1 / S-ADM2 Formal Closure)

### Scope
Close remaining Wave 4 documentation drift for features already implemented and running in production.

### Delivered (already active in app)
- `S-AN1` Announcements System confirmed as delivered:
  - global top-of-site banner rendering via `AnnouncementBanner` in `BaseLayout`
  - admin management (publish/toggle/delete) in `/admin`
  - dismiss-by-session behavior and severity/expiry handling
- `S-ADM2` Leadership Snapshot confirmed as delivered:
  - chapter/tribe/date filters
  - quick date presets and local persistence
  - CSV export
  - PT/EN/ES i18n coverage
  - completion/blocking counters and recent Credly feed

### Completion update
- backlog status aligned with production reality:
  - `S-AN1` -> Completed
  - `S-ADM2` -> Completed

## 2026-03-08 — Wave 4 Sprint Increment (S10 Credly Auto Sync v1)

### Scope
Automate recurring bulk Credly synchronization to reduce manual admin operations.

### Delivered
- `sync-credly-all` now supports secure cron execution mode:
  - validates `x-cron-secret` against `SYNC_CREDLY_CRON_SECRET`
  - preserves existing superadmin/manual flow when cron secret is absent
  - reports `execution_mode` and `triggered_by` in response payload
- added weekly scheduler workflow:
  - `.github/workflows/credly-auto-sync.yml`
  - triggers every Sunday (`05:00 UTC`) and supports manual dispatch
  - fails fast on missing secrets or non-success HTTP/function response
- added setup runbook:
  - `docs/CREDLY_AUTO_SYNC_SETUP.md`
  - includes required Supabase/GitHub secrets and verification curl

### Follow up still required
- deploy updated `sync-credly-all` function to production
- configure production secrets:
  - Edge Function env: `SYNC_CREDLY_CRON_SECRET`
  - GitHub Actions secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SYNC_CREDLY_CRON_SECRET`

### Completion update (production rollout closed)
- deployed `sync-credly-all` in production with cron-secret support
- configured secrets in production:
  - Supabase Edge Function: `SYNC_CREDLY_CRON_SECRET`
  - GitHub Actions repo secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SYNC_CREDLY_CRON_SECRET`
- validated end-to-end execution via manual workflow dispatch:
  - workflow run `22814354422` succeeded
  - response payload: `"execution_mode":"cron"`, `"fail_count":0`, `"success_count":6`

## 2026-03-08 — Wave 4 Sprint Increment (S-DB1 Credly/Gamification Data Sanitation Pack v1)

### Scope
Prepare a production-safe SQL package to reconcile legacy Credly scoring drift and remove gamification double counting.

### Delivered
- added audit script:
  - `docs/migrations/credly-gamification-audit-v1.sql`
  - checks points distribution, tier mismatch hotspots, duplicates, double counting, and null/missing `tier` in `members.credly_badges`
- added sanitize script:
  - `docs/migrations/credly-gamification-sanitize-v1.sql`
  - includes backup snapshot, points normalization, dedupe, manual-vs-Credly cleanup, and JSON tier/points repair when inferable
- added execution runbook:
  - `docs/migrations/CREDLY_GAMIFICATION_SANITIZE_RUNBOOK.md`
  - defines order `audit -> sanitize -> audit` and DoD criteria for DB cleanup

### Validation captured
- SQL pack reviewed against current Edge Function scoring behavior (`verify-credly` / `sync-credly-all`) for keyword parity and operational consistency.

### Follow up still required
- execute sanitize pack in production window and attach before/after audit outputs
- decide on optional unique partial index for hard prevention of future Credly duplicate inserts

### Completion update (same day, v2 DB hardening pack)
- added DB-level hardening scripts for recurrence prevention:
  - `docs/migrations/credly-gamification-hardening-v1.sql`
  - `docs/migrations/credly-gamification-hardening-rollback-v1.sql`
- hardening script includes:
  - duplicate pre-check query
  - partial unique index creation on Credly rows (`member_id + lower(trim(reason))`)
  - post-check index verification
- runbook updated with hardening/rollback sequence and operational notes

### Completion update (same day, v3 production execution closed)
- production execution completed (`audit -> sanitize -> audit`)
- post-fix applied for `SFPC` Tier 2 mapping and persisted in sanitize SQL
- production hardening applied:
  - partial unique index `uq_gp_credly_member_reason_ci` created on `gamification_points`
- final checks in production:
  - no Credly duplicates by `member_id + lower(trim(reason))`
  - no manual-vs-Credly double counting for mini trail
  - no null/missing tier fields in `members.credly_badges` audit queries

## 2026-03-08 — Wave 4 Sprint Increment (S-COM6 COMMS_METRICS_V2)

### Scope
Add an operational ingestion backbone for communications KPIs with SQL-governed observability.

### Delivered
- created new edge function:
  - `supabase/functions/sync-comms-metrics/index.ts`
  - supports secret-based auth (`SYNC_COMMS_METRICS_SECRET`)
  - supports external fetch (`COMMS_METRICS_SOURCE_URL` + optional token) or manual payload (`rows`)
  - normalizes metrics and upserts into `comms_metrics_daily`
  - writes execution telemetry to `comms_metrics_ingestion_log`
- added migration pack for V2 ingestion:
  - `supabase/migrations/20260308003330_comms_metrics_v2_ingestion.sql`
  - `docs/migrations/comms-metrics-v2-ingestion.sql`
  - `docs/migrations/comms-metrics-v2-ingestion-audit.sql`
  - `docs/migrations/comms-metrics-v2-ingestion-rollback.sql`
  - `docs/migrations/COMMS_METRICS_V2_RUNBOOK.md`
- SQL additions include:
  - ingestion log table with run-level telemetry
  - admin-level RLS policies for ingestion logs
  - `public.can_manage_comms_metrics()` helper function
  - `public.comms_metrics_latest_by_channel(p_days)` RPC-ready read function

### Validation captured
- local tests pass (`npm test`)
- migration and function package prepared for production apply/deploy

### Follow up still required
- deploy `sync-comms-metrics` in production
- configure secrets in Supabase project
- run V2 audit SQL after first production sync

## 2026-03-08 — Wave 4 Sprint Increment (S-RM4 ACL Hardening v1)

### Scope
Reduce authorization drift by centralizing admin tier checks and reusing them across critical admin routes.

### Delivered
- centralized ACL utilities in `src/lib/admin/constants.ts`:
  - `resolveTierFromMember`
  - `hasMinimumTier`
  - `canAccessAdminRoute`
  - route-level minimum tier map for:
    - `admin_panel`
    - `admin_analytics`
    - `admin_member_edit`
- `/admin` now uses centralized tier resolution/gate for panel access
- `/admin/analytics` gate now uses centralized ACL helper
- `/admin/member/[id]` gate now uses centralized ACL helper and includes robust boot fallback:
  - nav member
  - session + `get_member_by_auth`
  - deterministic redirect on deny

### Validation captured
- local `npm run build` passed after ACL hardening changes

### Follow up still required
- extend centralized ACL checks to additional privileged actions (non-route actions/buttons)
- align RLS policy naming/docs with same tier matrix for backend parity

### Completion update (same day)
- delivered `S-RM4 v2` with in-page action ACL guards in `/admin`:
  - added reusable guard helpers (`ensureAdminAction`, `ensureLeaderAction`)
  - protected privileged actions against console-trigger bypass:
    - tribe allocation and member edit actions
    - announcements CRUD actions
    - reports/snapshot preview + export actions
    - cycle history write actions (superadmin-only via centralized ACL)
    - tribe settings/slots actions (leader+)
- local `npm run build` passed after ACL action hardening

### Completion update (same day, v3 backend parity pack)
- added backend parity artifacts for ACL tier matrix rollout:
  - `docs/migrations/acl-tier-parity-v1.sql`
  - `docs/migrations/ACL_POLICY_CHECKLIST.md`
  - `docs/migrations/acl-tier-parity-audit.sql`
- pack includes:
  - tier rank resolver (`current_member_tier_rank`)
  - min-tier helper (`has_min_tier`)
  - sample policy mappings aligned with frontend ACL tiers
  - rollout/validation checklist for staging -> production

### Completion update (same day, regression safety)
- added automated ACL tests:
  - `tests/admin-acl.test.mjs`
  - covers tier resolution, tier ordering, and route/action access guards
- `npm test` passed with full suite green

### Completion update (production rollout closed)
- applied backend parity in production:
  - `current_member_tier_rank()` and `has_min_tier(int)` active in `public`
  - helper grants restricted (`authenticated`, `service_role`, `postgres`) and `anon` execute revoked
- effective policy state validated in production:
  - `announcements`: admin+ write (`has_min_tier(4)`)
  - `member_cycle_history`: superadmin write (`has_min_tier(5)`)
- duplicate `announcements` admin policy removed to keep single source of truth
- rollout caveat handled:
  - `tribe_slots` policy skipped (table absent in current schema)
  - reverted over-broad `tribes_leader_write` test policy to preserve existing “leader edits own tribe” guard

## 2026-03-08 — Wave 4 Sprint Increment (S-PA1 Product Analytics v1)

### Scope
Start analytics governance rollout with protected access and iframe-first dashboards.

### Delivered
- created new protected route:
  - `/admin/analytics` with tier gate (`superadmin` and `admin` only)
  - denied state for non-authorized users
- analytics embeds configured by environment variables:
  - `PUBLIC_POSTHOG_PRODUCT_DASHBOARD_URL`
  - `PUBLIC_LOOKER_COMMS_DASHBOARD_URL`
- added analytics shortcut card in `/admin` reports panel
- privacy hardening in PostHog identify (`BaseLayout`):
  - removed `name` and `email` from identify payload
  - kept `member_id` + minimal operational metadata

### Validation captured
- local `npm run build` passed after analytics route and privacy changes

### Follow up still required
- provision production dashboard URLs in environment
- optional consent/opt-out toggle in UI for session replay controls

### Completion update (same day)
- delivered `S-PA1 v2` with consent-aware controls:
  - new consent card in `/admin/analytics` (`Allow Analytics` / `Revoke Analytics`)
  - local consent state persisted in browser (`analytics_consent`)
  - global listener applies PostHog `opt_in_capturing`/`opt_out_capturing`
  - session replay starts/stops based on consent state
  - PostHog identify now runs only when consent is granted
- local `npm run build` passed after consent and privacy updates

## 2026-03-08 — Wave 4 Sprint Increment (S-ADM2 Leadership Snapshot v1)

### Scope
Deliver first operational version of leadership training snapshot in `/admin` for management visibility.

### Delivered
- added new `Leadership Training Snapshot` block in admin reports panel with:
  - active base size
  - mini-trail status counters (`Trilha Concluída`, `Em Progresso`, `Bloqueados 0/8`)
  - completion bars by chapter
  - completion bars by tribe
  - recent Credly certification feed with member/chapter/tribe/date/XP
- data sources combined client-side:
  - `members` (active operational base)
  - `course_progress` (8 official mini-trail course codes)
  - `gamification_points` filtered by `Credly:%`

### Validation captured
- local `npm run build` passed after admin changes

### Follow up still required
- i18n keys for new S-ADM2 copy
- optional filters (chapter/tribe/date window) and export CSV for snapshot

### Completion update (same day)
- delivered `S-ADM2 v2` in `/admin` reports:
  - snapshot filters: chapter, tribe, from, to
  - CSV export for per-member snapshot rows
  - i18n keys added for new snapshot labels/actions/messages in PT/EN/ES

## 2026-03-08 — Wave 4 Sprint Increment (S-REP1 VRMS Export Filters v1)

### Scope
Improve VRMS export usability for leadership reporting by adding optional segmentation filters.

### Delivered
- `/admin` VRMS report card now supports optional filters:
  - chapter (`PMI-XX`)
  - tribe (`T0X`)
- preview flow (`Preview VRMS`) now applies the same chapter/tribe filters used in export
- preview summary shows active filter scope (all chapters/tribes or selected values)
- CSV export filename now includes filter suffixes when selected:
  - example: `vrms_2026-03-01_2026-03-08_PMI-SP_T02.csv`
- i18n keys added in PT/EN/ES for the new optional selectors

### Validation captured
- local `npm run build` passed after VRMS filter additions

### Follow up still required
- optional date presets (`7d`, `30d`, current cycle) for faster reporting
- align future snapshot export UX with same filter persistence

### Completion update (same day, v2)
- delivered VRMS quick period presets in `/admin`:
  - `Last 7 days`
  - `Last 30 days`
  - `Current cycle`
- presets auto-fill `from`/`to` fields for faster preview/export workflows
- i18n keys added for quick-range labels in PT/EN/ES
- local `npm run build` and `npm test` passed after update

### Completion update (same day, v3)
- delivered VRMS filter persistence in `/admin` using browser `localStorage`
- restored automatically on reports tab open:
  - date range (`from`/`to`)
  - chapter filter
  - tribe filter
- auto-save on user changes and preset actions (`7d`, `30d`, `cycle`)
- local `npm run build` and `npm test` passed after update

### Completion update (same day, v4 snapshot parity)
- delivered quick period presets for Leadership Snapshot in `/admin`:
  - `Last 7 days`
  - `Last 30 days`
  - `Current cycle`
- presets now auto-fill `ls-from`/`ls-to` before applying/exporting snapshot filters
- i18n keys added in PT/EN/ES for snapshot quick-range labels
- local `npm run build` and `npm test` passed after update

### Completion update (same day, v5 snapshot persistence)
- delivered Leadership Snapshot filter persistence using browser `localStorage`
- restored automatically on reports open:
  - chapter
  - tribe
  - date range (`ls-from`/`ls-to`)
- auto-save on filter changes, apply action, and quick presets (`7d`, `30d`, `cycle`)
- local `npm run build` and `npm test` passed after update

### Completion update (same day, v6 UX hardening / S-REP1 closure)
- added explicit `Clear` actions for both report surfaces:
  - VRMS filters clear/reset
  - Leadership Snapshot filters clear/reset
- added active-filter visual indicators:
  - VRMS preview highlights when filters are active
  - Leadership Snapshot shows active filter badge
- added restore feedback when saved filters are reapplied automatically
- i18n labels/messages added in PT/EN/ES for active/restored/cleared filter states
- local `npm run build` and `npm test` passed after update
- local `npm run build` passed after v2 changes

## 2026-03-08 — Wave 3 Sprint Increment (S11 UI Polish / Empty States)

### Scope
Improve UX clarity on internal pages with better loading placeholders and actionable empty states.

### Delivered
- `/artifacts`:
  - replaced plain "Carregando..." text with skeleton rows in all tab panels
  - added richer empty states with CTA for:
    - catalog (login CTA for guests, submit CTA for logged users)
    - my artifacts (submit CTA)
    - review queue (clear empty-state messaging)
- `/attendance`:
  - replaced initial loading placeholders in events/ranking with skeleton rows
  - events tab empty state now includes contextual CTA:
    - managers/leaders: `+ Novo Evento`
    - others: `Atualizar`
  - ranking tab empty state now explains when data will appear

### Validation captured
- local `npm run build` passed after UI changes

## 2026-03-08 — HF5 Data Patch Follow Through (SQL Pack)

### Scope
Prepare a deterministic, idempotent data-cleanup pack for legacy member inconsistencies called out in HF5.

### Delivered
- added migration-ready SQL files:
  - `docs/migrations/hf5-audit-data-patch.sql` (pre/post audit)
  - `docs/migrations/hf5-apply-data-patch.sql` (idempotent patch)
- patch behaviors:
  - restores Sarah LinkedIn only when blank and only from an existing matching non-empty source
  - aligns `members.operational_role/designations` with active `member_cycle_history` snapshot
  - enforces deputy hierarchy consistency (`deputy_manager` must include `co_gp`; `manager` must not carry `co_gp`)

### Validation captured
- SQL syntax reviewed locally and designed to be safely re-runnable
- no runtime codepath changes introduced (DB migration pack only)

### Follow up still required
- execute audit -> apply -> audit in production SQL editor
- if Sarah LinkedIn remains blank after run, apply a one-off manual update with canonical URL

## 2026-03-08 — Wave 3 Sprint Increment (S8b Internal i18n, Attendance Shell)

### Scope
Advance internal-page localization with a low-risk first pass on the attendance route.

### Delivered
- `/attendance` now resolves active language from URL and applies existing i18n keys for:
  - page metadata title
  - auth gate title/description/button
  - loading states
  - tab labels
  - section headers and refresh label
  - empty-state no-events copy

### Validation captured
- local `npm run build` passed after attendance i18n changes

### Follow up still required
- continue i18n migration on `/admin` and remaining internal flows

### Completion update (same day)
- attendance modal components localized with `attendance.modal.*` keys in PT/EN/ES:
  - `NewEventModal`
  - `RecurringModal`
  - `EditEventModal`
  - `RosterModal`
- `/admin` received first i18n shell pass with localized:
  - page title/meta/subtitle
  - restricted access state
  - access checking/loading strings
  - top stats labels
  - primary tab labels
  - pending pool heading
- `/admin` i18n expanded to filters and reports panel labels:
  - member filters (search/chapter/role/designation/status/login/tribe/clear)
  - VRMS/report card labels and preview table headers
  - member export labels and descriptions
- `/admin` i18n expanded again with:
  - allocation/edit/cycle-history modal labels
  - loading string for announcements
  - critical dynamic admin toast/confirm messages migrated to `admin.msg.*`
  - slot settings validations/success messages migrated to `admin.msg.*`
  - locale parity fix for `admin.msg.saveError` across PT/EN/ES

## 2026-03-08 — Wave 3 Sprint Increment (S-UX1 Trail Clarity)

### Scope
Improve researcher clarity for mini trail completion status directly in gamification workflows.

### Delivered
- added logged-in trail clarity card in `/gamification` with:
  - explicit progress indicator (`X de Y cursos concluídos`)
  - completion percentage bar
  - missing course list required to finish the mini trail
  - in-progress course list when applicable
- card refreshes after sync workflow execution to keep status aligned with latest backend updates

### Validation captured
- local `npm run build` passed after UI and query changes

## 2026-03-08 — Wave 3 Sprint Increment (S-RM3 Gamification XP Split)

### Scope
Advance Gamification v2 with explicit distinction between current cycle points and lifetime XP.

### Delivered
- `/gamification` leaderboard now supports mode switch:
  - `Ciclo Atual` (existing cycle ranking source)
  - `XP Vitalício` (aggregated from `gamification_points` per member)
- ranking rows now display both references simultaneously (current cycle vs lifetime) to reduce interpretation drift
- `Meus Pontos` panel now labels total as lifetime XP and shows current cycle points explicitly

### Validation captured
- local `npm run build` passed after gamification changes

### Follow up still required
- continue with `S-UX1` trail clarity item in Wave 3

### Completion update (same day)
- cycle vs lifetime distinction was extended to:
  - tribe ranking panel (mode switch + recalculated score basis)
  - achievements panel context (lifetime XP with current-cycle reference)
- S-RM3 scope considered complete for current sprint baseline

## 2026-03-08 — Wave 3 Sprint Increment (S-RM2 Profile Journey)

### Scope
Advance Wave 3 by delivering profile journey visibility and cycle-aware completeness improvements.

### Delivered
- profile data loading now treats `member_cycle_history` as first-class context with fallback safety
- added `Resumo da Jornada` card in `/profile` with:
  - total cycles
  - current cycle label
  - first join date
  - latest activation date
- timeline section hardened with explicit empty state when no cycle history exists
- completeness signal for operational members now checks cycle context from history (`Vínculo de ciclo`) instead of relying only on local snapshot fields

### Validation captured
- local `npm run build` passed after profile changes

### Follow up still required
- continue Wave 3 with `S-RM3` (lifetime XP vs current cycle split)
- continue Wave 3 with `S-UX1` (explicit per-member trail completion + missing course list)

## 2026-03-08 — Gamification Stability Sprint (S-HF6 + S-HF7)

### Scope
Close critical stabilization items in gamification UX and data consistency between trail progress and score surfaces.

### Delivered
- `S-HF7` completed in `/gamification`:
  - added bounded query timeout for secondary panels
  - added defensive `try/catch` and explicit error render paths for tabs that previously could remain in indefinite loading
- `S-HF6` completed in `sync-credly-all`:
  - legacy hardening now also syncs trail completion into `course_progress` when member has legacy Credly badges but no current `credly_url`
  - added reconciliation metric `legacy_trail_synced` in bulk sync report

### Validation captured
- local `npm run build` passed after frontend hardening changes
- `sync-credly-all` deployed in production as version 9
- member-level SQL validation confirmed trail state consistency (7 completed, 1 in progress) for sampled account

### Follow up still required
- keep recurring audit for legacy points drift and duplicate `member_id + reason` rows in `gamification_points`
- continue Wave 3 planned items (`S-RM2`, `S-RM3`, `S-UX1`)

## 2026-03-08 — Credly Data Sanitization and Dedup Hardening

### Scope
Production hardening to eliminate legacy Credly scoring drift and enforce safer dedup behavior for gamification records.

### Delivered
- `verify-credly` updated with Tier 2 expansion (`business intelligence`, `scrum foundation`, `sfpc`)
- `verify-credly` scoring upsert hardened to:
  - keep a single `gamification_points` record per `member_id + reason`
  - update points when classification changes
  - delete duplicate residual rows
- manual trail cleanup hardened from case-sensitive `like` to case-insensitive `ilike` for `Curso:CODE` legacy patterns
- `sync-credly-all` hardened to process active members without `credly_url` when `credly_badges` exists, sanitizing `tier/points` and recalculating related Credly point entries
- production data cleanup executed:
  - `system_tier` nulls reduced to zero in JSON badge payloads
  - legacy Tier 1 row (`PMP` with 10 points) corrected to 50 points

### Validation captured
- `verify-credly` deployed as active version 13
- `sync-credly-all` deployed as active version 8
- audit query for null tiers returned `0`
- targeted query confirmed BI/SFPC at `25` points

### Follow up still required
- run periodic audit query for `member_id + reason` duplicates in `gamification_points`
- complete UI alignment and loading fixes tracked in `S-HF6` and `S-HF7`

## 2026-03-07 — Stabilization Hotfix Train

### Scope
Production stabilization covering route compatibility, SSR safety, and documentation discipline.

### Included changes

#### `6f1593d`
**Message:** `fix: add Cloudflare Pages SPA fallback redirects`

**Why**
Reduce direct navigation failures and improve resilience for non standard entry paths on Cloudflare Pages.

#### `f33afce`
**Message:** `fix: add legacy route aliases for team and rank pages`

**Why**
Restore compatibility for old or live links still pointing to:
- `/teams`
- `/rank`
- `/ranks`

#### `87cde9a`
**Message:** `fix: guard tribes deliverables mapping against missing data`

**Why**
Prevent SSR failure in `TribesSection.astro` when static data is incomplete or optional.

### Validation captured
- local `npm run build` passed
- local `npm run dev -- --host 0.0.0.0 --port 4321` started successfully
- local access confirmed through `http://localhost:4321/`

### Known follow up
- production propagation of aliases should still be smoke tested
- SSR safety audit should continue in other sections
- docs were behind the code and are now being corrected

---

## 2026-03-07 — Credly Tier Scoring Expansion

### Scope
Backend scoring logic for Credly verification was expanded beyond the older coarse behavior.

### Delivered
- tier based certification scoring in the verification flow
- richer scoring breakdown in backend response
- improved zero match handling

### Important caveat
This release is **not complete from a product standpoint** because rank and gamification UI surfaces still need alignment with the new scoring logic.

### Operational note
When backend truth and frontend experience diverge, the release log must say so plainly instead of pretending the feature is done. Reality is stubborn like that.

---

## Release policy from now on

Every production affecting hotfix, stabilization batch, or materially visible backend change should create or update an entry in this file.

Automated semantic versioning can come later. Team memory cannot.
