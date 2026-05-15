# ADR-0083 — Capability cache for UI gates (V4 conformity)

**Status:** ACCEPTED 2026-05-15
**Date:** 2026-05-15
**Session:** p163
**Refs:** ADR-0007 (V4 authority via can()), ADR-0080 (V4 engagement canonical), `docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md`

## Context

V3 frontend gates check authority by exact-match on the legacy cache `members.operational_role`:

```ts
member.operational_role === 'tribe_leader'
['manager','deputy_manager','tribe_leader','comms_leader',...].includes(member.operational_role)
```

This pattern fails the V4 reality. `operational_role` is a single-value GLOBAL cache derived by trigger `sync_operational_role_cache` from a priority ladder over engagements. The trigger is **"highest engagement wins"** without scope distinction:

- `volunteer.leader` (research_tribe leadership) → `tribe_leader`
- `workgroup_member.leader` (Hub Comunicação leadership) → `tribe_leader`
- `committee_coordinator.coordinator` → `tribe_leader`
- `study_group_owner.leader` → `tribe_leader`

But `TIER_PERMISSIONS.tribe_leader` in `src/lib/permissions.ts` grants **cross-context privileges** (admin.access, admin.portfolio, board.edit_tribe_items, event.create globais). Logo, anyone who leads any workgroup or committee gets "leader of tribe of pesquisa" privileges everywhere.

p163 audit (2026-05-15): a Track E (p162) backfill promoted 6 mems via the trigger compute. PM flagged that 5/6 promotions were scope-leak (Sarah/Roberto are curators not tribe leaders; Mayanna/Maria Luiza/Leticia lead Hub Comunicação workgroup but are researchers in their tribes). Backfill was reverted.

The fix in `sync_operational_role_cache` would be invasive and trigger-state-coupled. ADR-0007 already established that `can()` is the V4 source of truth, scoped per resource. The frontend just hadn't migrated.

## Decision

Introduce a capability cache RPC `get_caller_capabilities()` that returns the caller's full action surface, scoped, in a single bootstrap call. Frontend gates evaluate against the cache locally with `canFor(action, scope?)`. Migrate V3 exact-match gates to consult the cache.

### Payload shape

```json
{
  "caller_id": "uuid",
  "person_id": "uuid",
  "is_superadmin": false,
  "org_actions": ["write", "manage_event", ...],
  "initiative_actions": {
    "<initiative_uuid>": ["write_board", "award_champion", ...]
  },
  "tribe_actions": {
    "<legacy_tribe_id_int>": ["write_board", ...]
  }
}
```

Mirrors `can()` semantics:
- `org_actions` = scope IN ('organization','global')
- `initiative_actions` = scope='initiative' indexed by `auth_engagements.initiative_id`
- `tribe_actions` = same engagement set indexed by `auth_engagements.legacy_tribe_id` (mirrors `can()` resource_type='tribe' branch)

### Frontend helpers (`src/lib/permissions.ts`)

```ts
canFor(action: string, scope?: { type: 'initiative'|'tribe', id })
  // org-scoped check + scope-specific lookup; superadmin bypass

canForAnyTribe(action: string)
  // true if action holds in ANY tribe/initiative scope (binary gates)

canForAdminEntry()
  // true if caller has any of ADMIN_TIER_ACTIONS org-scoped
  // (write, manage_event, manage_member, manage_partner, manage_finance,
  //  manage_comms, manage_board_admin, manage_platform,
  //  view_internal_analytics, view_chapter_dashboards)
```

### Bootstrap (`src/components/nav/Nav.astro`)

`bootNav()` calls `get_caller_capabilities()` in parallel with `get_member_by_auth()`, stores result in `window.__nucleoCapabilities`, dispatches `nav:capabilities`. Re-runs on `try_auto_link_ghost` success and on `SIGNED_OUT`.

Astro inline scripts use `window.__nucleoCanFor()` and `window.__nucleoCanForAdminEntry()` mirrors. React islands import from `permissions.ts`.

## Migration approach (gradual)

### Tier A — exact-match `tribe_leader` gates (HIGH risk of scope-leak)

Migrated in p163:
1. `src/pages/admin/index.astro:122` — admin entry → canForAdminEntry()
2. `src/pages/admin/tribes.astro:30` — admin tribes entry → canForAdminEntry()
3. `src/components/board/CardDetail.tsx:83` — isLeader → canFor('manage_board_admin', tribe/initiative scope)
4. `src/components/governance/GovernancePage.tsx:143` — isLeader → canFor('sign_chain_leader') / canFor('participate_in_governance_review')
5. `src/pages/publications/submissions.astro:52` — canEdit → window.__nucleoCanFor('write')
6. `src/pages/publications/submissions/[id].astro:49` — canManage → window.__nucleoCanFor('write')
7. `src/pages/attendance.astro:509` — visibility=leadership filter → scope-aware canFor('manage_event', tribe/initiative)
8. `src/pages/attendance.astro:676` — canAdminCheckin → scope-aware via ev arg
9. `src/components/attendance/AttendanceGridTab.tsx:58` — canManageAttendance → canForAnyTribe('manage_event')
10. `src/components/admin/VepReconciliationWidget.tsx:63` — admin gate → canForAdminEntry()
11. `src/components/admin/VepReconciliationIsland.tsx:262` — same

