# ADR-0058: multiple_permissive_policies cleanup (P2 RLS perf class)

| Field | Value |
|---|---|
| Status | Accepted (batches 1+2+3+4+5+6; remaining deferred — Class D/E saturation) |
| Date | 2026-04-27 (session p74) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | `230000`–`280000` (6 sequential batches) |
| Cross-ref | ADR-0011 (V4 auth), ADR-0053..0057 (auth_rls_initplan series) |
| Closes | **58 of 133** mpp WARN (b1:18 + b2:4 + b3:12 + b4:12 + b5:10 + b6:2 — see audit doc) |

## Context

Post-ADR-0057 (auth_rls_initplan 100% closed), the next-largest perf class
is `multiple_permissive_policies` at 133 WARN. Unlike auth_rls_initplan
(purely mechanical wrap), mpp closure requires per-table judgment:

* Some sets of permissive policies are **mergeable** (same role/cmd, OR-able predicates)
* Some are **intentional separation** (different paths for different signal sources)
* Some are **anomalies** (a single policy mis-marked PERMISSIVE that should be RESTRICTIVE)

Audit produced in this session (`docs/audit/MPP_AUDIT_P74.md`) categorized
all 133 WARNs. Batch 1 ships the cleanest win first.

## Decision

### Batch 6 — Split board_items + project_boards write_v4 ALL → per-cmd (2 WARN)

Migration `20260514280000`. Same pattern as batch 3: `*_write_v4` policies
declared `cmd=ALL` overlapping on SELECT with `*_read_members`. Split into
3 per-cmd policies (INSERT/UPDATE/DELETE) leaves SELECT covered only by
`*_read_members`. -1 WARN per table = -2 total.

This finishes the "ALL-cmd write policy + read SELECT policy" pattern
across the major tables (cycles + tribe_deliverables done in batch 3,
publication_series done in batch 4, board_items + project_boards now).

Effect: `mpp` WARN 77 → 75 (-2 WARN).

### Saturation note

After batch 6, the remaining 75 mpp WARN are distributed as:
* 2 tables × 2 WARN (`members`, `tribes` — Class D intentional 5-way SELECT split / multi-path UPDATE)
* 73 tables × 1 WARN — long tail of per-table judgments

Closing further requires either (a) per-table review with PM signal on
mergeability or (b) a structural split-ALL pattern applied uniformly that
would inflate `pg_policy` from ~73 ALL policies to ~219 per-cmd policies.
Trade-off not justified. ADR-0058 effectively reaches its closure ceiling
at batch 6.

### Batch 5 — Drop misleading PERMISSIVE deny policies (no-ops, 10 WARN)

Migration `20260514270000`. Across 4 tables (`member_cycle_history`,
`notification_preferences`, `notifications`, `partner_cards`) a deny-named
policy was declared `AS PERMISSIVE FOR ALL ... USING false`. This is
**functionally a no-op**:

* PERMISSIVE policies grant via OR — `USING false` adds no grants.
* Real denial requires `AS RESTRICTIVE` (which adds an AND filter).
* The actual denial-by-default already came from RLS being enabled with
  no PERMISSIVE policy passing for the disallowed roles/cmds.

The PERMISSIVE deny policies were therefore decorative, but they DID
register against the `multiple_permissive_policies` lint (counted as
overlap with the legitimate ownership/admin policy). Dropping them
eliminates 10 mpp WARN with zero behavior change.

To replace the lost documentation intent, each table now carries a
`COMMENT ON TABLE ...` describing the actual security model (RLS
default-deny + explicit PERMISSIVE grants + SECDEF RPC mutation paths).

This is **not** a one-shot pattern fix — 22 other tables across the
schema still carry similar PERMISSIVE-deny policies that don't currently
generate mpp WARN (because they're the only PERMISSIVE for that
table/role/cmd). They could be cleaned in a future cosmetic sweep, but
that's out of scope for an mpp-driven ADR.

