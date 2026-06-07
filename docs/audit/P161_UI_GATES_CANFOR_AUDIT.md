# P161 — Sensitive UI Gates Audit (V3 `hasPermission` → V4 `canFor`)

**Issue:** #161 — *permissions: audit sensitive UI gates against V4 canFor*
**Date:** 2026-06-06
**Trigger:** p201 root cause — Roberto & Sarah held `curate_content=true` via **engagement**, but the UI gated on
a global `hasPermission(...)` keyed on the cached `operational_role`, which didn't reflect it → they were wrongly
**blocked**. Same class can leak the other way (a tribe-X leader sees tribe-Y controls via a global gate).

## The two functions

| | `hasPermission(member, perm)` (`src/lib/permissions.ts:563`) | `canFor(action, scope?)` (`:418`) |
|---|---|---|
| Source | `member.operational_role` (ONE cached tier) + `member.designations` | engagement-derived `org_actions` / `initiative_actions` / `tribe_actions` |
| Scope awareness | **None** — global/tier only | initiative- or tribe-scoped |
| Simulation | Yes (`_simulation` branch) | No (reads real caps) |

`canFor` for `.astro` inline scripts is reached via the `window.__nucleoCanFor` bridge defined in
`Nav.astro:1056`; React islands import `canFor` directly. The reference migration pattern is
`CardDetail.tsx:103-104` (initiative-first, tribe fallback).

## Classification rubric (3 classes + orphan)

- **A — KEEP**: gate decides a global/org-tier affordance (page entry to an admin surface, "is staff-tier",
  self-service "can this person submit at all"). No specific tribe/initiative resource is gated. `hasPermission`
  (or `canForAdminEntry`) is the correct axis.
- **B — MIGRATE**: gate controls an action on a SPECIFIC tribe/initiative that is in scope at the callsite, but
  uses the global `hasPermission`. Scope-leak / under-grant bug. Migrated to `canFor(action, {type, id})`.
