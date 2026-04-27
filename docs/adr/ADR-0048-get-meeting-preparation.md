# ADR-0048: `get_meeting_preparation` RPC (#84 Onda 2 cont., 7/10)

- Status: **Accepted** (2026-04-27 — autonomous-shippable continuation)
- Data: 2026-04-27 (p72)
- Autor: Claude (proposal autônomo)
- Escopo:
  - 1 RPC: `get_meeting_preparation(event_id)` — read-only prep pack
  - 1 MCP tool wrapper (v2.28.0 → v2.29.0; 152 → 153 tools)
- Implementation:
  - Migration `20260514100000_adr_0048_get_meeting_preparation.sql`
  - MCP EF v2.29.0 deployed
- Cross-references: ADR-0045 (#84 Onda 1 schema), ADR-0046+0047 (#84 Onda 2
  RPCs prior), GitHub #84 (issue spec)

---

## Contexto

#84 Onda 2 progress is now 7/10 with this ADR. The RPC `get_meeting_preparation`
is the central pre-meeting prep pack — answers "what should I review before
this meeting?". Designed deliberately as v1 (no KPI/showcase heuristics)
to ship simply; v2 can layer on those when threshold logic is designed.

---

## Decisão

### `get_meeting_preparation(p_event_id)` — read-only prep pack

Returns:
```json
{
  "event": { id, title, date, type, duration_minutes, meeting_link, agenda_text, agenda_url },
  "initiative": { id, name, kind, legacy_tribe_id } | null,
  "expected_attendees": [
    { member_id, name, operational_role, engagement_kind, engagement_role, photo_url }
  ],
  "pending_action_items": [
    { id, event_id, event_title, event_date, description, kind, assignee_name, due_date, days_open }
  ],
  "open_cards": [
    { id, title, status, curation_status, assignee_name, due_date, forecast_date,
      baseline_date, days_since_update, tags, is_at_risk }
  ],
  "recent_meetings": [
    { id, title, date, type, has_minutes, attendance_count, open_actions_count }
  ],
  "generated_at": timestamp
}
```

**Auth gate**: authenticated only.

### Sub-queries explained

1. **`expected_attendees`**: members with `is_active=true` + authoritative
   `auth_engagements` row matching `event.initiative_id`. Engagement-derived
   attendance prediction. ORDER BY name. NULL initiative → empty array.

2. **`pending_action_items`**: open action items (resolved_at IS NULL) from
   prior meetings of the same initiative (event.date < this.date),
   90-day window. Includes carry-forward candidates. Joined with event for
   context (title, date). Includes `days_open` derived field.

3. **`open_cards`**: cards on the initiative's primary board (initiative_id
   match), not archived. Includes derived `is_at_risk` flag:
   - `forecast_date > baseline_date + 7 days` (forecast slip), OR
   - `updated_at < now() - 14 days AND status NOT IN ('done', 'archived')` (stale)
   ORDER BY non-done first, then due_date, then updated_at DESC. LIMIT 50.

4. **`recent_meetings`**: last 5 meetings of the same initiative within
   60 days, with metadata snapshots (`has_minutes`, `attendance_count`,
   `open_actions_count`). Helps the meeting opener review trend.

### `is_at_risk` heuristic v1

Two simple rules:
1. **Forecast slip**: `forecast_date > baseline_date + 7 days` (card has
   slipped > 7 days from baseline)
2. **Staleness**: `updated_at < now() - 14 days` AND status not done/archived
   (no progress in 2 weeks)

Both rules are derived in-query — no separate column. v2 future iteration
can add: KPI threshold breaches, attendance-drop signals, dependent-card
chain delays, etc. Per #84, full agenda-smart RPC will subsume these.

---

## Out of scope (v2 / future)

- **KPI status** in result envelope (depends on `tribe_kpi_contributions`
  having data + threshold logic for RED/YELLOW/GREEN)
- **Showcase candidates** (members with recent unmessaged deliverables —
  needs `event_showcases` cross-ref to `tribe_deliverables.created_at`)
- **Cards-of-attendees** filter (subset of open_cards filtered by
  attendees as assignees) — would benefit prep without full open_cards list
