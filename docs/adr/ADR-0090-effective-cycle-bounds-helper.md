# ADR-0090: `effective_cycle_bounds(member_id)` helper view

| Field | Value |
|---|---|
| Status | Proposed |
| Date | 2026-05-19 (sessão p202, issue #166 scaffold) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | (none yet — to land in dedicated implementation session) |
| Cross-ref | [ADR-0001](./ADR-0001-source-of-truth-and-cycle-history.md) (snapshot vs history) · [ADR-0006](./ADR-0006-persons-engagements-canonical.md) (persons/engagements canonical) · [ADR-0080](./ADR-0080-v4-engagement-canonical-deprecate-members-initiative-id.md) (V4 engagement) · `docs/architecture/SEMANTIC_LAYER_ROADMAP.md` §2.4 |
| Closes (proposed) | Roadmap §3 rank 5 — "active in cycle" duplicated across RPCs |

## Context

The phrase "member X is active in cycle Y" appears across many RPCs:

- `get_cycle_report(p_cycle_id)` — uses `member_cycle_history` join with cycle window
- `exec_cross_initiative_comparison` — uses live `members.cycles` array + last engagement
- `detect_inactive_members` — uses `member_status_transitions` + cycle bounds
- Attendance/XP RPCs — usually rely on `gp.cycle_id = current_cycle_id` shortcut

Each RPC ends up re-implementing the "active in cycle" predicate. Subtle differences exist:

- Is a person "active" if they joined mid-cycle? (Yes, but with prorated bounds.)
- Is a person "active" if they offboarded mid-cycle? (Yes, until offboard_date — historical context preserved.)
- What about `inactive` status from `member_status_transitions`? (Active members include `inactive`-status if their engagement is current; the status field is HR-style, not engagement-state.)
- For research_tribe members vs committee members vs observers — does "active in cycle" mean the same thing?

The lack of a single canonical definition means each RPC author has to decide, and inconsistencies accumulate.

## Decision (proposed)

### §1. Define `effective_cycle_bounds` as a SECURITY INVOKER view

```sql
CREATE VIEW effective_cycle_bounds AS
SELECT
  e.member_id,
  e.initiative_id,
  e.cycle_id,
  GREATEST(e.start_date, c.start_date) AS effective_start_date,
  LEAST(COALESCE(e.end_date, c.end_date), c.end_date) AS effective_end_date,
  CASE
    WHEN e.end_date IS NULL OR e.end_date > c.end_date THEN 'open'
    WHEN e.end_date >= c.start_date THEN 'closed_in_cycle'
    ELSE 'pre_cycle'
  END AS bound_state
FROM engagements e
JOIN cycles c ON c.id = e.cycle_id
WHERE c.end_date IS NULL OR c.end_date >= CURRENT_DATE - INTERVAL '5 years';  -- LGPD-aware
```

Naming conventions:
- `effective_start_date` — when the engagement actually started AT or after the cycle began (the later of the two)
- `effective_end_date` — when the engagement actually ended AT or before the cycle ended (the earlier of the two; NULL is treated as cycle.end_date)
- `bound_state` — categorical: `open` (still active), `closed_in_cycle` (offboarded mid-cycle), `pre_cycle` (engagement was already closed when cycle started — should NOT happen, but defensive)

### §2. Authoritative usage rules

When a RPC asks "is this member active in cycle X for initiative Y?", the answer is:

```sql
EXISTS (
  SELECT 1 FROM effective_cycle_bounds ecb
  WHERE ecb.member_id = $member_id
    AND ecb.cycle_id = $cycle_id
    AND ($initiative_id IS NULL OR ecb.initiative_id = $initiative_id)
    AND ecb.bound_state IN ('open', 'closed_in_cycle')
)
```

For "active right now", the predicate adds:
- `AND ecb.effective_start_date <= CURRENT_DATE`
- `AND (ecb.effective_end_date IS NULL OR ecb.effective_end_date >= CURRENT_DATE)`

### §3. Member-level rollup helper

For convenience, an additional rollup view `member_effective_cycles`:

```sql
CREATE VIEW member_effective_cycles AS
SELECT
  member_id,
  cycle_id,
  array_agg(DISTINCT initiative_id) AS active_initiatives,
  MIN(effective_start_date) AS member_cycle_start,
  MAX(effective_end_date) AS member_cycle_end
FROM effective_cycle_bounds
GROUP BY member_id, cycle_id;
```

This answers "what cycles is this member active in, and via which initiatives" in a single row per (member, cycle).

### §4. RPC refactor scope (separate sessions)

The view itself ships in one migration. Migrating individual RPCs to consume the view is **opt-in per RPC and per session** — not a single sweep. Acceptance criterion: any RPC that touches "active in cycle" semantics MUST consume `effective_cycle_bounds` or document why it cannot (e.g., it's historical-only and needs `member_cycle_history` directly).

`get_cycle_report`, `detect_inactive_members`, `exec_cross_initiative_comparison`, and `get_member_cycle_xp` are the four highest-traffic call sites in the matrix; they get refactored in their own follow-up sessions if and when their behaviour needs to change.

## Consequences

### Positive

- Single canonical definition of "active in cycle" — future RPC authors don't reinvent it.
- Easier to test: one view to validate, not N RPCs.
- Self-documenting: `effective_cycle_bounds` row is human-readable; tells you exactly when the engagement was effective.

### Negative / risk

- Views can hide query planner pain — must benchmark with `EXPLAIN ANALYZE` on representative cycles before adoption.
- Adds a new abstraction layer that someone has to know exists; mitigated by linking from `docs/architecture/SEMANTIC_LAYER_ROADMAP.md`.
- If `engagements.cycle_id` is wrong for any rows (legacy data), the view inherits the wrong bounds — backfill audit must precede adoption.

### Acceptance test for future session

- [ ] View created; `SELECT count(*) FROM effective_cycle_bounds` returns a sensible number (roughly: active members × cycles they're in × initiatives).
- [ ] Sample query: pick 3 known cases (one open, one closed-in-cycle, one pre-cycle) and verify the view returns the correct row for each.
- [ ] Benchmark: typical query `SELECT * FROM effective_cycle_bounds WHERE member_id = ? AND cycle_id = ?` runs in <10ms on production-shape data.
- [ ] Documentation added to `docs/reference/` explaining the semantic.
- [ ] `check_schema_invariants()` 16/16 = 0 violations post-migration.

## Rollback

- Drop the views: `DROP VIEW member_effective_cycles; DROP VIEW effective_cycle_bounds;`
- No data loss (views are read-only).
- Any RPC migrated to consume the view must roll back simultaneously or grace-period to re-implement the in-line predicate.

## Implementation session checklist

- [ ] Schema audit: confirm `engagements.cycle_id`/`start_date`/`end_date` is populated for all active rows
- [ ] View migration with `EXPLAIN ANALYZE` evidence
- [ ] At least one RPC migrated as proof-of-life (`get_cycle_report` recommended)
- [ ] Documentation in `docs/reference/` linking from `docs/architecture/SEMANTIC_LAYER_ROADMAP.md`
- [ ] `check_schema_invariants()` 16/16 = 0 violations
- [ ] GC entry recording the canonical definition
