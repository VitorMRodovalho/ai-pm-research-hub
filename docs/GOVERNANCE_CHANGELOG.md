# Governance Changelog

## 2026-03-12 — Waves 36-40: Analytics V2 Rollout

### Decisions

1. **`/admin/analytics` becomes an internal read-only surface, not an admin-write surface by accident**: `sponsor`, `chapter_liaison`, and `curator` can now read Analytics V2, but write/admin powers remain anchored to `admin_manage_actions` and the sensitive selection route stays admin-only.

2. **Analytics stories must land on explicit SQL contracts before frontend storytelling**: funnel, innovation hours, certification delta, chapter ROI, and leadership journey now each have a dedicated RPC or shared scoped helper, so product logic is not spread across browser-only aggregation code.

3. **Cycle-aware filtering is the default contract for executive dashboards**: the new global filter bar (`cycle_code`, `tribe_id`, `chapter_code`) is now the stable entry point for partner-facing internal reads, rather than per-chart one-off filters.

### Process Lessons Learned

1. **Read-only audience expansion should happen through route-specific exceptions, not by lowering the whole admin tier model**: keeping analytics as a designation-aware exception avoided accidental write access drift across other admin pages.

2. **One migration can still be multi-wave if the product dependency graph is already aligned**: once the ACL, filter model, and chart direction were decided, it was safer to ship the whole analytics contract set together than to leave half the dashboard on placeholders.

---

## 2026-03-12 — Wave 35: Dynamic Tribe Catalog Foundation

### Decisions

1. **Tribe routing and navigation can no longer be hard-bounded to the original `1..8` set**: the internal catalog now needs to accept runtime tribe ids so project management can open new workstreams without first editing route guards and static dropdowns.

2. **Active/inactive tribe visibility must be explicit at the catalog level**: deriving “active tribe” only from current member rosters is not enough once the platform starts preserving inactive and historical tribes. `tribes.is_active` becomes the current-cycle visibility flag, while member history and past-cycle reads remain separate concerns.

3. **Opening a new tribe belongs to project management, while inactive history remains a superadmin privilege**: GP / Deputy Manager / `co_gp` can now create and operate the runtime tribe catalog for the current cycle, but only superadmin should broadly browse inactive tribes in the general navigation and exploration surfaces.

### Process Lessons Learned

1. **A quick fix can become the blueprint for the structural slice**: once `Explorar Tribos` was reopened for active members, the next blocker surfaced immediately in the fixed catalog assumptions spread across admin, workspace, artifacts, and gamification.

2. **Runtime catalog work needs both schema and UI passes**: adding `is_active` without replacing fixed dropdowns would still leave the admin surface partially trapped in the old `01..08` model. The structural slice had to move both the database contract and the client-side selectors together.

---

## 2026-03-11 — Wave 34: Tribe Exploration Access And Lifecycle Expansion

### Decisions

1. **Tribe discovery should be available to active members even without a current tribe allocation**: The platform now treats active membership as sufficient to explore active tribes in read-only mode, instead of hiding tribe navigation behind personal allocation only.

2. **Viewing another tribe and managing another tribe are separate concerns**: `/tribe/[id]` now allows broader read access for active members, but editing, broadcast, and other management actions remain restricted to local leadership or the project-management layer.

3. **Project management must be able to operate tribe lifecycle flows without waiting on superadmin**: The existing lifecycle RPCs for moving members, replacing tribe leaders, and deactivating members/tribes now extend to GP / Deputy Manager / `co_gp`, while superadmin remains the broader historical and inactive-state authority.

### Process Lessons Learned

1. **Navigation bugs can hide source-of-truth drift**: The broken `Explorar Tribos` flow surfaced that the frontend still assumed a `tribes.is_active` field that is not present in the typed schema. Deriving visibility from the active roster is safer than relying on a phantom flag.

2. **Quick fixes should still close the security side of the loop**: Fixing the menu alone would have left `/tribe/[id]` loosely exposed. The route guard had to be tightened in the same slice so discovery and protection stayed aligned.

3. **Not every adjacent ask belongs in the same sprint**: Dynamic tribe creation was intentionally left for a later slice because the route, catalog, and i18n layers are still hard-bounded to the current `1..8` tribe set.

---

## 2026-03-11 — Wave 33: Webinars In-Module Authoring Aids

### Decisions

1. **Reuse surfaces can expose contextual aids without becoming webinar-specific products**: `Attendance` now offers webinar-aware edit guidance, and `Admin Comms` now offers webinar-aware draft snippets, but both remain their original modules rather than sprouting a second CRUD flow.

