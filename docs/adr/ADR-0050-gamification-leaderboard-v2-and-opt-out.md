# ADR-0050: gamification_leaderboard RPC v2 + member opt-out

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-27 (session p73) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migration | `20260514130000_adr_0050_gamification_leaderboard_v2_and_opt_out.sql` |
| Cross-ref | #82 (closed), ADR-0024 (public_members accepted-risk) |
| Closes | #101 P0+P1 (P2 chapter/tribe scope filter deferred to ADR-0051) |

## Context

#101 was created as a #82 spinoff with three areas:
1. **Pagination** — `get_gamification_leaderboard` returned all rows
   regardless of UI rendering capacity (members table is small now,
   but unbounded growth)
2. **Cycle filter** — RPC only computed current-cycle aggregates;
   no way to query past cycles
3. **Opt-out** — no LGPD-aligned mechanism for members to remove
   themselves from the public leaderboard. Forced ranking as a
   "default visibility" for all active members violates the
   member-self-management principle implicit in LGPD Art. 18

This ADR delivers P0+P1 of #101 in a single migration (PM
discretion — opt-out is the LGPD-priority item, pagination + cycle
filter are infrastructural).

P2 (chapter/tribe scope filter via `p_scope_kind text, p_scope_id uuid`)
is deferred until first frontend caller demands the segmentation.

## Decision

### Schema: `members.gamification_opt_out boolean NOT NULL DEFAULT false`

Single column on the canonical `members` table. Member-managed via
new RPC. Opt-out preserves underlying gamification points (no data
deletion); only display visibility is suppressed.