Effect: `mpp` WARN 87 → 77 (-10 WARN).

### Batch 4 — Eliminate redundant superadmin_all policies (mixed C, 12 WARN)

Migration `20260514260000`. Three tables had a `*_superadmin_all` PERMISSIVE
policy whose grant is either subsumed by another policy or splittable:

* **DROP subsumed**: `board_items_superadmin_all` and
  `project_boards_superadmin_all` (both ALL × authenticated × `EXISTS
  rls_is_superadmin`) are strictly subset of their `*_write_v4` peer
  policies which use `(rls_is_superadmin() OR rls_can_for_initiative('write_board', ...))`.
  Dropping eliminates 3 mpp WARN per table = -6 total. SELECT remains
  covered by `*_read_members`.
* **Split**: `publication_series_superadmin_all` (ALL × PUBLIC) is the only
  path for INSERT/UPDATE/DELETE on publication_series. Same batch-3 split
  pattern: drop ALL policy, create per-cmd `_admin_insert/_update/_delete`.
  SELECT now covered only by `_read_members`. Effect: SELECT × 6 PUBLIC
  roles → no overlap → -6 WARN.

Effect: `mpp` WARN 99 → 87 (-12 WARN total).

### Batch 3 — Split ALL-cmd admin policies into per-cmd policies (Class C, 12 WARN)

Migration `20260514250000`. For two tables, an admin/write PERMISSIVE policy
declared `cmd=ALL` (covering INSERT/UPDATE/DELETE/SELECT) overlapping on
SELECT with a separate read policy. Splitting the ALL policy into 3 per-cmd
policies (INSERT, UPDATE, DELETE) leaves SELECT covered ONLY by the read
policy — eliminating SELECT overlap and the resulting 6 WARNs per table:

* `public.cycles`: drop `cycles_admin_write` (ALL/superadmin); create
  `cycles_admin_insert`, `cycles_admin_update`, `cycles_admin_delete` with
  same superadmin predicate. SELECT remains covered by `cycles_read_all`
  (USING true).
* `public.tribe_deliverables`: drop `tribe_deliverables_write_v4` (ALL);
  create `tribe_deliverables_{insert,update,delete}_v4` with same
  `rls_is_superadmin OR rls_can_for_initiative('write_board')` predicate.
  SELECT remains covered by `tribe_deliverables_read`.

The split is **mechanical** — no predicate composition, no semantic change.
Re-evaluated as low-risk vs the audit's initial "medium" classification:
no OR-merging happens, just decomposition by cmd. RESTRICTIVE org_scope
policies still apply uniformly to all 3 new policies (preserving multi-org
filter).

Effect: `mpp` WARN 111 → 99 (-12 WARN, 6/table × 2 tables).

### Batch 2 — Drop subset duplicate policies (Class B, 4 WARN)

Migration `20260514240000`. Two tables had a "PUBLIC + EXPLICIT subset"
policy pair where both policies have `USING true` and the EXPLICIT role
list (`{authenticated, anon}`) is strictly subset of PUBLIC:

* `public.courses`: drop `anon_read_courses` (subset). Keep `"Public courses"` (PUBLIC).
* `public.tribe_selections`: drop `anon_read_tribe_selections` (subset). Keep `"Public tribe counts"` (PUBLIC).

PUBLIC role-list applies to all roles (anon, authenticated, authenticator,
service_role, supabase_admin). The EXPLICIT-list policy was strictly
subset, so dropping is functionally a no-op for any caller path. Verified:
both pairs had `USING true` (identical predicate), so no semantic change.

Effect: `mpp` WARN 115 → 111 (-4 WARN, 4/4 from courses + tribe_selections
SELECT × {anon, authenticated} pairs).

### Batch 1 — Flip `publication_series_v4_org_scope` PERMISSIVE → RESTRICTIVE

