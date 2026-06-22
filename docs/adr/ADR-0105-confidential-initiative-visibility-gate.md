# ADR-0105: Confidential Initiative Visibility Gate

| Field | Value |
|---|---|
| Status | Accepted (PR-1 column+helper · PR-2 RLS · PR-3 SECDEF read RPCs · PR-4 governance + write surface) |
| Date | 2026-06-22 |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | `20260805000231_p785_pr1_initiative_visibility_and_helper.sql` (column + `rls_can_see_initiative`) · `20260805000232_p785_pr2_confidential_initiative_rls.sql` (RESTRICTIVE SELECT policies + resolvers + invariant `AJ`) · `20260805000233_p785_pr3_confidential_initiative_rpcs.sql` (gate on 26 SECDEF read/list RPCs + curation carve-out + public aggregates) · `20260805000234_p785_pr4_initiative_visibility_write_surface.sql` (visibility in `create_initiative`/`update_initiative`) |
| Cross-ref | [ADR-0005](./ADR-0005-initiative-as-domain-primitive.md) (initiative as domain primitive) · [ADR-0007](./ADR-0007-authority-as-engagement-grant.md) (authority as engagement grant) · [ADR-0012](./ADR-0012-schema-consolidation-principles.md) (schema consolidation) · `docs/reference/V4_AUTHORITY_MODEL.md` (visibility axis) |
| Refs | Issue #785 · related #212 (collaboration-hub/multi-hub), #97 (LATAM scoped access) |

## Context

The org needs **confidential initiatives (and, via the tribe bridge, confidential tribes)** whose
existence, board, events, meeting artifacts, deliverables and governance documents do **not** leak to
the wider member base, to leaders of other tribes, or to curation. The immediate motivating case is the
**Presidência × GP (Governança do Núcleo)** cadence — presidential MOUs, VEP seats, INPI/IP matters.
But the requirement is broader and structural: this is the rail for the **Intellectual Property policy**
under construction, including **approval of patentable research lines**, where premature disclosure can
destroy novelty/patentability. The solution therefore had to be correct and scalable, not a patch.

Pre-state (grounded live 2026-06-22, before PR-1):
- `initiatives` had **no visibility column**. The only control was `join_policy` (who *joins*, not who *sees*).
- Read RLS was open: `initiatives` = `USING(true)`; `board_items` = `rls_is_member()`; `events` =
  `rls_is_member() OR type IN ('geral','webinar')`.
- CLAUDE.md decision #5 (board_items read-all so curators get cross-board access) is a **load-bearing
  invariant** → the board cannot be closed globally; a scoped carve-out was required.
- A V4 pattern already existed: the `view_pii` action has `scope='initiative'`, scoped via
  `auth_engagements.initiative_id`. We **reuse that pattern** rather than invent a new mechanism.
- Tribes ARE initiatives (dual-write bridge, [ADR-0005](./ADR-0005-initiative-as-domain-primitive.md)) →
  a flag on `initiatives` covers tribes automatically.

## Decision

Introduce an **orthogonal visibility axis** on the initiative primitive, gated by engagement, layered
so the non-confidential path is byte-for-byte unchanged.

### 1. Model — `initiatives.visibility` + one helper (PR-1)
- `initiatives.visibility text NOT NULL DEFAULT 'standard' CHECK (visibility IN ('standard','confidential'))`.
  Enum-as-text (not boolean) for extensibility (a future `'restricted_to_kinds'` needs no type migration);
  `'standard'` (not `'public'`) because the floor is already org-members-only.
