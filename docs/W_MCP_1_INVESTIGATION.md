# W-MCP-1: Custom MCP Server for Tribe Leaders
## AI & PM Research Hub — Investigation Report + Implementation Plan

**Status:** Investigation complete. Ready for prioritization.
**Investigator:** Claude (Product Leader)
**Date:** 27 March 2026

---

## 1. EXECUTIVE SUMMARY

Build a custom MCP server as a Supabase Edge Function that allows tribe leaders to plug their personal AI assistants (Claude, ChatGPT, Gemini) into the Hub platform. The server exposes domain-specific tools (board status, attendance, meeting notes, XP) scoped to the leader's permissions via Supabase Auth.

**Key finding:** The official Supabase MCP server is a DEVELOPER tool — it bypasses RLS, gives admin-level access, and Supabase explicitly warns "don't give it to your customers." We need a CUSTOM MCP server that authenticates as the user and respects our existing permission model.

**Effort:** ~2 sessions (Camada 1 + 2). Zero additional cost (Edge Functions are free tier).

---

## 2. ARCHITECTURE DECISION

### ❌ NOT THIS: Official Supabase MCP Server
- Operates under DEVELOPER permissions (service role key)
- Bypasses ALL RLS policies
- Exposes raw SQL execution (`execute_sql` tool)
- Supabase docs: "Don't give to your customers"
- Would let Fabrício's Claude see ALL data across ALL tribes

### ✅ THIS: Custom MCP Server (Edge Function + mcp-lite)
- Authenticates as the USER (via Supabase Auth OAuth 2.1)
- RLS applies automatically — leaders only see their own tribe data
- Exposes curated TOOLS that map 1:1 to existing RPCs
- No raw SQL access — only business-level operations
- Scoped by role: tribe_leader sees different tools than researcher

### Architecture Diagram

```
Claude/ChatGPT/Gemini (leader's personal AI)
         │
         │  MCP protocol (Streamable HTTP)
         ▼
┌─────────────────────────────────────────────┐
│   Supabase Edge Function: nucleo-mcp        │
│   (mcp-lite + Hono + WebStandard transport) │
│                                             │
│   Auth: Supabase Auth OAuth 2.1             │
│   ├─ User authenticates as themselves       │
│   ├─ Gets access token (JWT)                │
│   └─ RLS applies on every query             │
│                                             │
│   Tools (Phase 1 — read-only):              │
│   ├─ get_my_board_status                    │
│   ├─ get_my_tribe_attendance                │
│   ├─ get_my_tribe_members                   │
│   ├─ get_upcoming_events                    │
│   ├─ get_my_xp_and_ranking                  │
│   ├─ get_meeting_notes                      │
│   ├─ get_my_notifications                   │
│   ├─ search_board_cards                     │
│   ├─ get_tribe_deliverables_summary         │
│   └─ get_hub_announcements                  │
│                                             │
│   Tools (Phase 2 — write):                  │
│   ├─ create_board_card                      │
│   ├─ update_card_status                     │
│   ├─ create_meeting_notes                   │
│   ├─ register_attendance                    │
│   └─ send_notification_to_tribe             │
│                                             │
│         ▼ calls existing RPCs               │
│   supabase.rpc('get_tribe_dashboard', ...)  │
│   supabase.rpc('list_tribe_deliverables')   │
│   supabase.rpc('get_my_member_record')      │
│   ... (300+ existing RPCs, reuse all)       │
└─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────┐
│   Supabase PostgreSQL   │
│   (RLS enforced)        │
│   auth.uid() = leader   │
└─────────────────────────┘
```

---

## 3. TOOL STACK

| Component | Choice | Rationale |
|-----------|--------|-----------|
| MCP framework | `mcp-lite` | Zero-dependency, TypeScript, Supabase EF template oficial |
| Transport | `WebStandardStreamableHTTPServerTransport` | Supabase recommended pattern |
| HTTP router | `Hono` | Lightweight, already in Supabase EF examples |
| Auth | Supabase Auth OAuth 2.1 | Reuses existing user base, RLS applies automatically |
| Deployment | Supabase Edge Function | Free tier, same infra, zero new services |

### Framework alternatives considered

| Framework | Verdict |
|-----------|---------|
| `mcp-lite` | ✅ Chosen. Zero deps, EF template, lightweight |
| `@modelcontextprotocol/sdk` | ❌ Heavier, more boilerplate |
| `FastMCP` | ⚠️ Promising (built-in Supabase Auth), but newer and less documented |
| Custom from scratch | ❌ No reason to reinvent |

---