- **C — DOCUMENT (intentional local-tier)**: tier-level affordance (view-tier selector, display/UX hint, or
  self-service filtered to the viewer's own id) where the underlying **data RPC enforces the real gate
  server-side**. Kept as `hasPermission`.
- **ORPHAN**: gates in `TribeKanbanIsland.tsx` — a confirmed 0-mount orphan (imported by `tribe/[id].astro` but
  never JSX-rendered; the live board is `BoardEngine`). MOOT — to be **deleted** separately (its 3
  ui-stabilization test reads must be re-pointed first), not migrated.

## Result

| Class | Count |
|---|---|
| A — keep (global-tier, correct) | 37 |
| **B — migrated to `canFor`** | **8** |
| C — documented local-tier | 9 |
| Orphan (TribeKanbanIsland — delete separately) | 11 |
| **Total `hasPermission(` callsites audited** | **65** |

## Class B — migrated (this PR)

Each MCP/UI gate now **mirrors the underlying RPC's own server gate** (verified live from `pg_proc`):

| Callsite | Gated resource | RPC server gate (verified) | New UI gate |
|---|---|---|---|
| `tribe/[id].astro:983` (canSeeContacts) | member-contact PII display | `get_*_member_contacts` → **`view_pii`** (init) / `view_pii` OR tribe `write` | `canSeeTribeContacts()` helper |
| `tribe/[id].astro:~1622` (fetch contacts) | PII RPC fetch | idem | `canSeeTribeContacts()` |
| `tribe/[id].astro:~1818` (fetch contacts) | PII RPC fetch | idem | `canSeeTribeContacts()` |
| `tribe/[id].astro:~1456` (broadcast tab) | leader broadcast affordance | leader/write | `isLeaderOfThisTribeV4()` → `write_board` |
| `tribe/[id].astro:~1887` (canEdit) | minutes/board edit | `write_board` | `isLeaderOfThisTribeV4()` |
| `workspace.astro:425` (isLeader) | own-tribe dashboard link/badge | `write_board` | `__nucleoCanFor('write_board', {tribe})` |
| `meetings/MeetingsPage.tsx:236` (canCurateChampions) | champions-da-noite picker | `set_event_champions` → **`manage_event` OR `award_champion`** (org-level `can_by_member`) | **scopeless** `canFor` (org mirror) — see note |
| `ui/PresentationLayer.astro:109` (canShowToggle) | tribe presentation toggle | `write_board` | scoped `canFor` on CTX init/tribe |

**Corrections caught during audit/review (UI gate must mirror the real RPC gate, not a plausible substitute):**
- The contact gates (983/1622/1818) gate **`view_pii`** server-side, not `write_board`
  (`get_initiative_member_contacts` → `can(view_pii, initiative)`; `get_tribe_member_contacts` → `view_pii` OR
  tribe `write`).
- `set_event_champions` gates on **org-level** `can_by_member('manage_event') OR can_by_member('award_champion')`
  (`can(…, NULL, NULL)`), so the champions gate is a **scopeless** `canFor('manage_event') || canFor('award_champion')`
  — NOT scoped to the event. Scoping it to the event's tribe/initiative was both an over-restriction (the RPC is
  org-wide) and a regression on *geral* meetings (no tribe/initiative → permanently false; also
  `get_meeting_detail` doesn't return `initiative_id`). Caught by the adversarial review.

### Simulation overlay (DoD: "no regression in simulation mode")

`canFor` reads **real** capabilities (superadmin bypass), so it cannot preview a lower tier. Mirroring the
established pattern (`AdminNav.astro:122-126` uses `!isSimulating ? canFor : hasPermission(effectiveMember)`;
`useBoardPermissions.ts:113-119` overlays `getSimulation()` onto an effective role/tribe), every migrated gate
branches:

```
const sim = getSimulation();
if (sim.active) return hasPermission(member, 'board.edit_tribe_items') && getEffectiveTribeId(member) === ID; // V3 preview
… canFor(...) …                                                                                                 // V4 real
```

This also **fixes** a pre-existing simulation bug: the old gates compared the **real** `member.tribe_id` even
while simulating; the overlay now uses `getEffectiveTribeId` (the simulated tribe).

## Class C — intentional local-tier (kept; data gated server-side)

| Callsite | Permission | Why local-tier is correct |
|---|---|---|
| `workspace.astro:596` | `content.submit_publication` | "My Publications" self-service; data filtered to the viewer's own `member.id`. |
| `workspace.astro:807` | `event.create` | Un-hides the AttendanceForm island; the island filters to `member.tribe_id` server-side. |
| `workspace/AttendanceDashboard.tsx:77` | `event.create` | `isLeader` view-tier selector; rows come from a tribe-filtered RPC. |
| `workspace/AttendanceForm.tsx:63` | `event.create` | `isLeader` filtering of an already tribe-scoped form. |
| `workspace/DropoutRiskBanner.tsx:43` | `event.create` | `isLeader` reveals the banner; `get_dropout_risk_members` filters to the caller's tribe. |
| `admin/gamification.astro:706` | `champion.award` | Deliberate surface-visibility gate (audit GI-2/#424); the award RPC re-gates. |
| `admin/gamification.astro:728` | `champion.award_general` | Pure UX hint dropping the 'general' `<option>`. |
| `help/HelpFloatingButton.tsx:360` | `board.create_item` | Pure display hint: show the "leaders" FAQ section. |
| `help/HelpFloatingButton.tsx:361` | `admin.access` | Pure display hint: show the "admin" FAQ section. |

These rely on the data RPC as the real enforcer; the `hasPermission` gate is a tier-level UI affordance only.

## Class A — kept (global-tier, correct)

37 callsites: admin page-entry gates (`admin/*.astro` — `admin.access`/`admin.portfolio`/`admin.analytics`/…),
the admin-nav link map (`AdminNav.astro:126`), self-service global gates (`publications.astro:515`,
`gamification.astro:1446`), workspace org-tier gates (`workspace.astro:502` GP alerts), and the
`isGP` (`admin.access`) axis in the attendance components (distinct from the `isLeader` Class-C flag). All gate a
global/org-tier affordance with no specific tribe/initiative in scope — `hasPermission` is the right axis.

## Follow-up (not in this PR)

- **Delete the `TribeKanbanIsland.tsx` orphan** (11 MOOT gates). Blocked on re-pointing 3 `ui-stabilization`
  test reads to `BoardEngine` first (see [[handoff-2026-06-05-curatorship-cluster-swept]]).

## Persona smoke (DoD)

| Persona | Expectation | Mechanism |
|---|---|---|
| Roberto / Sarah (curator via engagement) | sees curation + own-tribe contacts despite stale `operational_role` | `canFor('view_pii'/'curate_content', scope)` reads engagement caps ✓ |
| Tribe leader (engagement) of tribe X | edit/contacts on tribe X only, not tribe Y | scoped `canFor` — no cross-tribe leak ✓ |
| Marcos / Herlon / member | masked contacts, no edit | gate returns false; server RPC returns `{}` ✓ |
| chapter_liaison | admin entries via `canForAdminEntry`; no tribe-scoped edit | Class-A gates unchanged ✓ |
| superadmin simulating tier T | previews tier T's affordances | simulation overlay (V3 path on effective tribe) ✓ |
