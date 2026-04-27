# ADR-0041: `participate_in_governance_review` V4 action — document_comments + curation cluster (9 fns)

- Status: **Accepted** (2026-04-27 — PM Vitor pre-ratified per p70 decision log §G)
- Data: 2026-04-27 (p72)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo:
  - Section A — New V4 action `participate_in_governance_review` catalog seed
    (4 rows in `engagement_kind_permissions`)
  - Section B — Phase B'' V3→V4 conversion (9 fns) — document_comments
    cluster (3) + curation/board cluster (6)
  - Section C — Defense-in-depth `REVOKE FROM anon` for all 9 fns
- Implementation:
  - Migration `20260427233000_adr_0041_governance_review_action_and_9_fns.sql`
  - Migration `20260427233005_adr_0041_revoke_anon.sql`
- Cross-references: ADR-0007 (V4 authority via can_by_member),
  ADR-0011 (Amendment B catalog tightening), ADR-0030 (chapter_board × liaison
  inclusion), ADR-0037 + ADR-0039 (Path Y precedent for engagement preservation)

---

## Contexto

PM decision log §G (2026-04-27 p70 ratifications) approved Opção A — a new
V4 action `participate_in_governance_review` to cover the 9-fn cluster split
across two adjacent operational subsystems:

1. **Document comments (3 fns)**: `create_document_comment`,
   `list_document_comments`, `resolve_document_comment` — comment threads on
   governance documents (used by `ClauseCommentDrawer.tsx`).
2. **Curation/board writers (6 fns)**: `assign_curation_reviewer`,
   `assign_member_to_item`, `submit_curation_review`, `submit_for_curation`,
   `unassign_member_from_item`, `publish_board_item_from_curation` — used by
   `CardDetail.tsx` + `CuratorshipBoardIsland.tsx`.

These 9 fns share a thematic concern (governance/curation review participation)
but had divergent V3 gates: each used some combination of `is_superadmin`,
`operational_role IN ('manager', 'deputy_manager', 'tribe_leader')`, and
`designations @> ['curator' | 'co_gp' | 'founder']`. Single new V4 action
unifies them under engagement-derived authority.

### Why a new action (not reuse `manage_platform` or `manage_event`)

- **`manage_platform`** is too broad — would grant participate-in-review
  access alongside platform-admin power. Wrong granularity.
- **`manage_event`** is event-scoped — wrong domain.
- **`view_internal_analytics`** is read-only — doesn't cover write operations
  like assign/submit/resolve.
- A dedicated action `participate_in_governance_review` creates a precise
  precedent: separates *governance review participation* from
  *platform/finance/event/comms management*. Future `committee_curator`
  engagement kind (per PM decision log §G item 2) will extend this action's
  audience without affecting other catalog actions.

---

## Decisão

### Section A — Catalog seed

```sql
INSERT INTO engagement_kind_permissions (kind, role, action, scope) VALUES
  ('volunteer',     'manager',         'participate_in_governance_review', 'organization'),
  ('volunteer',     'deputy_manager',  'participate_in_governance_review', 'organization'),
  ('volunteer',     'co_gp',           'participate_in_governance_review', 'organization'),
  ('chapter_board', 'liaison',         'participate_in_governance_review', 'organization');
```

Audience pattern matches `view_internal_analytics`, `manage_partner`,
`manage_board_admin` (organization-scope read/write actions with
`chapter_board.liaison` inclusion).

### Section B — V3→V4 conversion of 9 fns

Each fn gets `can_by_member(v_caller.id, 'participate_in_governance_review')`
as the primary V4 gate. Where operational continuity demands additional
preservation (UI workflow, author self-service, tribe→committee handoff),
**Path Y additions** are explicitly documented per fn:

| # | Fn | V4 gate | Path Y additions |
|---|---|---|---|
| 1 | `create_document_comment` | strict V4 | none |
| 2 | `list_document_comments` | strict V4 | none |
| 3 | `resolve_document_comment` | V4 | author self-resolve preserved |
| 4 | `assign_curation_reviewer` | strict V4 | none |
| 5 | `assign_member_to_item` | V4 | tribe_leader, board_admin, self+author claim, curator+curation_reviewer |
| 6 | `submit_curation_review` | strict V4 | none |
| 7 | `submit_for_curation` | V4 | tribe_leader (operational handoff) |
| 8 | `unassign_member_from_item` | V4 | tribe_leader (symmetric) |
| 9 | `publish_board_item_from_curation` | strict V4 | none |

**Path Y rationale per fn**:

- **`resolve_document_comment` — author self-resolve**: an author resolving
  their own comment is intrinsic UX, not governance authority. Preserved
  via `c.author_id = v_member.id` direct check (already in V3 body).
- **`assign_member_to_item` — self+author claim**: any member can claim a
  card via "Pegar para mim" UI button (`CardDetail.tsx:940`). Removing this
  breaks general board UX. Preserved via `(v_caller.id = p_member_id AND
  p_role = 'author')` direct check.