## 4. AUTH MODEL — CRITICAL DESIGN

### How it works

1. Leader adds MCP server URL to their AI client:
   ```
   https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp
   ```

2. MCP client initiates OAuth 2.1 flow → browser opens → leader logs in with Google/LinkedIn/Azure (same as platform login)

3. Supabase Auth issues JWT for the authenticated user

4. Every tool call includes this JWT → Edge Function creates Supabase client with user's token → RLS enforced

5. Leader can only see/do what their role permits (same as website)

### Token scoping

| Role | Tools visible | Data scope |
|------|--------------|------------|
| tribe_leader | All Phase 1 + Phase 2 write tools for own tribe | Own tribe members, boards, attendance |
| researcher | Read-only subset | Own data, own tribe data (exploration mode) |
| manager/deputy | All tools + cross-tribe | All tribes, all members |
| observer | Minimal read-only | Public data only |
| stakeholder | Chapter-level metrics | get_chapter_dashboard equivalent |

**No new permissions needed.** The existing RPC auth guards + RLS handle everything.

### Fabrício pilot — superadmin question

**Answer: No need to revoke superadmin.**

When Fabrício authenticates via OAuth to the MCP server, his `auth.uid()` resolves to his `members` record. The RPCs he calls through the MCP will use the same auth path as the website. His superadmin flag means he CAN see everything — but the MCP tools we expose are scoped by design (e.g., `get_my_board_status` only returns HIS tribe's board).

To test the "normal leader experience," we can:
- Create a tool `get_my_tribe_board` that explicitly filters by `tribe_id` from the caller's member record
- OR: ask Fabrício to test specific queries and report if he sees data he shouldn't

**Removing superadmin is unnecessary friction that could break his admin access to the website.**

---

## 5. SECURITY ANALYSIS

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Prompt injection via board card content | Medium | MCP tools return structured JSON, not raw text. Wrap responses with instruction boundaries (Supabase pattern). |
| Token leakage | Medium | OAuth tokens expire. Refresh tokens handled by Supabase Auth. Leader revokes via platform settings. |
| Leader sees other tribe data | Low | RLS enforced. Existing RPCs already filter by caller's tribe_id. |
| Write operations (Phase 2) | Medium | Phase 1 is read-only. Phase 2 writes require explicit user confirmation in MCP clients. |
| PII in LLM context | Medium | Tools return `members_public_safe` equivalent (name, role, XP — no email, no phone). |
| Rate limiting / abuse | Low | Supabase Edge Functions have built-in rate limits. Add custom per-user limit if needed. |

### LGPD compliance

| Concern | Status |
|---------|--------|
| Data minimization | Tools return only necessary fields. PII excluded. |
| User consent | OAuth flow = explicit consent. Leader chooses to connect. |
| Data processing by LLM | Leader's responsibility (same as copy-pasting from website). Platform TOS should mention MCP access. |
| Right to erasure | Disconnecting MCP = revoking OAuth token. No data persisted in MCP layer. |

---

## 6. COMPATIBILITY MATRIX

| AI Client | MCP Support | Transport | Auth | Status |
|-----------|-------------|-----------|------|--------|
| Claude Desktop | ✅ Native | Streamable HTTP | OAuth 2.1 | Works |
| Claude.ai (web) | ✅ Remote MCP | Streamable HTTP | OAuth 2.1 | Works |
| Claude Code | ✅ Native | Streamable HTTP | OAuth / PAT header | Works |
| ChatGPT | ❌ No MCP | — | — | Needs REST API wrapper (Phase 3) |
| Gemini | ❌ No MCP | — | — | Needs REST API wrapper (Phase 3) |
| Cursor | ✅ Native | Streamable HTTP | OAuth 2.1 | Works |
| VS Code Copilot | ✅ MCP extension | Streamable HTTP | OAuth 2.1 | Works |

**Important:** ChatGPT and Gemini do NOT support MCP natively. For those users, we'd need a REST API layer (Phase 3) that those tools can call via function calling/plugins. The MCP server (Phase 1-2) serves Claude, Cursor, and VS Code users directly.

---

## 7. RPCs TO EXPOSE (Phase 1 — Read-Only)

All 10 tools map to EXISTING RPCs — zero new SQL needed:

| MCP Tool | Existing RPC | Returns |
|----------|-------------|---------|
| `get_my_profile` | `get_my_member_record()` | Name, role, tribe, XP, badges |
| `get_my_board_status` | `list_board_items(board_id)` | Cards by status (backlog/in_progress/done) |
| `get_my_tribe_attendance` | `get_tribe_dashboard_data(tribe_id)` | Attendance rates, detractors |
| `get_my_tribe_members` | `get_tribe_dashboard_data(tribe_id)` | Member list (public_safe fields) |
| `get_upcoming_events` | `list_events()` filtered by date | Next 7 days of events |
| `get_my_xp_and_ranking` | `get_member_cycle_xp()` | XP breakdown, rank position |
| `get_meeting_notes` | `list_meeting_minutes(tribe_id)` | Recent meeting notes |
| `get_my_notifications` | `list_my_notifications()` | Unread notifications |
| `search_board_cards` | `search_board_items(query)` | Full-text search on cards |
| `get_hub_announcements` | `list_announcements()` | Active announcements |

---

## 8. IMPLEMENTATION PLAN

### Phase 1: Read-Only MVP (1 session, ~3-4 hours)

**Deliverables:**
1. Edge Function `nucleo-mcp` using mcp-lite
2. 10 read-only tools mapping to existing RPCs
3. OAuth 2.1 auth via Supabase Auth
4. Deployed and accessible at EF URL
5. Tested by GP (Vitor) with Claude

**Steps:**
```
1. npx create-mcp-lite@latest (Supabase EF template)
2. Implement 10 tool definitions with Supabase client
3. Configure OAuth 2.1 in Supabase Dashboard (Auth > OAuth Server)
4. Deploy: supabase functions deploy nucleo-mcp --no-verify-jwt
5. Test: add to Claude Desktop, run all 10 tools
6. Document: setup guide for leaders
```

### Phase 2: Pilot with Fabrício (1 session, ~2 hours)

**Deliverables:**
1. 5 write tools (create card, update status, create notes, register attendance, notify tribe)
2. Fabrício tests with his Claude
3. Friction report documented
4. Decision: roll out to 6 remaining leaders or iterate

### Phase 3: REST API for ChatGPT/Gemini (future, deferred)

**Deliverables:**
1. REST API endpoints wrapping same tools
2. API key generation in user profile
3. OpenAPI spec for ChatGPT plugin / Gemini function calling
4. Documentation for non-Claude users

---

## 9. COST ANALYSIS

| Component | Cost |
|-----------|------|
| Supabase Edge Functions | Free (500K invocations/month) |
| mcp-lite | Free (MIT, zero deps) |
| Supabase Auth OAuth | Free (included) |
| New infrastructure | Zero |
| **Total** | **$0** |

Zero-cost architecture constraint: ✅ respected.

---

## 10. SUCCESS METRICS

| Metric | Target | How to measure |
|--------|--------|----------------|
| Leaders using MCP weekly | 3/7 leaders in first month | Audit log of MCP tool calls |
| Avg tool calls per leader/week | 10+ | Edge Function logs |
| Time to answer "status do meu board" | <5 sec (vs 30 sec website) | User feedback |
| New Sentry errors from MCP | 0 | Sentry monitoring |
| PII leakage incidents | 0 | LGPD audit |

---

## 11. RISKS THAT COULD KILL THIS

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Supabase Auth OAuth for MCP is marked "coming soon" for EF auth | Medium | Blocks auth entirely | Fallback: API key auth (simpler, less elegant) |
| Leaders don't have Claude/Cursor | Low | No users | Survey first; most have ChatGPT at minimum |
| RPC returns too much data for LLM context | Medium | Truncated/confused responses | Limit response size in tool definitions |
| mcp-lite breaking change (pre-1.0) | Low | Migration effort | Pin version, monitor releases |

---

## 12. GC ENTRY (when approved)

```
GC-132: W-MCP-1 — Custom MCP server investigation complete.
Architecture: Supabase Edge Function (mcp-lite) with OAuth 2.1 auth.
NOT using official Supabase MCP (developer-only, bypasses RLS).
Custom server authenticates as user, respects RLS, exposes 10 curated read-only tools.
Phase 1: Read-only MVP. Phase 2: Write tools + Fabrício pilot.
Phase 3 (deferred): REST API for ChatGPT/Gemini users.
Zero cost. Target: second half of April 2026.
```

---

## 13. RECOMMENDATION

**Proceed.** The architecture is sound, the stack is mature (mcp-lite has official Supabase template), the cost is zero, and the alignment with the Núcleo's mission is perfect.

**Timeline:** After Relatório C2→C3 (4/Apr) and Resend DNS resolution. Target: week of 14-18 April.

**First step:** Verify Supabase Auth OAuth server status for the project (may need to enable in Dashboard: Auth > OAuth Server > Enable dynamic client registration).

**Pilot:** Fabrício with Claude, scoped to T6 board + tribe data.
