# Governance Changelog

## 2026-03-11 — Wave 16: Supabase Audit, Profile And Selection Stabilization

### Decisions

1. **Migration drift must be corrected in docs even when no new schema ships**: The repo currently carries 44 migration files, and regenerating `src/lib/database.gen.ts` from the linked project confirms the remote schema already includes the latest tracked objects (`site_config`, `project_boards`, `board_items`, `volunteer_applications`, and related RPCs). This wave ships no new migration, but it does correct the stale `42/42` documentation.

2. **Profile field hygiene should survive rerenders without rebinding**: `profile.astro` still rebuilt its card cluster through `innerHTML`, so field normalization tied to the newly created Credly input was fragile. The normalization path now uses delegated `focusout` / `paste` / `input` listeners instead of a per-render binding helper.

3. **Selection cycle UX should follow runtime metadata, not fixed cycle copy**: `/admin/selection` keeps the same `admin_selection` and LGPD guard, but cycle tabs and snapshot titles now derive from `loadCycles()` / `getCurrentCycle()` instead of hardcoded `Ciclo 1/2/3` copy.

4. **Shared confirm dialogs should keep static listeners and mutable state separate**: `ConfirmDialog.astro` no longer rewires `btn.onclick` for each open. The dialog updates its state on `showConfirm(...)`, while the confirm button now uses a single listener that consumes the stored callback.

### Process Lessons Learned

1. **Linked schema generation is a practical read-only audit fallback**: When `supabase migration list` is blocked locally by stale DB auth, refreshing generated types from the linked project still provides strong evidence that the remote schema contains the expected tracked objects. Before the next schema-writing sprint, the CLI DB credential path on this workstation should be refreshed.

2. **Textual tests remain useful for stabilization waves**: Small regression checks for dynamic cycle copy, delegated binding patterns, and mutable `onclick` usage are cheap safeguards while broader browser coverage is still being expanded.

---

## 2026-03-11 — Post Wave 15: Attendance ACL And Modal Delegation

### Decisions

1. **`/attendance` remains member-visible, but management is `leader+`**: The page itself still supports self-service member actions such as own presence/check-in, but event creation, recurring scheduling, roster management, and administrative presence toggles now align with the tier rule already described in `PERMISSIONS_MATRIX`: `leader`, `admin`, and `superadmin`.

2. **Attendance modal flows should use delegated events, not inline handlers**: The remaining modal cluster in attendance (`NewEventModal`, `RecurringModal`, `EditEventModal`, `RosterModal`) has been moved off `onclick` / `onchange` / `oninput` and into delegated `click` / `change` / `input` / `submit` handling inside `attendance.astro`.

3. **No new event library is required yet**: A lightweight library like `delegate-it` remains a valid option if event sprawl grows again, but for the current Astro inline-script footprint the local delegated handlers remain simpler than adding a new dependency. For regression coverage, Playwright is the strongest next candidate because it already exists in the repo and matches the modal/ACL interaction needs better than a lower-level DOM helper.

### Process Lessons Learned

1. **ACL drift often hides in page-level guards, not route config**: Even when navigation and matrix docs are mostly correct, page-local `CAN_MANAGE` shortcuts can silently narrow permissions. Tier helpers should be reused on operational pages, not only admin pages.

2. **Textual regression tests are acceptable for UI debt cleanup**: A small file-level test preventing inline handlers from returning is a cheap way to lock in this style migration before broader browser automation is added.

---

## 2026-03-11 — Wave 15: Cycle-Config Hardening

### Decisions

1. **Cycle reads should prefer `list_cycles`, not local constants**: The repo already had `cycles` table + RPC helpers, but `profile.astro`, `tribe/[id].astro`, and parts of `admin/index.astro` still depended on `cycle_3`, `2026-01-01`, or deprecated constants. Wave 15 moves these operational surfaces to runtime cycle resolution.

