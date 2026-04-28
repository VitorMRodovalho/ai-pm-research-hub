# ADR-0058: multiple_permissive_policies cleanup (P2 RLS perf class)

| Field | Value |
|---|---|
| Status | Accepted (batches 1+2; remaining batches deferred) |
| Date | 2026-04-27 (session p74) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | `20260514230000` (batch 1) + `20260514240000` (batch 2) |
| Cross-ref | ADR-0011 (V4 auth), ADR-0053..0057 (auth_rls_initplan series) |
| Closes | 22 of 133 mpp WARN (batch 1: 18; batch 2: 4 — see audit doc for remaining) |

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
