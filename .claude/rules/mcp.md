# MCP Server Rules (nucleo-mcp — /mcp full catalog + /semantic bridge)

## Current State (do NOT pin counts here)

Two surfaces shipped post-p222 #280 (Semantic MCP Gateway bridge):
- `/mcp` (server: `nucleo-ia-hub`) — the full internal capability registry (~300 tools + 4 prompts + 3 resources).
- `/semantic` (server: `nucleo-ia-semantic`) — bridge-first public semantic gateway (wave-1: 3 tools), stable
  envelope `{ok,data,summary,warnings,next_actions,audit}`.

**The exact tool count changes every session — never recite it from memory or pin it here.** Get the live count:
```bash
curl -sS -X POST https://nucleoia.vitormr.dev/mcp -H 'Authorization: Bearer test' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | grep -oE '"name":"[^"]+"' | wc -l
# or structured per-surface report:
curl https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/health
```
The per-session tool-count change-history is archived at `docs/audit/MCP_RULES_TOOLCOUNT_HISTORY_ARCHIVED_2026-05-30.md`.

Worker proxy paths (`nucleoia.vitormr.dev`): `/mcp` → EF `/nucleo-mcp/mcp`; `/mcp/semantic` → EF `/nucleo-mcp/semantic`.
Both shave the SDK 1.29.0 `execution.taskSupport` field via post-process strip (Perplexity-spec compat). See
`docs/MCP_SETUP_GUIDE.md` for client routing.

- Transport: `@modelcontextprotocol/sdk@1.29.0` `WebStandardStreamableHTTPServerTransport` (native).
- Tool params: Zod schemas (`z.string()`, `z.number()`, …) — NOT plain JSON Schema objects.
- Auth: OAuth 2.1 via Workers (nucleoia.vitormr.dev) → Supabase JWT. All tools log to `mcp_usage_log`.
- Health observability tools: `get_invitation_health`, `get_lgpd_cron_health`, `get_digest_health`.

**Audit-script note:** `scripts/audit-mcp-tool-matrix.mjs` hardcodes the /mcp endpoint and treats all `mcp.tool(`
calls as a flat list (total = /mcp + 3 /semantic). It flags the 3 semantic tools as "static-only" — expected
post-bridge, NOT drift; a surface-aware audit is on the #280 follow-up backlog.

## MCP tool name ↔ RPC name divergences (alias map)

Most MCP tools share the underlying RPC name (e.g., `submit_evaluation` tool → `submit_evaluation` RPC). A handful diverge intentionally to give consumers a more discoverable tool name without renaming the SQL surface. Known divergences:

- `sign_ratification_gate` (MCP tool) → `public.sign_ip_ratification` (RPC). Registered at `supabase/functions/nucleo-mcp/index.ts:5337` and dispatched via `sb.rpc("sign_ip_ratification", { ... })`. The tool name reads better for cross-document consumers ("sign a gate on a ratification chain") while the RPC keeps the IP-3d-era body name. **Implication for migrations**: fixes to `sign_ip_ratification` body apply transparently to all consumers (MCP host calling `sign_ratification_gate`, native UI calling the RPC directly). Do NOT rename either side — the divergence is stable and consumer-breaking to undo. Verified during p269 SEDIMENT-268.A audit (`approval_signoffs.organization_id` remediation).

## Pre-Deploy Check (MANDATORY)

### 1. Duplicate tool names
```bash
grep 'mcp.tool(' supabase/functions/nucleo-mcp/index.ts | awk -F'"' '{print $2}' | sort | uniq -d
```
Must return empty. Duplicate names cause SDK boot crash → HTTP 500 on ALL requests including `initialize`. If 500 with "already registered": rename the duplicate tool.

### 2. Zod 3→4 incompatibilities (sediment p122b — silent tools/list breakage)
The project pins `npm:zod@4.3.6`. Zod-3-style usage compiles fine but breaks tools/list at request time with `Cannot read properties of undefined (reading '_zod')` — the SDK's JSON-Schema converter reaches into a key that doesn't exist and the whole list fails. Initialize keeps working, so the breakage is invisible in basic smoke tests.
```bash
# Single-arg z.record (Zod 3) — must be z.record(keySchema, valueSchema) in Zod 4
grep -nE 'z\.record\([^,)]*\)' supabase/functions/nucleo-mcp/index.ts | grep -v ', '

# Top-level format helpers that moved (Zod 4 has them, but the canonical spelling is z.string().X())
grep -nE 'z\.(uuid|email|url|cuid|cuid2|ulid|emoji|datetime|nanoid)\s*\(' supabase/functions/nucleo-mcp/index.ts
```
Both must return empty. The first command caught the `capture_visitor_lead` regression (p122b commit `65ad84b`); the second is preventive for future tools.