2. **Legacy cycle constants are no longer the admin source of truth**: `CYCLE_META` and `CYCLE_ORDER` were still exported from `src/lib/admin/constants.ts` even after the DB-backed cycle model existed. They are removed from the active path so admin history, filters, and add-record flows derive from `list_cycles`.

3. **Compatibility fallbacks remain allowed when they are explicitly bounded**: `src/lib/cycles.ts` keeps the shared fallback dataset for offline/RPC-failure scenarios, and `src/lib/cycle-history.js` keeps a small label fallback for backward compatibility with tests and sparse records. The important rule is that operational reads must prefer DB-backed cycle data first.

### Process Lessons Learned

1. **A completed migration still needs consumer cleanup**: Having the `cycles` table in production was not enough while UI surfaces still queried `cycle_3` directly. Migration closure must include consumer audits.

2. **Warnings count as doc-drift signals too**: The old `cycles.ts` import warning was a small but useful indicator that the helper layer still needed cleanup while being adopted more widely.

---

## 2026-03-11 — Wave 14: Divergence Cleanup, Gap Audit & Deferred Structuring

### Decisions

1. **Docs must reflect production, not old strategy**: `README.md`, `docs/MIGRATION.md`, and `CONTRIBUTING.md` still described PostHog/Looker as the preferred analytics pattern and had outdated setup guidance. Wave 14 realigns them with native Chart.js + Supabase RPC dashboards, smoke routes, and the current repo/workflow.

2. **Event delegation remains the target pattern, but migration is incremental**: The repo still contained legacy inline handlers in older surfaces. Rather than claiming the migration is complete, Wave 14 updates the guidelines to say new work must use delegated events and touched legacy surfaces should be refactored progressively. The first focused tranche was applied to `admin/index.astro` and shared UI components.

3. **Deferred items now need lane ownership before implementation**: `S23`, `S24`, `S-KNW7`, and webinars were not ready for execution because they lacked requirement ownership. They are now classified by lane (`planning`, `product`, `backend`, `integration`, `ui`) with dependencies and explicit exit criteria from deferred.

4. **Site hierarchy audits should include route metadata, not only pages**: The page `/admin/webinars` already existed and was present in nav and permissions docs, but `AdminRouteKey` had no `admin_webinars` entry. Wave 14 adds that route key so nav, route metadata, and ACL constants stay synchronized.

### Process Lessons Learned

1. **Guidelines can drift even when the product evolves correctly**: The code had already moved to native dashboards, while README/MIGRATION still documented the old embed strategy. Sprint doc hygiene should cross-check product docs, migration notes, and contributor docs together.

2. **Deferred is not enough without a re-entry rule**: A backlog item marked deferred needs a lane owner, dependencies, and a condition for returning to implementation; otherwise it remains invisible work.

---

## 2026-03-11 — Wave 13: Doc Hygiene (Edge Functions)

### Decisions

1. **AGENTS.md and PROJECT_ON_TRACK were stale on Edge Functions**: Both documents stated sync-credly-all and sync-attendance-points were "absent" or "not in repo." They have been in supabase/functions/ since at least Wave 8. Doc hygiene corrects this to prevent future confusion and redundant work.

2. **ResourcesSection already uses hub_resources**: The component has a client-side fetch from hub_resources when Supabase is available; the static array is an SSR/visitor fallback. No code change needed for Wave 13; any SSR fetch improvement is deferred.

3. **PROJECT_ON_TRACK F1 marked Concluído**: The Batch 1 item "Trazer sync-credly-all e sync-attendance-points" is done. Remaining F2–F4 items stay as-is.

### Process Lessons Learned

1. **Periodic doc audits catch drift**: Edge functions were added to the repo but PROJECT_ON_TRACK and AGENTS.md were not updated. Wave 13 reinforces that doc hygiene should include cross-checking "on track" and "where key things live" against actual repo state.

---

## 2026-03-11 — Wave 12: Agent Interaction, Release Workflow & Screenshots

### Decisions

