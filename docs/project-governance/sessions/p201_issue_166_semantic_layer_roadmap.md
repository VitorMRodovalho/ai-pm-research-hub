---
issue: 166
title: architecture - semantic layer roadmap for facts dimensions snapshots
lane: Foundation + Governance
priority: P2
effort: L (roadmap + ADRs)
status: ready (depends on #162 matrix for downstream classification)
opened: 2026-05-19
github: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/166
---

# p201 Session Brief - Issue #166: Semantic Layer Roadmap

## Why this matters

`nucleo-mcp/index.ts` exposes 293 tools from a monolithic file and mixes
direct table reads (`members`, `public_members`, `events`,
`project_boards`, `board_items`, plus 15 single-use tables) with
RPC-backed semantic operations. Runtime is healthy, but the history
shows MCP behaviour can break silently when domain primitives migrate
faster than MCP callsites. The same gap exists in analytics RPCs:
`gamification_points` lacks `initiative_id` for strict scoping (ADR-0085
limitation), `champion_criteria_catalog` semantics still informal,
ADR-0015 has pending tribe-bridge work, and document permissions V4
sweep is incomplete (carry from ADR-0087 / GAP-200.A).

## Lane and gates

- Lane: Foundation (SQL/RPC/RLS) + Governance (ADR, semantic contracts)
- Can touch: `docs/adr/`, `docs/reference/`, no SQL unless an ADR
  authorises it
- Can't touch: existing tables/RPCs without an ADR; this issue is
  primarily a roadmap, not implementation
- Gates: each proposed schema change needs ADR or explicit no-ADR
  rationale; downstream P1 items must have backfill + rollback strategy

## Dependencies

- Issue #162 (MCP contract matrix) provides the data classification of
  which tools touch which tables - upstream input for "encapsulate vs
  accept vs retire".
- ADR-0011 (V4 invariants), ADR-0012 (schema consolidation), ADR-0015
  (tribe bridge), ADR-0080 (pending cutover), ADR-0085 (cross-init
  comparison scoping), ADR-0087 (V4 curate_content).

## In scope

1. Author `docs/architecture/SEMANTIC_LAYER_ROADMAP.md`:
   - Inventory facts (`events`, `attendance`, `gamification_points`),
     dimensions (`members`, `initiatives`, `cycles`), snapshots
     (`member_cycle_history`, `member_status_transitions`).
   - List current drift risks (direct-table reads in MCP, missing
     scoping columns, stale catalogs).
   - Propose P0/P1/P2 priorities with effort + risk per item.
2. Author or scaffold ADRs for each P1:
   - ADR for `gamification_points.initiative_id` (backfill source,
     trigger strategy, scoping contract).
   - ADR for `champion_criteria_catalog` (CRUD surface, audit, who can
     edit).
   - ADR for `effective_cycle_bounds` view/helper (semantic of "active
     in cycle").
   - ADR for ADR-0015 remaining tribe bridge (which tables still
     dual-write).
   - ADR for document permissions V4 sweep (close ADR-0087 carry).
3. Add a "Semantic contracts" section to the MCP matrix in #162 once
   contracts exist (cross-reference).
4. Record decisions in `docs/GOVERNANCE_CHANGELOG.md` as ADRs land.

## Out of scope

- Implementing any of the P1 schema changes (each ADR triggers its own
  session).
- Refactoring `nucleo-mcp/index.ts` into per-domain modules (separate
  issue if desired).
- Touching the `mcp_usage_log` aggregation or analytics RPCs.

## Recommended approach

1. Read all six referenced ADRs to map current state.
2. Read #162 matrix output (if not yet available, classify direct-table
   reads manually using the audit doc's hotspot table).
3. Draft the roadmap doc in three passes:
   - Pass 1: inventory + drift risks.
   - Pass 2: P0/P1/P2 prioritisation + effort estimates.
   - Pass 3: ADR scaffolds for P1 items.
4. PM review; ratify by adding GC entry per accepted ADR.

## Files likely to touch

- `docs/architecture/SEMANTIC_LAYER_ROADMAP.md` (new)
- `docs/adr/ADR-008X_*.md` (one per P1 item)
- `docs/adr/README.md` (index update)
- `docs/GOVERNANCE_CHANGELOG.md` (GC entries per accepted ADR)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` (close items #34, #38;
  partial close on others as ADRs land)

## Validation

- Roadmap doc reviewed by PM and accepted (status `Adopted`).
- Each P1 has an ADR with `Status: Proposed` and a clear acceptance
  test for the future implementation session.
- No SQL/RPC shipped in this session (it would mean scope creep).
- GC entries link to the ADRs.

## Rollback

- Pure docs PR; revert if PM rejects the model.

## Cross-references

- Issue #162 (MCP matrix - upstream)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` items #34, #38, #29 (doc
  permissions sweep)
- `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` §6 Onda B
- ADR-0011, ADR-0012, ADR-0015, ADR-0080, ADR-0085, ADR-0087

## Handoff (fill on completion)

```md
## Handoff
Issue: #166
Branch:
Roadmap status:
ADRs scaffolded:
Files:
Validacao:
Riscos:
Rollback:
Docs:
Proximo passo:
```
