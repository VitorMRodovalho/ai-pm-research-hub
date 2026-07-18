# MCP Setup Guide — Núcleo IA & GP Research Hub

## What is MCP?

MCP (Model Context Protocol) is an open protocol that allows AI assistants to interact with external services. The Núcleo server exposes **three surfaces**: `/mcp` (the full internal capability registry), `/mcp/semantic` (an intent-level semantic gateway with a stable envelope), and `/mcp/actions` (an overflow surface for connectors with a per-connector tool cap). All surfaces let you query and manage project data from your AI assistant using natural language. A dynamic knowledge layer adapts guidance to each member's role and permissions.

> **Member onboarding (2026-07-18):** the member-facing default route is now the single semantic connector `https://nucleoia.vitormr.dev/mcp/semantic` (one connector, fits every client's tool cap, alpha). The full `/mcp` registry is the documented escape-hatch when a client rejects the semantic connector or a capability is missing. The member-facing quick-start (single source of truth, on the live site, trilingual) is `/docs/mcp/conectar`; this repo-only guide is the technical reference behind it. Feedback: GH #1428.

## Endpoints

Live counts are at `/health`; the `tools/list` response is the source of truth. Never pin a number, query it.

| Endpoint | Tools | Purpose | Recommended clients |
|----------|-------|---------|---------------------|
| `https://nucleoia.vitormr.dev/mcp` | 342 | Full internal capability registry. Default for clients that accept large catalogs. | Claude.ai, Claude Code, Cursor / VS Code, ChatGPT developer mode, Manus AI |
| `https://nucleoia.vitormr.dev/mcp/semantic` | 52 | **Intent-level semantic gateway (SPEC-280 / #1383, `nucleo-ia-semantic` v0.11.0).** One tool per user intent (~7:1 consolidation over the raw registry) with a stable envelope `{ok,data,summary,warnings,next_actions,audit}`; write tools carry authority + confidential-visibility (#785) gates as a contract. **Member-facing default route** (single connector, alpha), and the surface for strict clients and store/directory submissions. | Members onboarding (default), Perplexity, OpenAI Apps SDK review, Anthropic Connectors Directory review, future store/directory submissions |
| `https://nucleoia.vitormr.dev/mcp/actions` | 88 | **Overflow surface (#1377).** The Claude connector ingests at most 256 tools per connector, alphabetically, dropping the write/action tail. `/actions` re-exposes that dropped tail as a second connector, reusing the same tool definitions. | Claude.ai / Claude Code, consumed alongside `/mcp` as a second connector |

All endpoints share the same OAuth 2.1 flow (same account, same login). For **member onboarding**, use the single `/semantic` connector (default). For power users on the full registry, `/mcp` is the escape-hatch, with `/actions` as a second connector for the write tail that the 256-tool per-connector cap drops. Strict clients and store/directory submissions also target `/semantic`.

The 52 semantic tools cover seven intent domains (full catalog: [`docs/reference/SEMANTIC_TOOL_CATALOG.md`](reference/SEMANTIC_TOOL_CATALOG.md)):
- **Boards & cards** — `board_overview`, `card_search`, `card_get`, `card_write`, `card_checklist`, `card_comment`, `portfolio_report`, `platform_context`.
- **Members, engagements & initiatives** — `member_search`, `member_get`, `member_emails`, `member_lifecycle`, `engagement_write`, `initiative_roster`, `initiative_directory`, `initiative_report`, `my_status`.
- **Events, attendance & meetings** — `event_search`, `event_write`, `attendance_record`, `attendance_report`, `meeting_minutes`, `meeting_actions`.
- **Selection & evaluation** — `selection_dashboard`, `application_get`, `evaluation_submit`, `interview_manage`, `selection_decide`, `visitor_leads`.
- **Governance, documents & certificates** — `document_get`, `document_version_write`, `document_comment`, `change_request`, `signature_flow`, `certificate_manage`, `ip_exclusion`.
- **Comms, Drive & partners** — `comms_report`, `comms_post`, `webinar_manage`, `idea_pipeline`, `drive_links`, `drive_access_admin`, `partner_crm`.
- **Knowledge, gamification & admin** — `search_nucleo_knowledge`, `gamification_report`, `champion_award`, `admin_dashboard`, `audit_log`, `lgpd_admin`, plus the bridge tools `get_my_context`, `get_board_or_initiative_context`, `get_operational_status`.

## Compatibility

| Client | Status | Recommended endpoint | Notes |
|--------|--------|----------------------|-------|
| Claude.ai | ✅ Verified | `/mcp` (full catalog) | Web and desktop. Streamable HTTP SSE. |
| Claude Code | ✅ Verified | `/mcp` (full catalog) | Terminal — see token workaround below. |
| ChatGPT | ✅ Verified (beta) | `/mcp` (full catalog) | Settings → Apps → Connectors → Advanced → New App. Apps SDK submission should target `/mcp/semantic`. |
| Perplexity | ⚠️ Use `/mcp/semantic` | **`/mcp/semantic`** | Transport: **Streamable HTTP** (not SSE). Auth: OAuth 2.0. Perplexity rejected the full tool catalog (see GH #277 / #280). |
| Cursor / VS Code | ✅ Verified | `/mcp` (full catalog) | Settings → MCP → Add. OAuth flow. |
| Manus AI | ✅ Verified | `/mcp` (full catalog) | Import by JSON: `{"url": "https://nucleoia.vitormr.dev/mcp"}` |
| xAI / Grok | 🟡 Custom MCP | `/mcp/semantic` | BYO remote MCP via API; catalog submission not yet documented publicly. |
| OpenAI Apps SDK review | 🟡 For submission | `/mcp/semantic` | Apps SDK review expects bounded tools + review-account; use semantic surface. |
| Anthropic Connectors Directory review | 🟡 For submission | `/mcp/semantic` | Directory pre-submission checklist favors short bounded tool catalogs. |

## Setup by Client

### Claude.ai (Web / Desktop)

1. Open Claude.ai → Settings → Integrations → MCP
2. Click "Add MCP Server"
3. Paste URL: `https://nucleoia.vitormr.dev/mcp`
4. A browser window opens — log in with your Núcleo account
5. Approve the OAuth consent
6. Done — ask Claude anything about the project

### Claude Code (Terminal)

Claude Code doesn't auto-initiate OAuth. Workaround:

1. Open the platform in your browser and log in
2. Open DevTools → Application → Local Storage → find `sb-ldrfrvwhxsmgaabwmaik-auth-token`
3. Copy the `access_token` value
4. In Claude Code config (`.claude/settings.json` or `--mcp-config`):

```json
{
  "mcpServers": {
    "nucleo-ia": {
      "type": "url",
      "url": "https://nucleoia.vitormr.dev/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_TOKEN_HERE"
      }
    }
  }
}
```

Manual bearer tokens copied into Claude Code expire in 1 hour. Prefer the OAuth connector flow when available; if using this manual workaround, refresh by repeating step 2-3.

### Cursor / VS Code

1. Open Settings → MCP Servers → Add
2. URL: `https://nucleoia.vitormr.dev/mcp`
3. Authentication: OAuth (automatic flow)
4. Save and test

### ChatGPT (Beta)

1. Go to chatgpt.com → Settings → Apps → Connectors → Advanced
2. Click "New App"
3. Name: `Nucleo-IA`
4. MCP Server URL: `https://nucleoia.vitormr.dev/mcp`
5. Authentication: OAuth
6. Check "I understand and want to continue"
7. Click Create

> Note: ChatGPT MCP support is in beta. If you see "Internal Server Error", this is a known ChatGPT-side issue. The server is compatible — it will work once their beta stabilizes.

## Representative Tools

The live source of truth is the MCP `tools/list` response (or the `/health` endpoint for a per-surface count). The examples below cover the most common member and operator workflows on the raw `/mcp` registry (342 tools); prefer the 52 intent-level `/semantic` tools where your client supports them. Never pin the exact number, query it live.

For the **complete machine-generated contract matrix** (tool → domain → RPC dependencies → tables → canV4 gate → external fetches → service_role usage), see:

- [`docs/reference/MCP_TOOL_MATRIX.md`](reference/MCP_TOOL_MATRIX.md) — human-readable markdown
- [`docs/reference/mcp-tool-matrix.json`](reference/mcp-tool-matrix.json) — structured JSON (consumable by audit tooling)

Re-generate with:

```bash
node scripts/audit-mcp-tool-matrix.mjs --runtime
# Cross-checks index.ts static parser vs live tools/list; flags drift.
```

### Read Tool Examples

| Tool | Description |
|------|-------------|
| `get_my_profile` | Your profile, role, tribe, and status |
| `get_my_board_status` | Your tribe's board cards grouped by status |
| `get_my_tribe_attendance` | Attendance records for your tribe |
| `get_my_tribe_members` | Members of your tribe with roles |
| `get_upcoming_events` | Next events with dates, times, and links |
| `get_my_xp_and_ranking` | Your XP breakdown and leaderboard position |
| `get_meeting_notes` | Meeting minutes from your tribe |
| `get_my_notifications` | Your unread and recent notifications |
| `search_board_cards` | Search cards across boards you have access to |
| `get_hub_announcements` | Platform-wide announcements |
| `get_my_attendance_history` | Your personal attendance history |
| `list_tribe_webinars` | Webinars for your tribe or chapter |
| `get_comms_pending_webinars` | Webinars needing communication action |
| `get_my_certificates` | Your certifications, badges, and trails |
| `search_hub_resources` | Search the resource library (247+ items) |
| `get_adoption_metrics` | MCP adoption metrics (admin/GP only) |
| `get_chapter_kpis` | KPIs for a chapter (liaisons and admins) |
| `get_tribe_dashboard` | Full tribe dashboard: members, cards, attendance, XP |
| `get_attendance_ranking` | Attendance ranking — members sorted by rate |
| `get_portfolio_overview` | Executive portfolio overview (admin/GP only) |
| `get_operational_alerts` | Operational alerts — inactivity, overdue, drift (admin/GP) |
| `get_cycle_report` | Full cycle report — members, tribes, KPIs (admin/GP) |
| `get_annual_kpis` | Annual KPIs — targets vs actuals (admin/sponsor) |

### Write Tool Examples

| Tool | Description |
|------|-------------|
| `create_board_card` | Create a new card on your tribe's board |
| `update_card_status` | Move a card to a different column |
| `create_meeting_notes` | Create meeting minutes |
| `register_attendance` | Register attendance for a tribe meeting |
| `send_notification_to_tribe` | Send a notification to all tribe members |
| `create_tribe_event` | Create a new tribe meeting or event |
| `register_showcase` | Register a showcase presentation |
| `submit_chapter_need` | Submit a chapter need request |
| `drop_event_instance` | Cancel a specific event occurrence |
| `update_event_instance` | Edit a specific event (date, time, notes) |
| `mark_member_excused` | Mark a member as excused (justified absence) |
| `manage_partner` | Manage partnership records |
| `bulk_mark_excused` | Mark member excused for a date range |

## Security Model

- **OAuth 2.1** with PKCE — industry standard
- **Row Level Security (RLS)** enforced on every query — you only see data your role permits
- **No personal data exposed** — emails, phones are excluded from tool responses
- **Write guards** — only tribe leaders, GP, and deputy can use write tools
- **Access tokens expire** in 1 hour; OAuth clients refresh directly against Supabase Auth's native OAuth 2.1 token endpoint on a client-scoped session (#1210) — independent of the member's browser session, so neither invalidates the other.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Unauthorized" | Token expired or refresh failed — reconnect the OAuth connector. If this happens in under 24h, check refresh-token metadata/logs; it is not expected steady-state behavior. |
| "Permission denied" | Your role doesn't have access to that tool |
| Empty response | You may not have data in that category yet |
| ChatGPT "Internal Server Error" | Known ChatGPT beta issue — try again later |
| OAuth window doesn't open | Check browser popup blocker settings |
| HTTP `403 Error 1010 browser_signature_banned` on `/mcp` or `/.well-known/oauth-*` | Cloudflare BIC block. See [`docs/infra/CLOUDFLARE_MCP_RULES.md`](infra/CLOUDFLARE_MCP_RULES.md) — WAF skip rule + rate limit applied for programmatic clients (Python-urllib, etc.). |

## Architecture

```
Your AI Client → Workers Proxy → Supabase Edge Function (nucleo-mcp)
                  ↓                        ↓
         OAuth Discovery          RLS-enforced queries
         (.well-known/)           (your JWT → your data)
```

The Workers proxy at `nucleoia.vitormr.dev` routes:
- `/mcp` → Supabase Edge Function `nucleo-mcp` (`/nucleo-mcp/mcp`)
- `/mcp/semantic` → `nucleo-mcp` `/nucleo-mcp/semantic` (semantic gateway)
- `/mcp/actions` → `nucleo-mcp` `/nucleo-mcp/actions` (overflow surface)
- `/.well-known/oauth-authorization-server` → OAuth discovery JSON

This ensures OAuth discovery is at the domain root (required by some clients like ChatGPT).

## Source Code

- Platform: [github.com/VitorMRodovalho/ai-pm-research-hub](https://github.com/VitorMRodovalho/ai-pm-research-hub)
- Edge Function: `supabase/functions/nucleo-mcp/`
- This guide: `docs/MCP_SETUP_GUIDE.md`