1. **Agent interaction formalized**: AGENTS.md now has a mandatory "Interação com agentes" section. At sprint start: read backlog, check site hierarchy and PERMISSIONS when adding routes. At sprint end: execute 5-phase routine without skipping. SPRINT_IMPLEMENTATION_PRACTICES references this section.

2. **Release workflow over postinstall scripts**: Semantic Versioning tech debt addressed via GitHub Actions `workflow_dispatch` rather than a local npm script. Agents and humans can create tags from the Actions UI with version input. Avoids local git push permissions and keeps release traceable.

3. **AGENT_BOARD_SYNC repo corrected**: Document referenced `ai-pm-hub-v2` but the actual repo is `ai-pm-research-hub`. Updated gh commands and URLs.

4. **S-SC1 Screenshots use Playwright**: Playwright chosen over Puppeteer for screenshots: modern API, good Chromium support, `npx playwright install chromium` for CI. Script assumes preview server is running; first-run requires `npm run screenshots:setup`.

### Process Lessons Learned

1. **5-phase routine must be discoverable by agents**: Adding an explicit "ao iniciar" and "ao encerrar" checklist in AGENTS.md ensures agents don't skip the closure routine when continuing development.

---

## 2026-03-11 — Wave 11: Doc Hygiene, Site Config & S-AN1 Closure

### Decisions

1. **S-AN1 Rich Editor closed as partial**: The markdown preview toggle (W10.5) provides **bold**, *italic*, `code`, and line breaks. A full WYSIWYG (TipTap/Quill) would add a dependency and scope. The tech debt item is closed as "Partial" with a note that WYSIWYG can be revisited if there is explicit demand.

2. **S-RM5 Site Config uses key-value table**: A single `site_config` table with `key TEXT PRIMARY KEY` and `value JSONB` supports flexible, extensible configuration without schema changes for new keys. Seed keys: `group_term`, `cycle_default`, `webhook_url`. Admin tier can read; only superadmin can write via `set_site_config` RPC.

3. **Site hierarchy checkpoint added to sprint closure**: Phase 2 Audit in SPRINT_IMPLEMENTATION_PRACTICES.md now explicitly includes verification that every nav href has a matching page and that AdminNav is aligned.

### Process Lessons Learned

1. **Tech debt table must be updated when features partially address items**: S-AN1 Scheduling was delivered in W10.4 but remained "Open" until W11 doc hygiene. Updating the tech debt table should be part of the same sprint that delivers the feature.

---

## 2026-03-11 — Wave 10: Site-Hierarchy Integrity & UX Polish

### Decisions

1. **Admin Analytics was a nav orphan**: The `/admin/analytics` page existed and had a route key in constants.ts, but no entry in navigation.config.ts or AdminNav.astro. This was a site-hierarchy gap — users could access via direct URL or admin index link but not via the drawer. Added full nav integration.

2. **PERMISSIONS_MATRIX is the audit checklist**: Every new route and designation must be reflected in PERMISSIONS_MATRIX. Sections 3.13-3.15 formalize Wave 8-9 features (Tribe Kanban, Selection LGPD, Progressive disclosure) that were missing.

3. **Announcement scheduling uses existing schema**: The `announcements` table already had `starts_at` and `ends_at`; only the frontend form was missing the starts_at picker. No migration required.

4. **Markdown preview is lightweight**: Implemented inline with a minimal regex-based renderer (bold, italic, code, line breaks) — no new dependency. Announcement body changed from single-line input to textarea.

### Process Lessons Learned

1. **Site-hierarchy audits catch orphan pages**: When adding pages, always add the corresponding nav entry. A periodic audit (nav config vs. pages) prevents drift.

2. **PERMISSIONS_MATRIX should be updated in the same sprint as feature delivery**: Deferring permission docs creates a maintenance backlog.

---

## 2026-03-11 — Wave 9: Intelligence & Cross-Source Analytics

### Decisions

