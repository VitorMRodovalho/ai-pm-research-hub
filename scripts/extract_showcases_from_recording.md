# Showcase Extraction from Meeting Recordings

## Overview

Workflow for extracting showcase/protagonist presentations from general meeting recordings using AI, then registering them via MCP.

## Prerequisites

- Meeting recording (Google Meet, Teams, or Zoom)
- Access to Gemini 2.5 Pro (via Google AI Studio) or NotebookLM
- MCP connection to `nucleoia.vitormr.dev/mcp`

## Step 1: Upload Recording

Upload the meeting recording to **Google AI Studio** (Gemini 2.5 Pro) or **NotebookLM**.

For Google AI Studio: use the file upload feature in the prompt interface.

## Step 2: Extract Showcases

Use this prompt:

```
Analyze this meeting recording and extract all presentations/showcases where a member presented something to the group.

For each presentation found, output a JSON array with these fields:
- member_name: full name of the presenter (as spoken or shown on screen)
- showcase_type: one of: "case_study" (success story, 25 XP), "tool_review" (AI/PM tool demo, 20 XP), "prompt_week" (prompt engineering tip, 20 XP), "quick_insight" (short insight/tip, 15 XP), "awareness" (awareness/sensitization, 15 XP)
- title: brief title of what was presented
- duration_min: approximate duration in minutes
- notes: 1-2 sentence summary of the content

Rules:
- Only include actual presentations, not Q&A or general discussion
- If unsure about showcase_type, use "quick_insight"
- Use the presenter's full name as shown/spoken in the meeting
- Duration should be approximate (round to nearest 5 minutes)

Output ONLY valid JSON, no markdown wrapping.
```

## Step 3: Validate Output

Example output:
```json
[
  {
    "member_name": "Maria Silva",
    "showcase_type": "tool_review",
    "title": "Claude Code para gestao de projetos",
    "duration_min": 15,
    "notes": "Demonstracao de como usar Claude Code para automatizar tarefas de GP"
  },
  {
    "member_name": "Joao Santos",
    "showcase_type": "quick_insight",
    "title": "Prompts eficazes para analise de riscos",
    "duration_min": 5,
    "notes": "Compartilhou 3 templates de prompt para identificacao de riscos em projetos"
  }
]
```

**Validation checklist:**
- [ ] Member names match the platform member list (check via `search_members` MCP tool)
- [ ] `showcase_type` is one of the 5 valid types
- [ ] No duplicates (same member + same event)
- [ ] Max 2 showcases per member per event (platform limit)

## Step 4: Register via MCP

For each item in the JSON output, call the MCP tool `register_showcase`:

```
Register showcase for [member_name] at event [event_id]:
- type: [showcase_type]
- title: [title]
- duration: [duration_min] minutes
- notes: [notes]
```

Or via natural language: "Register a [showcase_type] showcase for [member_name] at event [event_id], titled '[title]', duration [duration_min] minutes."

## XP Values by Type

| Type | XP | When to use |
|------|-----|-------------|
| case_study | 25 | Full case study or success story presentation |
| tool_review | 20 | Demo of an AI/PM tool |
| prompt_week | 20 | Prompt engineering technique or tip |
| quick_insight | 15 | Short insight, lesson learned, or tip |
| awareness | 15 | Awareness/sensitization about a topic |

## Notes

- The `event_id` must be obtained from the platform (use `get_upcoming_events` or `get_event_detail`)
- The member must have been marked as present at the event for the showcase to be registered
- Each showcase awards XP automatically via the `register_event_showcase` RPC
