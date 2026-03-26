# MCP Server Setup Guide — Núcleo IA & GP

Connect your AI assistant (Claude, Cursor, VS Code) to the Hub platform.
10 read-only tools for tribe leaders: profile, board, attendance, XP, meetings, notifications, search.

## Quick Setup

### Claude Desktop / Claude Code

Add to your MCP config (`~/.claude.json` or Claude Desktop settings):

```json
{
  "mcpServers": {
    "nucleo-ia": {
      "url": "https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp"
    }
  }
}
```

### Cursor

Settings → MCP → Add Server → paste the URL:
```
https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp
```

### VS Code (MCP Extension)

MCP extension → Add server → paste the URL above.

## First Connection

1. Your AI assistant will open a browser window
2. Login with Google / LinkedIn / Microsoft
3. Approve the consent screen ("Autorizar acesso")
4. Done — the assistant now has read-only access to your Hub data

## Available Tools

| Tool | Description |
|------|-------------|
| `get_my_profile` | Your member profile, role, tribe, certifications |
| `get_my_board_status` | Tribe board cards grouped by status |
| `get_my_tribe_attendance` | Attendance grid for your tribe |
| `get_my_tribe_members` | Active members in your tribe |
| `get_upcoming_events` | Events in the next 7 days |
| `get_my_xp_and_ranking` | XP breakdown and leaderboard position |
| `get_meeting_notes` | Recent meeting minutes for your tribe |
| `get_my_notifications` | Your unread notifications |
| `search_board_cards` | Full-text search across board cards |
| `get_hub_announcements` | Active Hub announcements |

## Security

- **Read-only**: No tool can modify data
- **RLS enforced**: You only see data your role allows
- **OAuth 2.1**: Standard authorization flow, revocable anytime
- **No PII exposed**: Email and phone are never returned

## Troubleshooting

- **"Not authenticated"**: Re-authorize via browser
- **Empty results**: You may not have a tribe assigned yet
- **Connection refused**: Check if your firewall blocks Supabase

## MCP Endpoint

```
https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp
```

Health check:
```
https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/health
```