- **`assign_member_to_item` — tribe_leader**: tribe leaders manage
  assignments on their tribe's board cards. Preserved via
  `v_caller.operational_role = 'tribe_leader'` direct check.
- **`assign_member_to_item` — board_admin**: board administrators (per
  `board_members` junction table) manage assignments on their board.
  Preserved via existing `board_members` lookup.
- **`assign_member_to_item` — curator+curation_reviewer special-case**:
  curators assigning themselves as curation reviewers is an operational
  pattern that pre-dates the formal review subsystem. Preserved until
  future `committee_curator` engagement kind covers it.
- **`submit_for_curation` — tribe_leader**: this is the operational handoff
  from tribe deliverable to curation pipeline. Tribe leaders submit their
  own tribe's items. V4 catalog at organization-scope is for committee work;
  tribe→committee submission needs preservation. Preserved via
  `v_caller.operational_role = 'tribe_leader'`.
- **`unassign_member_from_item` — tribe_leader**: symmetric with
  `assign_member_to_item`. Same preservation.

### Section C — REVOKE FROM anon

Defense-in-depth: explicit `REVOKE EXECUTE ... FROM anon` for all 9 fns.
SECURITY DEFINER fns should never be callable by anonymous role. Implicit
gating via `auth.uid()` IS NULL → 'Not authenticated' was already in place,
but explicit REVOKE is the established hardening pattern (see ADR-0035
no-gate hardening sweep, ADR-0040 helper REVOKE).

---

## Privilege expansion (verified pre-apply against current member population)

### Document comments cluster (3 fns)

```
=== create_document_comment ===
V3 union (curator/founder/manager/deputy/tribe_leader) = 13 members:
  Andressa, Antonio, Ana Carla, Débora, Fabricio, Fernando, Hayala,
  Ivan, Jefferson, Marcos, Roberto, Sarah, Vitor
V4 set                          = 5 members:
  Vitor (volunteer/manager), Fabricio (volunteer/co_gp),
  Ana Cristina Fernandes Lima (chapter_board/liaison),
  Roberto Macêdo (chapter_board/liaison),
  Rogério Peixoto (chapter_board/liaison)
gains = [Ana Cristina, Rogério]
losses = [Andressa, Antonio, Ana Carla, Débora, Fernando, Hayala, Ivan,
          Jefferson, Marcos, Sarah]  (10)

=== list_document_comments ===
V3 union (curator/founder/manager/deputy)  = 7 members:
  Andressa, Antonio, Fabricio, Ivan, Roberto, Sarah, Vitor
V4 set                                      = 5 members
gains   = [Ana Cristina, Rogério]
losses  = [Andressa, Antonio, Ivan, Sarah]  (4)

=== resolve_document_comment (with author self-resolve preservation) ===
V3 union (author OR curator OR manager/deputy) = (any commenter) ∪ {7}
V4 set + Path Y author                          = (any commenter) ∪ {5}
gains  (non-author)  = [Ana Cristina, Rogério]
losses (non-author)  = [Andressa, Antonio, Ivan, Sarah]  (4)
```

### Curation/board cluster (6 fns)

```
=== assign_curation_reviewer / submit_curation_review / publish_board_item_from_curation ===
V3 union (superadmin OR manager/deputy OR curator OR co_gp) = 4 members:
  Vitor (super+manager), Fabricio (super+co_gp+curator), Roberto (curator), Sarah (curator)
V4 set                                                       = 5 members
gains  = [Ana Cristina, Rogério]
losses = [Sarah]  (1)

=== assign_member_to_item (with Path Y: tribe_leader + board_admin + self+author + curator-special) ===
V3 union (super OR manager/deputy/tribe_leader OR board_admin OR (curator+curation_reviewer) OR (self+author))
       = 8 + (board_admin members) + (any member self-claim) + (curators with curation_reviewer scope)
V4 + Path Y = 11 (Vitor, Fabricio, 6 tribe_leaders, Ana Cristina, Roberto, Rogério)
            + (board_admin members) + (any member self-claim) + (curators)
gains  = [Ana Cristina, Roberto (also gained via tribe-scoped role coverage), Rogério]
losses = none

=== submit_for_curation / unassign_member_from_item (with Path Y: tribe_leader) ===
V3 union (super OR manager/deputy/tribe_leader) = 8 members:
  Vitor, Fabricio, Ana Carla, Débora, Fernando, Hayala, Jefferson, Marcos
V4 + Path Y                                       = 11 members:
  V3 set + Ana Cristina + Roberto + Rogério (chapter_board.liaison gain)
gains  = [Ana Cristina, Roberto, Rogério]
losses = none
```

### Aggregate impact

**Gains (consistent across 9 fns)**:
- **Ana Cristina Fernandes Lima** — `chapter_board × liaison` engagement.
  PMI-CE chapter governance representative.
- **Rogério Peixoto** — `chapter_board × liaison` engagement. Same PMI-CE
  representative.
- **Roberto Macêdo** — gains via `chapter_board × liaison` (was already in V3
  via `curator` designation; route now via V4 catalog instead of designation).