2. **Drafting and QA assistance are valid steps before any deeper workflow build-out**: The new aids reduce operator effort by focusing attention and seeding communication copy, which delivers value without schema changes or new backend actions.

### Process Lessons Learned

1. **Interoperability can evolve from navigation into task assistance**: Once contextual landing states exist, the next meaningful improvement is helping the operator perform the intended task faster inside the destination module.

2. **Keep helper scope intentionally thin**: Subject lines, body seeds, field focus, and targeted reminders are enough to improve execution without duplicating the final authoring or send workflow.

---

## 2026-03-11 — Wave 32: Webinars Attendance And Comms Handoffs

### Decisions

1. **The contextual-handoff pattern should include the highest-friction operator destinations, not only content surfaces**: After `Presentations` and `Workspace` accepted query-driven context, the remaining friction lived in `Attendance` and `Admin Comms`. Those destinations now understand webinar handoff state too.

2. **Focused route state is still preferable to webinar-local workflow duplication**: `Attendance` now lands on the right webinar context and can optionally open the edit modal, while `Admin Comms` can open with webinar-oriented history focus. This preserves reuse and avoids creating a second operational UI inside `/admin/webinars`.

### Process Lessons Learned

1. **A handoff is stronger when it reaches the action surface, not only the reporting surface**: Operators save more time when the destination is ready for the intended task, not just filtered to the right record family.

2. **Browser checks can still protect interoperability indirectly**: Even without full end-to-end coverage for each destination page, validating that `/admin/webinars` emits the expected contextual links helps keep the flow coherent.

---

## 2026-03-11 — Wave 31: Webinars Contextual Handoffs

### Decisions

1. **Cross-module handoffs should land in filtered views, not generic destination pages**: Once `/admin/webinars` began recommending actions, the next friction point was that `Presentations` and `Workspace` still opened in broad list mode. They now accept URL-driven filters so operators land closer to the relevant webinar.

2. **Shareable query-based context is a good intermediate step before more workflow-specific UI**: Search and filter parameters reduce context switching without adding schema, local write paths, or webinar-specific duplicates of existing modules.

### Process Lessons Learned

1. **Thin orchestration gets better when the target surface also understands the context**: Linking to the right module helps, but linking with the right filter helps more. Small deep-link improvements can materially reduce operator effort.

2. **Reused modules benefit from small interoperability passes**: Even when a module is not webinar-specific, adding stable query-driven entry points makes it more useful as part of a broader operational flow.

---

## 2026-03-11 — Wave 30: Webinars Operator Actions

### Decisions

1. **The webinars panel should recommend the next operator step, not just report status**: Publication and attendance signals were already visible, but the operator still had to infer which module to open next. The panel now derives a recommended action per webinar and links directly to the existing operational surface.

2. **Guidance should stay on top of the current modules instead of creating local write paths**: Quick actions now route users toward `Attendance`, `Admin Comms`, `Presentations`, or `Workspace` according to the webinar state, preserving the events-first model and avoiding premature CRUD sprawl inside `/admin/webinars`.

### Process Lessons Learned

1. **Operator UX improves when status is paired with a concrete handoff**: “Pending” alone still leaves work ambiguous. Pairing state with a recommended destination makes the panel materially more useful without backend changes.

2. **Small orchestration improvements are valid sprint slices**: The page does not need new schema or new mutations to deliver value; reducing context switching for admins is already meaningful product progress.

---

## 2026-03-11 — Wave 29: Webinars Browser Coverage

### Decisions

1. **`/admin/webinars` now deserves real browser coverage, not only file-level guards**: Once the page became an actual operational surface with ACL behavior and publication signals, textual regression checks alone were no longer enough. The browser suite now validates both anonymous denial and a mocked admin rendering path.

2. **Lightweight mock injection is acceptable for internal browser coverage when credentials are unavailable**: The browser test now injects a controlled admin member and Supabase-like responses into the page so the operational webinar UI can be validated without depending on real login credentials or production data.

3. **Anonymous admin routes should fail closed, not hang in loading**: Browser coverage exposed that `/admin/webinars` could stay stuck in loading for anonymous visitors because it only waited for `nav:member`. The page now resolves anonymous sessions to denied state explicitly while still listening for future authenticated handoff.

### Process Lessons Learned

1. **Browser tests can expose guard bugs that textual tests miss completely**: The loading-state bug in `/admin/webinars` was not visible through file-level checks. Real browser execution surfaced it immediately.

2. **Test harness resilience matters too**: The browser test script now claims an actually free port before starting Astro, which makes the suite more reliable under repeated local runs.

