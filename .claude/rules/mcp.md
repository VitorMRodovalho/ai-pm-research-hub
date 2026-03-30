---
description: MCP server rules and tool patterns
globs: supabase/functions/nucleo-mcp/**
---

# MCP Server Rules (nucleo-mcp v2.5.0)

## Current State
- 26 tools (20 read + 6 write)
- Transport: @modelcontextprotocol/sdk@1.28.0 WebStandardStreamableHTTPServerTransport (native)
- Tool params: Zod schemas (z.string(), z.number(), z.boolean()) — NOT plain JSON Schema objects
- Auth: OAuth 2.1 via Workers (nucleoia.vitormr.dev) → Supabase JWT
- All tools log usage to mcp_usage_log
- Claude.ai connector: verified working (26 tools visible)

## SDK Compatibility
- **SDK 1.28.0**: Latest stable. Works on Deno with native `WebStandardStreamableHTTPServerTransport`. Tool params MUST use Zod schemas.
- **Zod import**: `import { z } from "npm:zod@^3.25";` — SDK 1.28.0 requires `zod ^3.25 || ^4.0`.
- **History**: SDK 1.27.1 worked but required manual SSE wrapping (85 lines). SDK 1.28.0 initially failed on Deno due to non-Zod schemas + old dep versions. After converting tools to Zod and upgrading all deps, 1.28.0 native transport works.

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

## Streamable HTTP (native transport)
- `WebStandardStreamableHTTPServerTransport` handles all protocol details
- Stateless mode: `sessionIdGenerator: undefined`
- Workers proxy streams SSE responses through without buffering
- GET /mcp → 406 (native transport returns Not Acceptable when no session)
- Transport handles: initialize, tools/list, tool/call, notifications, SSE streams
