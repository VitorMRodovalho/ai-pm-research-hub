# SPEC-280.B — Semantic MCP Gateway Implementation Brief

**Date:** 2026-05-22  
**Status:** Draft implementation brief  
**Parent:** GitHub #280 — Semantic MCP Gateway + internal capability registry  
**Depends on:** SPEC-280.A / GitHub #283 — Connector Store Readiness Matrix

## Decision Summary

Build the Semantic MCP Gateway as a bridge-first endpoint:

- keep `/mcp` as the existing full-catalog endpoint during transition;
- introduce `/mcp/semantic` as the public semantic gateway;
- validate `/mcp/semantic` first with Perplexity and other strict clients;
- migrate `/mcp` to semantic-first only after usage metrics, smoke tests, docs, and communication gates pass;
- keep the 299-tool catalog as an explicit internal/dev mode later, for example `/mcp/full` or `?profile=full`.

This is not a reduced capability plan. It is a public semantic contract that orchestrates the internal capability registry.

## Implementation Goal

Expose a small, stable, review-ready set of semantic tools that:

- cover the highest-value operational intents;
- route internally to existing RPCs/tools/tables;
- return bounded, structured responses;
- avoid unnecessary PII;
- pass strict MCP client discovery;
- are suitable for future OpenAI/Anthropic directory review.

## Architecture

```text
AI client
  -> /mcp/semantic
    -> Semantic MCP server surface
      -> Domain orchestrators
        -> existing RPCs / internal tools / Supabase tables / AI functions
          -> RLS + can_by_member + audit logs
```

The internal 299-tool catalog remains the implementation registry and audit inventory.

## Placement Options

| Option | Description | Pros | Risks | Recommendation |
|---|---|---|---|---|
| A. Implement semantic registration in `supabase/functions/nucleo-mcp/index.ts` | Add `registerSemanticTools()` and route `/mcp/semantic` in the Edge Function. Worker forwards path to EF. | Cleanest protocol behavior; semantic tools are first-class MCP tools; avoids brittle response mutation. | Requires EF deploy; must keep route compatibility and tests. | Preferred. |
| B. Filter serialized `tools/list` in `src/pages/mcp.ts` Worker proxy | Proxy intercepts `tools/list` and returns subset/profile. | Fast to prototype. | Brittle; tool calls still need routing; repeats current regex/post-processing failure mode. | Avoid except for temporary diagnostics. |
| C. Separate `nucleo-mcp-semantic` Edge Function | New EF with only semantic tools. | Strong isolation; lower blast radius. | Duplicates auth/client/bootstrap code; more deploy/config overhead. | Consider if A becomes too risky. |

Recommended initial design: Option A.

## Baseline Metrics Query

Before finalizing first-wave semantic tools, run a 90-day Pareto audit from `mcp_usage_log`.

```sql
-- Top technical tools by calls, users, reliability, and latency.
SELECT
  tool_name,
  count(*) AS calls,
  count(DISTINCT member_id) AS users,
  count(*) FILTER (WHERE success) AS ok,
  count(*) FILTER (WHERE NOT success) AS fail,
  round((count(*) FILTER (WHERE NOT success))::numeric / NULLIF(count(*), 0) * 100, 1) AS error_rate_pct,
  round(avg(execution_ms) FILTER (WHERE success)::numeric, 0) AS avg_success_ms,
  max(execution_ms) FILTER (WHERE success) AS max_success_ms,
  max(created_at) AS last_call
FROM public.mcp_usage_log
WHERE created_at >= now() - interval '90 days'
  AND tool_name NOT IN ('tools/list', 'initialize')
GROUP BY tool_name
ORDER BY calls DESC, users DESC
LIMIT 50;
```

