---
description: MCP server rules (nucleo-mcp) — pre-deploy checks (duplicate names, Zod 3→4, contract matrix drift), tool-count grounding, MCP↔RPC alias map, OAuth/Streamable-HTTP transport, auto-refresh
paths:
  - "supabase/functions/nucleo-mcp/**"
  - "src/pages/mcp.ts"
  - "scripts/audit-mcp-tool-matrix.mjs"
---

# MCP Server Rules (nucleo-mcp — /mcp full catalog + /semantic bridge + /actions overflow)

## Current State (do NOT pin counts here)

Three surfaces:
- `/mcp` (server: `nucleo-ia-hub`) — the full internal capability registry (~340 tools + 4 prompts + 3 resources).
- `/semantic` (server: `nucleo-ia-semantic`) — bridge-first public semantic gateway (wave-1: 3 tools; wave-2: +get_operational_status, SPEC-280.C), stable
  envelope `{ok,data,summary,warnings,next_actions,audit}`.
- `/actions` (server: `nucleo-ia-actions`, #1377) — **overflow surface** for the Claude chat connector's
  **256-tool per-connector cap**. The connector ingests tools ALPHABETICALLY by display name and drops
  everything past the ~`manage_*` boundary — i.e. almost the entire write/action tail (schedule_interview,
  submit_interview_scores, move_card, offboard_member, …). `/actions` re-exposes that dropped tail as a SECOND
  connector, reusing the SAME `registerTools` definitions via `ACTIONS_ALLOWLIST` + `filterToAllowlist()` (zero
  body duplication; no `registerKnowledge`). Consumed alongside `/mcp` (reads/browse) as a separate connector
  URL. Coverage is guarded by `tests/contracts/1377-mcp-actions-overflow-coverage.test.mjs` — a future tool
  addition that shifts the /mcp 256-cut and drops a write tool fails CI until it is added to the allowlist.
  **The 256 cap is per-connector, not global** (validated when /actions' write tools became callable with /mcp
  still connected); if that ever changes, the fix reverts to shrinking /mcp below 256 (consolidate thin tools).
  Worker proxy: `/mcp/actions` → EF `/nucleo-mcp/actions` (`src/pages/mcp/actions.ts`, mirrors `semantic.ts`).

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
- Health observability tools: `get_invitation_health`, `get_lgpd_cron_health`, `get_digest_health`, `get_ots_pipeline_health`.

**Audit-script note:** `scripts/audit-mcp-tool-matrix.mjs` hardcodes the /mcp endpoint and treats all `mcp.tool(`
calls as a flat list (total = /mcp + 4 /semantic). It flags the 4 semantic tools as "static-only" — expected
post-bridge, NOT drift; a surface-aware audit is on the #280 follow-up backlog.

## MCP tool name ↔ RPC name divergences (alias map)

Most MCP tools share the underlying RPC name (e.g., `submit_evaluation` tool → `submit_evaluation` RPC). A handful diverge intentionally to give consumers a more discoverable tool name without renaming the SQL surface. Known divergences:

- `sign_ratification_gate` (MCP tool) → `public.sign_ip_ratification` (RPC). Registered at `supabase/functions/nucleo-mcp/index.ts:5337` and dispatched via `sb.rpc("sign_ip_ratification", { ... })`. The tool name reads better for cross-document consumers ("sign a gate on a ratification chain") while the RPC keeps the IP-3d-era body name. **Implication for migrations**: fixes to `sign_ip_ratification` body apply transparently to all consumers (MCP host calling `sign_ratification_gate`, native UI calling the RPC directly). Do NOT rename either side — the divergence is stable and consumer-breaking to undo. Verified during p269 SEDIMENT-268.A audit (`approval_signoffs.organization_id` remediation).
- `propose_new_version` + `edit_document_version_draft` (MCP tools) → `public.upsert_document_version` (RPC única). Ambas despacham a MESMA RPC (`index.ts` ~6368/~6400: create passa `p_version_id=null`, edit passa o id do draft). NÃO existe RPC `propose_new_version` — fixes de corpo entram em `upsert_document_version` e valem para as duas tools. Registrado no import #632 (2026-06-11), quando o fallback impersonado precisou localizar a RPC real após o conector expirar.
- `get_governance_document_body` (MCP tool, #459) → `public.get_governance_document_reader` (RPC). Dispatched via `sb.rpc("get_governance_document_reader", { p_document_id })`. The tool name reads as "read the body/clauses of a governance document"; the RPC keeps its p263 W4d "reader" name (also called directly by the member-facing `/governance/document/[id]` route). The tool **wraps** the RPC and enriches in the EF layer (Markdown + section anchors via `./governance-html.mjs`, ratification caveat, MCP-channel `visibility_class` ceiling = `public`/`active_members` only) — so RPC body fixes apply transparently to both consumers. **Do NOT** mirror `get_version_diff`'s gate for any governance body read (its active-member-only check is weaker than the canonical visibility model). Legal gate cleared GO-com-condições (`docs/council/decisions/2026-06-07-459-governance-document-body-build.md`).

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

## OAuth Flow — Supabase NATIVE OAuth 2.1 server (#1210, 2026-07-08)
Token issuance lives in GoTrue's native OAuth server (dashboard: Authentication →
OAuth Server, enabled, authorization path `/oauth/consent`; OAuth app "Nucleo IA
MCP" `8636c0d0-…`, public + PKCE, claude.ai/claude.com redirect URIs). Each OAuth
client gets a DEDICATED client-scoped session/refresh chain — the browser session
is only the approver identity on the consent page.

- Discovery: /.well-known/oauth-{authorization-server,protected-resource} — Worker
  routes, ORIGIN-AWARE (issuer/resource = request origin; alias-ready). The AS
  metadata is hybrid: authorize/token → `https://<ref>.supabase.co/auth/v1/oauth/*`,
  registration → our shim.
- Register: /oauth/register (DCR shim, returns the fixed pre-registered client_id —
  keeps Supabase dynamic registration OFF)
- Authorize: GoTrue `/auth/v1/oauth/authorize` validates client_id/redirect_uri/PKCE
  → redirects to Site URL + `/oauth/consent?authorization_id=…`
- Consent: `src/pages/oauth/consent.astro` — login (browser session) + settle via
  `supabase.auth.oauth.{getAuthorizationDetails,approveAuthorization,denyAuthorization}`
- Token + refresh: GoTrue `/auth/v1/oauth/token` (code exchange + rotation). The
  Worker `/oauth/token` is a RETIRED STUB (400 invalid_grant → stale clients re-auth);
  `/oauth/exchange` is deleted.
- Scopes: GoTrue supports only openid/email/profile/phone (default email). NEVER
  advertise custom scopes in metadata. Access tokens are standard Supabase JWTs
  (+ `client_id` claim) — RLS/EF surface unchanged.
- Per-client revocation: `supabase.auth.oauth.revokeGrant(clientId)` / grants list
  via `listGrants` (closes the #1051 self-service gap).
- Guarded by `tests/contracts/1210-mcp-native-oauth.test.mjs`.

## Streamable HTTP (native transport)
- `WebStandardStreamableHTTPServerTransport` handles all protocol details
- Stateless mode: `sessionIdGenerator: undefined`
- Workers proxy streams SSE responses through without buffering
- GET /mcp → 406 (native transport returns Not Acceptable when no session)
- Transport handles: initialize, tools/list, tool/call, notifications, SSE streams

## Token refresh — history: #1053 single-refresher → #1210 native server
**Current model (#1210): NOTHING in the Worker issues or refreshes tokens.** Claude
refreshes directly against GoTrue's `/auth/v1/oauth/token` on its own client-scoped
chain; the browser session rotates independently. The #1053 model below is retained
as history because it explains the failure class (two holders of one rotating chain).

#1053 (2026-07-05, superseded by #1210): Claude was the sole refresher THROUGH our
`/oauth/token`, which kept a KV copy (`mcp_refresh:{sub}`, 30-day TTL) in sync. That
still shared ONE chain with the BROWSER session (consent copied it) — the residual
collision #1210 eliminated. KV refresh entries are dead; left to expire by TTL.

### Why the proxies must NEVER refresh (the #1053 bug)
The proxies (`src/pages/mcp.ts`, `src/pages/mcp/semantic.ts`) used to auto-refresh
server-side (`tryAutoRefresh`) on any expiring request. That was a **second refresher**
racing Claude over the SAME rotating Supabase refresh token: whoever refreshed first
rotated R→R' and invalidated the other's copy. When the proxy won, Claude's next
refresh 400'd ("already used") → `token.ts` returned `invalid_grant` → **Claude
re-logged-in every ~1h**. #580's KV re-store could not fix it (keeps the *server*
copy fresh; no channel pushes R' back to Claude). Fix = remove the proxy refresh.
- `tryAutoRefresh` / `isExpiringSoon` remain in `src/lib/mcp-refresh.ts` (unit-tested)
  but are **deprecated for proxy use** — do NOT re-wire them into the proxies.
- Guarded by `tests/contracts/1053-mcp-single-refresher.test.mjs`.
- Diagnostic note: `kvLog` in both proxies + `token.ts` is a **no-op** (KV free-tier
  write protection) — there is no `token-refresh-fail`/`auto-refresh-*` telemetry to
  read; classify refresh issues from code + a live `/oauth/token` smoke, not KV logs.
- Dashboard (owner-only, Auth → Sessions): keep refresh-token rotation as-is; ensure
  no aggressive session/inactivity timeout (would re-login even with a perfect flow).
