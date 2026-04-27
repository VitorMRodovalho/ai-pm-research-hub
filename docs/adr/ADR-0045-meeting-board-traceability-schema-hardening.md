# ADR-0045: Meeting ↔ Board traceability schema hardening (#84 Onda 1)

- Status: **Accepted** (2026-04-27 — autonomous-shippable per #84 Onda 1
  classification: 🟢 baixo risco, aditivo)
- Data: 2026-04-27 (p72)
- Autor: Claude (proposal autônomo) + #84 issue specification
- Escopo:
  - Section A — Add 6 columns to `meeting_action_items` (FK to board_items
    + checklist_items, kind classifier, resolution metadata)
  - Section B — Add 3 columns to `event_showcases` (FK to board_items +
    tribe_deliverables, xp_awarded snapshot)
  - Section C — New table `tribe_kpi_contributions` (initiative ↔ KPI
    target mapping, GAP 7)
  - Section D — New table `board_item_event_links` (bidirectional
    cross-reference for card timeline 360°, GAP 4)
- Implementation:
  - Migration `20260514070000_adr_0045_meeting_board_traceability_schema.sql`
- Cross-references: GitHub #84 (specification), ADR-0012 (organization_id
  invariant), ADR-0015 (initiative-native), ADR-0042 (manage_event audience)

---

## Contexto

GitHub #84 ("Meeting↔Board traceability gap") identifies 7 structural gaps
that prevent the platform from delivering on the GP's vision:

> "Ao fim de uma reunião de tribo/iniciativa, o fluxo ideal deveria
> atualizar cards planejados (avançar, reprogramar, comentar) com
> rastreabilidade (ata ↔ card ↔ activity). Action items deveriam linkar
> a cards. Quando líder/pesquisador/GP pesquisar atividade ou artefato,
> ter trail completo (por que sucesso/não), o que alimenta lições
> aprendidas."

The platform has the primitives — `events`, `meeting_action_items`,
`board_items`, `event_showcases`, `annual_kpi_targets` — but lacks the FKs
that connect them semantically. `meeting_action_items` has 0 prod rows
despite existing for months because:
- UX has no structured component (only string-based markdown)
- No trigger extracts items from minutes_text into the table
- MCP `create_meeting_notes` passes action_items as a comma-separated string
- `generate_agenda_template` queries the empty table → carry-forward never works