1. **Selection Process frontend is admin-only and LGPD-classified**: The `/admin/selection` page shows volunteer names and locations but deliberately omits email addresses from the list view. The `lgpdSensitive: true` flag ensures the nav item is fully hidden from non-admin users, not just disabled.

2. **Cross-source analytics uses a single aggregation RPC**: Rather than making 6 separate API calls from the frontend, `platform_activity_summary()` consolidates all metrics into one JSON response. This reduces network overhead and ensures atomic consistency of the dashboard numbers.

3. **Documentation reform is a sprint-worthy deliverable**: AGENTS.md, SPRINT_IMPLEMENTATION_PRACTICES.md, and DEPLOY_CHECKLIST.md had drifted significantly from the actual system state. Treating doc reform as a formal sprint item (W9.5) ensures it gets the attention it deserves.

4. **5-phase sprint closure routine is now mandatory**: The routine (Execute, Audit, Fix, Docs, Deploy) has been formalized in SPRINT_IMPLEMENTATION_PRACTICES.md and AGENTS.md. Every future sprint must follow this sequence.

5. **W9.2 (Governance Journal) and W9.3 (Semantic Search) deferred**: Governance journal has no DB schema yet and the user explicitly chose `governance_later`. Semantic search requires pgvector extension and has low immediate impact. Both move to Wave 10+.

### Process Lessons Learned

1. **Aggregation RPCs outperform multiple frontend calls**: The `platform_activity_summary` pattern of bundling 7 queries into one RPC should be the default for dashboard-type pages.

2. **LGPD classification should be decided at nav config level**: The `lgpdSensitive` flag on NavItem is the right abstraction -- it's auditable, centralized, and doesn't require per-page logic.

3. **Documentation drift compounds**: After 8 waves of rapid delivery, AGENTS.md had multiple contradictions with the actual codebase. Regular doc audits should be part of sprint closure.

---

## 2026-03-11 — Wave 8: Reusable Kanban & UX Architecture

### Decisions

1. **Tier-aware progressive disclosure implemented**: `getItemAccessibility()` now returns `{visible, enabled, requiredTier}`. Items above a user's tier appear disabled with lock icon and tooltip, rather than hidden. Exception: LGPD-sensitive items remain hidden via `lgpdSensitive` flag. This ensures users can discover features they can aspire to unlock.

2. **Legacy role columns dropped**: Migration `20260312020000` removes `role`, `roles` columns and `sync_legacy_role_columns` trigger from `members`. All frontend code has been verified to use `operational_role` + `designations` exclusively. This closes a long-standing tech debt item.

3. **Universal Kanban Component deferred**: W8.1 (extracting a reusable Kanban component from curatorship) was deferred because there is no second consumer with identical requirements yet. The tribe board reuses the same visual pattern but with different data sources and column definitions. Extraction will happen when a third board instance is needed.

4. **PostHog/Looker fully superseded**: Native Chart.js analytics now cover all use cases previously handled by external iframes. PostHog session replay and Looker Studio references in backlog have been marked as superseded.

5. **Selection process analytics uses aggregated data only**: The `volunteer_funnel_summary` RPC returns statistical aggregates (counts, distributions) -- never individual PII. Individual-level data access is gated by RLS admin-only policy on `volunteer_applications`.

### Process Lessons Learned

1. **Progressive disclosure requires careful LGPD classification**: Not all restricted items should be "visible but disabled." Data pages with LGPD-sensitive content must remain fully hidden. The `lgpdSensitive` flag on `NavItem` provides a clear, auditable mechanism.

2. **5-phase sprint closure routine validated**: Execute → Audit → Fix → Docs → Deploy cycle ensures no regressions reach production. Build + test + lint + route smoke before every commit.

3. **Schema cleanup should be a dedicated sprint item**: Dropping legacy columns sounds trivial but requires verifying every frontend file, generated type, and migration dependency. Treating it as a sprint item ensures it gets proper attention.

---

