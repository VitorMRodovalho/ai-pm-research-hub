---
issue: 162
title: mcp - generate 293-tool contract matrix and refresh tool reference
lane: MCP/AI
priority: P1
effort: L (parser + matrix + doc refresh)
status: ready
opened: 2026-05-19
github: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/162
---

# p201 Session Brief - Issue #162: MCP 293-Tool Contract Matrix

## Why this matters

MCP runtime exposes 293 tools (verified at `/health` and `tools/list`).
A simple grep parser counts 292 from `index.ts` (drift). 25 handlers do
direct `.from(...)` table reads, 277 use `.rpc(...)`, and 83 use the
`canV4(...)` JS gate. Without a generated matrix that maps tool ->
dependency -> gate -> output shape -> drift risk, we have no canonical
contract for AI clients and no early warning when a migration breaks an
MCP callsite (failures stay HTTP-200 + inside the JSON payload).

## Runtime baseline (already collected)

- `nucleo-mcp /health`: 293 tools, version `2.76.1`, SDK `1.29.0`.
- `tools/list`: 293 tools.
- `check_schema_invariants()`: 16/16 violations = 0.
- `mcp_usage_log`: 0 failures last 14 days.
- Direct-table-access hotspots: `members` (5), `board_items` (4),
  `project_boards` (3), `events` (3), `initiatives` (2), `engagements`
  (2), `initiative_invitations` (2), plus 12 single-use tables.
- External fetch / service role tools: `upload_text_to_drive_folder`,
  `create_drive_subfolder`, `analyze_application`,
  `generate_interview_briefing` (need separate secrets/LGPD audit).

## Lane and gates

- Lane: MCP/AI (`supabase/functions/nucleo-mcp/`, MCP docs, generated
  scripts in `scripts/`)
- Can touch: parser/generator scripts, generated artifacts, MCP doc
  references, `tool-reference` resource definition
- Can't touch: tool semantics, RPC bodies, RLS, migrations (open a
  Foundation issue if drift is found)
- Gates: pre-deploy duplicate-name grep PASS, Zod 3->4 incompat grep
  PASS, smoke initialize + tools/list PASS, no new failures in
  `mcp_usage_log`

## In scope

1. Build a generator script (`scripts/audit-mcp-tool-matrix.mjs` or
   `.ts`) that:
   - Reads `tools/list` from runtime (293) as the canonical inventory.
   - Parses `index.ts` to extract per-tool: RPC calls, direct table
     reads/writes, `canV4(...)` calls, external fetches, response shape
     hints.
   - Joins runtime + static into one CSV/JSON matrix.
   - Flags drift (tool listed by parser but not in runtime, or vice
     versa).
2. Output a markdown matrix (or JSON) in `docs/reference/MCP_TOOL_MATRIX.md`
   (or `docs/audit/`). At minimum: 293 rows, columns
   `[name, domain, rpcs, tables, gate_js, gate_rpc, output_shape, drift, smoke]`.
3. Refresh `tool-reference` MCP resource to point to runtime-derived data
   (either inline render or pointer to the matrix).
4. Update `.claude/rules/mcp.md` if the pre-deploy check should grep the
   matrix for drift.
5. Add a CI/local invocation note in `docs/MCP_SETUP_GUIDE.md`.

## Out of scope

- Refactoring any tool body or migrating direct-table tools to RPCs.
- Updating tool semantics (canV4 layer changes, new permissions).
- Splitting `index.ts` into per-domain modules (separate ADR).

## Files likely to touch

- `scripts/audit-mcp-tool-matrix.mjs` (new)
- `docs/reference/MCP_TOOL_MATRIX.md` (new)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` (close #35, #36, #38 if matrix
  resolves them)
- `.claude/rules/mcp.md` (add matrix check to pre-deploy)
- `docs/MCP_SETUP_GUIDE.md` (replace static count with reference to
  matrix + tools/list)
- `supabase/functions/nucleo-mcp/index.ts` ONLY if the tool-reference
  resource definition changes (no semantic edits)

## Validation

- `node scripts/audit-mcp-tool-matrix.mjs` exits 0 with matrix
  generated; drift count = 0 or explicitly explained.
- Spot-check 10 random tools across domains - matrix row matches actual
  index.ts handler.
- `tools/list` count = matrix row count = 293.
- No regression in pre-deploy smoke (initialize + tools/list both PASS).
- `mcp_usage_log` shows no new failures after deploy (if any deploy is
  required - this issue should NOT need an EF deploy).

## Rollback

- Pure docs/scripts addition; revert PR if matrix is wrong.
- If `tool-reference` resource changed, restore previous body via prior
  commit.

## Cross-references

- `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` §2 (parser baseline)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` items #35, #36, #38
- `.claude/rules/mcp.md` (current pre-deploy checks)
- Issue #166 (semantic layer) - matrix is upstream input

## Handoff (fill on completion)

```md
## Handoff
Issue: #162
Branch:
Escopo:
Matrix rows:
Drift detected:
Files added:
Validacao:
Riscos:
Rollback:
Docs:
Proximo passo:
```