---

## 2026-03-11 — Wave 28: Webinars Replay Publication Follow-Through

### Decisions

1. **Replay publication status should be visible from the webinar admin surface itself**: Once `/admin/webinars` started orchestrating sessions on top of `events`, operators still had to infer manually whether a replay had reached `Presentations` or `Workspace`. The panel now reads both surfaces and exposes that state directly.

2. **Cross-surface matching can remain heuristic while the model stays schema-light**: `Presentations` can be matched through `meeting_artifacts.event_id`, while `Workspace` can be inferred from active `hub_resources` webinar entries keyed by replay URL or title context. That is good enough for an events-first MVP and avoids premature schema expansion.

### Process Lessons Learned

1. **Operational reuse becomes stronger when publication gaps are explicit**: Reusing existing modules is not only about linking to them; it is also about making the missing handoff visible so operators know what still needs to be published.

2. **A thin admin orchestrator can still provide meaningful observability**: Even without direct write actions, the webinar panel now helps teams understand replay coverage across the Hub in one place.

---

## 2026-03-11 — Wave 27: Admin Webinars Events-First MVP

### Decisions

1. **`/admin/webinars` should orchestrate the existing event workflow, not create a parallel webinar CRUD**: The new admin surface now reads webinar sessions from `get_events_with_attendance`, filters `type='webinar'`, and points operators back to the modules already responsible for scheduling, comms, replay, and content publication.

2. **Webinar-specific operator visibility can ship before webinar-specific schema**: Upcoming sessions, replay backlog, attendance totals, and quick operational links are already derivable from the current event stack. The platform can expose webinar-focused guidance without committing to new tables.

### Process Lessons Learned

1. **Deferred discovery work should convert quickly into a thin operational surface**: Once the source of truth and scope boundaries were defined, the next useful step was not more planning but a small admin UI that makes the approved model visible and actionable.

2. **Cross-module orchestration is a legitimate MVP outcome**: An admin page does not need to own every create or edit action to be valuable. In this case, linking `attendance`, `admin/comms`, `presentations`, and `workspace` produced a coherent operational hub with minimal implementation risk.

---

## 2026-03-11 — Wave 26: Webinars Module Discovery

### Decisions

1. **Webinars should be implemented on top of the current event stack before new schema is introduced**: The repo already supports `events.type='webinar'`, authenticated attendance, replay publication, comms, and aggregated analytics. The next MVP should reuse those paths instead of opening a parallel operational model prematurely.

2. **The existing `webinars` table is not yet the operational source of truth**: Because it overlaps with `events` but does not sit on the current attendance and reporting path, promoting it now would create dual-source drift. A convergence or retirement decision must come before any broader webinar build-out.

3. **The first webinars slice remains internal/member-first**: External registration, reusable speaker records, automated certificates, and provider integrations remain out of scope until product and governance explicitly approve the extra ACL, LGPD, and data-model requirements.

### Process Lessons Learned

1. **Discovery needs to settle source of truth before UI or schema expansion**: The repo already had enough webinar-related assets to start building, but not enough agreement on which model should drive them. Clarifying that first avoids rework across attendance, analytics, and comms.

2. **Cross-module reuse is often the fastest gap-closure path**: Existing attendance, workspace, presentations, comms, and analytics surfaces already cover most webinar MVP requirements. A focused reuse decision can move the product forward faster than creating more tables.

---

## 2026-03-11 — Wave 25: Public Home Browser Coverage Expansion

### Decisions

1. **Runtime home work now deserves browser assertions, not only file-level locks**: After several waves moved public-home behavior from fixed literals to runtime schedule state, textual checks alone were no longer enough. The public browser suite now covers the key `Hero` and `Tribes` runtime signals on a real page.

2. **Stable browser hooks are preferable to brittle selector guesswork**: `TribesSection` now exposes explicit ids for the state, deadline, and notice summary elements so browser tests can verify behavior directly without coupling to incidental DOM structure.

### Process Lessons Learned

1. **Browser coverage should grow alongside runtime complexity**: Once `Hero` and `Tribes` both depended on runtime schedule state, asserting only one public element left a meaningful gap. Lightweight end-to-end checks continue to provide strong value here.

2. **Public anonymous behavior is a valid regression surface on its own**: Even without authenticated flows, the anonymous home path already exercises schedule state, visibility transitions, and call-to-action behavior worth protecting in browser tests.

---

## 2026-03-11 — Wave 24: Tribes Deadline Formatting Cleanup

### Decisions

