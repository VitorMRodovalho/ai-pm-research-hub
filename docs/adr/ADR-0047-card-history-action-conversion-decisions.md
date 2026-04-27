# ADR-0047: Card history + action conversion + decisions (#84 Onda 2 cont.)

- Status: **Accepted** (2026-04-27 — autonomous-shippable continuation;
  builds on ADR-0045 schema + ADR-0046 lifecycle)
- Data: 2026-04-27 (p72)
- Autor: Claude (proposal autônomo)
- Escopo:
  - 3 more #84 Onda 2 RPCs (6/10 cumulative):
    - `get_card_full_history(card_id)` — 360° timeline join (read-only)
    - `convert_action_to_card(action_item_id, board_id, ...)` — atomic flow
    - `register_decision(event_id, title, description, related_card_ids[])`
  - 3 MCP tool wrappers (v2.27.0 → v2.28.0; 149 → 152 tools)
- Implementation:
  - Migration `20260514090000_adr_0047_card_history_action_conversion_decisions.sql`
  - MCP EF v2.28.0 deployed
- Cross-references: ADR-0045 (#84 Onda 1 schema), ADR-0046 (#84 Onda 2 partial),
  GitHub #84 (issue spec)

---

## Decisão

### 1. `get_card_full_history(p_card_id)` — read-only 360° join

Returns:
```json
{
  "card": { id, title, description, status, curation_status, board_id, assignee_id, created_at, updated_at },
  "lifecycle_events": [...],          // board_lifecycle_events
  "meeting_links": [...],             // board_item_event_links + event metadata
  "action_items": [...],              // meeting_action_items linked to this card
  "showcases": [...],                 // event_showcases linked to this card
  "curation_reviews": [...],          // curation_review_log entries
  "generated_at": timestamp
}
```

**Auth gate**: authenticated only (privacy enforced by event RLS at frontend).

**Closes #84 GAP 4** — central use case: "Quais reuniões discutiram este
card? Quais decisions impactaram? Quem apresentou em showcase?"

### 2. `convert_action_to_card(action_item_id, board_id, title?, description?, status?, due_date?)`

Atomic flow:
1. Pre-checks: action exists, not already linked to a card; board exists + active
2. Defaults: title = first 80 chars of action description; description = action.description + meeting reference; due_date = action.due_date
3. INSERT new `board_items` row (position = max+1)
4. INSERT `board_lifecycle_events` ('created' with reason)
5. UPDATE `meeting_action_items.board_item_id` to point to new card
6. INSERT `board_item_event_links` (link_type='action_emerged') ON CONFLICT DO NOTHING

**Auth gate**: V4 `write_board` (creating cards is board mutation auth).

**Returns**: `{success, action_item_id, new_board_item_id, board_id, position, created_at}`

**Use case**: in a meeting, an action emerges that warrants tracking as a
card on a specific board ("convert this action to a tribe deliverable
card"). Single MCP call replaces 4-5 manual ops.

### 3. `register_decision(event_id, title, description?, related_card_ids[]?)`

Specialized form of `create_action_item` with kind='decision':
1. INSERT `meeting_action_items` with kind='decision', status='completed'
2. UPDATE the same row with `resolved_at = now()`, `resolved_by = caller`,
   `resolution_note = 'Decision registered'`
3. FOREACH `related_card_ids[]`: INSERT `board_item_event_links` with
   link_type='decision' (multi-card fanout)

**Auth gate**: V4 `manage_event`.

**Returns**: `{success, decision_id, event_id, title, related_cards_linked, created_at}`

**Distinct from `create_action_item(kind='decision')`**: this RPC is
decision-first (title required as first-class field) and supports
**multi-card fanout** in a single call. Common use case: "Aprovamos a
publicação dos artigos X, Y, Z em Q3" — one decision, three cards linked.

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
| `get_meeting_preparation` | ⏳ remaining | — |
| `get_agenda_smart` | ⏳ remaining | — |
| `update_card_during_meeting` | ⏳ remaining | — |
| `meeting_close` | ⏳ remaining | — |
| `get_tribe_housekeeping` | ⏳ remaining | — |

**Onda 2 progress: 6/10 (~60%)**.

5 remaining (note: original issue said 10 but `get_tribe_housekeeping` is
arguably Onda 1.5 since it depends on `tribe_kpi_contributions` having
data) — PM-discretionary continuation.

---

## Trade-offs aceitos

1. **`convert_action_to_card` blocks if action already linked**: refuses
   to overwrite existing `board_item_id`. Trade-off: prevents accidental
   double-create. PM can manually update if needed via direct SQL.

2. **`register_decision` defaults `resolution_note` to 'Decision registered'**:
   thin/generic. If audit trail clarity is needed, future v2 can require
   non-empty resolution context.

3. **`get_card_full_history` does NOT enforce board_item visibility**:
   any authenticated member can call with any card_id. Privacy relies on
   the join paths (event RLS, showcase RLS, etc.) at frontend join time.
   **Important**: when frontend renders this output, must respect RLS on
   downstream tables OR augment this RPC with explicit visibility checks
   if PII concerns emerge.

4. **No `update_card_during_meeting` in this batch**: would wrap
   `update_board_item` + insert `board_item_event_links` of link_type
   'status_changed'. Adds complexity (which fields trigger which
   link_type?) — defer to next batch.

5. **`get_meeting_preparation` + `get_agenda_smart` deferred**: highest
   value RPCs but require carry-forward query design + KPI
   threshold logic + cards-at-risk heuristic. Worth a focused ADR session
   when prioritized.

---

## Cross-cutting precedent

### Multi-aggregate read RPCs

`get_card_full_history` is the first RPC that aggregates 5+ tables into a
single jsonb response. Pattern for future timeline/360° views:
1. Anchor on the entity being viewed (here: board_item)
2. For each related table, COALESCE jsonb_agg with '[]'::jsonb default
3. Order each subarray by event/created timestamp DESC
4. Return single envelope object with metadata (`generated_at`, optional
   filters)
5. Author/assignee/curator name lookups via LEFT JOIN to avoid breaking
   on referential gaps

Reusable for future RPCs: `get_member_full_profile`, `get_event_full_details`,
`get_initiative_full_state`, etc.

### Atomic conversion RPCs

`convert_action_to_card` shows the pattern for atomic multi-table mutations:
1. Pre-check all preconditions (existence, state)
2. Compute derived values (position, defaults)
3. INSERT primary entity
4. INSERT side-effects (lifecycle events, links)
5. UPDATE source entity (forward reference)
6. Return references to enable frontend optimistic updates

Pattern reusable for: `convert_card_to_artifact`, `promote_application_to_member`, etc.

### Multi-target fanout pattern

`register_decision` with `related_card_ids[]` shows array-fanout pattern.
Each FOREACH iteration is independent (ON CONFLICT DO NOTHING ensures
idempotency). Pattern reusable for: `notify_multiple_recipients`,
`tag_cards_in_batch`, etc.

---

## Status / Next Action

- [x] Migration `20260514090000_adr_0047_card_history_action_conversion_decisions.sql`
- [x] MCP v2.28.0 deployed (152 tools, 98R + 54W)
- [x] Smoke test: HTTP 200 + serverInfo.version = 2.28.0
- [x] Schema invariants: 11/11 = 0
- [x] Tests preserved: 1415 / 1383 / 0 / 32
- [x] Astro build clean
- [ ] Comment on #84 with ADR-0047 status

---

## Forward backlog

- **#84 Onda 2 remaining (4-5 RPCs)**:
  - `get_meeting_preparation(event_id)` — high-value prep pack
  - `get_agenda_smart(event_id)` — replaces dumb generate_agenda_template
  - `update_card_during_meeting(card_id, changes, event_id)` — wraps update + link
  - `meeting_close(event_id, summary)` — atomic multi-op close
  - `get_tribe_housekeeping(tribe_id)` — KPI rollup (depends on `tribe_kpi_contributions` data)
- **#84 Onda 3** — UX + LLM extractor (PM design session)
- **Frontend integration**: `CardDetail.tsx` "Histórico em reuniões" tab
  can now call `get_card_full_history` for full 360° view