- **Decision suggestion** (action items aging > N days suggesting decision
  point) — heuristic for `get_agenda_smart`

These are best done in `get_agenda_smart` (Onda 2 RPC #8), not here.

---

## Cumulative #84 Onda 2 progress

| RPC | Status | ADR |
|---|---|---|
| `create_action_item` | ✅ p72 | ADR-0046 |
| `resolve_action_item` | ✅ p72 | ADR-0046 |
| `list_meeting_action_items` | ✅ p72 | ADR-0046 |
| `get_card_full_history` | ✅ p72 | ADR-0047 |
| `convert_action_to_card` | ✅ p72 | ADR-0047 |
| `register_decision` | ✅ p72 | ADR-0047 |
| **`get_meeting_preparation`** | ✅ **p72** | **ADR-0048** |
| `get_agenda_smart` | ⏳ remaining | — |
| `update_card_during_meeting` | ⏳ remaining | — |
| `meeting_close` | ⏳ remaining | — |
| `get_tribe_housekeeping` | ⏳ remaining | — |

**Onda 2 progress: 7/11 (~64%)**.

---

## Trade-offs aceitos

1. **`expected_attendees` based on engagement**: assumes any member with
   active engagement to the initiative will attend. Real attendance has
   variance. Trade-off: prep is "expected", not "confirmed". Frontend
   can layer on "confirmed via RSVP" if/when added.

2. **`open_cards` LIMIT 50**: tribes with >50 active cards would have
   truncated view. Reasonable default; future v2 can paginate or filter
   by status priority.

3. **`recent_meetings` window 60 days**: balances trend visibility with
   query speed. Very long-running tribes lose deep history view.

4. **`is_at_risk` heuristic in-query**: tightly couples logic to this
   specific RPC. If the same heuristic is needed elsewhere (future
   `get_agenda_smart`, dashboard widgets), should be extracted to a
   helper view or function. v1 ship-fast wins; refactor when 2nd caller
   appears.

5. **Excludes `event_showcases` data from prep**: showcases are
   retrospective (what happened in past meetings). `get_meeting_preparation`
   is forward-looking. Could optionally include "showcase candidates"
   (members with recent deliverables) but that's an `get_agenda_smart`
   concern.

---

## Cross-cutting precedent

### Read-only prep pack pattern

ADR-0048 establishes the prep pack pattern for forward-looking RPCs:
- Anchor entity (here: event)
- Sub-arrays for related data (attendees, prior actions, open cards, recent history)
- Derived flags (is_at_risk) computed in-query for view-time efficiency
- LIMIT defaults for safety
- COALESCE jsonb_agg with '[]' fallback

Reusable for: `get_card_preparation` (review pack pre-status-change),
`get_member_preparation` (review pack pre-onboarding session), etc.

### Engagement-derived attendance

`expected_attendees` filters via `auth_engagements.initiative_id` match.
Pattern: when "who's involved with X?" is the question, query engagements
not legacy designations. This is V4-native (no `members.tribe_id`
reference), future-proof for ADR-0015 Phase 5.

---

## Status / Next Action

- [x] Migration `20260514100000_adr_0048_get_meeting_preparation.sql`
- [x] MCP v2.29.0 deployed (153 tools, 99R + 54W)
- [x] Smoke test: HTTP 200 + serverInfo.version = 2.29.0
- [x] Schema invariants: 11/11 = 0
- [x] Tests preserved: 1415 / 1383 / 0 / 32

---

## Forward backlog

- **#84 Onda 2 remaining (4 RPCs)**:
  - `get_agenda_smart(event_id)` — next logical (subsumes prep + adds carry-forward + suggests decisions)
  - `update_card_during_meeting(card_id, changes, event_id)` — wraps update + link
  - `meeting_close(event_id, summary)` — atomic multi-op close
  - `get_tribe_housekeeping(tribe_id)` — KPI rollup (data dep)
- **#84 Onda 3** — UX + LLM extractor (PM design)
- **Frontend**: integrate `get_meeting_preparation` into a "next meeting"
  dashboard widget for tribe leaders
