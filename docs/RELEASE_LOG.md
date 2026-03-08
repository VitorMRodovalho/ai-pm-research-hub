# Release Log

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
