# ADR-0088: `gamification_points.initiative_id` scoping contract

| Field | Value |
|---|---|
| Status | Proposed |
| Date | 2026-05-19 (sessão p202, issue #166 scaffold) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | (none yet — to land in dedicated implementation session) |
| Cross-ref | [ADR-0085](./ADR-0085-exec-cross-initiative-comparison-metric-scoping.md) §3 (cohort-scoping limitation) · [ADR-0081](./ADR-0081-gamification-config-driven-and-champions-ledger.md) (XP rules) · `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #34 · GAP-194.B |
| Closes (proposed) | GAP-194.B + audit item #34 + ADR-0085 §3 cohort-scoping carry |

## Context

`gamification_points` is the high-volume fact table that records every XP grant to a member. Current columns include `member_id`, `cycle_id`, `rule_id`, optional `event_id`, `awarded_at`, and points. **It has no `initiative_id`**.

ADR-0085 §3 documents that, because of this, the `exec_cross_initiative_comparison` RPC must use **cohort-scoped XP** (sum of XP earned by members-of-initiative across all events in the cycle) rather than **strict event-scoped XP** (sum of XP earned for events tied to this initiative). When one person earns XP across two initiatives in the same cycle, both initiatives' XP totals inflate by the same row — silent misattribution.

This is the only event-derived metric in `exec_cross_initiative_comparison` that lacks the strict-scoping principle codified in ADR-0085 §1. Other cohort-vs-event ambiguities have been resolved (GAP-192.C `total_hours`, GAP-194.A `members_inactive_30d`); XP remains the carry because of the missing column.

## Decision (proposed)

### §1. Add `initiative_id uuid` to `gamification_points`

Schema change:

```sql
ALTER TABLE gamification_points ADD COLUMN initiative_id uuid REFERENCES initiatives(id);
CREATE INDEX gamification_points_initiative_id_idx ON gamification_points(initiative_id);
```

Initially NULLable to permit existing rows to remain valid while backfill runs. PM Open Question Q1 in `docs/architecture/SEMANTIC_LAYER_ROADMAP.md` §6: should the column eventually become `NOT NULL` (after backfill reaches 100% coverage) or stay nullable forever (to accept "global" XP grants like onboarding completion that aren't tied to any specific initiative).

### §2. Backfill source rules

For each existing `gamification_points` row, the implementation session must determine `initiative_id` deterministically:

1. **If `event_id IS NOT NULL`** → `initiative_id = events.initiative_id` for that event. Covers attendance-XP, meeting participation, etc.
2. **If `rule_id` is initiative-scoped** (showcase XP, board contribution) → derive from `card.board.initiative_id` via FK chain (subject to schema audit during implementation).
3. **If `rule_id` is global** (onboarding completion, system bonuses) → `NULL` is the correct value (do NOT backfill).
4. **Manual award via Champions ledger** (ADR-0081) → derive from `champion_award.initiative_id` if linked; else `NULL`.

The implementation session ships a one-shot backfill query in the migration file with row counts pre/post.

### §3. Forward-strategy trigger

For new rows after the migration lands, a `BEFORE INSERT` trigger on `gamification_points` derives `initiative_id` from `event_id` when present and the column is NULL on insert. This treats the new column as a **cache, not authoritative** — the parent (`events.initiative_id` or the explicit grant context) remains canonical, the trigger just maintains the cache.

Trigger pseudocode:

```sql
CREATE FUNCTION _gamification_points_set_initiative_id() RETURNS trigger AS $$
BEGIN
  IF NEW.initiative_id IS NULL AND NEW.event_id IS NOT NULL THEN
    SELECT initiative_id INTO NEW.initiative_id FROM events WHERE id = NEW.event_id;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
```

### §4. Update `exec_cross_initiative_comparison` XP metric

Once column populated, the RPC's XP subquery moves from cohort-scope to strict-scope, mirroring `total_hours`/`members_inactive_30d` pattern:

```sql
-- Before (current):
SELECT COALESCE(SUM(gp.points), 0)
FROM gamification_points gp
JOIN members m ON m.id = gp.member_id
WHERE m.initiative_id = i.id  -- cohort (member-of-initiative)

-- After (post-ADR-0088):
SELECT COALESCE(SUM(gp.points), 0)
FROM gamification_points gp
WHERE gp.initiative_id = i.id   -- strict (XP-grant-belongs-to-initiative)
  AND gp.cycle_id = current_cycle_id
```

ADR-0085 §3 should be amended at that point to record the carry being resolved.

## Consequences

### Positive

- Closes the last cohort-vs-strict-scope ambiguity in `exec_cross_initiative_comparison`.
- Honest reporting: a person who earns XP only in research_tribe doesn't inflate their workgroup's XP.
- Enables future per-initiative XP leaderboards (currently impossible without re-joining via events).

### Negative / risk

- Backfill must be carefully audited per source rule (§2) — a wrong attribution is hard to detect later.
- Adds a trigger on a high-write table; benchmark trigger overhead before enabling in production.
- Existing `get_member_cycle_xp` and other XP RPCs may need updates to surface initiative scoping; full caller audit required in the implementation session.

### Acceptance test for future session

Before merge, the implementation session must:

1. Show `SELECT count(*) FROM gamification_points WHERE initiative_id IS NULL` before backfill vs. after — number of NULLs after must equal exactly the count of rows where rule is "global" per §2 rule 3.
2. Add a contract test in `tests/contracts/` that calls `exec_cross_initiative_comparison(NULL)` and asserts that no `total_xp` field exceeds the sum of grants for members of that initiative (catches re-introducing cohort-leak).
3. Run `node scripts/audit-mcp-tool-matrix.mjs --runtime` post-migration; expect drift = 0 (matrix should not gain a new direct-table hit on `gamification_points`).

## Rollback

- Drop column: `ALTER TABLE gamification_points DROP COLUMN initiative_id CASCADE;` (cascade dumps the index).
- Drop trigger: `DROP TRIGGER ... ON gamification_points; DROP FUNCTION _gamification_points_set_initiative_id();`.
- Revert RPC: re-apply the previous `exec_cross_initiative_comparison` body via `pg_get_functiondef` capture from the prior migration's commit.

Rollback should be considered safe within the shadow window; after that, downstream tooling may already depend on the column.

## Implementation session checklist

- [ ] Backfill query authored + row counts captured pre/post
- [ ] Trigger benchmarked on staging
- [ ] `exec_cross_initiative_comparison` XP subquery updated
- [ ] ADR-0085 §3 amended to mark carry resolved
- [ ] Contract test added
- [ ] `check_schema_invariants()` 16/16 = 0 violations post-migration
- [ ] `mcp-tool-matrix.json` drift = 0 post-migration
- [ ] GC entry written
- [ ] Audit log item #34 + GAP-194.B marked RESOLVED
