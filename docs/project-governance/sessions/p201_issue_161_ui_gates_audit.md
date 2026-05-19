---
issue: 161
title: permissions - audit sensitive UI gates against V4 canFor
lane: Frontend + Foundation
priority: P1
effort: M (inventory) + variable (per surface)
status: partial-done (curatorship hotfix shipped)
opened: 2026-05-19
github: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/161
---

# p201 Session Brief - Issue #161: Sensitive UI Gates Audit (V4 canFor)

## Already shipped (do not redo)

- `CuratorshipBoardIsland.tsx` and `AdminNav.astro` now accept
  `canFor('curate_content')` and `canFor('participate_in_governance_review')`
  as fallback to legacy `hasPermission('admin.curation')` (commit
  `a6f10cdb`).
- Backlog entry `#43` in `docs/audit/P162_GAP_OPPORTUNITY_LOG.md`.

## Why this matters

V4 source of truth for authority is `can_by_member()` / `canFor()` /
capability cache. Many UI surfaces still gate visibility/enablement via
`hasPermission(...)` which reads role/designation maps. When V4
capabilities are granted through engagements (committee coordinator,
study group owner, etc.), the UI can hide actions or whole pages even
though the DB/RLS would allow them. This is the class of bug that hit
Roberto and Sarah on `/admin/curatorship`.

## Lane and gates

- Lane: Frontend (`src/components/`, `src/pages/`, `src/i18n/`,
  `src/lib/navigation.config.ts`) + Foundation (read-only RPC inspection
  to confirm what actions the surface should require)
- Can touch: any `*Island.tsx` and `*Nav*.astro`, the helpers in
  `src/lib/permissions.ts`
- Can't touch: `engagement_kind_permissions` seed, `can()` /
  `can_by_member()`, RLS policies. If a missing capability is discovered,
  open a new Foundation issue rather than seeding inline.
- Gates: `npx astro build` PASS; persona smoke for Roberto, Sarah,
  Marcos, Herlon, leader, curator, chapter_liaison; superadmin
  simulation must remain isolated from real-user capability cache.

## In scope

1. Inventory every `hasPermission(...)` callsite (start with
   `grep -rn "hasPermission(" src/`).
2. Classify each callsite:
   - **a) Local-tier (intentional)**: tier-derived visibility for nav
     discoverability, no scoped authority. Document and keep.
   - **b) Scoped authority (must migrate)**: gates a write/read action
     that V4 grants through engagement or capability cache. Migrate to
     `canFor(...)` with legacy fallback for compatibility.
   - **c) Designation hardcoded (anti-pattern)**: gates a sensitive
     action by a static designation array. Replace with `canFor(...)`.
3. For each (b) and (c), patch the surface + add a quick smoke note in
   the PR description.
4. Add (or extend) a smoke test file under `tests/personas/` (or
   `tests/integration/`) that runs the 7 personas through key surfaces.

## Out of scope

- Refactoring `src/lib/permissions.ts` shape (helpers stay as-is).
- Touching the capability cache or `get_caller_capabilities()`.
- Deciding whether to deprecate `operational_role` cache (separate ADR).

## Recommended surfaces (priority order)

1. `src/components/nav/AdminNav.astro` - rest of the link map (only
   `curatorship` patched in #161 hotfix; audit `applications`,
   `cycles`, `analytics`, `partners`, `sustainability`, `tribes`,
   `wiki`, `cpmai`).
2. Admin pages with write actions:
   - `/admin/tribes/[id]` (manage_event, manage_member)
   - `/admin/portfolio` (write_board)
   - `/admin/partners` (manage_partner)
   - `/admin/gamification` (award_champion, manage_platform)
   - `/admin/attendance` (manage_event)
3. Member-side action surfaces that V4 should grant via engagement:
   - `BoardCardIsland` (write_board scoped to initiative)
   - `TribeEventRoster` (manage_event scoped to tribe)
   - `ProposeWebinarIsland`, `CurationReviewIsland`

## Validation

- `grep -rn "hasPermission(" src/ | wc -l` decreasing trend across PRs.
- `grep -rn "canFor(" src/` covers each migrated surface.
- `npx astro build` PASS, `npm test` PASS (baseline 1449/0/46 offline).
- Manual persona smoke: Roberto sees curation, Sarah sees curation,
  Marcos sees tribe-7 actions, Herlon sees pending-leadership badge (if
  #160 path C picked), generic curator sees curation, chapter_liaison
  sees chapter analytics.

## Rollback

- Each migrated surface is a small diff; revert the specific file. The
  legacy fallback (`hasPermission(...) || canFor(...)`) means revert is
  always safe.

## Cross-references

- Issue #160 (Herlon) - affects persona smoke
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` items #43, #44
- `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` §5.4 (recommended audit matrix)
- ADR-0007 (V4 authority), ADR-0011 (V4 cutover invariants)

## Handoff (fill on completion)

```md
## Handoff
Issue: #161
Branch:
Escopo:
Inventory size:
Surfaces migrated:
Persona smoke results:
Validacao:
Riscos:
Rollback:
Docs:
Proximo passo:
```
