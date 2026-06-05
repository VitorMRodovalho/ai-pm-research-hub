# ADR-0091: Tribe bridge remaining tables — accept C2 permanent or sweep to C4

| Field | Value |
|---|---|
| Status | Proposed |
| Date | 2026-05-19 (sessão p202, issue #166 scaffold) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | (none yet — to land in dedicated implementation session) |
| Cross-ref | [ADR-0015](./ADR-0015-tribes-bridge-consolidation.md) (5-phase plan) · [ADR-0005](./ADR-0005-initiatives-as-domain-primitive.md) · [ADR-0006](./ADR-0006-persons-engagements-canonical.md) · [ADR-0080](./ADR-0080-v4-engagement-canonical-deprecate-members-initiative-id.md) · `docs/architecture/SEMANTIC_LAYER_ROADMAP.md` §2.2 |
| Closes (proposed) | ADR-0015 C2/C4 carry — final tribe bridge decision |

## Context

ADR-0015 set up a 5-phase consolidation that:

- **C1**: introduced `initiatives` and `engagements` as canonical, with `tribes` and `members.tribe_id` as bridges
- **C2**: identified 7 tables that remain bridge-locked (e.g., `member_cycle_history`, `tribe_deliverables`) because dropping `tribe_id` from them would require schema-wide refactor of history reads
- **C3**: dropped `tribe_id` from 11 tables already covered by `initiative_id` (e.g., `events`, `announcements`, `webinars`)
- **C4**: deferred drop of `members.tribe_id` and the `tribes` table itself

After 1+ year on V4 and consistent engagement-coverage growth (ADR-0080), the C2/C4 decision points need closure. Today the schema has two parallel pointer columns on some tables (`tribe_id` + `initiative_id`) and the V4 invariants (`A1/A3`) enforce consistency between them — but maintaining the bridge has cost:

1. Every new engagement-driven feature has to remember to dual-write the legacy `tribe_id` on bridge-locked tables.
2. RLS policies need to handle both `tribe_id`-keyed paths and `initiative_id`-keyed paths.
3. AI/MCP tools see two pointers and must choose, occasionally inconsistently.

## Decision (proposed)

This ADR is structured as a **decision matrix**, not a single decision. The PM ratification chooses one of three options for each bridge table.

### Option A — Accept C2 as permanent bridge

`tribes`, `members.tribe_id`, and the 7 C2 tables stay forever. The bridge cost is the price of historical readability (showing "tribe X had Y members in cycle Z" without joining engagement history).

Implementation: drop the "future C4 cleanup" backlog item; update `ADR-0015` status from "Phase C3 complete, C4 deferred" to "Accepted as permanent bridge".

### Option B — Sweep to C4 (drop `members.tribe_id` + `tribes` table)

After verifying that all `tribe_id` reads have a V4 replacement via `engagements` JOIN, perform:

1. Migration: backfill any remaining `tribe_id`-only data into `engagements` (should be zero rows if invariants held).
2. Migration: drop `members.tribe_id`.
3. Migration: drop the `tribes` table.
4. Update all 7 C2 tables to read tribe context via `engagements` JOIN at query time (no schema change, just RPC rewrites).

Risk: history readability suffers if joins are expensive on past cycles. Mitigation: materialised view per `(cycle_id, initiative_id, member_id)` for historical queries.

### Option C — Partial sweep (drop `members.tribe_id`, keep `tribes` table + bridge on history tables)

Pragmatic middle ground:

1. Drop `members.tribe_id` (live state always derivable from engagements).
2. Keep `tribes` table (alias of `initiatives WHERE kind='research_tribe'`) for backward compat with reports/dashboards.
3. Keep `tribe_id` on the 7 C2 history tables (`member_cycle_history` etc.) for read performance and "show me what tribe this person was in cycle Z" lookups.

Most of the V4 invariant benefit, minimal disruption.

## Recommendation

**Option C** (partial sweep) is recommended pending PM ratification:

- Removes the most error-prone column (`members.tribe_id` — most-changed bridge surface).
- Preserves history-table performance.
- Aligns with ADR-0080 spirit (V4 engagement canonical for live state).
- Doesn't force a multi-month schema refactor.

PM Open Question Q3 in `docs/architecture/SEMANTIC_LAYER_ROADMAP.md` §6 is the canonical decision point. The implementation session for this ADR cannot start until the PM chooses A/B/C.

## Consequences

### If Option A chosen

- Status quo holds; bridge cost continues; tools must keep dual-write awareness.
- ADR-0015 closes formally as "permanent bridge accepted".
- Backlog item for C4 sweep is closed without action.

### If Option B chosen

- ~3 migrations; full RPC sweep; historical query performance must be re-tuned.
- Largest payoff in clean schema; largest delivery cost.

### If Option C chosen

- ~1 migration (`members.tribe_id` drop) + audit of all callers via `mcp-tool-matrix.json`.
- `tribes` table becomes a view: `CREATE VIEW tribes AS SELECT id, name, ... FROM initiatives WHERE kind = 'research_tribe';` — preserves API surface for legacy callers.
- History tables keep their bridge.

### Common to all options

- The decision must be recorded in `docs/GOVERNANCE_CHANGELOG.md` with PM signature.
- ADR-0015 status moves from "C3 complete, C4 deferred" to a final state.

## Acceptance test for future session

For Option B or C:

- [ ] All callers of dropped column/table identified via `mcp-tool-matrix.json` + `pg_proc.prosrc` grep + frontend grep.
- [ ] Each caller has either a V4 replacement path or an explicit deprecation note.
- [ ] If `tribes` becomes a view: SELECT shape unchanged for current callers (smoke 5 representative MCP tools).
- [ ] `check_schema_invariants()` 16/16 = 0 violations post-migration.
- [ ] At least one cycle-historical query (`get_cycle_report` for a past cycle) runs in <2s on production data.

## Rollback

- For each migration: capture pre-drop schema via `pg_dump --schema-only` of the affected tables.
- For Option C: the `tribes` view is trivially droppable + the column re-addable from `engagements` backfill.

## Implementation session checklist

- [ ] PM ratification of Q3 (Option A / B / C)
- [ ] If A: close backlog, update ADR-0015 status
- [ ] If B/C: caller audit complete via matrix + grep
- [ ] If C: `tribes` view definition tested with existing callers
- [ ] Migration with rollback documented
- [ ] `check_schema_invariants()` 16/16 = 0 violations
- [ ] GC entry recording the decision
