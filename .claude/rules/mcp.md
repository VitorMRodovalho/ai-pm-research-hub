---
description: MCP server rules and tool patterns
globs: supabase/functions/nucleo-mcp/**
---

# MCP Server Rules (nucleo-mcp v2.25.1)

## Current State
- 143 tools (96 read + 47 write) + 1 dynamic prompt + 1 static resource
- Transport: @modelcontextprotocol/sdk@1.29.0 WebStandardStreamableHTTPServerTransport (native)
- Tool params: Zod schemas (z.string(), z.number(), z.boolean()) — NOT plain JSON Schema objects
- Auth: OAuth 2.1 via Workers (nucleoia.vitormr.dev) → Supabase JWT
- All tools log usage to mcp_usage_log
- Claude.ai connector: verified working (73 tools visible)

## Pre-Deploy Check (MANDATORY)
Before deploying nucleo-mcp EF, check for duplicate tool names:
```bash
grep 'mcp.tool(' supabase/functions/nucleo-mcp/index.ts | awk -F'"' '{print $2}' | sort | uniq -d
```
Must return empty. Duplicate names cause SDK boot crash → HTTP 500 on ALL requests including `initialize`. Smoke test with curl after deploy:
```bash
curl -sS -X POST "https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp" \
  -H "Content-Type: application/json" -H "Authorization: Bearer test" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}' \
  -w "\nHTTP:%{http_code}\n"
```
Expected: HTTP 200 + serverInfo. If 500 with "already registered": rename the duplicate tool.

## SDK Compatibility
- **SDK 1.29.0**: Latest stable. Works on Deno with native `WebStandardStreamableHTTPServerTransport`. Tool params MUST use Zod schemas.
- **Zod import**: `import { z } from "npm:zod@4.3.6";` — pinned to exact version (was `^4.0`, pinned 2026-04-26 for reproducibility — MCP is critical infra; minor zod bumps could change validation behavior silently). SDK 1.29.0 supports `zod ^3.25 || ^4.0`. Update consciously when reading release notes.
- **History**: SDK 1.27.1 worked but required manual SSE wrapping (85 lines). SDK 1.29.0 initially failed on Deno due to non-Zod schemas + old dep versions. After converting tools to Zod and upgrading all deps, 1.28.0 native transport works.

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

## Auto-Refresh (v2.7.1 — server-side token renewal)
- Worker proxy (`src/pages/mcp.ts`) decodes JWT `exp` before forwarding upstream
- If expired or expiring within 5 minutes, looks up `mcp_refresh:{sub}` from KV
- Calls Supabase Auth API directly (`/auth/v1/token?grant_type=refresh_token`)
- Forwards request with new access_token — transparent to MCP host
- KV keys: `mcp_refresh:{user_id}` with 30-day TTL (set at token issuance + refresh)
- Token endpoint (`/oauth/token`) stores refresh_token in KV on both `authorization_code` and `refresh_token` grants
- Supabase JWT TTL is 3600s (1h, not configurable via dashboard) — auto-refresh compensates
- Best practice: never depend on MCP hosts to implement refresh — do it server-side
