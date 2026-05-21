---
description: MCP server rules and tool patterns
globs: supabase/functions/nucleo-mcp/**
---

# MCP Server Rules (nucleo-mcp v2.77.0)

## Current State
- **296 tools + 4 prompts + 3 resources** (Issue #205 fully closed via 3-PR sequence — p215 GAP-205.C close PR #242 squash `4be3ad83` drops dead-schema `member_emails.verified_at` column + rebuilds `member_list_emails` RPC sans verified_at in return TABLE + 2 forward-defense contract tests asserting column absence; `member_list_emails` MCP tool result shape simplified from 8→7 columns transparently — tool description unchanged, count unchanged 296; was p214 GAPs A/B close PR #241 squash `b039d74d` adding 10 RLS multi-tenant static-analysis assertions to `tests/contracts/member-emails-rls-multi-tenant.test.mjs` + migration 20260802000011 FK `member_emails.organization_id → organizations(id) ON DELETE RESTRICT` matching canonical members/tribes/engagements pattern; was p213 #205 ADR-0095 alternate member emails core — +3 tools `member_resolve_email` (resolve any registered email — primary or alternate — to member_id; STABLE SECDEF; gates: any authenticated user) + `member_list_emails` (list all emails for a member_id; STABLE SECDEF; gates: self / `manage_member` / `view_pii`) + `member_add_alternate_email` (insert alternate email with kind ∈ {personal,institutional,chapter,other}; VOLATILE SECDEF; gates: self / `manage_member`); wraps new `public.member_emails` table + `sync_member_email_trigger_fn` (AFTER INSERT/UPDATE OF email ON members keeps `members.email` ↔ `member_emails` primary in sync for backward compat); migration `20260802000008_member_alternate_emails.sql` pre-applied to live DB by prior session before commit `af378809` push; backfill 73 members → 73 primary rows live verified; invariant T added to `check_schema_invariants()` (count 18 → 19, all violation_count=0 live); tool count 293 → 296; MCP layer uses `getMember()` not `canV4` since authorization is in RPC SECDEF body — defensible per ADR-0007 (V4 authority lives in `can_by_member()` callable from inside SECDEF); was p199-a council fix bundle v2.76.1 — analyze_application_video gains JS-layer `canV4('view_pii')` guard + docstring polish (return envelope shape + force param wording fix) per code-reviewer HIGH; pairs with p199-a HIGH #1 fix in migration 20260519131912 rollback comment (post-smoke live rows make naive rollback non-idempotent — now documents DELETE step + LGPD Art. 37 §3 audit trail caveat); tool count unchanged 293; was p199-a v2.76.0 — +1 tool analyze_application_video (p197d D1 producer): triggers Whisper transcription + Claude Haiku 4.5 multimodal (transcription + Drive thumbnail) per pillar (5 pillars: background + communication + culture_alignment + proactivity + teamwork); generates selection_evaluation_ai_suggestions(evaluation_type='video') consumable via submit_evaluation(ai_suggestion_id=...); idempotent + LGPD-gated via consent_ai_analysis_at; co-shipped with migration 20260519131912 expanding ai_processing_log.purpose CHECK to allow 'video_screening' — pre-fix smoke revealed silent check_violation inside try/catch caused EF to 202-OK with zero rows in any of {ai_processing_log, selection_evaluation_ai_suggestions, pmi_video_screenings.transcription}; post-fix smoke 2026-05-19 13:53 confirmed INSERT path live (ai_processing_log row 'fd8d32df…' created with purpose='video_screening', status='failed' due to OpenAI Whisper 429 quota — NOT code bug, graceful degradation works); was p197c v2.75.0 — +1 tool list_ai_suggestions (consumer surface for ai_suggestion_id) + compute_pert_cutoff refactored into _compute_pert_cutoff_core helper + pg_cron weekly recompute-pert-cutoffs-weekly Mon 13:00 UTC; was p197c v2.74.0 — submit_interview_scores upgraded to rich preview parity with submit_evaluation + get_selection_rankings + get_application_score_breakdown enriched server-side (description bumps only, tool count unchanged 291); was p197b v2.73.0 — +2 tools surfacing PERT cutoff to MCP: get_pert_cutoff_summary + compute_pert_cutoff; was p197 v2.72.0 — submit_evaluation rich preview + new params criterion_notes_json/ai_suggestion_id; was p193 v2.71.0 — get_tribes_comparison upgraded to V4 wrapping exec_cross_initiative_comparison; was v2.70.0 p172 — meeting_close tool extended em p171 #9 Track B aceita suggested_champion_ids[] param; was v2.69.0 p165 — same 289 count; was 284 at p133 close; was 283 post p117 +get_extraction_health for ADR-0075; was 266 post p106 #97 W3 G4; was 217 = 141R + 76W at p77 marathon close — R/W split tracking dropped p106 since heuristic unreliable; total + canonical commit log replaces it)
- Transport: @modelcontextprotocol/sdk@1.29.0 WebStandardStreamableHTTPServerTransport (native)
- Tool params: Zod schemas (z.string(), z.number(), z.boolean()) — NOT plain JSON Schema objects
- Auth: OAuth 2.1 via Workers (nucleoia.vitormr.dev) → Supabase JWT
- All tools log usage to mcp_usage_log
- Claude.ai connector: verified working
- Health observability: `get_invitation_health` (W7) + `get_lgpd_cron_health` (W8) + `get_digest_health` (W9 issue #99) — Pattern 43 saturation reached

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

The MCP 293-tool contract matrix is generated by `scripts/audit-mcp-tool-matrix.mjs` and stored in `docs/reference/MCP_TOOL_MATRIX.md` + `docs/reference/mcp-tool-matrix.json`. Pre-deploy:

```bash
# Regenerate matrix + cross-check static vs runtime tools/list
node scripts/audit-mcp-tool-matrix.mjs --runtime
```

Expected output: `[runtime] clean (N runtime ≡ N static)` with N matching the count claimed by `.claude/rules/mcp.md` header. If drift is reported (`drift: X static-only, Y runtime-only`), investigate before deploy — common causes:
- Tool added to `index.ts` but EF not redeployed (static>runtime)
- Tool removed from `index.ts` but EF still has stale version (runtime>static)
- Duplicate name collapsed by SDK (rename one)

If the script reports more or fewer tools than the header claims, update the header count in `.claude/rules/mcp.md`. Re-running the matrix is also useful after migrations that change RPC signatures — diff `mcp-tool-matrix.json` to see which tools call the changed RPC.

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