1. **Public deadline formatting should use the same locale-aware runtime path across sections**: `AgendaSection` and `ResourcesSection` had already moved to `Intl.DateTimeFormat` with the Sao Paulo timezone, but `TribesSection` still rendered the selection deadline through a manual UTC-3 adjustment and a Portuguese-only month array. This wave aligns that formatting path.

2. **Dormant fixed-date locale strings are still drift risk**: Even if `tribes.deadline` was no longer the active render path, leaving the old March date in locale bundles kept stale copy one refactor away from resurfacing. Generic fallback wording is safer.

### Process Lessons Learned

1. **Formatting debt can hide inside “working” runtime flows**: A surface may already be runtime-driven while still formatting the resulting timestamp through brittle hand-written logic. Runtime adoption is not complete until formatting paths are normalized too.

2. **Dead fallback copy deserves regression coverage once cleaned**: When a locale key becomes effectively dormant, removing stale literals is only half the job. A small textual test is enough to keep them from coming back unnoticed.

---

## 2026-03-11 — Wave 23: Hero Kickoff Runtime Truth

### Decisions

1. **`home_schedule` should decide when kickoff is over, not the latest `events` row**: The hero already depended on `home_schedule` for public schedule messaging, but its post-kickoff state still flipped based on the latest global event date. Wave 23 moves that state transition to `kickoffAt`, which is the intended public schedule contract.

2. **Legacy event reads remain acceptable only as optional enrichment**: Replay links and meeting links can still come from `events`, but the public home should no longer wait on or trust that table to know whether kickoff already happened.

### Process Lessons Learned

1. **Runtime source-of-truth work often needs a second pass on client scripts**: Server-rendered copy had already moved toward `home_schedule`, but one client-side branch still encoded operational truth via `events`. Hydration paths need the same audit discipline as SSR props.

2. **Validation failures can be environmental without invalidating the slice**: The first smoke rerun failed due to `ENOSPC` from orphaned `astro dev` watchers, while browser validation for the actual behavior had already passed. Cleaning the stale processes and rerunning smoke was enough to confirm the tranche.

---

## 2026-03-11 — Wave 22: Public Cycle Copy Cleanup

### Decisions

1. **Public labels should prefer generic current-cycle wording until cycle metadata is runtime-driven**: The home hero badge and supporting sections still exposed `Cycle 3` even after schedule-sensitive text had been cleaned up. Where runtime cycle metadata is not yet available, generic current-cycle copy is safer than a stale cycle number.

2. **Visible public drift matters even when behavior is correct**: The schedule flow, ACL, and page wiring were already aligned, but visitors could still read copy that implied an older cohort. Copy-only cleanup remains valid engineering work when it prevents misleading public state.

### Process Lessons Learned

1. **Runtime hardening exposes neighboring static labels**: Once date and deadline strings are cleaned up, fixed cycle labels stand out immediately. Public-home audits should check both schedule references and cohort/cycle wording together.

2. **Regression tests should target the exact literals removed**: File-wide bans on `Cycle 3` can overreach into unrelated surfaces. The safer pattern is to lock the exact public strings touched in the current slice.

---

## 2026-03-11 — Wave 21: Resources Runtime Fallback Alignment

### Decisions

1. **Shared home schedule inputs should feed every visible schedule-adjacent fallback card**: After Hero, Agenda, Tribes, and generic home copy were aligned, `ResourcesSection` still exposed a playlist card with the old Saturday-noon deadline. Passing the same `deadlineIso` into that section keeps the public home from splitting its runtime truth across components.

2. **Shared public components should not ship one-language fallback copy**: `ResourcesSection.astro` served Portuguese-only fallback card labels even on English and Spanish pages. Fallback content now lives in locale keys so the component degrades consistently in every language.

### Process Lessons Learned

1. **Runtime consistency work often reveals latent localization debt**: A schedule-related cleanup in one card quickly exposed that the entire fallback list was still hardcoded in a single language. Small runtime slices should still scan for neighboring localization drift.

2. **Textual tests are enough to lock prop wiring between home sections**: Verifying that all localized pages pass `deadlineIso` into another section is a cheap way to prevent copy drift from reappearing as new runtime-aware sections are added.

---

## 2026-03-11 — Wave 20: Generic Home Fallback Cleanup

### Decisions

1. **Public fallback copy should degrade generically, not lie precisely**: Once the home moved to runtime `home_schedule`, leftover literal fallback strings such as fixed March kickoff dates or recurring Thursday times became a reliability risk. When schedule runtime is missing or partial, generic cycle-oriented messaging is safer than stale precision.