## 2026-03-11 — Wave 7: Data Ingestion Platform -- Execution and Lessons Learned

### Decisions

1. **Roadmap waves reorganized**: The previous Wave 5 Phase 2 and Wave 6 have been restructured into Waves 7-10 to reflect the new data-driven strategy. Wave numbering continues sequentially from the last completed wave.

2. **Data ingestion as prerequisite**: All external data sources (Trello boards, Google Calendar, PMI volunteer CSVs, Miro board) must be ingested into the platform DB before building frontend features that consume them. This follows the established rule: "Feature de frontend sem backend/API/SQL pronto nao avanca para desenvolvimento."

3. **New tables follow architecture doctrine**: `project_boards` and `board_items` extend the existing data model without replacing it. `volunteer_applications` is LGPD-sensitive with admin-only RLS. No existing tables were modified.

4. **Backlog items absorbed or reframed**: S-KNW4 (Views Relacionais) is now W8.1+W8.2 (Universal Kanban). DS-1 (Data Science PMI-CE) is now W8.3+W9.4 (Selection Analytics + Cross-Source Dashboards). S-KNW7 (Gemini Extraction) is deferred to Wave 10.

5. **Tier-aware progressive disclosure planned for Wave 8**: Navigation items will be visible to all tiers but disabled (with lock icon) for insufficient permissions. Sensitive DATA remains hidden per LGPD. This architectural decision affects `navigation.config.ts` and all rendering components.

### Execution Results

All 4 importers executed successfully against production database:
- 119 Trello cards across 5 boards
- 67 calendar events from ICS export
- 143 volunteer applications across 3 cycles (64% matched to existing members)
- 51 Miro board links

### Process Lessons Learned

1. **Import scripts must always support `--dry-run` and dedup/upsert**: All 4 scripts are idempotent. Re-running produces zero duplicate rows. This is now a mandatory pattern for all future data import scripts.

2. **Service role key should never be stored in `.env`**: Use `npx supabase projects api-keys` at runtime and pass via environment variable. This is now the standard practice documented here.

3. **CSV line counts are unreliable for multi-line content**: PMI volunteer CSVs contain essay answers with embedded newlines. `wc -l` reported 779 lines but actual data rows were 143. Always use a proper CSV parser, never line counting, for estimating import sizes.

4. **Calendar keyword filters need both include AND exclude lists**: "PMI" as a keyword matches global conferences (PMI Annual Summit, TED@PMI). Future calendar imports must maintain an exclude list for known false positives.

5. **Member matching priority**: Email is reliable (64% match rate). Name matching is fragile (Trello only has usernames). Future data sources should export email whenever possible.

6. **Cross-tribe boards are common**: 4 of 5 Trello boards had `tribe_id: null` because they serve the comms team or cross-tribe functions. Wave 8 Kanban component must support both tribe-scoped and cross-tribe boards.

### Affected governance documents

- `backlog-wave-planning-updated.md` updated (Wave 7 marked CONCLUIDA with actual counts)
- `docs/RELEASE_LOG.md` updated (v0.5.0 with execution results and lessons)
- `docs/GOVERNANCE_CHANGELOG.md` updated (this entry)

---

## 2026-03-10 — CPO Production Audit: Information Architecture restructure

### Decisions

1. **Help page made public**: `/admin/help` migrated to `/help` with `minTier: member`. LGPD-sensitive topics (privacy, data protection) are hidden client-side for non-admin users. The old `/admin/help` route returns a 301 redirect to `/help`.

2. **Onboarding removed from main navbar**: Moved to the profile drawer (`section: 'drawer'`, `group: 'profile'`). Requires authentication (`minTier: member`). This reduces main nav clutter without removing the feature.

3. **Universal tribe visibility**: The tribe dropdown now queries ALL tribes (active + inactive). Inactive or legacy tribes render with reduced opacity, a lock icon, and tooltip "Tribo Fechada". Members can discover tribes they cannot currently access.

