# SPEC-280.C — Wave-2 `/semantic` tool: `get_operational_status`

**Status:** SPEC (spec-first — not yet built). Authored 2026-06-07.
**Parent:** #280 (Semantic MCP Gateway). **Sibling specs:** [SPEC-280.A](./SPEC_280A_CONNECTOR_STORE_READINESS.md) (connector-store readiness, #283 — closed), [SPEC-280.B](./SPEC_280B_SEMANTIC_MCP_GATEWAY_IMPLEMENTATION.md) (gateway implementation + first-wave candidates).
**Decision:** PM selected `get_operational_status` as the wave-2 `/semantic` tool (2026-06-07, grounded in the 90d Pareto below). Build is a separate greenlight — this spec is the Definition of Ready.

> ⚠️ The `/mcp` → `/mcp/full` surface rename (SPEC-280.B "Future target") stays **blocked on gate G19**. This spec adds **one tool to the existing `/semantic` surface** (3 → 4); it does **not** touch `/mcp` and is **not** blocked by G19.

---

## 1. Why this tool, why now (90d Pareto, `mcp_usage_log`)

Pareto over the trailing 90 days (~1,364 calls):

- The dominant cluster is **write / operational** tools (`add_checklist_item` 16.5%, `register_attendance` 5.6%, `update_card_fields` 5.5%, `create_board_card`, `submit_evaluation`, `create_meeting_notes`) — **not** candidates for a public read-only gateway.
- Wave-1 already covers the top **read** intents: personal (`get_my_context`), knowledge (`search_nucleo_knowledge`), board/initiative (`get_board_or_initiative_context`).
- **Operational dashboards** are a recurring read need (`get_tribe_dashboard` 17, plus the health tools). `get_operational_status` is the natural composite for "how is the chapter doing right now?" — and it now also surfaces the **#415 recurrence-stockout** alert added to `detect_operational_alerts`.
- It composes **only already-built, already-gated** read RPCs → no new RPCs/migrations, lowest implementation risk of the wave-2 candidates.
- `get_governance_context` was **deferred**: governance reads show ~0 current MCP demand in the Pareto, and the #459 clause-body read is a separate legal-reviewed sub-decision. Selection composites (`get_candidate_context`/`get_selection_workspace`) stay deferred — high-PII, committee-only.

(Re-run the Pareto at build time — the source of truth is the query, not these frozen numbers. See SPEC-280.B §"Pareto audit".)

## 2. Intent & scope

A single read-only call that returns a **compact operational-health summary** for the chapter: active alerts (incl. recurrence stockout), event/attendance health, and cron/sync health. Summary-first; aggregate counts and short messages only — **no member PII, no raw audit payloads**.

## 3. Composition (all sources already exist + carry their own gate)

`get_operational_status` aggregates these existing RPCs via `Promise.allSettled` with graceful per-source degradation (same pattern as `get_my_context`, `index.ts:7083`):

