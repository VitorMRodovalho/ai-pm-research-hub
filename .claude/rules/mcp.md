---
description: MCP server rules and tool patterns
globs: supabase/functions/nucleo-mcp/**
---

# MCP Server Rules (nucleo-mcp v2.4.0)

## Current State
- 23 tools (17 read + 6 write)
- Transport: @modelcontextprotocol/sdk@1.27.1 + InMemoryTransport + manual Streamable HTTP SSE
- Tool params: Zod schemas (z.string(), z.number(), z.boolean()) — NOT plain JSON Schema objects
- Auth: OAuth 2.1 via Workers (nucleoia.vitormr.dev) → Supabase JWT
- All tools log usage to mcp_usage_log
- Claude.ai connector: verified working (23 tools visible, 5 tested)

## SDK Compatibility (critical)
- **SDK 1.27.1**: Works on Deno. Tool params must use Zod schemas — plain `{ param: { type: "string" } }` objects get misidentified as ToolAnnotations, leaving inputSchema empty.
- **SDK 1.28.0**: Breaks on Deno — `mcp.tool()` API changed to require Zod natively, `WebStandardStreamableHTTPServerTransport` crashes at runtime. Do NOT upgrade until Deno compat is confirmed.
- **Zod import**: `import { z } from "npm:zod@3";` — SDK 1.27.1 requires `zod ^3.25 || ^4.0`. The `npm:zod@3` specifier resolves to latest 3.x (currently 3.25.76) which satisfies this. Do NOT change to `npm:zod@4` without testing.

## Tool Pattern
```typescript
import { z } from "npm:zod@3";

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

## Write Permission
- `canWrite(member)` gates write tools: manager, deputy_manager, tribe_leader, is_superadmin
- NEVER skip the canWrite check for write tools

## OAuth Flow (all in Workers, NOT in EF)
- Discovery: /.well-known/oauth-{authorization-server,protected-resource}
- Register: /oauth/register (DCR, returns fixed client_id)
- Authorize: /oauth/authorize → /oauth/consent (login + approve)
- Exchange: /oauth/exchange (generates code in KV)
- Token: /oauth/token (PKCE verify, returns JWT)

## Streamable HTTP (manual implementation)
- POST /mcp → JSON-RPC request → SSE response (when Accept includes text/event-stream)
- POST notification (no id) → 202 Accepted
- GET /mcp → 405 (stateless mode, no server-initiated messages)
- DELETE /mcp → 405 (stateless mode, no session termination)
- Workers proxy streams SSE responses through without buffering
