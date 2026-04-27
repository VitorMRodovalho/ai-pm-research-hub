# ADR-0046: Action item lifecycle RPCs (#84 Onda 2 partial)

- Status: **Accepted** (2026-04-27 — autonomous-shippable; builds on
  ADR-0045 schema; #84 Onda 2 partial scope: 3 of 10 planned RPCs)
- Data: 2026-04-27 (p72)
- Autor: Claude (proposal autônomo)
- Escopo:
  - 3 RPCs leveraging ADR-0045 schema:
    - `create_action_item(...)` — structured INSERT
    - `resolve_action_item(...)` — UPDATE with optional carry-forward
    - `list_meeting_action_items(...)` — SELECT with filters
  - 3 MCP tool wrappers (v2.26.0 → v2.27.0; 146 → 149 tools)
- Implementation:
  - Migration `20260514080000_adr_0046_action_item_lifecycle_rpcs.sql`
  - MCP EF v2.27.0 deployed
- Cross-references: ADR-0045 (#84 Onda 1 schema), GitHub #84 (issue spec),
  ADR-0042 (manage_event audience)

---

## Contexto

ADR-0045 shipped #84 Onda 1 schema:
- `meeting_action_items` gained 6 columns (board_item_id, checklist_item_id,
  kind, resolved_at, resolved_by, resolution_note)
- `board_item_event_links` table created

But the schema is empty without RPCs to populate/query it. ADR-0046 ships
3 core RPCs as Onda 2 partial — the action item lifecycle (CRUD-without-D,
since DELETE remains schema-only via cascade). The remaining 7 Onda 2 RPCs
(`get_meeting_preparation`, `get_agenda_smart`, `register_decision`,
`convert_action_to_card`, `update_card_during_meeting`, `meeting_close`,
`get_card_full_history`, `get_tribe_housekeeping`) defer to PM-discretionary
sprint; they have more design surface (e.g., agenda-smart heuristics,
meeting_close atomicity).

The 3 RPCs in this ADR are deliberately the simplest viable subset:
- INSERT (create_action_item)
- UPDATE (resolve_action_item with carry-forward)
- SELECT (list_meeting_action_items with filters)

---

## Decisão

### 1. `create_action_item`

```sql
create_action_item(
  p_event_id uuid,
  p_description text,
  p_assignee_id uuid DEFAULT NULL,
  p_due_date date DEFAULT NULL,
  p_board_item_id uuid DEFAULT NULL,
  p_checklist_item_id uuid DEFAULT NULL,
  p_kind text DEFAULT 'action'
) RETURNS jsonb
```

**Auth gate**: V4 `manage_event` (mirrors ADR-0045 RLS on
`board_item_event_links`).

**Behavior**:
- Validates event exists, kind in valid enum, description non-empty
- Looks up assignee_name (snapshot, even if member renamed later)
- INSERT into `meeting_action_items` with status='open' (or 'completed' if kind='decision' — decisions are immediately final)
- If `board_item_id` is provided, ALSO inserts into `board_item_event_links`
  with link_type derived from kind (decision → 'decision', action →
  'action_emerged', else → 'discussed'). ON CONFLICT DO NOTHING (idempotent).
- Returns `{success, action_item_id, event_id, kind, created_at}`

**Side-effect**: cross-references between cards and events emerge
automatically when action items link to cards. No separate "create link"
RPC needed for the common path.

### 2. `resolve_action_item`

```sql
resolve_action_item(
  p_action_item_id uuid,
  p_resolution_note text DEFAULT NULL,
  p_carry_to_event_id uuid DEFAULT NULL
) RETURNS jsonb
```

**Auth gate**: V4 `manage_event`.

**Behavior**:
- Pre-checks: action exists, not already resolved
- If `p_carry_to_event_id` provided:
  - Validates target event exists
  - INSERT new action item in target event with description suffixed
    `' (carried from prior meeting)'`, same assignee/due_date/links
  - UPDATE original: `carried_to_event_id` set
  - status='carried_forward'
- Else: status='completed'
- Always: `resolved_at = now()`, `resolved_by = caller`, optional
  `resolution_note`

**Returns**: `{success, action_item_id, resolved_at, carried_to_action_item_id}`

**Use case**: weekly status review where some open items get carried to
next meeting + others get marked done with explanation.

### 3. `list_meeting_action_items`

```sql
list_meeting_action_items(
  p_event_id uuid DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_assignee_id uuid DEFAULT NULL,
  p_kind text DEFAULT NULL,
  p_unresolved_only boolean DEFAULT false
) RETURNS jsonb
```

**Auth gate**: authenticated only — any member can see all action items.
Privacy is enforced by event RLS at frontend join time (member sees only
events they have access to).

**Behavior**:
- Returns `jsonb_agg` with enriched fields: event_title, event_date,
  board_item_title, assignee_name (snapshot), resolved_by_name (lookup)
- ORDER BY: unresolved first, then by due_date ASC NULLS LAST, then
  created_at DESC
- LIMIT 200

**Use cases**:
- "What action items are open assigned to me?" — `p_assignee_id = my_id, p_unresolved_only = true`
- "What got decided in event X?" — `p_event_id = X, p_kind = 'decision'`
- "All carried-forward items in this cycle" — `p_status = 'carried_forward'`
- Tribe leader retrospective: `p_event_id = last_meeting`

### MCP tool layer

3 new MCP tools wrapping these RPCs:
- `create_action_item` — manage_event gate
- `resolve_action_item` — manage_event gate
- `list_meeting_action_items` — authenticated only

MCP version: v2.26.0 → v2.27.0 (146 → 149 tools, 97R + 52W).

---

## Out of scope (deferred to subsequent Onda 2 work + Onda 3)

7 remaining Onda 2 RPCs:
- `get_meeting_preparation(event_id)` — prep pack
- `get_agenda_smart(event_id)` — replaces dumb generate_agenda_template
- `register_decision(event_id, ...)` — could be wrapped via create_action_item kind='decision'
- `convert_action_to_card(action_item_id, board_id, ...)` — atomic flow
- `update_card_during_meeting(card_id, changes, event_id)` — wraps update_board_item + creates board_item_event_links
- `meeting_close(event_id, summary)` — atomic close with multi-op transaction
- `get_card_full_history(card_id)` — timeline expansion via board_item_event_links
- `get_tribe_housekeeping(tribe_id)` — KPI contribution rollup

Onda 3 (UX + extractor) — full PM-design-needed:
- Trigger AFTER UPDATE on `events.minutes_text` for LLM-based action item extraction
- Frontend `CardDetail.tsx` "Histórico em reuniões" tab
- Frontend `MeetingMode` modal during live meetings

---

## Trade-offs aceitos

1. **`list_meeting_action_items` accessible to all authenticated**: privacy
   relies on event RLS at join time. If a member queries without filters,
   they see metadata for events they shouldn't access. Acceptable because:
   - The metadata exposed (event_title, action_description) is non-PII
   - Members can already see meeting notes; action items are a structured
     subset
   - True privacy enforcement should be added IF a future feature exposes
     PII via this RPC (currently none).

2. **Carry-forward duplicates the action item rather than re-uses**: each
   carry creates a NEW `meeting_action_items` row. Trade-off: trail
   completeness (each meeting's records are immutable) vs. row count
   inflation. Acceptable; queries can JOIN on `carried_to_event_id` to
   reconstruct chains.

3. **`board_item_event_links` auto-populated on INSERT**: when an action
   item links to a card, a link row appears automatically. This may create
   "duplicate" links if the same card is mentioned multiple times in
   different action items. Mitigated by UNIQUE(board_item_id, event_id,
   link_type) — only ONE link per (card, event, link_type) regardless of
   how many action items reference it.

4. **`register_decision` deferred**: a decision can be created via
   `create_action_item` with `kind='decision'`. Future `register_decision`
   could be a thin wrapper if the use case demands distinct API
   (e.g., decisions need different fields like vote counts, signatories).

---

## Cross-cutting precedent

### Schema-then-RPC pattern (continuation of ADR-0045)

ADR-0045 shipped schema; ADR-0046 ships the simplest viable RPCs against
it. Future Ondas (per #84) can layer on more sophisticated RPCs without
re-touching schema. This is the recommended pattern for any feature with
multiple Onda waves:
1. Onda 1 ADR — schema only (fast, low risk)
2. Onda 2-partial ADR — simplest viable RPCs (fast, baixo risco)
3. Onda 2-full ADR — substantive RPCs requiring more design
4. Onda 3 — UX + LLM/automation

Each Onda is autonomous-shippable in isolation.

### Side-effect cross-reference

`create_action_item` automatically populates `board_item_event_links` when
a card is linked. Pattern: when domain entities have implicit cross-refs,
ship them automatically rather than requiring explicit "create_link" RPCs.
Reduces frontend boilerplate + ensures consistency.

### MCP tool naming for write-side complement of read-side

Write tools `create_*` / `resolve_*` complement existing read tool
`list_*`. Reads existed first (legacy `get_meeting_notes`); writes ship
later as workflow becomes structured. Pattern for future #84/#88/#91 work:
ship reads first to surface data, then writes once data flow is clear.

---

## Phase B'' tally update

Pre-ADR-0046: 99/246 (~40.2%)
Post-ADR-0046: 99/246 (~40.2%) — UNCHANGED

(ADR-0046 introduces 3 NEW V4 RPCs — net-new code, not V3→V4 conversions.
Phase B'' tracks conversions, not new RPCs. New RPCs use V4 by default
per ADR-0011 cutover.)

---

## Status / Next Action

- [x] Migration `20260514080000_adr_0046_action_item_lifecycle_rpcs.sql`
- [x] MCP v2.27.0 deployed (149 tools, 97R + 52W)
- [x] Smoke test: HTTP 200 + serverInfo.version = 2.27.0
- [x] Schema invariants: 11/11 = 0
- [x] Tests preserved: 1415 / 1383 / 0 / 32
- [x] Astro build clean
- [ ] Comment on #84 with ADR-0046 status

---

## Forward backlog

- **#84 Onda 2 remaining (7 RPCs)**: PM-discretionary timing
- **#84 Onda 3 (UX + extractor)**: PM design session needed
- Frontend integration: `CardDetail.tsx` could show "Histórico em
  reuniões" tab querying `list_meeting_action_items` filtered by board_item_id