#84 proposes a 3-Onda plan:
- **Onda 1 — Schema hardening (1-2 days, additive, low risk)** ← THIS ADR
- Onda 2 — 10 new MCP tools (3-4 days, medium risk, overlaps with #83)
- Onda 3 — UX + LLM extractor (sprint dedicated)

ADR-0045 ships Onda 1 as a single autonomous-shippable migration. No
behavior changes — pure schema preparation that unlocks Ondas 2/3 without
blocking current functionality.

---

## Decisão

### Section A — `meeting_action_items` FK linkages

Add 6 columns:
- `board_item_id uuid REFERENCES board_items(id) ON DELETE SET NULL` —
  optional link to a card created from / related to the action item
- `checklist_item_id uuid REFERENCES board_item_checklists(id) ON DELETE
  SET NULL` — sub-card-level link
- `kind text DEFAULT 'action' CHECK IN ('action','decision','followup','general')`
  — semantic classifier (decisions ≠ actions)
- `resolved_at timestamptz` — explicit resolution timestamp
- `resolved_by uuid REFERENCES members(id)` — who marked resolved
- `resolution_note text` — free-text resolution explanation

Indexes:
- Partial index on `board_item_id WHERE NOT NULL` — for "which actions link
  to this card" queries
- Partial index on `(event_id, resolved_at) WHERE resolved_at IS NULL` — for
  "open actions in this event" queries

### Section B — `event_showcases` artifact linkages

Add 3 columns:
- `board_item_id uuid REFERENCES board_items(id) ON DELETE SET NULL` —
  link showcase to the card being presented
- `artifact_id uuid REFERENCES tribe_deliverables(id) ON DELETE SET NULL`
  — link to a delivered artifact
- `xp_awarded integer` — snapshot of XP awarded (avoids drift if XP rules
  change later)

Index: partial on `board_item_id WHERE NOT NULL`.

### Section C — `tribe_kpi_contributions` table (GAP 7)

Maps `annual_kpi_targets` to `initiatives` (tribes/workgroups). Replaces
the missing tribe_id/initiative_id link in `annual_kpi_targets`.

```sql
CREATE TABLE tribe_kpi_contributions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  kpi_target_id uuid NOT NULL REFERENCES annual_kpi_targets(id) ON DELETE CASCADE,
  initiative_id uuid NOT NULL REFERENCES initiatives(id) ON DELETE CASCADE,
  contribution_query text,
  weight numeric NOT NULL DEFAULT 1.0 CHECK (weight > 0),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(kpi_target_id, initiative_id)
);
```

RLS:
- SELECT: any authenticated (governance transparency — KPI contribution
  mapping is platform-wide knowledge)
- WRITE (FOR ALL): `can_by_member('manage_platform')` only

Use cases enabled (Onda 2):
- "Quais KPIs anuais a Tribo 6 contribui?"
- "Meta `webinars_delivered` está em 60% — qual tribo tem cards atrasados?"
- Tribe dashboard shows linked KPI contributions with current/target values

Note: native `initiative_id` reference (per ADR-0015 native-first) — no
legacy tribe_id column. Tribes are reachable via `initiatives.legacy_tribe_id`.

### Section D — `board_item_event_links` table (GAP 4)

Cross-reference between cards and events for bidirectional traceability:

```sql
CREATE TABLE board_item_event_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  board_item_id uuid NOT NULL REFERENCES board_items(id) ON DELETE CASCADE,
  event_id uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  link_type text NOT NULL CHECK (link_type IN
    ('discussed','action_emerged','decision','status_changed','showcased')),
  author_id uuid REFERENCES members(id),
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(board_item_id, event_id, link_type)
);
```

RLS:
- SELECT: any authenticated (mirror board_items + events visibility)
- WRITE (FOR ALL): `can_by_member('manage_event')` (matches Onda 2
  `update_card_during_meeting` intent — event organizers manage links)

Use cases enabled (Onda 2):
- "Quais reuniões discutiram este card?" — card detail tab "Histórico em reuniões"
- "Esta reunião alterou status de quais cards?" — meeting impact view
- "Lessons learned: cards onde decisions emerged from meeting X"

---

## Out of scope (deferred to Onda 2/3)

- 10 new MCP tools (`get_meeting_preparation`, `get_agenda_smart`,
  `create_action_item`, `register_decision`, `convert_action_to_card`,
  `update_card_during_meeting`, `resolve_action_item`, `meeting_close`,
  `get_card_full_history`, `get_tribe_housekeeping`)
- Trigger AFTER UPDATE on `events.minutes_text` for LLM extraction
- Frontend `CardDetail.tsx` "Histórico em reuniões" tab
- Frontend `MeetingMode` modal during meetings
- Dashboard GP "Tribes contributions to annual goals"
- Invariant: meeting with `- [ ]` markdown but 0 rows in
  meeting_action_items → flag in board_taxonomy_alerts

---

## Trade-offs aceitos

1. **Adding columns/tables that are not yet used**: Onda 2 hasn't shipped
   yet. Risk: dormant schema may drift if Onda 2 design changes. Mitigation:
   schema is purely additive — Onda 2 can refine without ALTER table
   churn (already 0 rows so no migration cost).
2. **`meeting_action_items.board_item_id` as nullable optional FK**: not
   every action item maps to a card (e.g., "send email follow-up to
   Acme"). Trade-off: traceability is opt-in for non-card actions. Acceptable.
3. **`tribe_kpi_contributions` separate from `annual_kpi_targets`**:
   could have added `initiative_id` directly to `annual_kpi_targets`. Chose
   junction table for: (a) M:N flexibility — one KPI may be contributed by
   multiple tribes; (b) per-link weight + contribution_query; (c) keeping
   annual_kpi_targets schema stable.
4. **`board_item_event_links` UNIQUE on (board_item_id, event_id,
   link_type)**: prevents duplicate links of same type. Trade-off: cannot
   record "card X was discussed twice in meeting Y at minutes 12 and 47".
   Acceptable — the granularity is the meeting, not the timestamp.
5. **RLS write gates differ between new tables**: `tribe_kpi_contributions`
   = `manage_platform` (governance); `board_item_event_links` =
   `manage_event` (operational). Reflects the intent of each table.

---

## Cross-cutting precedent

### Schema-hardening-first ADR

ADR-0045 establishes the precedent of shipping schema-only ADRs as Onda 1
of larger feature plans. Pattern:
1. Identify additive schema changes (no behavior change, no breakage)
2. Add columns/tables/RLS in one focused migration
3. Document deferred Onda 2/3 in ADR
4. Future Ondas reference ADR-0045 as schema foundation

Future feature plans (#88, #89, #91, #94 substantive features) can follow
this template — ship Onda 1 schema autonomously, then PM-sync for Onda 2/3.

### Mirror RLS pattern for cross-reference tables

`board_item_event_links` is the first card-event cross-reference table.
Pattern: any future cross-reference table (e.g., `board_item_initiative_links`,
`event_kpi_links`) should:
- Mirror SELECT visibility from referenced tables (authenticated)
- Restrict WRITE to the action that owns the cross-reference semantically
- Include `organization_id` per ADR-0012 invariant
- Use UNIQUE on the natural key tuple (avoid duplicate links)

### Native initiative_id-first

`tribe_kpi_contributions` uses `initiative_id` (not `legacy_tribe_id`)
per ADR-0015 native-first stance. Tribes are reachable via
`initiatives.legacy_tribe_id`. When ADR-0015 Phase 5 drops `tribe_id`,
this table needs ZERO changes — already future-proof.

---

## Status / Next Action

- [x] #84 issue specifies Onda 1 as quick win — autonomous-shippable
- [x] Migration `20260514070000_adr_0045_meeting_board_traceability_schema.sql`
- [x] Schema invariants: 11/11 = 0 (verified post-apply)
- [x] Tests preserved: 1415 / 1383 / 0 / 32
- [ ] **Onda 2** — 10 new MCP tools (PM-discretionary; medium risk)
- [ ] **Onda 3** — UX + LLM extractor (PM design session needed)

---

## Forward backlog

- **#84 Onda 2**: schedule when MCP tool layer expansion is prioritized
- **#84 Onda 3**: LLM extractor + UX needs design session
- **Comment on #84**: link this ADR + recommend Onda 2 next