Rationale for `NOT NULL DEFAULT false`:
* Backwards compat: all existing rows default to "visible" (current
  behavior preserved for members who haven't expressed preference)
* No nullable means leaderboard query has a single, fast WHERE clause

### `get_gamification_leaderboard` v2 (DROP + CREATE)

Signature change forced DROP + CREATE (per database rules — `CREATE OR
REPLACE FUNCTION` doesn't allow signature changes). New params:

```
get_gamification_leaderboard(
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_cycle_code text DEFAULT NULL
)
```

Backwards compat strategy: all params have DEFAULT, so existing
callsites in `src/pages/gamification.astro` (3 zero-arg calls) continue
to work without code changes. They get current-cycle results paginated
to the first 50 rows (effectively their previous behavior since member
count is well under 50).

New return column `total_count integer` repeated per row (standard
pagination metadata pattern). Frontend reads first row's `total_count`
to drive pager UI.

Internal logic:
1. Validate pagination: `limit ∈ [1, 200]` (clamped via GREATEST/LEAST),
   `offset ≥ 0`
2. Resolve cycle window: explicit `cycle_code` → cycles row;
   NULL → `cycles.is_current = true`. Invalid cycle_code → exception
   with `no_data_found` ERRCODE
3. Compute `total_count` once via separate aggregate (post-filter,
   pre-pagination)
4. Main query: same 16+ category breakdowns as v1, **plus** WHERE
   `gamification_opt_out = false` (LGPD opt-out filter)
5. ORDER BY `total_points DESC, name ASC` (stable secondary)

### `set_my_gamification_visibility(p_opt_out boolean)`

Member self-management RPC. Authenticated only — caller can only
edit own record (resolved via `auth.uid() → members.auth_id`).

Idempotent: short-circuits when `p_opt_out` matches current value
(no UPDATE, returns `changed: false`). Enables UI to call freely on
form submit without checking diff.

Returns jsonb summary: `{success, member_id, opt_out, changed,
previous_value (only if changed), updated_at}`.

### MCP layer (v2.31.0, +1 tool)

`set_my_gamification_visibility` exposed as MCP tool for AI
orchestration: "Don't show me on the leaderboard" → tool call with
`opt_out: true`. 158 tools total (101R + 57W).

`get_gamification_leaderboard` already exposed; new params are
additive on the RPC layer (no MCP-level surface change needed —
existing callers see same surface, plus optional new params for
power users).

## Consequences

**Positive**:
* LGPD-aligned: members can self-manage leaderboard visibility
  without admin intervention
* Pagination unblocks UI performance for any future leaderboard
  growth (chapter expansion, multi-org scenarios)
* Cycle filter enables "Top 10 of cycle 2-2025" historical queries
  for blog posts, anniversary content, etc.
* `total_count` lets frontend render pager UI without separate count
  query

**Neutral**:
* Existing zero-arg callsites in `gamification.astro` work unchanged
  (DEFAULT params)
* `members.gamification_opt_out` adds 1 byte per row × ~50 active
  members = trivial size delta

**Negative**:
* Two SELECTs per RPC call (one for `total_count`, one for the
  paginated rows) — small overhead but repeated per page navigation.
  Could be optimized via window function `COUNT(*) OVER()` if
  benchmarks warrant
* No bulk admin opt-out tool. If admin needs to opt-out N members
  (e.g., legal request), they'd run it manually per-member via SQL.
  Acceptable for low-frequency operation
* P2 (chapter/tribe scope filter) remains in #101; this ADR only
  closes P0+P1

## Patterns sedimented

1. **DEFAULT-param signature evolution**: when changing an RPC's
   signature, give all new params DEFAULT values — existing zero-arg
   callsites remain valid. Avoids requiring frontend code change in
   the same migration.
2. **Idempotent toggle RPC**: `set_my_gamification_visibility` returns
   `changed: false` on no-op rather than erroring. Enables
   "fire-and-forget" UX without caller-side diff checks.
3. **Total count at row level for pagination**: the `total_count`
   column repeated per row is wasteful but standard. Frontend reads
   first row only. Trade-off: avoids second RPC roundtrip vs minor
   over-fetch.
4. **LGPD opt-out without data deletion**: visibility flag, not
   deletion. Member's points preserved (still counts toward their
   personal `get_my_xp_and_ranking`). Reversible.

## Rollback

```sql
DROP FUNCTION IF EXISTS public.set_my_gamification_visibility(boolean);
DROP FUNCTION IF EXISTS public.get_gamification_leaderboard(integer, integer, text);
ALTER TABLE public.members DROP COLUMN IF EXISTS gamification_opt_out;
-- Restore previous get_gamification_leaderboard() (zero-arg) from
-- migration 20260513-... (pre-#82 Onda 3 conversion). NB: old version
-- returned all rows + had no opt-out filter.
```

Rollback would un-do LGPD compliance — only execute if v2 introduced
a critical regression.

## P2 deferred (ADR-0051 candidate)

Per #101 P2 scope:
* `p_scope_kind text` — `'chapter' | 'tribe' | 'global'` (default global)
* `p_scope_id uuid` — chapter_code or initiative_id
* Aggregate stats: `current_streak_count`, `points_this_cycle`

Trigger to ship: first frontend caller (e.g., chapter dashboard) demands
the segmentation, OR PM ratifies new RPC for "compete within chapter"
UX.

## P0+P1 verification

* [x] Migration applied (`20260514130000`)
* [x] Schema column present (`members.gamification_opt_out`)
* [x] RPC v2 returns rows with `total_count` populated
* [x] Pagination: limit=5, offset=0 returns ≤5 rows
* [x] Cycle filter: invalid cycle_code raises `no_data_found`
* [x] Opt-out toggle: idempotent + returns expected jsonb shape
* [x] MCP smoke: `serverInfo.version=2.31.0` (HTTP 200)
* [x] Tests preserved 1415/1383/0/32
* [x] Invariants 11/11 = 0
* [x] Existing `gamification.astro` callsites unchanged (verified via
  inspection — 3 zero-arg `sb.rpc('get_gamification_leaderboard')` calls)

## References

* GitHub #101
* `src/pages/gamification.astro` lines 848, 891, 982 — existing
  callsites (zero-arg, backwards-compat preserved)
* ADR-0024 — `public_members` accepted-risk (related LGPD context)
* `tests/contracts/rpc-migration-coverage.test.mjs` — Track Q-C
  ensures pg_proc body matches latest migration

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