- Canonical helper `rls_can_see_initiative(p_initiative_id uuid)` (`SECURITY DEFINER STABLE`):
  returns `true` for `NULL` initiative_id (org-level rows with no initiative stay visible), for any
  `standard` initiative, for the caller's engaged confidential initiatives
  (`auth_engagements.initiative_id` + `is_authoritative`), and for superadmin / `manage_platform`.
  Because the helper returns `true` for `standard` and for `NULL`, **everything that is not confidential
  behaves exactly as before** — curation read-all (decision #5) is intact.

### 2. RLS — RESTRICTIVE SELECT cascade (PR-2)
Eight dependent tables with `initiative_id` get a **RESTRICTIVE** SELECT policy that `AND`s the helper
onto the existing permissive policies (so it can only *narrow*): `initiatives`, `events`,
`project_boards`, `board_items`, `meeting_artifacts`, `tribe_deliverables`, `recurring_meeting_rules`,
`governance_documents`. Two `SECURITY DEFINER` resolvers (`rls_can_see_board`, `rls_can_see_artifact_link`)
avoid the inline-subquery leak (a subquery in `USING` suffers the referenced table's own RLS → `NULL` →
`helper(NULL)=true` → would leak). Structural invariant `AJ_confidential_visibility_gate_present` added to
`check_schema_invariants()`.

### 3. SECDEF read RPCs — explicit gate (PR-3)
~170 RPCs are `SECURITY DEFINER` and **bypass RLS**, so RLS alone is insufficient. 26 read/list RPCs that
return per-initiative data apply the gate explicitly (via `rls_can_see_initiative` / the board / artifact
resolvers). Per **PM decision #2**, curation RPCs **exclude** confidential initiatives by default. Public
aggregates (`get_homepage_stats`, `get_public_platform_stats`) filter `visibility <> 'confidential'` so
counts are unaffected by confidential initiatives.

### 4. Write surface (PR-4 — this step's code)
`create_initiative` and `update_initiative` accept/edit `visibility` (DROP+CREATE — param-count change):
- **create_initiative**: appends `p_visibility text DEFAULT 'standard'`, threaded into the `initiatives`
  INSERT. The #708 `board_scope` derivation is preserved verbatim. No new authorization guard: marking a
  brand-new initiative confidential only *raises the wall* on the creator's own initiative, so it inherits
  the RPC's existing create authority.
- **update_initiative**: appends `p_visibility text DEFAULT NULL` (NULL = unchanged), COALESCE'd into the
  UPDATE. Visibility edits ride the **existing `can(person,'manage_member','initiative',id)` guard** — the
  same coordinator-level gate that already protects title/status/metadata. GP (`manage_platform`) inherits
  it via `can()`. Lowering `confidential → standard` exposes previously-hidden data, so it is deliberately
  kept behind that coordinator/GP gate; GP oversight is always present (decision #1).
- Both validate the enum and raise `P0007` on an invalid value (clean error ahead of the column CHECK).
- The **UI badge + restricted toggle** in `/admin/initiatives` is a **separate FE slice** (align #211/#212),
  out of scope here. The write surface is sufficient for the downstream confidential initiative to be
  created via direct RPC.

### PM decisions (2026-06-22), ratified here
1. **GP / `manage_platform` / superadmin ALWAYS see** confidential initiatives (administrative oversight,
   audit, LGPD). Fine-grained single-artifact compartmentalization (e.g. a legal opinion that must not
   circulate beyond two named people) stays **outside the platform** (Google Drive ACL) — out of scope for
   this gate.
2. **Curation EXCLUDES confidential by default** (a curator without engagement does not see them);
   cross-board read of non-confidential initiatives is unchanged.
3. **Scope is the confidentiality GATE only.** IP-track modelling (patent status, INPI registration,
   research-line approval) is a separate follow-up reusing `exclusion_declarations`.

## Consequences

- **Positive:** confidentiality is a first-class, engagement-derived property of the initiative primitive;
  tribes inherit it for free; the non-confidential path is provably unchanged (default `standard`, helper
  returns `true`); the IP/governance rail now has a correct foundation.
- **Defense in depth:** RLS (PR-2) + SECDEF RPC gates (PR-3) are both required because SECDEF bypasses RLS;
  neither alone is sufficient. New per-initiative read RPCs MUST add the gate (see V4 doc checklist).
- **Boundary (accepted risk):** per-artifact secrecy finer than per-initiative lives in Drive ACL, not the
  platform. GP can always see (no compartmentalization from GP) — by design, for oversight.
- **Authority axis is orthogonal:** `rls_can_see_initiative` is a **visibility** gate, distinct from the
  three V4 **action-authority** paths. See `V4_AUTHORITY_MODEL.md` ("visibility ≠ action-authority").
- **Maintenance:** any PR touching `get_initiative_detail` / `get_initiative_gamification` must re-point the
  md5 body-hash lock in `tests/contracts/...` (these were re-created in PR-3). Any new SECDEF read RPC over
  the eight dependent tables must call the gate or it will leak confidential rows.

## Status of rollout
Live in production: PR-1/PR-2/PR-3 merged (#834/#836/#838, 2026-06-22). PR-4 DDL applied to the shared DB
(behavior-neutral; **0 confidential initiatives in prod**), code pending PR merge with explicit PM go.
Downstream (not infra): create the confidential `GP × Presidência — Governança do Núcleo` initiative
(kind `committee`), validate the gate BEFORE populating, then populate the `[PRIVADA]` cards.
