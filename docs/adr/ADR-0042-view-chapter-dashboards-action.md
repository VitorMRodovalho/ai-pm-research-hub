# ADR-0042: `view_chapter_dashboards` V4 action — sponsor + chapter_board read access restore + `_can_manage_event` helper conversion

- Status: **Accepted** (2026-04-27 — PM Vitor pre-ratified per p70 decision log §B.3 + §H)
- Data: 2026-04-27 (p72)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo:
  - Section A — New V4 action `view_chapter_dashboards` catalog seed
    (3 rows in `engagement_kind_permissions`)
  - Section B — Add `OR can_by_member('view_chapter_dashboards')` gate to
    8 admin dashboard reader RPCs converted in ADR-0011 Amendment B
  - Section C — Convert `_can_manage_event` helper V3→V4
    (`is_superadmin + operational_role` → `can_by_member('manage_event')` +
    Path Y for tribe scope and event creator)
- Implementation:
  - Migration `20260427234000_adr_0042_view_chapter_dashboards_and_helper.sql`
- Cross-references: ADR-0007 (V4 authority via can_by_member),
  ADR-0011 (Amendment B catalog tightening), ADR-0030 (chapter_board × liaison
  inclusion), ADR-0040 (helper REVOKE-from-anon predecessor)

---

## Contexto

### Section A + B — Sponsor visibility restore

ADR-0011 Amendment B (2026-04-26) tightened admin dashboard reader RPCs from
V3 role-list gates to V4 `can_by_member('manage_platform')`. The V4
`manage_platform` audience is `volunteer × {manager, deputy_manager, co_gp}`
only — does NOT include `chapter_board` or `sponsor` engagement kinds.

**Documented impact (Amendment B, "Behavior change documented")**:
> A migração tightens authority for **non-superadmin sponsor (5 users) e
> chapter_liaison (2 users)** que tinham acesso V3 a admin dashboards via
> role-list gate. Em V4, `manage_platform` não inclui esses operational_roles.

PM decision log (§B.3) accepted that the tightening was operationally
over-corrected for chapter governance: chapter board members and sponsors
need read-only visibility into platform health to perform their governance
roles (board oversight, sponsor reporting, chapter_liaison cross-chapter
coordination).

PM ratified **Opção C** — a new V4 action `view_chapter_dashboards` (read-
only) granted to:
- `chapter_board × board_member` (sponsors registered as chapter board)
- `chapter_board × liaison` (chapter_liaisons)
- `sponsor × sponsor` (Ivan-class direct sponsor engagement)

`manage_platform` remains the sole gate for write actions; this ADR only
adds read-side gates (`OR can_by_member(...)`).

### Section C — `_can_manage_event` helper V3→V4

PM decision log (§H) ratified converting `_can_manage_event` to V4
(`is_superadmin + operational_role IN ('manager','deputy_manager')` →
`can_by_member('manage_event')`), preserving Path Y for tribe scope and
event-creator self-management. The helper is used by 3 SECDEF callers
(per ADR-0040 audit).

PM deferred 3 other helpers from this batch:
- `_can_sign_gate` (needs ADR-0016 Amendment 3 design call)
- `has_min_tier` (low value; leave-as-is)
- `can_manage_comms_metrics` (Path Y comms_member preservation — design call)

---

## Decisão

### Section A — Catalog seed

```sql
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope) VALUES
  ('chapter_board', 'board_member', 'view_chapter_dashboards', 'organization'),
  ('chapter_board', 'liaison',      'view_chapter_dashboards', 'organization'),
  ('sponsor',       'sponsor',      'view_chapter_dashboards', 'organization');
```

### Section B — 8 reader RPCs gate addition

Each reader RPC's existing `IF NOT can_by_member(..., 'manage_platform')`
becomes:
```sql
IF NOT (
  public.can_by_member(v_caller_id, 'manage_platform')
  OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')
) THEN
  RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
END IF;
```

| # | Fn | Type | Notes |
|---|---|---|---|
| 1 | `exec_all_tribes_summary` | reader | All-tribes summary metrics |
| 2 | `get_cross_tribe_comparison` | reader | Cross-tribe metrics summary |
| 3 | `exec_cross_tribe_comparison` | reader | Cross-tribe comparison v2 |
| 4 | `exec_cycle_report` | reader | Cycle-level dashboard |
| 5 | `get_admin_dashboard` | reader | Admin home KPIs + alerts |
| 6 | `get_adoption_dashboard` | reader | Platform adoption metrics |
| 7 | `get_campaign_analytics` | reader | Email campaign metrics |
| 8 | `exec_tribe_dashboard` | reader | Tribe drill-down (cross-tribe path only) |

For `exec_tribe_dashboard`, the existing own-tribe carve-out is preserved
(any caller views their own tribe). The cross-tribe path adds `OR
view_chapter_dashboards`.

### Section C — `_can_manage_event` V3→V4

```sql
CREATE OR REPLACE FUNCTION public._can_manage_event(p_event_id uuid)
  RETURNS boolean
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_event_tribe_id int;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN false; END IF;

  -- ADR-0042: V4 catalog source-of-truth for org-tier event management
  IF public.can_by_member(v_caller.id, 'manage_event') THEN RETURN true; END IF;

  -- Path Y: tribe-scoped management (tribe_leader / researcher own-tribe events)
  -- and event-creator self-management — preserved from V3 body.
  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN false; END IF;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  IF v_caller.operational_role = 'tribe_leader' AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_caller.operational_role = 'researcher'   AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_event.created_by = v_caller.id THEN RETURN true; END IF;
  RETURN false;
END;
$function$;
```

