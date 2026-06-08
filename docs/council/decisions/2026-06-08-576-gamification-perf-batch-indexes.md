# Decision — #576 gamification cockpit RPC performance (batch N+1 + indexes + roster hoist)

- **Date:** 2026-06-08
- **Issue:** #576 (follow-up to #425 / PR #575)
- **Migration:** `20260805000132_p576_gamification_perf_batch_indexes.sql` (DB-only, no deploy)
- **Decider:** PM (chose #576 from the PM-agreed NEXT set); PL/CTO recommended #576 as the
  zero-decision-gate, measurable, self-contained completion of the #425 cockpit.
- **Council:** equivalence-verifier (GO), data-architect (GO_W_FIXES), senior-engineer
  (GO_W_FIXES), code-reviewer (GO_W_FIXES), security-engineer (GO) — **0 blockers**
  (run `wf_f8f73ec7`). All GO_W_FIXES findings folded before apply.

## Context

`get_tribe_gamification(integer)` / `get_initiative_gamification(uuid)` turned into a
per-member coaching cockpit in #425. That added per-member work that is fine at current
scale (tribe-8 ~6 members) but becomes load-bearing as the cockpit scales to
cross-initiative views. This is a **performance** change with **byte-identical output**.

## What shipped

1. **attendance_rate N+1 → batched map.** `public.get_attendance_rate(member, cycle)` was
   called once per member inside `jsonb_agg` (a SQL function gets no inline benefit in a
   plpgsql caller). Now one grouped scan into a `member_id → rate` jsonb map, read with
   `(v_attendance -> member::text)`. The grouped body mirrors `get_attendance_rate`'s
   numerator/denominator/event-window. `get_attendance_rate` is **unchanged** and remains
   the SSOT for every other caller.
2. **last_activity fold.** Was a per-member correlated `MAX(gamification_points.created_at)`
   subquery → folded into the existing `points_per_member` aggregate as `MAX(gp.created_at)`,
   reusing the one gp scan.
3. **Roster hoist (tribe fn).** The five initiative-filtered `v_initiative_roster` sub-scans
   now reuse the `v_member_ids` array collected once (`x IN (SELECT member_id FROM
   v_initiative_roster WHERE initiative_id=X)` ≡ `x = ANY(v_member_ids)` since `v_member_ids
   := array_agg(member_id)` over the same source+filter). `points_per_member` also gains
   `WHERE member_id = ANY(v_member_ids)`. The two **global** cross-tribe roster scans
   (tribe_rank / tribe_ranking) are intentionally retained.
4. **Roster hoist (initiative fn).** `init_members` + `member_data` CTEs marked MATERIALIZED.
5. **Delegation double-fetch (item 5).** `get_initiative_gamification` resolves routing
   (`resolve_tribe_id`) BEFORE the members-by-auth_id fetch; tribe-backed initiatives
   delegate straight to `get_tribe_gamification` (its own auth gate), avoiding a second
   members lookup on the common path. Standalone path authenticates inline. Output identical.

### Indexes
- **ADD** `idx_gp_member_created (member_id, created_at DESC)` — serves the folded
  last_activity MAX (now an Index-Only Scan, `Heap Fetches: 1`), the `cycle_points`
  created_at FILTER, and the `get_member_gamification_stats` streak-walk.
- **DROP** `idx_gamification_member (member_id)` — redundant; the composite leading column
  covers it. (Correcting the issue's premise: the bare member_id index still existed; the
  one dropped in `20260514450000` was a *duplicate*, `idx_gamification_points_member_id`.)
- **ADD** `idx_cp_member_status (member_id, status)` — status-filtered course_progress reads.
- **NOT added:** the issue's proposed `(course_id, member_id)` — redundant with the existing
  UNIQUE `course_progress_member_id_course_id_key (member_id, course_id)` for the
  both-equality `trail_courses` join.

## Folded council fixes (pre-apply)

- **Unanimous (data-architect + senior-eng + code-reviewer):** removed the dead-code
  `COALESCE(v_cycle_start, (SELECT cycle_start FROM cycles …))` inside the batched attendance
  subquery — `v_cycle_start` is already resolved, and the fallback can only ever return what
  `v_cycle_start` already holds → bare `v_cycle_start` is provably equivalent and drops a
  redundant per-call cycles scan.
- Added `COMMENT ON INDEX idx_gp_member_created` recording the supersession lineage.
- Sharpened the rollback header (explicit recreate DDL for `idx_gamification_member`).

## Equivalence evidence (live, this session)

- Per-member attendance-map ≡ `get_attendance_rate`: **37/37 members, 0 mismatches**
  (covers numeric `ROUND(,2)` scale + the absent-key→null and present-with-null→null cases).
- BEFORE→AFTER full-output md5 fingerprints: **6/7 tribes + 2 standalone initiatives
  byte-identical**. Tribe 4 differs only by the order of 2 members tied at 150 total_points
  (no tie-breaker — pre-existing nondeterminism, NOT a #576 regression); **direct byte-proof:**
  reversing the tied pair in the AFTER output hashes exactly to the BEFORE fingerprint.
- AFTER plan: `MAX(created_at)` now an `Index Only Scan using idx_gp_member_created`
  (was a bitmap-heap scan of 89 rows / 56 buffers).

## Not done (deliberate)

- **#577** (collapse raw-point columns into the drill-down) — separate, needs PM/UX nod.
- `trail_progress` / `trail_courses` remain per-member subqueries (now index-supported);
  batching them is tracked for a future pass.
- **resolve_tribe_id RLS bypass** inside SECURITY DEFINER (security-engineer): a wrong-org
  caller learns the boolean "is this initiative tribe-backed?" before the Unauthorized gate.
  **Pre-existing** (identical delegation in #425), minimal exposure — follow-up ADR note only.

## Verification gate

Build pass · full suite **3644/0/0** (DB-gated, 0 skipped) · new test
`576-gamification-perf-batch-indexes` (9) in both whitelists · Phase-C drift clean (both
functions live==file) · `check_schema_invariants()` 0 · ACL preserved (authenticated +
service_role, no anon/PUBLIC) · 0 `--admin`.
