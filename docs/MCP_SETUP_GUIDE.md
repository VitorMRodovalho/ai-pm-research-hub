# MCP Setup Guide — Núcleo IA & GP Research Hub

## What is MCP?

MCP (Model Context Protocol) is an open protocol that allows AI assistants to interact with external services. The Núcleo server exposes 52 tools (45 read + 7 write) that let you query and manage project data directly from your AI assistant using natural language. A dynamic knowledge layer adapts guidance to each member's role and permissions.

## Universal URL

All clients use the same URL:

```
https://nucleoia.vitormr.dev/mcp
```

Authentication: OAuth 2.1 — you'll be redirected to log in with the same account you use on the platform (Google, LinkedIn, or Microsoft).

## Compatibility

| Client | Status | Notes |
|--------|--------|-------|
| Claude.ai | ✅ Verified (52 tools) | Web and desktop app. Streamable HTTP SSE. |
| Claude Code | ✅ Verified | Terminal — see token workaround below |
| ChatGPT | ✅ Verified (beta) | Settings → Apps → Connectors → Advanced → New App |
| Perplexity | ✅ Verified | MCP connector in settings. |
| Cursor / VS Code | ✅ Verified | Settings → MCP → Add. OAuth flow. |
| Manus AI | ✅ Verified | Import by JSON: `{"url": "https://nucleoia.vitormr.dev/mcp"}` |

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

Token expires in 1 hour. Refresh by repeating step 2-3.

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

## Available Tools (29 total)

### Read Tools (23 — all members)

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

### Write Tools (6 — tribe leaders, GP, deputy only)

| Tool | Description |
|------|-------------|
| `create_board_card` | Create a new card on your tribe's board |
| `update_card_status` | Move a card to a different column |
| `create_meeting_notes` | Create meeting minutes |
| `register_attendance` | Register attendance for a tribe meeting |
| `send_notification_to_tribe` | Send a notification to all tribe members |
| `create_tribe_event` | Create a new tribe meeting or event |

## Security Model

- **OAuth 2.1** with PKCE — industry standard
- **Row Level Security (RLS)** enforced on every query — you only see data your role permits
- **No personal data exposed** — emails, phones are excluded from tool responses
- **Write guards** — only tribe leaders, GP, and deputy can use write tools
- **Tokens expire** in 1 hour — no persistent access

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Unauthorized" | Token expired — log in again |
| "Permission denied" | Your role doesn't have access to that tool |
| Empty response | You may not have data in that category yet |
| ChatGPT "Internal Server Error" | Known ChatGPT beta issue — try again later |
| OAuth window doesn't open | Check browser popup blocker settings |

## Architecture

```
Your AI Client → Workers Proxy → Supabase Edge Function (nucleo-mcp)
                  ↓                        ↓
         OAuth Discovery          RLS-enforced queries
         (.well-known/)           (your JWT → your data)
```

The Workers proxy at `nucleoia.vitormr.dev` routes:
- `/mcp` → Supabase Edge Function `nucleo-mcp`
- `/.well-known/oauth-authorization-server` → OAuth discovery JSON

This ensures OAuth discovery is at the domain root (required by some clients like ChatGPT).

## Source Code

- Platform: [github.com/VitorMRodovalho/ai-pm-research-hub](https://github.com/VitorMRodovalho/ai-pm-research-hub)
- Edge Function: `supabase/functions/nucleo-mcp/`
- This guide: `docs/MCP_SETUP_GUIDE.md`