```sql
-- Intent buckets for first-wave semantic grouping.
WITH classified AS (
  SELECT
    tool_name,
    CASE
      WHEN tool_name LIKE '%selection%' OR tool_name LIKE '%application%' OR tool_name LIKE '%candidate%' OR tool_name LIKE '%evaluation%' OR tool_name LIKE '%interview%' THEN 'selection'
      WHEN tool_name LIKE '%wiki%' OR tool_name LIKE '%knowledge%' OR tool_name LIKE '%resource%' OR tool_name LIKE '%hub%' THEN 'knowledge'
      WHEN tool_name LIKE '%governance%' OR tool_name LIKE '%manual%' OR tool_name LIKE '%document%' OR tool_name LIKE '%signature%' THEN 'governance'
      WHEN tool_name LIKE '%board%' OR tool_name LIKE '%card%' OR tool_name LIKE '%initiative%' OR tool_name LIKE '%tribe%' THEN 'operations'
      WHEN tool_name LIKE '%profile%' OR tool_name LIKE '%my_%' OR tool_name LIKE '%attendance%' OR tool_name LIKE '%certificate%' THEN 'personal'
      WHEN tool_name LIKE '%report%' OR tool_name LIKE '%kpi%' OR tool_name LIKE '%portfolio%' OR tool_name LIKE '%dashboard%' OR tool_name LIKE '%metrics%' THEN 'reporting'
      ELSE 'other'
    END AS semantic_domain,
    success,
    member_id,
    execution_ms,
    created_at
  FROM public.mcp_usage_log
  WHERE created_at >= now() - interval '90 days'
)
SELECT
  semantic_domain,
  count(*) AS calls,
  count(DISTINCT member_id) AS users,
  count(DISTINCT tool_name) AS technical_tools,
  round((count(*) FILTER (WHERE NOT success))::numeric / NULLIF(count(*), 0) * 100, 1) AS error_rate_pct,
  round(avg(execution_ms) FILTER (WHERE success)::numeric, 0) AS avg_success_ms
FROM classified
GROUP BY semantic_domain
ORDER BY calls DESC;
```

## First-Wave Semantic Tool Candidates

Final names must be validated against usage data. These candidates are intentionally few and read/context-heavy.

| Candidate tool | Primary intent | Internal capability families | Risk | Store-readiness notes |
|---|---|---|---|---|
| `get_my_context` | Give the authenticated user a compact personal operating context. | profile, XP/ranking, attendance hours/history, notifications, upcoming events, certificates, current cycle. | Low/medium PII. | Must avoid exposing email/phone unless self and necessary. Read-only annotation. |
| `search_nucleo_knowledge` | Search and summarize knowledge assets. | hub resources, wiki, governance/public docs, publications. | Low. | Good first smoke tool. Bounded results and citations. |
| `get_selection_workspace` | Give committee/admin a cycle-level selection workspace. | dashboard, rankings, pending evaluations, health, PERT cutoff, committee assignments. | Medium/high PII. | Gate strongly; summary-first; no candidate PII unless authorized. |
| `get_candidate_context` | Build a single candidate review pack. | application detail, resume/cv, LinkedIn fields, scholar/latex context if present, AI suggestions, video status, evaluations, interview state. | High PII. | Requires view/committee gate, audit log, bounded output, clear human-decision disclaimer. |
| `get_governance_context` | Retrieve governance state and relevant docs. | governance docs, manual sections, signatures, approval chains, change log. | Medium. | Avoid raw sensitive audit payload by default. |
| `get_operational_status` | Summarize operational health. | operational alerts, adoption metrics, event attendance health, data anomalies, cron/sync health where available. | Medium. | Admin-only or scoped summaries. |
| `get_board_or_initiative_context` | Summarize an initiative/board/tribe in one call. | board status, cards, events, meeting notes, deliverables, housekeeping, partner cards. | Medium. | Scope by initiative/tribe; avoid bulk dumps. |
| `run_nucleo_report` | Generate bounded report packs by type. | cycle report, annual KPIs, chapter dashboard, portfolio overview/health, attendance ranking. | Medium/high. | Enum report types; response size bounds; admin/chapter scoping. |