1. **Anomaly**: 40 of 41 `*_v4_org_scope` policies in public schema are
   already RESTRICTIVE (matching the canonical "scoping filter" pattern).
   Only `publication_series_v4_org_scope` was PERMISSIVE.

2. **Mathematical impact**: PERMISSIVE policies on `cmd=ALL` for
   `role={}` (PUBLIC) generate WARN combinations of ~6 roles × 4 cmds
   per pair. With 3 PERMISSIVE policies on `publication_series` (this
   one + `superadmin_all` + `read_members`), the lint counted 24 WARNs.
   Flipping one to RESTRICTIVE drops it from the permissive set → 24 → 6.

3. **Production impact**: zero. The platform currently runs with 1
   organization. The behavior change (RESTRICTIVE enforces org match
   even for superadmin) only matters post-multi-org-launch, where it
   IS the desired symmetry.

4. **Symmetry argument**: tables like `members`, `tribes`, `events`,
   `cycles` already enforce per-org RESTRICTIVE scoping. `publication_series`
   should too — the PERMISSIVE was a regression, not a feature.

## Consequences

**Positive**:
* `multiple_permissive_policies` WARN: 133 → 115 (-18, ~13.5%)
* `publication_series` mpp WARN: 24 → 6 (-18 from this single policy)
* Restores org-scope symmetry across V4 substrate
* Multi-org launch readiness improved (one less policy to fix later)

**Neutral**:
* No ACL/role/cmd change. Still ALL on no roles, still org-scope predicate.
* Preserves NULL organization_id allowance (legacy/seed rows).

**Negative**:
* If any cross-org publication_series viewing is in flight (impossible at
  N=1 org), it would be blocked. Mitigation: re-grant via PERMISSIVE in a
  follow-up if ever needed (no breakage observed).

## Pattern sedimented

28. **PERMISSIVE→RESTRICTIVE flip for org_scope anomalies**: when a
    `*_v4_org_scope` policy is PERMISSIVE while peers are RESTRICTIVE,
    flipping is usually correct (canonical pattern is RESTRICTIVE
    scoping filter). Verify (a) production has 1 org (no behavior
    change) OR all rows have org_id matching auth_org caller; (b) no
    code path depends on cross-org row visibility for this table.

## Remaining batches (see audit doc for full picture)

`docs/audit/MPP_AUDIT_P74.md` categorizes the remaining 115 WARNs:

* **Class A (anomaly fixes)**: this batch (DONE)
* **Class B (mergeable)**: `cycles` × 6, `tribe_deliverables` × 6 — could
  combine `cycles_admin_write` + `cycles_read_all` into single PERMISSIVE
  with USING `(true OR superadmin)` for SELECT, then keep admin_write
  for mutations. Requires policy rewrite + smoke test
* **Class C (intentional separation)**: `members` × 2, `notification_preferences`
  × 4 (rpc_only_deny_all + ownership policy intentional pattern) — leave
  as-is, document
* **Class D (per-table judgment)**: ~80 policies across many tables, each
  needs review of whether overlap is intentional. Defer pending PM signal
  or per-table sweep

Total potential closure with all batches: ~30-50 WARN; remaining ~65 are
likely intentional or require ACL judgment.

## Verification

* [x] Migration applied (`20260514230000`)
* [x] `pg_policy.polpermissive = false` for `publication_series_v4_org_scope`
* [x] Advisor: `mpp` 133 → 115 (publication_series 24 → 6)
* [x] Tests preserved 1418 / 1383 / 0 / 35
* [x] Invariants 11/11 = 0
* [x] Single org production: behavior change moot (org_count=1)
* [x] All 5 publication_series rows have organization_id IS NOT NULL

## References

* ADR-0011 V4 authority (RLS pattern)
* `docs/audit/MPP_AUDIT_P74.md` — full audit & batch plan
* `docs/adr/ADR-0053..0057` — sibling RLS perf series

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