2. **Localized runtime hardening includes inline script defaults, not only locale files**: Updating the i18n bundles alone would still leave the hero client script capable of showing old fixed meeting times if its payload was incomplete. The remaining inline defaults were therefore normalized in the same wave.

### Process Lessons Learned

1. **Small copy debt can still be operational debt**: Even when behavior and ACL are correct, stale public dates erode trust quickly. Small cleanup waves are justified when they remove misleading operational messaging.

2. **Textual regression checks are effective for fallback hygiene**: A lightweight test that asserts old literals are absent is enough to keep these stale schedule strings from quietly reappearing.

---

## 2026-03-11 — Wave 19: Agenda Runtime Deadline Sync

### Decisions

1. **Runtime schedule consistency matters even in supporting sections**: After Hero and Tribes moved to runtime `home_schedule`, the agenda still announced the tribe-selection deadline through a fixed locale string. Wave 19 aligns that supporting section with the same runtime source to avoid split-brain messaging on the landing page.

2. **Localized runtime copy should prefer composable prefixes over duplicated date strings**: Instead of hardcoding another date variant per locale, the agenda now combines a translated prefix with the formatted runtime deadline. This keeps localization intact while reducing future date churn.

### Process Lessons Learned

1. **Small follow-through waves are worth closing cleanly**: Once the larger runtime home model existed, this agenda drift was a small but visible inconsistency. Treating it as its own closure step avoids leaving low-grade copy debt behind.

---

## 2026-03-11 — Wave 18: Home Runtime Messaging And Browser Expansion

### Decisions

1. **Home schedule should feed user-facing copy, not only lock rules**: After Wave 17 moved selection availability off the `2030` sentinel, the next gap was that the landing page still introduced the kickoff and recurring meeting cadence through static locale strings. Wave 18 promotes `home_schedule` from a gate-only source to a presentation input for the home hero.

2. **One shared schedule read is preferable to multiple narrow reads**: The three localized home pages now load the same `getHomeSchedule()` contract and pass it down, instead of each surface or helper fetching only one field. This keeps runtime messaging and deadline logic aligned.

3. **Visibility transitions should not wait for analytics/count fetches**: The hero's cycle-status shell should become visible as soon as the schedule state says the countdown is over. Fetching counts can remain asynchronous, but the layout transition itself should not depend on `navGetSb()` timing.

4. **Browser coverage should pair public-state checks with ACL checks**: Testing only the admin guard was useful but incomplete. The browser suite now also validates a public home behavior driven by runtime schedule state, giving coverage to both access control and post-deadline UX in one lightweight path.

### Process Lessons Learned

1. **Runtime-driven copy often reveals hidden script-scope assumptions**: The `HeroSection` post-deadline state still depended on a variable defined in a separate script block. Browser validation exposed that gap quickly, and the fix was to pass the state explicitly through the client payload.

2. **Public browser checks provide fast value without credentials**: Before tackling authenticated modal flows, there is still substantial regression value in verifying anonymous guards and public runtime UI states against real pages.

---

## 2026-03-11 — Wave 17: Home Schedule Hardening And Browser Guard Base

### Decisions

1. **Missing schedule config should no longer look like an open window**: The old far-future fallback (`2030-12-31`) kept the home selection surfaces in a fake "still open" state when `home_schedule.selection_deadline_at` was absent. The landing flow now treats that condition explicitly as `pending`, which is safer and more honest than inventing a date.

2. **Hero and Tribes should derive availability from the same runtime schedule source**: `schedule.ts`, `HeroSection.astro`, and `TribesSection.astro` now share the same operational truth: valid deadline means countdown/open window, past deadline means closed, no deadline means pending configuration.

3. **Touched legacy links should leave inline handlers behind**: While hardening `TribesSection.astro`, the remaining `onclick="event.stopPropagation()"` links were migrated to explicit listeners so the touched surface keeps following the delegated/no-inline direction adopted in later waves.

4. **Browser guard coverage starts with ACL, not UI polish**: The first Playwright-backed check targets `/admin/selection` access denial for anonymous users. This gives immediate regression value on LGPD-sensitive access control before broader modal or authenticated flows are added.

### Process Lessons Learned

1. **A restored CLI audit path should be re-validated immediately**: After the earlier transient auth failure, rerunning `supabase migration list` in the next slice confirmed the live path is healthy again and reduced the operational uncertainty left over from Wave 16.

2. **Standalone browser scripts are a better first step than forcing a full browser test runner**: Reusing the smoke-test pattern (`start dev server → exercise real browser → shut down`) is enough to start browser coverage without adding extra framework overhead.

---

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