Privilege expansion: zero net change. V4 `manage_event` audience
(volunteer × {manager, deputy_manager, co_gp}) covers all V3 cases
(`is_superadmin` + `operational_role IN ('manager','deputy_manager')`)
because the 2 superadmins (Vitor, Fabricio) both have authoritative
`volunteer × {manager, co_gp}` engagements. Path Y preserves
tribe-scoped and creator-scoped flows unchanged.

---

## Privilege expansion (verified pre-apply)

### `view_chapter_dashboards` audience after seed

```
V4 set (10 members):
  Ana Cristina Fernandes Lima   (chapter_board/liaison)
  Emanoela Kerkhoff             (chapter_board/board_member)
  Felipe Moraes Borges          (chapter_board/board_member, sponsor)
  Francisca Jessica de Sousa    (chapter_board/board_member, sponsor)
  Ivan Lourenço                 (sponsor/sponsor + chapter_board/board_member)
  Lorena Souza                  (chapter_board/board_member)
  Márcio Silva dos Santos       (chapter_board/board_member, sponsor)
  Matheus Frederico Rosa Rocha  (chapter_board/board_member, sponsor)
  Roberto Macêdo                (chapter_board/liaison)
  Rogério Peixoto               (chapter_board/liaison)
```

### Reader RPCs effective audience after Section B

```
Pre-ADR-0042   = manage_platform set = {Vitor, Fabricio}
Post-ADR-0042  = manage_platform ∪ view_chapter_dashboards = 12 members
                 (2 manage_platform + 10 view_chapter_dashboards; no overlap
                  except Vitor/Fabricio who are unique to manage_platform)
```

**Restored** (5 sponsors + 2 chapter_liaisons, per Amendment B doc):
- Felipe Moraes Borges, Francisca Jessica, Márcio, Matheus (4 sponsor users)
- Ivan Lourenço (5th sponsor; via sponsor.sponsor or chapter_board.board_member)
- Ana Cristina Fernandes Lima, Rogério Peixoto (2 chapter_liaisons)

**New gains** (not in pre-Amendment-B V3 set, but legitimate per V4 engagement):
- Emanoela Kerkhoff, Lorena Souza (chapter_board/board_member observer-status
  members; engagement IS source of truth per V4 model)
- Roberto Macêdo (chapter_board/liaison; gains read alongside ADR-0041
  participate_in_governance_review write access)

### `_can_manage_event` privilege expansion

```
V3 set (is_superadmin OR manager/deputy + Path Y) = N members
V4 set (manage_event + same Path Y)               = N members
delta = 0 (Vitor + Fabricio both have V4 engagements)
```

Note: 1 active manager (Vitor) + 0 deputies + 1 active co_gp (Fabricio) all
have V4 engagements that grant `manage_event`. No member loses this helper's
return value.

---

## Cross-cutting precedent

### Read/write action separation

ADR-0042 establishes the precedent that **read** and **write** actions
should be cataloged separately. `view_chapter_dashboards` is read-only;
`manage_platform` covers writes. This separation lets us tighten write
authority while preserving read visibility (the central PM concern in §B.3
ratify).

Forward commitment: future ADRs that introduce new write actions should
also evaluate whether a sibling read-only action is needed (e.g., a future
`manage_finance` could pair with `view_finance_reports`).

### V4 + OR pattern for read additions

Adding `OR can_by_member('alternative_action')` to existing V4-gated readers
is a clean composition pattern: preserves existing audience, additively
extends access. Useful for restore patterns post-tightening.

### Helper V3→V4 conversion with Path Y preservation

`_can_manage_event` shows the pattern: replace V3 `is_superadmin OR
operational_role IN (...)` with `can_by_member` only — preserve everything
ELSE in the helper body (tribe scope, creator scope, event-specific logic).
Helper bodies often contain domain-specific Path Y that should NOT be
replaced.

---

## Phase B'' tally update

Pre-p72 (post-ADR-0041): 95/246 (~38.6%)
Post-ADR-0042: 96/246 (~39.0%) — +1 helper conversion (`_can_manage_event`)

(Section B does NOT count as Phase B'' V3→V4 conversions — those 8 fns are
already V4. Section B is a *gate addition*, not a V3→V4 conversion.)

---

## Status / Next Action

- [x] PM ratifica ADR (Opção C + §H partial) — 2026-04-27 p70 decision log
- [x] Migration `20260427234000_adr_0042_view_chapter_dashboards_and_helper.sql`
- [x] Audit doc update — Phase B'' tally bumps (95 → 96 / 246, ~39.0%)
- [x] Tests preserved: 1415 / 1383 / 0 / 32

---

## Trade-offs aceitos

1. **Observer-status chapter_board members gain read access**: Emanoela
   Kerkhoff and Lorena Souza are observer-status (not actively volunteering)
   but have chapter_board × board_member engagements. V4 model treats
   engagement as source of truth, so they gain access. PM ratify §B.3
   accepted this as legitimate (board membership IS active even if member
   status is observer).
2. **`get_campaign_analytics` included in scope**: comms-team metrics may
   not be primary chapter-dashboard concern, but PM ratify said "every
   admin dashboard reader from Amendment B". Future tightening possible
   if scope feedback indicates noise.
3. **`exec_tribe_dashboard` cross-tribe path**: chapter_board members can
   now see ANY tribe's dashboard (cross-tribe). Acceptable for governance
   oversight; PM accepted in §B.3.

---

## Forward backlog

- **PM action item (§J)**: PM toggle `auth_leaked_password_protection` in
  Supabase Dashboard (~2 min, manual).
- **Sprint Session 3**: #82 closure + spinoffs + B.1 (cost/revenue
  notification trigger) + B.2 (generate_manual_version 2-of-N approval).
- **Helper batch follow-up**: `_can_sign_gate`, `has_min_tier`,
  `can_manage_comms_metrics` deferred per PM §H.
