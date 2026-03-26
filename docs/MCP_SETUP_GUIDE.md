# MCP Setup Guide — Núcleo IA & GP Research Hub

## What is MCP?

MCP (Model Context Protocol) is an open protocol that allows AI assistants to interact with external services. The Núcleo server exposes 15 tools that let you query and manage project data directly from your AI assistant using natural language.

## Universal URL

All clients use the same URL:

```
https://platform.ai-pm-research-hub.workers.dev/mcp
```

Authentication: OAuth 2.1 — you'll be redirected to log in with the same account you use on the platform (Google, LinkedIn, or Microsoft).

## Compatibility

| Client | Status | Notes |
|--------|--------|-------|
| Claude.ai | ✅ Stable | Web and desktop app |
| Claude Code | ✅ Stable | Terminal — see token workaround below |
| Cursor | ✅ Stable | Settings → MCP → Add |
| VS Code | ✅ Stable | MCP extension required |
| ChatGPT | ⏳ Beta | Settings → Apps → Connectors → Advanced → New App |

## Setup by Client

### Claude.ai (Web / Desktop)

1. Open Claude.ai → Settings → Integrations → MCP
2. Click "Add MCP Server"
3. Paste URL: `https://platform.ai-pm-research-hub.workers.dev/mcp`
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
      "url": "https://platform.ai-pm-research-hub.workers.dev/mcp",
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
2. URL: `https://platform.ai-pm-research-hub.workers.dev/mcp`
3. Authentication: OAuth (automatic flow)
4. Save and test

### ChatGPT (Beta)

1. Go to chatgpt.com → Settings → Apps → Connectors → Advanced
2. Click "New App"
3. Name: `Nucleo-IA`
4. MCP Server URL: `https://platform.ai-pm-research-hub.workers.dev/mcp`
5. Authentication: OAuth
6. Check "I understand and want to continue"
7. Click Create

> Note: ChatGPT MCP support is in beta. If you see "Internal Server Error", this is a known ChatGPT-side issue. The server is compatible — it will work once their beta stabilizes.

## Available Tools

### Read Tools (all members)

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

### Write Tools (tribe leaders, GP, deputy only)

| Tool | Description |
|------|-------------|
| `create_board_card` | Create a new card on your tribe's board |
| `update_card_status` | Move a card to a different column |
| `create_meeting_notes` | Create meeting minutes |
| `register_attendance` | Register attendance for a tribe meeting |
| `send_notification_to_tribe` | Send a notification to all tribe members |

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

The Workers proxy at `platform.ai-pm-research-hub.workers.dev` routes:
- `/mcp` → Supabase Edge Function `nucleo-mcp`
- `/.well-known/oauth-authorization-server` → OAuth discovery JSON

This ensures OAuth discovery is at the domain root (required by some clients like ChatGPT).

## Source Code

- Platform: [github.com/VitorMRodovalho/ai-pm-research-hub](https://github.com/VitorMRodovalho/ai-pm-research-hub)
- Edge Function: `supabase/functions/nucleo-mcp/`
- This guide: `docs/MCP_SETUP_GUIDE.md`
