# Decision — MCP Semantic Gateway wave-2 tool = `get_operational_status`

**Date**: 2026-06-07
**Decider**: PM (Vitor) via AskUserQuestion
**Domain**: MCP / AI lane (#280 Semantic MCP Gateway)
**Status**: DECIDED → SPEC'd (SPEC-280.C) → BUILT + DEPLOYED same session

## Context

The `/semantic` gateway shipped wave-1 (3 read-only composite tools: `get_my_context`, `search_nucleo_knowledge`, `get_board_or_initiative_context`). The MCP-wave deliverable was: confirm #283 (SPEC-280.A connector-store readiness — already CLOSED), run a 90d `mcp_usage_log` Pareto, and pick the wave-2 tool **spec-first** (no code jump; the `/mcp`→`/mcp/full` rename stays blocked on gate G19).

## Options presented (with live grounding)

The recommendation was produced AFTER a live 90d Pareto (`mcp_usage_log`, ~1,364 calls) + reading SPEC-280.B's candidate table — not from assumption. Options:

1. **`get_operational_status`** *(recommended)* — composes already-built+gated ops reads (incl. `detect_operational_alerts`, now carrying the #415 recurrence-stockout alert). Lowest-risk, no new RPCs/migrations, medium-PII admin-scoped.
2. `get_operational_status` + a calendar/events composite (biggest uncovered low-PII read demand in the Pareto).
3. `get_governance_context` (metadata-only; routes #459 clause-body read to a separate legal sub-decision).
4. Defer wave-2 entirely.

## Recommendation & rationale (PL/CTO)

**Option 1.** Pareto evidence:
- Dominant cluster = write/ops tools (not gateway candidates).
- Wave-1 already covers personal/knowledge/board reads.
- Operational dashboards are the recurring uncovered read need; this composite also surfaces the new #415 stockout observability.
- Composes only existing gated reads → lowest implementation risk.
- `get_governance_context` deferred: governance reads show ~0 current MCP demand in the Pareto, and the #459 clause-body read is a legal call. Selection composites stay deferred (high-PII, committee-only).

## Decision

PM selected **Option 1 — `get_operational_status`**, spec-first.

## Execution (same session)

- **SPEC-280.C** authored + merged (PR #560).
- **Built + deployed** (PR #561): `/semantic` 3→4, surface version 0.1.0→0.2.0; gated `manage_platform`; PII-clean (`pii_level: none`, member-specific alert messages redacted); composes `detect_operational_alerts` + `get_recurrence_stockout` + `get_event_attendance_health` + cron/sync health trio via `Promise.allSettled`. EF deployed + smoked (tools/list 4, 0 `_zod`, /health 0.2.0/4). Council (ai-engineer + code-reviewer): SHIP-WITH-NITS, 0 blockers; 4 nits folded.
- `/mcp` untouched (307).

## Follow-ups (backlog)

- Broaden `get_event_attendance_health` gate (`view_internal_analytics`/`view_chapter_dashboards`) — narrower than `manage_platform`, so it degrades to a warning for pure-`manage_platform` callers (graceful, but data-incomplete).
- Manifest domain tag for `get_operational_status` (`tribe` → `admin`/`health`).
- `get_governance_context` (#459 clause-body read) — legal/RLS review before spec.
- `/mcp` → `/mcp/full` rename — blocked on gate G19.
