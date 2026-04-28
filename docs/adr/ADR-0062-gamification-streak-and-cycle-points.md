# ADR-0062: #101 P2 final — gamification streak + cycle points aggregate stats

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-28 (sessão p76) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migration | `20260514380000_adr_0062_gamification_streak_and_cycle_points.sql` |
| Issue | #101 P2 (final closure — aggregate stats) |
| Cross-ref | ADR-0050 (#101 P0+P1 v2 baseline), ADR-0051 (#101 P2 scope filter) |
| Closes | #101 backend completo (UI toggle ainda pendente — needs browser session) |

## Context

ADR-0050 entregou v2 do leaderboard (paginação + filtro de ciclo + LGPD opt-out + total_count). ADR-0051 fechou o filtro de scope (chapter/tribe). O que ficou no backlog do #101 P2 era os **aggregate stats per row**: `current_streak_count` + `points_this_cycle`. Esses stats permitem UX de tipo "🔥 4 ciclos consecutivos" + "150 pts neste ciclo" no leaderboard, motivando engagement contínuo.

ADR-0052 foi originalmente alocado para esse trabalho mas reaproveitado para perf cleanup (drop duplicate indexes). Esse ADR-0062 fecha o gap formal.

## Decision

### Components shipped

1. **RPC bulk `get_member_gamification_stats(p_member_ids uuid[])`** STABLE SECDEF
   - Returns: `{member_id, current_streak_count, points_this_cycle, active_cycles_count, longest_streak_count}` per input id
   - Max 200 member_ids per call (matches leaderboard p_limit ceiling)
   - Authenticated only — counts are derived/aggregated, no PII surface
   - GRANT EXECUTE TO authenticated; REVOKE FROM PUBLIC, anon

2. **RPC self `get_my_gamification_stats()`** STABLE SECDEF
   - Convenience wrapper for caller's own stats — returns single jsonb
   - Powers /profile/me streak badge + AI assistants asking "how am I doing this cycle?"

3. **MCP tool `get_my_gamification_stats`** — direct wrapper of the self RPC

### Streak algorithm

Window function with run-detection key:

```
sort_order + ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY sort_order DESC) AS run_key
```

For each member, identifying contiguous runs in their active-cycles set: rows in the same run share the same `run_key` because as you walk DESC through cycles the row_number increments by 1 and sort_order decrements by 1 (delta = constant).

**Streak alive condition** (1-cycle grace): `last_sort >= current_cycle_sort - 1`

This is permissive — if the member earned in the previous cycle but not yet in the current one, the streak is still considered alive. This avoids resetting streaks just because the new cycle started recently.

**Trace example** — current cycle sort=10, member earned in cycles {10, 9, 8, 6, 5, 4, 3}:

| sort_order | row_number (DESC) | run_key (sort+rn) |
|---|---|---|
| 10 | 1 | 11 |
| 9 | 2 | 11 |
| 8 | 3 | 11 |
| 6 | 4 | 10 |
| 5 | 5 | 10 |
| 4 | 6 | 10 |
| 3 | 7 | 10 |

Two runs detected: `run_key=11` (length 3, last_sort=10) and `run_key=10` (length 4, last_sort=6). Filter `last_sort >= 9`: only run_key=11 qualifies. **Current streak = 3** ✓

### NULL-safe cycle bound

Critical correction during smoke testing: the current cycle (`cycle_3`) has `cycle_end IS NULL` (ongoing). The naïve filter `gp.created_at < (c.cycle_end + interval '1 day')::timestamp` returns NULL when cycle_end is NULL (NULL arithmetic), so all current-cycle points were silently excluded.

**Fix**: `(c.cycle_end IS NULL OR gp.created_at < (c.cycle_end + interval '1 day')::timestamp)` — mirrors existing `get_gamification_leaderboard` pattern.

This bug surfaced in initial smoke (`pts_this_cycle = 0` for all top 5 leaderboard members). After fix, top 5 returned realistic values (90-160 pts in current cycle).

### Performance

For the leaderboard use case (50-row page):
- 50 member_ids → ~50 × ~10 cycle joins = ~500 row scans
- Window function over ≤50 rows per partition
- 4 CTEs LEFT JOINed by member_id (small)

Estimated: <50ms for 50-row leaderboard. Not measured under load — defer to ADR-0058 P3 if perf issue surfaces.

Existing index `idx_gamification_member` covers `gp.member_id = ANY(p_member_ids)`. The created_at filter is row-scan but per-member is small (~10s of rows).

## Consequences

**Positive:**
- #101 backend complete (UI toggle remains for browser session)
- Streak feature unblocks UX engagement loop ("don't break your streak")
- Reusable bulk RPC pattern for future profile/leaderboard enrichment
- 1-cycle grace prevents new-cycle reset frustration
- NULL-safe bound discovery → reusable pattern for other cycle-aware RPCs

**Neutral:**
- Streak considers gamification_points only (not engagement-derived activity). Member who's "active" but earned 0 points in a cycle has streak break. Acceptable: showcase/attendance/cert all generate points, so any meaningful activity scores.

**Negative:**
- Two RPCs (bulk + self) is mild duplication, but self-wrapper is essential for SECDEF semantics (caller resolves auth.uid() → member_id without leaking the bulk shape)

## Path impact (Trentim)

- **Path A (PMI internal)**: streak feature aligns with PMI member-engagement KPIs
- **Path B (consulting)**: bulk leaderboard stats RPC = product feature for other PMI chapters / project communities
- **Path C (community)**: streak signal increases sustained voluntary participation (anti-decay)

## Pattern sedimented

39. **Bulk-then-self RPC pair for derived stats**: when frontend needs per-row enrichment for a paginated list AND individual self-view, ship `get_<entity>_stats(ids[])` (bulk, max-bounded) + `get_my_<entity>_stats()` (self-resolving wrapper). Bulk RPC handles batch performance; self-wrapper handles auth context. Aplicável a: streak, attendance, badges, certificate-progress.

40. **NULL-safe upper-bound pattern for cycle/period queries**: any RPC filtering `created_at < (period_end + interval '1 day')` MUST guard with `period_end IS NULL OR …`. Ongoing periods (current cycle, current month) commonly have NULL end. Apply consistently to: cycle filters, milestone windows, deadline checks. Failure mode is silent zero-result (smoke test obrigatório quando ongoing period existe).

41. **Window-function run-detection via sort_order + row_number()**: para detectar runs contíguos em DESC walk, `sort_order + row_number() OVER (ORDER BY sort_order DESC)` é constante dentro de uma run. Pattern reusável para: streaks, gaps em séries de IDs, segmentos contíguos de status, blocos de tempo consecutivos.

## Verification

- [x] Migration applied (`20260514380000`)
- [x] Schema invariants 11/11 = 0
- [x] Functions exist with proper grants (authenticated EXECUTE; PUBLIC + anon revoked)
- [x] Algorithm smoke: top 5 leaderboard members returned plausible streaks (1-4) + cycle pts (90-160)
- [x] NULL-safe bound: pre-fix returned all zeros; post-fix returns real values
- [x] Pre-deploy duplicate-tool check: 0 dupes
- [x] MCP smoke HTTP 200 + serverInfo.version=2.39.0
- [x] Tool count 178 → 179
- [ ] Frontend integration: UI cards in /leaderboard + /profile/me streak badge (separate session, browser required)

## P2 status (post-ADR-0062)

* [x] Scope filter (chapter/tribe) — shipped (ADR-0051)
* [x] Aggregate stats (current_streak_count, points_this_cycle) — **shipped (this ADR)**
* [ ] UI toggle in `/profile/settings` — **PM-discretionary; needs browser smoke**
* [ ] LGPD review formal — optional, PM-discretionary

#101 backend portion is complete. UI toggle remains as the only outstanding work item.

## References

* GitHub #101
* ADR-0050 — v2 baseline (pagination + cycle + opt-out + total_count)
* ADR-0051 — scope filter (chapter/tribe)
* ADR-0058 (perf cleanup mpp 6 batches) — context for pg_proc surface evolution
* PostgreSQL window functions: ROW_NUMBER + sort_order run-detection idiom

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