## Proposed Response Envelope

All semantic tools should use a stable envelope.

```json
{
  "ok": true,
  "data": {},
  "summary": "Short human-readable summary.",
  "warnings": [],
  "next_actions": [],
  "audit": {
    "tool": "get_my_context",
    "semantic_domain": "personal",
    "pii_level": "self",
    "permission": "authenticated",
    "source_tools": ["get_my_profile", "get_my_attendance_hours"],
    "generated_at": "2026-05-22T00:00:00.000Z"
  }
}
```

Error envelope:

```json
{
  "ok": false,
  "error": {
    "code": "permission_denied",
    "message": "You do not have access to this candidate context.",
    "action": "Ask a selection admin to verify your committee assignment."
  },
  "audit": {
    "tool": "get_candidate_context",
    "semantic_domain": "selection",
    "generated_at": "2026-05-22T00:00:00.000Z"
  }
}
```

## Tool Schema Rules

- Inputs should use small objects with explicit fields.
- Prefer enums for mode/report type/detail level.
- Use `limit` with caps for result lists.
- Avoid open object payloads in public semantic tools.
- Avoid arbitrary SQL-like filters.
- Include `detail_level` where needed: `summary`, `standard`, `full_authorized`.
- Include `include_pii` only when useful and always default false.
- Do not expose internal table/RPC names as required user inputs.

## Endpoint Contract

Initial bridge:

- `/mcp` -> current full MCP server behavior.
- `/mcp/semantic` -> semantic MCP tools only.

Future target:

- `/mcp` -> semantic MCP tools by default.
- `/mcp/full` or `?profile=full` -> full internal/dev catalog with explicit documentation and access policy.

## Documentation Scope

Same PR or release train as `/mcp/semantic` should update:

- `docs/MCP_SETUP_GUIDE.md`
- `src/pages/docs/mcp.astro`
- public blog/source for `mcp-server-launch`
- `docs/reference/MCP_TOOL_MATRIX.md` wording if needed to clarify internal registry vs public gateway

## Test Plan

Contract tests:

- `/mcp` still exposes current full catalog during bridge.
- `/mcp/semantic` exposes only semantic tools.
- Semantic `tools/list` payload is below a documented size threshold.
- Semantic tools include valid object `inputSchema`.
- Semantic tools use no non-spec top-level fields.
- Read-only semantic tools carry read-only annotations where SDK support allows.
- Write/destructive tools are absent from wave 1 or require preview/confirm.

Smoke tests:

- initialize + tools/list for `/mcp/semantic`.
- one success and one invalid-input call per semantic tool.
- Perplexity reconnect against `/mcp/semantic`.
- ChatGPT developer-mode app creation against `/mcp/semantic`.
- Claude custom connector against `/mcp/semantic`.

Regression tests:

- `/mcp` full catalog remains unchanged during bridge.
- OAuth discovery/authorization/token endpoints continue to work.
- `mcp_usage_log` records semantic tool calls with `tool_name` set to semantic tool names.

## Handoff To Implementation

Implementation should proceed as a MCP/AI lane task, with Foundation review if new RPCs or migrations are needed.

Suggested first implementation issue:

> Implement `/mcp/semantic` bridge with 3 read-only semantic tools (`get_my_context`, `search_nucleo_knowledge`, `get_board_or_initiative_context`) plus contract tests and docs stub.

Keep selection/candidate semantic tools for a second wave unless metrics show they are the dominant Pareto cluster and privacy gates are ready.

## Open Risks

- The existing `nucleo-mcp/index.ts` is monolithic; adding semantic registration may increase complexity unless helpers are extracted carefully.
- If semantic tools internally call existing tool handlers instead of shared domain helpers/RPCs, duplication may grow.
- If `/mcp/semantic` uses a separate EF, OAuth/discovery routing may drift.
- If response envelopes are too verbose, strict clients may still struggle.
- If no reviewer dataset exists, store-readiness remains theoretical.