| Source RPC | Contributes | Existing gate |
|---|---|---|
| `detect_operational_alerts` | alerts[] + by_severity (incl. `recurrence_stockout` from #415) | `manage_platform` |
| `get_event_attendance_health` | event attendance coverage health | `view_internal_analytics` / `view_chapter_dashboards` |
| `get_recurrence_stockout` | (`detail_level='standard'`) the resupply list behind the stockout alert count | `manage_event` |
| `get_digest_health` · `get_lgpd_cron_health` · `get_invitation_health` | cron/sync health rollup | `view_internal_analytics` |

> **Not composed (decided at build):** `get_adoption_metrics` is NOT a direct RPC — the `/mcp` tool of that name wraps `get_mcp_adoption_stats` (gated `manage_member`; MCP-route metrics, not chapter ops health). Excluded to avoid guessing; can be added later if a chapter-adoption RPC is introduced.
> **Gate note:** the composite gate is `manage_platform`; the attendance + stockout sources have narrower gates, so a pure `manage_platform` caller may see those degrade to a `warnings[]` entry (graceful, by design). Tracked as a backlog follow-up to broaden `get_event_attendance_health` if needed.

Each source runs under the **caller's JWT**, so each RPC enforces its own gate; a denied/failing source **degrades to a `warnings[]` entry** rather than failing the whole call (wave-1 invariant).

## 4. Authorization

- **Tool-level gate (fail-closed):** `manage_platform` — matches the most restrictive source (`detect_operational_alerts`) and the SPEC-280.B note ("Admin-only or scoped summaries"). Resolve via `getMember(sb)` → check; on miss return `buildSemanticError({ tool, semantic_domain:'operational', code:'unauthorized'|'unauthenticated', ... })` wrapped in `ok(...)` (wave-1 pattern, `index.ts:7072-7075`).
- Defense-in-depth: source RPC gates remain authoritative; the tool gate only decides whether the call is attempted at all.

## 5. Input schema (Zod)

```ts
{
  detail_level: z.enum(["summary", "standard"]).optional()
    .describe("'summary' = alert counts by severity + health rollup. 'standard' = adds the alert list + the recurrence-stockout resupply list + attendance detail. Default: 'summary'."),
  severity_min: z.enum(["low", "medium", "high"]).optional()
    .describe("Filter the returned alerts to >= this severity. Default: 'low' (all)."),
}
```

No write params. No free-text. Bounded output (cap alert list, e.g. 50).

## 6. Response envelope (stable, per SPEC-280.B §"Proposed Response Envelope")

```json
{
  "ok": true,
  "data": {
    "alerts_by_severity": { "high": 9, "medium": 3, "low": 1 },
    "alerts": [ { "type": "recurrence_stockout", "severity": "high", "message": "Série recorrente (tribo) no fim do estoque: última em 2026-05-30, próxima esperada ~2026-06-06" } ],
    "health": { "digest": "green", "lgpd_cron": "green", "invitations": "green" },
    "attendance_health": { "stale_events_no_attendance": 0, "oldest_stale_date": null, "window_days": 14 }
  },
  "summary": "12 alertas (9 alta · 3 média · 1 baixa) · crons ok · 8 séries no fim do estoque.",
  "warnings": [],
  "next_actions": [
    "get_recurrence_stockout: list series to resupply",
    "get_board_or_initiative_context: drill into a flagged tribe/initiative"
  ],
  "audit": {
    "tool": "get_operational_status",
    "semantic_domain": "operational",
    "pii_level": "none",
    "permission": "manage_platform",
    "source_tools": ["detect_operational_alerts", "get_recurrence_stockout", "get_event_attendance_health", "get_digest_health", "get_lgpd_cron_health", "get_invitation_health"],
    "generated_at": "<iso>"
  }
}
```

## 7. PII posture

`pii_level: "none"` — emits aggregate counts, severity rollups, and short alert messages (event type + dates, never member email/phone). `detect_operational_alerts` already strips raw audit payloads; the `member_absence_streak` alert carries `member_name` — **the semantic tool MUST drop `member_name`** (and any name field) before returning, or down-rank `pii_level` to `"low"` and document it. Default: drop names → keep `pii_level: "none"`.

## 8. Implementation notes

- Register as semantic tool 4/4 in `registerSemanticTools(...)` (`index.ts:7059`), mirroring `get_my_context`.
- `Promise.allSettled` over the source RPCs; reuse the `get(idx)`/`warnings` degradation helper.
- Bounded output; no bulk dumps.
- **Count bookkeeping (`/semantic` 3 → 4)** — update ALL of:
  - `index.ts` `/health` `"/semantic": { ... tools: 3 }` → 4, + header comment + a changelog entry.
  - The contract tests that pin `/semantic: 3` (grep `tools:\s*3` near `nucleo-ia-semantic`; mcp-semantic-gateway-bridge + any sibling — verify with a full `grep -rn "semantic" tests/`; note the #415 sediment that the count-registry can hold a stray 4th file).
  - Regenerate `docs/reference/MCP_TOOL_MATRIX.md` + `mcp-tool-matrix.json` + `src/lib/mcp-manifest.json` (the audit script treats `/semantic` tools as static-only; matrix flat total becomes 311 = 307 `/mcp` + 4 `/semantic`).
- Version posture: bump the `/semantic` surface version (currently `0.1.0`) — it is a real capability add on that surface (unlike `/mcp` count-only bumps). Suggest `0.2.0`.

## 9. Test plan

- **Contract (static):** semantic `tools/list` includes `get_operational_status`; `inputSchema` is a valid object; no non-spec top-level fields; read-only annotation where SDK supports; envelope keys present.
- **DB-gated:** call via service-role (no `auth.uid()`) → returns the `buildSemanticError` envelope with `code: 'unauthenticated'` (fail-closed; house pattern — service-role cannot impersonate). Register in `package.json` `test` + `test:contracts`.
- **Smoke (post-deploy):** `/semantic` initialize + tools/list = 4, 0 `_zod`; one authorized success (impersonated admin) + one `severity_min` filter; confirm no `member_name` leaks.

## 10. Out of scope / follow-ups

- `/mcp` → `/mcp/full` rename (G19-blocked, SPEC-280.B).
- `get_governance_context` (deferred; #459 clause-body read needs legal review).
- Selection composites (`get_candidate_context`/`get_selection_workspace`) — high-PII, deferred until a real connector-store submission is scheduled + privacy gates ratified.

## 11. Definition of Done

`get_operational_status` live on `/semantic` (4 tools), fail-closed, PII-clean (no names), envelope-compliant; contract + DB-gated tests green; matrix/manifest/health/version updated; smoke confirms 4 tools + no leak. EF deploy required (no migration).
