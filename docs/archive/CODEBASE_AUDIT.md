# Codebase Audit — March 2026

> Generated from automated analysis of all `src/`, `supabase/`, `tests/`, `scripts/`, and config files.
> Prioritized by impact on reliability, maintainability, and dark-mode/i18n readiness.

---

## Table of Contents

1. [P0 — Critical: Data & Security](#p0--critical-data--security)
2. [P1 — High: Simulated Features & Missing Backend](#p1--high-simulated-features--missing-backend)
3. [P2 — High: Design Token & Dark Mode Gaps](#p2--high-design-token--dark-mode-gaps)
4. [P3 — Medium: Hardcoded Data That Should Be Dynamic](#p3--medium-hardcoded-data-that-should-be-dynamic)
5. [P4 — Medium: Supabase RPC Hygiene](#p4--medium-supabase-rpc-hygiene)
6. [P5 — Low: Dependency Hygiene](#p5--low-dependency-hygiene)
7. [Appendix A — RPC Cross-Reference Matrix](#appendix-a--rpc-cross-reference-matrix)
8. [Appendix B — File-Level Token Migration Status](#appendix-b--file-level-token-migration-status)

---

## P0 — Critical: Data & Security

### 0.1 Hardcoded Supabase Credentials in Source

| File | Line(s) | Issue |
|------|---------|-------|
| `src/lib/supabase.ts` | 11–12 | Supabase URL and anon key as string literals (fallback when env vars are missing) |
| `src/components/nav/Nav.astro` | ~88 | Duplicate hardcoded Supabase URL |

**Risk:** Credentials in source code survive git history even if removed later. Anon keys are public by design, but the pattern is fragile — if someone copies this for a private key, it's a breach.

**Fix:** Remove hardcoded fallback values. Fail-fast if `PUBLIC_SUPABASE_URL` or `PUBLIC_SUPABASE_ANON_KEY` are not set.

### 0.2 Hardcoded PostHog Analytics Key

| File | Line(s) | Issue |
|------|---------|-------|
| `src/layouts/BaseLayout.astro` | 49–50 | PostHog project key and host URL as inline literals |

**Fix:** Move to `PUBLIC_POSTHOG_KEY` and `PUBLIC_POSTHOG_HOST` env vars.

### 0.3 Pre-Migration RPCs Not Tracked in Repo

14 RPCs are called by the frontend but have **no definition in `supabase/migrations/`**. They exist in the live DB (created before migration tracking began):

| RPC | Call Sites | Criticality |
|-----|-----------|-------------|
| `get_member_by_auth` | 10+ files (Nav, profile, admin, attendance, tribe) | **CRITICAL** — core auth function |
| `get_events_with_attendance` | attendance.astro, admin/webinars.astro | High |
| `register_own_presence` | attendance.astro | High |
| `create_event` | attendance.astro | High |
| `create_recurring_weekly_events` | attendance.astro | Medium |
| `update_event` | attendance.astro | High |
| `get_tribe_event_roster` | attendance.astro | Medium |
| `mark_member_present` | attendance.astro | High |
| `deselect_tribe` | TribesSection.astro | Medium |
| `admin_inactivate_member` | admin/member/[id].astro | Medium |
| `admin_reactivate_member` | admin/member/[id].astro | Medium |
| `get_member_cycle_xp` | profile.astro | Low |
| `get_my_member_record` | Internal helper | Low |
| `upsert_publication_submission_event` | PublicationsBoardIsland.tsx | Low |

**Risk:** If the live DB is reset or a new Supabase project is provisioned, these functions won't exist. The app would silently break on core flows (auth, attendance, tribe selection).

**Fix:** Create a baseline migration (`00000000_baseline_rpcs.sql`) that captures all pre-existing RPC definitions. Run `pg_dump --schema-only` filtered to these functions.

---

## P1 — High: Simulated Features & Missing Backend

### 1.1 `alert()` as User Feedback (8 instances)

| File | Lines | Context |
|------|-------|---------|
| `src/pages/admin/index.astro` | 3816, 3822, 3853, 3862, 3870, 3878, 3933 | Admin form submissions, destructive actions, validation |
| `src/pages/admin/settings.astro` | 107 | Settings save error |

**Impact:** Browser `alert()` blocks the main thread, is not themeable, not accessible, and provides no persistent feedback.

**Fix:** Replace with the existing `toast()` system already used in other components (CuratorshipBoardIsland, TribeKanbanIsland).

### 1.2 `confirm()` for Destructive Admin Actions (8 instances)

| File | Lines | Context |
|------|-------|---------|
| `src/pages/admin/index.astro` | 1611, 2646, 3180, 3854, 3863, 3871, 3879, 3942 | Replacing tribe leader, inactivating researchers, disbanding tribe, sending mass emails |

**Impact:** No audit trail. No undo. Irreversible actions protected only by a dismissable browser dialog.

**Fix:** Replace with confirmation modal components. For mass-email and member-inactivation, add server-side double-confirmation via RPC parameter.

### 1.3 XP Level Calculation Uses Rough Proxy

| File | Line | Issue |
|------|------|-------|
| `src/pages/profile.astro` | 713–714 | `totalHours = cycleStats.points / 10` with comment "placeholder hours — would come from a view/RPC" |

**Fix:** Create `get_member_xp_summary` RPC or use `get_member_cycle_xp` (already called elsewhere).

### 1.4 Credly Data Passed as Empty Array

| File | Line | Issue |
|------|------|-------|
| `src/pages/gamification.astro` | 584 | `aggregateCredlyByMember([])` — all members show 0 badges/points |

**Fix:** Query `credly_verifications` table before calling the aggregation function. The data exists (see `sync-credly-all` edge function).

### 1.5 `console.log` in Production Code

| File | Lines | Issue |
|------|-------|-------|
| `src/pages/tribe/[id].astro` | 1222, 1236 | Verbose broadcast logging (`jwt`, `status`, `body`) |

**Fix:** Remove or guard behind `import.meta.env.DEV`.

### 1.6 Static Tribe Fallback System

| File | Lines | Issue |
|------|-------|-------|
| `src/pages/tribe/[id].astro` | 14, 44–46 | Uses `getStaticTribeFallback()` for tribe name/description when DB unavailable |
| `src/data/tribes.ts` | Full file | 8 tribes with hardcoded names, descriptions, leaders, LinkedIn URLs |

**Impact:** If DB query fails silently, page shows stale data from `data/tribes.ts` instead of an error.

**Fix (phased):**
1. Short-term: Keep fallback but add error logging when it activates.
2. Medium-term: Migrate all tribe metadata (leader, LinkedIn, description, video URL) to `tribes` table columns. Remove `data/tribes.ts`.

---

## P2 — High: Design Token & Dark Mode Gaps

### Summary

| Metric | Count |
|--------|-------|
| Total `.astro` + `.tsx` files audited | 87 |
| Files fully on design tokens | 2–3 (BoardFilters.tsx, BaseLayout.astro) |
| Files with mixed tokens + hardcoded | ~40 |
| Files with zero token usage | ~20 |
| Files with dark mode support (`dark:` variants) | 6 (7%) |
| Estimated hardcoded color instances | **1,240+** |

### 2.1 Worst Offenders (20+ hardcoded color instances each)

| File | Hardcoded Instances | Notes |
|------|-------------------|-------|
| `src/pages/admin/index.astro` | 174 text + inline `#4F17A8` hex | Largest file in repo |
| `src/pages/admin/webinars.astro` | 51 | Heavy `bg-white`, `bg-slate-*` |
| `src/pages/gamification.astro` | 74 text + 42 border | Full page dark-mode broken |
| `src/pages/profile.astro` | 31 text + inline styles | Mixed token/hardcoded |
| `src/pages/admin/analytics.astro` | ~62 mixed | Some tokens, many hardcoded |
| `src/pages/artifacts.astro` | 42 text + 36 border | No dark-mode support |
| `src/pages/admin/selection.astro` | 34 text | No dark-mode support |
| `src/pages/presentations.astro` | Extensive | `bg-white`, `border-slate-200` throughout |
| `src/pages/help.astro` | Multiple | `bg-white border border-slate-200` |
| `src/pages/publications.astro` | Mixed | Has `dark:` variants but also hardcoded |

### 2.2 Missing Token Categories

The theme defines comprehensive surface/text/border tokens, but the following semantic categories are missing and would reduce hardcoded colors significantly:

| Missing Token | Current Hardcoded Pattern | Proposed |
|---------------|--------------------------|----------|
| Status badge colors | `bg-emerald-100 text-emerald-700` | `--badge-approved-bg`, `--badge-approved-text` |
| Status badge colors | `bg-red-100 text-red-700` | `--badge-rejected-bg`, `--badge-rejected-text` |
| Status badge colors | `bg-purple-100 text-purple-700` | `--badge-review-bg`, `--badge-review-text` |
| Status badge colors | `bg-amber-100 text-amber-800` | `--badge-pending-bg`, `--badge-pending-text` |
| Brand accent | `bg-navy`, `text-navy` | Already exists as `--color-navy` but many files use `bg-navy` hardcoded |
| KPI / metric | `bg-blue-900/10 text-blue-900` | `--kpi-bg`, `--kpi-text` |

### 2.3 Inline Style Hex Codes (22 files, 78 instances)

Most critical:
- `admin/index.astro`: `border-color:#4F17A830;background:#4F17A808`
- `AuthModal.astro`: `#0A66C2` (LinkedIn), `#BE2027` (Google), `#10B981`
- Various board components with `style={{ ... }}`

### 2.4 Typography & Spacing Inconsistencies

**Font sizes without tokens:** `text-[9px]`, `text-[10px]`, `text-[11px]`, `text-[12px]`, `text-[.65rem]`, `text-[.72rem]`, `text-[.78rem]` — used inconsistently across components. No type scale tokens exist in theme.css.

**Border radius:** Mix of `rounded-md`, `rounded-lg`, `rounded-xl`, `rounded-2xl`, `rounded-full` with no consistent scale per component type.

---

## P3 — Medium: Hardcoded Data That Should Be Dynamic

### 3.1 Tribe Metadata (16 hardcoded values)

| File | Data | Should Be |
|------|------|-----------|
| `src/data/tribes.ts` | 8 leader names + 8 LinkedIn URLs | `tribes.leader_name`, `tribes.leader_linkedin_url` DB columns |
| `src/lib/admin/constants.ts` | TRIBE_NAMES, TRIBE_LEADERS objects | Duplicate of tribes.ts — should use single DB source |
| `src/data/tribes.ts` | Tribe video URLs (8 YouTube links) | `tribes.video_url` DB column |

### 3.2 Cycle Data (4 cycles hardcoded)

| File | Data | Should Be |
|------|------|-----------|
| `src/lib/cycles.ts` | 4 cycles with dates, labels, hex colors | `cycles` table (already exists — wire it up) |

### 3.3 KPI Targets

| File | Data | Should Be |
|------|------|-----------|
| `src/data/kpis.ts` | `8 Chapters`, `+10 Articles`, `+6 Webinars`, `3 Pilots`, `1,800h Impact`, `70% Certification` | `site_config` table or `cycle_targets` |

### 3.4 Resource URLs

| File | Data | Should Be |
|------|------|-----------|
| `src/components/sections/ResourcesSection.astro` | YouTube playlist, Canva governance doc, PMI learning URL | `hub_resources` table (already exists) |
| `src/components/sections/TribesSection.astro` | YouTube playlist link | Same |

### 3.5 Contact Information

| File | Data | Should Be |
|------|------|-----------|
| `help.astro` | `https://wa.me/5562999999999` | `site_config.gp_whatsapp` |
| `onboarding.astro`, `ResourcesSection.astro` | `nucleoiagp@gmail.com` | `site_config.contact_email` |
| `admin/index.astro` | Validator name + email, base URL in VRMS evidence | Env var or `site_config` |

### 3.6 Color Constants Duplicated Across Files

| File | Data | Should Be |
|------|------|-----------|
| `src/lib/admin/constants.ts` | OPROLE_COLORS (7 roles), DESIG_COLORS (6 designations), TRIBE_COLORS (8 tribes) | Unified in theme.css or `site_config` |
| `src/lib/tribes/catalog.ts` | QUADRANT_COLORS (4), STATIC_TRIBE_COLORS (8) | Duplicate — consolidate with constants.ts |

### 3.7 Admin Import Options

| File | Data | Should Be |
|------|------|-----------|
| `admin/index.astro` | Trello board names: "Artigos - Ciclo 1", "Comunicação - Ciclo 3", etc. | Config or `import_sources` table |

### 3.8 Message Templates

| File | Data | Should Be |
|------|------|-----------|
| `admin/index.astro` | WhatsApp/email reminder messages with hardcoded URLs and greetings | i18n keys + `site_config.base_url` |

---

## P4 — Medium: Supabase RPC Hygiene

### 4.1 Unused RPCs (defined but never called from frontend)

| RPC | Migration File | Action |
|-----|---------------|--------|
| `get_curation_cross_board` | `20260317100000_board_engine_rpcs.sql` | Remove or wire to frontend |
| `publish_board_item_from_curation` | `20260315000007_curation_workflow_board_items.sql` | Remove or wire to curation flow |
| `list_webinars` | `20260309140000_webinars_and_rpc_security.sql` | Superseded by `get_events_with_attendance`? Verify and remove |
| `platform_activity_summary` | `20260312030000_list_volunteer_applications_rpc.sql` | Remove or wire to analytics |
| `kpi_summary` | `20260309001000_kpi_summary_rpc.sql` | Superseded by `get_executive_kpis`? Verify and remove |

### 4.2 Duplicate RPC Definitions (7 functions defined in multiple migrations)

| RPC | Migration Files |
|-----|----------------|
| `move_board_item` | `20260312000000`, `20260317100000` |
| `list_board_items` | `20260312000000`, `20260315000007` |
| `list_tribe_deliverables` | `20260309030000`, `20260309140000` |
| `upsert_tribe_deliverable` | `20260309040000`, `20260309070000` |
| `select_tribe` | `20260309010000`, `20260309070000` |
| `list_curation_pending_board_items` | `20260315000007`, `20260316140000` |
| `list_curation_board` | `20260311000000`, `20260311030000`, `20260311040000` |

**Risk:** Later migrations overwrite earlier ones via `CREATE OR REPLACE`, but it's unclear which version is "current". Makes debugging difficult.

**Fix:** Document in a `docs/RPC_REGISTRY.md` which migration holds the authoritative version.

### 4.3 Inconsistent Error Handling

~35 of 77 frontend RPC calls lack explicit error handling. Worst files:
- `attendance.astro` — many RPC calls without error checks
- `tribe/[id].astro` — some calls without error checks
- `admin/analytics.astro` — deferred error checking

### 4.4 Heavy Direct Table Access

20+ tables accessed directly via `.from()` with 150+ operations. Tables with heaviest direct access that could benefit from RPC abstraction:
- `tribes` (15+ calls)
- `artifacts` (10+ calls)
- `public_members` (10+ calls)
- `member_cycle_history` (10+ calls)

---

## P5 — Low: Dependency Hygiene

### 5.1 Summary

| Category | Count | Status |
|----------|-------|--------|
| Production dependencies | 20 | All actively used |
| Dev dependencies | 12 | All correctly placed |
| Unused dependencies | 0 | Clean |
| Issues found | 3 | See below |

### 5.2 Issues

| Issue | Severity | Detail |
|-------|----------|--------|
| `chart.js` listed as direct dependency | Low | Imported directly in `admin/analytics.astro`, `admin/index.astro`, `admin/comms.astro` — NOT redundant with recharts (both are used independently). **Keep.** |
| `@eslint/js` not in package.json | Low | Imported in `eslint.config.mjs` but only works as transitive dep of eslint. Add explicitly to devDependencies for safety. |
| `playwright` vs `@playwright/test` version mismatch | Low | playwright@1.49.0 vs @playwright/test@1.58.2. Align versions. |

### 5.3 Dependency Health

All dependencies are modern and well-chosen:
- `@dnd-kit/*` — correct choice over deprecated `react-beautiful-dnd`
- `@radix-ui/*` — accessibility-first headless UI
- `cmdk` — lightweight command palette
- `lucide-react` — tree-shakeable icons
- `recharts` + `chart.js` — complementary (recharts for React dashboards, chart.js for imperative admin charts)

No outdated patterns or deprecated libraries detected.

---

## Appendix A — RPC Cross-Reference Matrix

### Frontend → DB (77 unique RPCs called)

**Working (defined in migrations):** 56 RPCs
**Pre-migration (in live DB, not in repo):** 14 RPCs (see P0.3)
**Unused (defined but not called):** 5 RPCs (see P4.1)
**Edge Functions:** 13 in `supabase/functions/` (verify-credly, sync-comms-metrics, sync-knowledge-insights, sync-credly-all, sync-attendance-points, etc.)

### Tables Accessed Directly (via `.from()`)

`members`, `public_members`, `tribes`, `artifacts`, `hub_resources`, `attendance`, `events`, `course_progress`, `gamification_points`, `tribe_meeting_slots`, `announcements`, `tribe_selections`, `gamification_leaderboard`, `cycle_tribe_dim`, `impact_hours_summary`, `impact_hours_total`, `member_attendance_summary`, `cycles`, `certificates`, `broadcast_log`, `publication_submission_events`, `home_schedule`, `member_cycle_history`

---

## Appendix B — File-Level Token Migration Status

### Fully on Tokens (exemplars)
- `src/components/board/BoardFilters.tsx`
- `src/layouts/BaseLayout.astro`

### Mixed (tokens + hardcoded)
- `src/pages/profile.astro`
- `src/pages/admin/analytics.astro`
- `src/components/boards/CuratorshipBoardIsland.tsx`
- `src/components/boards/TribeKanbanIsland.tsx`
- `src/pages/publications.astro`

### Zero Tokens (need full migration)
- `src/pages/presentations.astro`
- `src/pages/help.astro`
- `src/pages/admin/settings.astro`
- `src/components/attendance/KpiBar.astro`

### Dark Mode Support Present (6 of 87 files)
- `src/pages/publications.astro` (3 instances)
- `src/pages/admin/webinars.astro` (11 instances)
- `src/pages/teams.astro` (15 instances)
- `src/components/ui/GlobalSearchIsland.tsx` (4 instances)
- `src/components/boards/TribeKanbanIsland.tsx` (6 instances)
- `src/components/boards/PublicationsBoardIsland.tsx` (26 instances)

---

## Action Plan (Recommended Order)

| # | Action | Priority | Effort | Impact |
|---|--------|----------|--------|--------|
| 1 | Create baseline migration for 14 untracked RPCs | P0 | S | Prevents catastrophic loss if DB is reprovisioned |
| 2 | Move Supabase + PostHog keys to env-only (remove fallbacks) | P0 | XS | Security hygiene |
| 3 | Replace `alert()`/`confirm()` with toast + confirmation modal | P1 | M | UX + accessibility |
| 4 | Wire Credly data to gamification page | P1 | S | Fixes empty leaderboard badges |
| 5 | Remove `console.log` from tribe broadcast | P1 | XS | Production hygiene |
| 6 | Add status badge tokens to theme.css | P2 | S | Unlocks dark mode for kanban boards |
| 7 | Migrate top-10 worst files to design tokens | P2 | L | Dark mode readiness |
| 8 | Migrate tribe metadata to DB columns | P3 | M | Eliminates `data/tribes.ts` |
| 9 | Wire KPIs + resources to `site_config` / `hub_resources` | P3 | M | Makes home page fully dynamic |
| 10 | Clean up 5 unused RPCs | P4 | XS | Reduces DB surface area |
| 11 | Add `@eslint/js` to devDeps, align playwright versions | P5 | XS | Dependency hygiene |

---

*Audit conducted 2026-03-12. Next review recommended after Workspace integration sprint.*