### 3. Smoke after deploy — verify both initialize AND tools/list
```bash
# initialize
curl -sS -X POST "https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp" \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "Authorization: Bearer test" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}' \
  -w "\nHTTP:%{http_code}\n"

# tools/list — required to catch _zod-style failures that initialize misses
curl -sS -X POST "https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp" \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "Authorization: Bearer test" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```
Expected: HTTP 200 + serverInfo on initialize, AND a non-empty `result.tools[]` array on tools/list. If tools/list returns `{"error":{"code":-32603,"message":"Cannot read properties of undefined..."}}` despite initialize succeeding, you have a Zod 3→4 issue — re-run grep #2 above.

### 4. Contract matrix drift (issue #162, p202)

The MCP tool contract matrix is generated by `scripts/audit-mcp-tool-matrix.mjs` and stored in `docs/reference/MCP_TOOL_MATRIX.md` + `docs/reference/mcp-tool-matrix.json`. Pre-deploy:

```bash
# Regenerate matrix + cross-check static vs runtime tools/list
node scripts/audit-mcp-tool-matrix.mjs --runtime
```

Expected: `[runtime] clean (N runtime ≡ N static)`. If drift is reported (`drift: X static-only, Y runtime-only`), investigate before deploy — common causes:
- Tool added to `index.ts` but EF not redeployed (static>runtime)
- Tool removed from `index.ts` but EF still has stale version (runtime>static)
- Duplicate name collapsed by SDK (rename one)

Re-running the matrix is also useful after migrations that change RPC signatures — diff `mcp-tool-matrix.json` to see which tools call the changed RPC.

## SDK Compatibility
- **SDK 1.29.0**: stable on Deno with native `WebStandardStreamableHTTPServerTransport`. Tool params MUST use Zod schemas. (Latest 1.x confirmed via npm `dist-tags.latest` — re-query, don't trust this line; 2.0 is a breaking alpha, do not adopt.)
- **Zod import**: `import { z } from "npm:zod@4.3.6";` — pinned exact (MCP is critical infra; minor zod bumps could change validation behavior silently). SDK 1.29.0 supports `zod ^3.25 || ^4.0`. Update consciously when reading release notes.
- **History**: SDK 1.27.1 worked but required manual SSE wrapping (85 lines). 1.29.0 native transport works after converting tools to Zod + upgrading deps.

## Tool Pattern
```typescript
import { z } from "npm:zod@4.3.6";

// Tools with parameters — MUST use Zod schemas
mcp.tool("tool_name", "Description.", {
  param: z.string().describe("Parameter description"),
  optional_param: z.number().optional().describe("Optional param. Default: 10")
}, async (params) => {
  const start = Date.now();
  const member = await getMember(sb);
  if (!member) { await logUsage(sb, null, "tool_name", false, "Not authenticated", start); return err("Not authenticated"); }
  const { data, error } = await sb.rpc("rpc_name", { p_param: params.param });
  if (error) { await logUsage(sb, member.id, "tool_name", false, error.message, start); return err(error.message); }
  await logUsage(sb, member.id, "tool_name", true, undefined, start);
  return ok(data);
});

// Tools without parameters — empty object is fine
mcp.tool("tool_name", "Description.", {}, async () => { ... });
```

## Write Permission (V4 — ADR-0007)
- `canV4(sb, member.id, action)` gates all write tools via RPC `can_by_member()` → `can()` (engagement-derived authority)
- Actions: `write`, `write_board`, `manage_partner`, `promote`, `manage_member`, `manage_event`, `view_pii`
- Permissions seeded in `engagement_kind_permissions` table (kind × role × action)
- Fail-closed: if RPC errors, access is denied
- NEVER skip the canV4 check for write tools
- Legacy `canWrite`/`canWriteBoard`/`WRITE_ROLES`/`BOARD_ROLES` removed in cutover 2026-04-13

## OAuth Flow (all in Workers, NOT in EF)
- Discovery: /.well-known/oauth-{authorization-server,protected-resource}
- Register: /oauth/register (DCR, returns fixed client_id)
- Authorize: /oauth/authorize → /oauth/consent (login + approve)
- Exchange: /oauth/exchange (generates code in KV)
- Token: /oauth/token (PKCE verify, returns JWT)

## Streamable HTTP (native transport)
- `WebStandardStreamableHTTPServerTransport` handles all protocol details
- Stateless mode: `sessionIdGenerator: undefined`
- Workers proxy streams SSE responses through without buffering
- GET /mcp → 406 (native transport returns Not Acceptable when no session)
- Transport handles: initialize, tools/list, tool/call, notifications, SSE streams

## Auto-Refresh (server-side token renewal)
- Worker proxy (`src/pages/mcp.ts`) decodes JWT `exp` before forwarding upstream
- If expired or expiring within 5 minutes, looks up `mcp_refresh:{sub}` from KV
- Calls Supabase Auth API directly (`/auth/v1/token?grant_type=refresh_token`)
- Forwards request with new access_token — transparent to MCP host
- KV keys: `mcp_refresh:{user_id}` with 30-day TTL (set at token issuance + refresh)
- Token endpoint (`/oauth/token`) stores refresh_token in KV on both `authorization_code` and `refresh_token` grants
- Supabase JWT TTL is 3600s (1h) — auto-refresh compensates
- Best practice: never depend on MCP hosts to implement refresh — do it server-side