Hard-tier fallback retained: `manager` and `deputy_manager` operational_role values stay as fallback for transient cap-load failures (these tiers do not have V4 scope-leak risk because their CASE chain is `volunteer.{manager,deputy_manager}` exclusively). Designations (curator, deputy_manager designation, chapter_board) also retained — these are institutionally assigned and not engagement-derived.

### Tier B — allowlist with `tribe_leader` (MEDIUM risk)

Pending follow-up sessions. Approach: replace allowlist with `canForAdminEntry()` + designation OR.

### Tier C — pure `manager`/`deputy_manager` exact-match (LOW risk)

Status quo retained — these tiers are stable. May migrate in a polish pass later.

### Display-only gates (TeamSection, PresentationLayer, Nav allowedOperationalRoles)

Pending. These show/hide UI items by tier — not security-critical (RPCs are the defense).

## Validation (smoke 2026-05-15)

| Member | Real institutional role | `canForAdminEntry()` | Expected |
|---|---|---|---|
| Vitor Maia Rodovalho | manager + superadmin | **true** (is_superadmin + org_actions full) | ✓ admin entry |
| Fabricio Costa | vice-GP (volunteer.co_gp) | true (write/manage_event/etc. org) | ✓ admin entry |
| Sarah Faria | curadora (designation; observer.* engagements) | **false** (only `participate_in_governance_review` org) | ✓ NOT admin |
| Mayanna Duarte | researcher + workgroup_member.leader Hub | **false** (zero ADMIN_TIER_ACTIONS org) | ✓ NOT admin |
| Mayanna scope-aware | `canFor('manage_event', initiative=Hub)` | **true** | ✓ leader em Hub |
| Mayanna scope-aware | `canFor('manage_event', tribe=8 her tribe)` | **false** (only `write_board` em tribe 8) | ✓ NOT leader na tribo dela |

Scope-leak fechado para os 4 mems flagados pelo PM.

## Consequences

### Positive

- Frontend gates respect engagement scope (initiative/tribe) automatically.
- `operational_role` cache continues to exist but loses load-bearing role in admin/security gates.
- Future trigger refinements (Track E v3, V4 cache cleanup) become safe — UI no longer leaks scope.
- Single bootstrap RPC; O(1) lookups per gate evaluation.
- Designation grants and superadmin retained as orthogonal authority sources.

### Negative

- Two parallel systems (V3 hasPermission + V4 canFor) coexist during gradual migration.
- Migration touches many files; risk of regression — mitigated by tier-by-tier rollout + tests.
- Capability cache may become stale if engagements change mid-session — refreshed on auth events; explicit re-fetch helper TBD.

### Neutral

- `members.operational_role` cache continues to be maintained (other code reads it for display, e.g. PostHog identify, nav badge). It just stops being authoritative for admin/security gates.

## Migration & Rollback

- Migration: `20260659_p163_capability_cache_get_caller_capabilities.sql` + `20260660_p163_capability_cache_add_superadmin_flag.sql`
- Frontend: `src/lib/permissions.ts` (helpers), `src/components/nav/Nav.astro` (bootstrap), 11 gate sites
- Tests: `tests/contracts/capability-cache.test.mjs`
- Rollback: revert frontend changes (gates fall back to `manager`/`deputy_manager` hard-tier + designation paths). RPC remains; harmless idle.

## Backlog

- **Tier B migration** (allowlist gates with `tribe_leader`)
- **Tier C polish** (manager/deputy_manager exact-match)
- **Display-only gates** (TeamSection, PresentationLayer, Nav items)
- **operational_role cache deprecation plan** — once Tiers A+B done, cache can be drift-tolerant (no security impact). A3 invariant could be downgraded to "informational" or removed.
- **Trigger refinement** (`sync_operational_role_cache` Track E v3): map workgroup/committee.leader → researcher (not tribe_leader) in cache; UI gates won't notice because they consult canFor.
- **Re-evaluate A3 backfill candidates** — Fabricio (manager via volunteer.co_gp) is the only institutionally legitimate promotion from the original 6.
- **Capability cache invalidation hook** — refresh on engagement INSERT/UPDATE/DELETE via realtime channel (today refresh is auth-event-bound only).
