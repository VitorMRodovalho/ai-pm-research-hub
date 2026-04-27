# ADR-0051: gamification_leaderboard RPC v3 — scope filter (chapter/tribe)

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-27 (session p73 EXTENDED) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migration | `20260514140000_adr_0051_gamification_leaderboard_scope_filter.sql` |
| Cross-ref | ADR-0050 (#101 P0+P1), ADR-0015 (initiative-native), #82 closure |
| Closes | #101 P2 (scope filter); aggregate stats + UI toggle remain |

## Context

ADR-0050 closed #101 P0 (LGPD opt-out) + P1 (pagination + cycle filter +
total_count). The remaining P2 scope is split:

* **Scope filter** (`p_scope_kind text, p_scope_id`) — pure SQL, autonomous
* **Aggregate stats** (`current_streak_count`, `points_this_cycle`) — feature
  expansion, no immediate caller demand
* **UI toggle** for `set_my_gamification_visibility` in `/profile/settings` —
  needs browser smoke (out of autonomous scope)
* **LGPD review formal** (legal-counsel agent) — optional process

This ADR delivers **scope filter only**. Streak/aggregate stats deferred to
ADR-0052 candidate when first frontend caller demands them. UI toggle remains
on the next-session backlog.

Why scope first: chapter dashboards and tribe pages will likely want a
"compete within my chapter/tribe" UX. The infrastructure should land before
the UI ask.

## Decision

### Three new params (all DEFAULT)

```
get_gamification_leaderboard(
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_cycle_code text DEFAULT NULL,
  -- NEW in v3:
  p_scope_kind text DEFAULT 'global',     -- 'global' | 'chapter' | 'tribe'
  p_chapter_code text DEFAULT NULL,        -- required if scope_kind='chapter'
  p_initiative_id uuid DEFAULT NULL        -- required if scope_kind='tribe'
)
```

Backwards compatibility:
* **0-arg** callsites (3 in `src/pages/gamification.astro`) — work unchanged
  (default `scope_kind='global'`)
* **3-arg** callsites (none in repo today, but contractual for ADR-0050) —
  work unchanged (same defaults)
* **6-arg** callers — new code paths can pass scope explicitly

DROP + CREATE forced because signature added 3 columns (per database rules).

### Validation logic

```
IF v_scope NOT IN ('global', 'chapter', 'tribe') THEN
  RAISE invalid_parameter_value;
IF v_scope = 'chapter' AND p_chapter_code IS NULL/empty THEN
  RAISE invalid_parameter_value;
IF v_scope = 'tribe' AND p_initiative_id IS NULL THEN
  RAISE invalid_parameter_value;
```

Errors use `invalid_parameter_value` ERRCODE so frontend can distinguish
config errors from auth/data errors via SQLSTATE.

### Filter semantics

| scope_kind | filter clause                                                                  |
|------------|--------------------------------------------------------------------------------|
| global     | (no extra filter — same as v2 behavior)                                        |
| chapter    | `m.chapter = p_chapter_code` (text equality on canonical chapter code)         |
| tribe      | EXISTS in `auth_engagements` with `initiative_id = p_initiative_id`            |
|            | AND `is_authoritative = true` AND `persons.legacy_member_id = m.id`            |

The tribe filter uses the **engagement-derived membership** path (ADR-0015 +
ADR-0006 native), not the legacy `members.tribe_id` cache. Members with
multiple engagements (e.g., observer + sponsor on different initiatives)
appear in each tribe's leaderboard separately if engagements are
authoritative.

`total_count` is computed POST-filter so frontend pager UI shows accurate
"X of Y" within the chosen scope.

### Chapter code values

Live values from `members.chapter`: `'PMI-CE'`, `'PMI-DF'`, `'PMI-GO'`,
`'PMI-MG'`, `'PMI-RS'`, `'Externo'`. Frontend should populate dropdown from
a config source rather than hardcoding strings.

## Consequences

**Positive**:
* Chapter dashboards can now render "Top members of PMI-CE this cycle" via
  one RPC call
* Tribe pages can render "Top members of Tribe X" without filtering
  client-side (less data over the wire)
* Validation errors via SQLSTATE enable typed error UX
* No breaking changes to existing callsites

**Neutral**:
* The tribe filter uses subquery EXISTS — performance is acceptable for
  current size (~50 active members). Index opportunity if size grows:
  `CREATE INDEX ON auth_engagements (initiative_id) WHERE is_authoritative = true`
  — deferred since current cost is negligible
* Each scope evaluation runs the EXISTS clause for every member row in the
  outer scan. Postgres should optimize via hash semi-join; verified
  EXPLAIN ANALYZE on dev would confirm

**Negative**:
* Signature now has 6 params, getting unwieldy for ad-hoc SQL invocations.
  Future ADR may consider a single jsonb config param (`p_filter jsonb`) if
  it grows further
* `total_count` recompute per scope means scope changes pay double cost
  (count + paginated query). Acceptable for UI scenarios

## Patterns sedimented

1. **Multi-param scope filter via enum + dependent params**: `p_scope_kind`
   enum drives validation of `p_chapter_code` / `p_initiative_id`. Pattern
   reusable for any "kind-and-id" filter (e.g., entity-scoped reports).
2. **SQLSTATE for typed errors**: `invalid_parameter_value` for config
   errors lets frontend distinguish from `insufficient_privilege` (auth)
   or `no_data_found` (data missing).
3. **Engagement-derived membership filter**: don't trust `members.tribe_id`
   cache; query `auth_engagements` directly for authoritative membership.
   Aligns with ADR-0015 native primitive.

## Rollback

```sql
DROP FUNCTION IF EXISTS public.get_gamification_leaderboard(integer, integer, text, text, text, uuid);
-- Restore v2 by re-running CREATE OR REPLACE block from migration
-- 20260514130000_adr_0050_gamification_leaderboard_v2_and_opt_out.sql
```

## Verification

* [x] Migration applied (`20260514140000`)
* [x] 0-arg callsite returns rows (backwards compat)
* [x] global scope == v2 behavior
* [x] chapter scope filters by chapter_code (PMI-CE smoke verified)
* [x] tribe scope uses auth_engagements (engagement-derived)
* [x] Invalid scope_kind raises `invalid_parameter_value`
* [x] chapter without code raises `invalid_parameter_value`
* [x] tribe without initiative_id raises `invalid_parameter_value`
* [x] Tests preserved 1415 / 1383 / 0 / 32
* [x] Invariants 11/11 = 0

## P2 status (post-ADR-0051)

* [x] Scope filter (chapter/tribe) — **shipped**
* [ ] Aggregate stats (current_streak_count, points_this_cycle) — deferred ADR-0052
* [ ] UI toggle in `/profile/settings` — next session (needs browser)
* [ ] LGPD review formal — optional, PM-discretionary

#101 may close when UI toggle ships, OR remain open for streak feature.
PM-discretionary.

## References

* GitHub #101
* ADR-0050 — v2 baseline (pagination + cycle + opt-out + total_count)
* ADR-0015 — initiative-native primitive
* ADR-0006 — engagement-derived membership

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