**Losses (governance review committee tightening)**:
- **Sarah Faria** — V3 access via `curator` designation + `founder` designation;
  loses access to all 9 fns under strict V4. Reason: PM decision log §G item 2
  defers `committee_curator` engagement kind to future seed; until then,
  curator designation alone does not grant `participate_in_governance_review`.
- **Andressa Martins, Antonio Marcos Costa, Ivan Lourenço** — `founder`
  designation; lose access to document_comments cluster (3 fns). Reason:
  founder designation is honorary/historical, not an active governance
  authority in V4 catalog. Antonio + Andressa: no chapter_board engagement.
  Ivan: has `chapter_board × board_member` engagement (sponsor) — does NOT
  match `chapter_board × liaison` seed; intentional separation between
  sponsor visibility (future ADR-0042 `view_chapter_dashboards`) and
  governance review participation.
- **Tribe_leaders for `create_document_comment`** (6: Ana Carla, Débora,
  Fernando, Hayala, Jefferson, Marcos) — lose ability to comment on
  governance documents. Reason: governance document review is committee work,
  not tribe operations. Tribe leaders retain access to the tribe→committee
  handoff fns (`submit_for_curation`, `assign/unassign_member_from_item`)
  via Path Y.

### Operational mitigation

For the 4 lost users (Sarah, Andressa, Antonio, Ivan), governance commenting
can be channeled through:
1. PM (Vitor) directly (always-authoritative).
2. Fabricio (volunteer/co_gp engagement, V4-authorized).
3. Roberto Macêdo (chapter_board/liaison, V4-authorized) for PMI-CE
   stakeholder voice.
4. **Future** `committee_curator` engagement kind (PM decision log §G item 2).
5. **Future** `committee_coordinator/coordinator` catalog seed (Sarah +
   Roberto + Fabricio engagements already exist for this kind).

---

## Cross-cluster notes

### Why publish_board_item_from_curation gets strict V4 (no Path Y)

This fn is called only internally by `submit_curation_review` when consensus
is reached (`v_approved_count >= v_required`). External callers (frontend)
do not invoke it directly. The strict V4 gate is a defense-in-depth measure;
in practice, only authorized reviewers reach this code path.

### Why assign_member_to_item retains the most Path Y exceptions

This fn services general board UX (claim card, manage assignments) AND
curation workflow (assign curation reviewer). Distinct call patterns require
distinct authority paths. Path Y additions preserve all V3 access patterns:
- Self-claim (any member, role=author): UI button "Pegar para mim".
- Tribe_leader: tribe operations on tribe board.
- Board admin: board-scoped admin (per `board_members` junction).
- Curator + curation_reviewer role: legacy curator self-assignment for review.

These are intentional, narrow, well-bounded exceptions — not blanket
authority elevation.

### Drift signal closures

This ADR closes:
- Drift signal cluster: `participate_in_governance_review` was the missing
  V4 action. Both clusters were V3-gated; both are now in catalog.

---

## Phase B'' tally update

Pre-p72:  86/246 (~35.0%)
Post-p72: 95/246 (~38.6%)

(9 fns converted in this ADR.)

---

## Status / Next Action

- [x] PM ratifica ADR (Opção A) — 2026-04-27 p70 decision log §G
- [x] Migration `20260427233000_adr_0041_governance_review_action_and_9_fns.sql`
- [x] Migration `20260427233005_adr_0041_revoke_anon.sql`
- [x] Audit doc update — Phase B'' tally bumps (86 → 95 / 246, ~38.6%)
- [x] Tests preserved: 1415 / 1383 / 0 / 32

---

## Trade-offs aceitos

1. **Sarah, Andressa, Antonio, Ivan loses governance comment access**: PM
   accepted this in §G ratify, with mitigation path (future
   `committee_curator` + `committee_coordinator/coordinator` seeds). Concrete
   workaround: PM/Fabricio/Roberto channel governance feedback during the
   transition period.
2. **Path Y for `tribe_leader` (3 fns)**: pragmatic preservation of
   tribe→committee handoff. Could be replaced later by `tribe × leader`
   engagement seed at `initiative` scope, but that requires resource_id
   plumbing from board_items → boards → initiatives. Deferred.
3. **`assign_member_to_item` complexity**: 4 distinct Path Y exceptions
   (self+author, tribe_leader, board_admin, curator+curation_reviewer).
   Justified by genuine operational diversity; documented openly.

---

## Cross-Cutting precedent

ADR-0041 establishes:
- **New action audience pattern**: `view_internal_analytics`-style audience
  (volunteer × {manager,deputy_manager,co_gp} + chapter_board × liaison)
  is the default for organization-scope governance/oversight actions.
- **Path Y for tribe→organization handoff**: when a fn services both general
  board UX and committee workflow, preserve operational paths via direct
  `auth_engagements` or `members` checks (not catalog-only).
- **Curator deferral**: governance review by curator designation is
  consistently deferred to future `committee_curator` engagement kind. ADR
  follow-up: when the kind is created, seed `participate_in_governance_review`
  + `manage_board_admin` (where curators currently have access via
  designation).