4. **Webinars placeholder**: `admin/webinars.astro` now renders a "Coming Soon / Módulo em Construção" UI with feature preview cards instead of a blank page. Admin-gated.

### Why

CPO audit revealed that the information architecture had UX friction: help was admin-locked despite being useful to all members, onboarding polluted the main nav, tribe discovery was limited to active tribes only, and the webinars page was blank in production.

### Affected governance documents

- `docs/PERMISSIONS_MATRIX.md` updated (help, onboarding, webinars rows + code mapping)
- `backlog-wave-planning-updated.md` updated (S-HF10 through S-IA3)
- `src/lib/navigation.config.ts` is the code source of truth for these changes

---

## 2026-03-07 — Documentation and release governance reset

### Decision
The repository will maintain a disciplined documentation set with clear boundaries:

- `README.md` = institutional context, platform scope, current status, stack, and documentation map
- `backlog-wave-planning-updated.md` = execution plan and debt visibility
- `docs/GOVERNANCE_CHANGELOG.md` = governance, access, and product engineering decisions
- `docs/MIGRATION.md` = transitional technical notes and compatibility state
- `docs/RELEASE_LOG.md` = operational release and hotfix history

### Why
Recent hotfixes exposed that code can move faster than shared team understanding. Documentation is now part of the delivery obligation.

---

## 2026-03-07 — Manual release log becomes mandatory

### Decision
Manual release logging is required immediately, even before automated semantic versioning exists.

### Rule
Every production affecting hotfix should document:

- what changed
- why it changed
- how it was validated
- what remains pending

### Note
Automated version tags can come later. Invisible releases are not acceptable now.

---

## 2026-03-07 — Route compatibility policy

### Decision
Legacy routes may be retained when there is evidence of active navigation patterns, bookmarks, old links, or prior product behavior.

### Current examples
- `/teams`
- `/rank`
- `/ranks`

### Implication
Backward compatibility is a product decision, not a random convenience.

---

## 2026-03-07 — SSR fail safe rule

### Decision
Server rendered sections must degrade safely when optional arrays or metadata are absent.

### Current reminder
`TribesSection.astro` already required a guard around missing `deliverables`.

### Rule
No server rendered page should assume optional data exists without a default or guard.

---

## 2026-03-07 — Role model v3 becomes the governing model

### Decision
The platform formally adopts the v3 separation between operational role and designations.

### Target fields
- `operational_role`
- `designations`

### Transitional note
Legacy `role` and `roles` may exist during migration but must not define the long term architecture.

---

## 2026-03-07 — Deputy PM hierarchy recognition

### Decision
The hierarchy must distinguish between the main Project Manager and the supporting Deputy PM role.

### Operational meaning
- `manager` remains the principal GP layer
- `deputy_manager` becomes the explicit Co GP / Deputy PM layer

### Product implication
Frontend ordering, badges, and admin views must reflect the distinction consistently.

---

## 2026-03-07 — Members snapshot vs cycle history

### Decision
`members` is the current snapshot table. Historical role, tribe, and cycle participation belongs to `member_cycle_history`.

### Why
Trying to force both current state and historical truth into one table creates ambiguity, broken reporting, and governance confusion.

### Rule
Future timeline and historical reporting features must read from cycle aware history tables.

---

## 2026-03-07 — Product analytics governance

### Decision
The Hub may adopt PostHog and Looker Studio style dashboards, but under strict governance.

### Rules
- no unnecessary PII in analytics identity
- input masking required
- access tier restrictions required
- right to be forgotten must include analytics systems when applicable
- iframe first strategy preferred over custom frontend charting for internal admin dashboards

---

## 2026-03-07 — Source of truth doctrine

### Decision
The Hub is the only source of truth for gamification and project operational metrics.

### Implication
External tools may feed or visualize data, but they do not own business truth.

This rule exists to stop the project from dissolving into a swamp of disconnected tools pretending to be architecture.
