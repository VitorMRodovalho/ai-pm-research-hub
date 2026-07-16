# Semantic Tool Catalog — `/semantic` surface (EPIC #1383)

_The operator-facing SSOT for the semantic MCP gateway. Companion to the machine matrix
(`docs/reference/MCP_TOOL_MATRIX.md`) and the raw-vs-semantic map
(`wave0-artifacts/taxonomy.md`, private). Waves land here one at a time._

## What the semantic surface is

Three MCP surfaces share ONE Edge Function (`supabase/functions/nucleo-mcp/index.ts`):

| Surface | Server | Purpose |
|---|---|---|
| `/mcp` | `nucleo-ia-hub` | Full internal capability registry (raw tools, 1 verb each). |
| `/actions` | `nucleo-ia-actions` | Overflow of the write/action tail dropped by the 256-tool connector cap (#1377). |
| **`/semantic`** | **`nucleo-ia-semantic`** | **Intent-level gateway (SPEC-280). Stable envelope. The migration target.** |

The transition (EPIC #1383) folds ~347 raw tools into ~50 **intent-level** semantic tools with a
single stable envelope, discriminated by an `action`/`mode`/`report`/`scope` param where a family has
several verbs (Supabase-MCP-style feature grouping). Raw tools stay registered — the migration is
**additive + deprecation, never breaking**.

## The stable envelope (the contract)

Every semantic tool returns this shape on success AND failure:

```jsonc
{
  "ok": true,                       // false on any error
  "data": { /* tool-specific */ },
  "summary": "1-2 sentence natural-language result",
  "warnings": ["partial-source failures surfaced here, never masked inside ok:true"],
  "next_actions": ["suggested follow-up semantic calls"],
  "audit": {
    "tool": "card_write",
    "semantic_domain": "boards",
    "pii_level": "none|low|self|high",
    "permission": "write_board",
    "source_tools": ["create_board_item"],   // the raw RPCs/tables dispatched
    "caller_member_id": "…",
    "gate_checked": "rls_can_see_item + write_board",  // the authority contract, machine-inspectable
    "resource_id": "…",                       // the board/card/initiative the call was scoped to
    "generated_at": "2026-07-15T…Z"
  }
}
```

On error, `ok:false` + a structured `error:{code,message,action}` block (never a raw `Error: …`
string, never an RPC `{error:…}` leaking inside `ok:true`). Codes: `unauthenticated`, `unauthorized`,
`invalid_input`, `not_found`, `internal_error`.

The contract is guarded statically by `tests/contracts/semantic-envelope-w1.test.mjs`.

### Security contract (baked, not optional)

- **Writes** carry `write_board` authority (via `canV4` → `can_by_member()`, ADR-0007) **and** the
  **#785 confidential-visibility gate** (ADR-0105) as a fail-fast: the target card/board must be
  visible to the caller (`rls_can_see_item → rls_can_see_board → rls_can_see_initiative`, fail-closed).
  This only ever RESTRICTS — the Tier-1 cross-board curator read-all model (CLAUDE.md #5) is preserved;
  only confidential initiatives are excluded from non-engaged callers.
- **Reads** that address a specific board/card/initiative carry the same #785 fail-fast; list/aggregate
  reads inherit #785 via the underlying RLS (`project_boards_confidential_visibility`, etc.).
- Destructive verbs (`card_write` archive/delete) return a **preview** unless `confirm=true` (ADR-0018).

---

## Wave 1 — Boards & cards (shipped 2026-07-15)

8 tools absorbing 43 raw tools (traffic order, 180d call data re-queried live at ship). `/semantic` 4 → 12.

### `card_checklist` (W)
- **Intent:** the card checklist writer — the platform's #1 write path (345 calls/180d).
- **`action`:** `add` (card_id + text) · `update` (checklist_item_id) · `complete` (checklist_item_id; `completed` default true) · `assign` (checklist_item_id + assigned_to) · `delete` (checklist_item_id).
- **Absorbs:** `add_checklist_item`, `update_checklist_item`, `complete_checklist_item`, `assign_checklist_item`, `delete_checklist_item`.
- **Gate:** `write_board` + #785 (`rls_can_see_item`). `complete` is RPC-self-gated to the activity owner (no `write_board` required).

### `card_write` (W)
- **Intent:** create/mutate/move/lifecycle a single card (297 calls/180d).
- **`action`:** `create` (board_id + title) · `update` · `move` · `move_to_board` · `archive`* · `restore` · `delete`* · `duplicate` · `mirror` · `forecast`. (*destructive → `confirm=true`.)
- **Absorbs:** `create_board_card`, `update_card_fields`, `update_card_status`, `move_card`, `move_card_to_board`, `archive_card`, `restore_card`, `delete_card`, `duplicate_card`, `create_mirror_card`, `update_card_forecast`.
- **Gate:** `write_board`, **board-scoped** via #785 on the target card (`create` gates the target board). Closes the Wave-0 resourceless-write concern for delete/duplicate/mirror.

### `card_comment` (W)
- **Intent:** comment on a card (create/edit/soft-delete), with @mentions.
- **`action`:** `create` (board_item_id + body) · `update` (comment_id + body; author only) · `delete` (comment_id).
- **Absorbs:** `create_card_comment`, `update_card_comment`, `delete_card_comment`.
- **Gate:** RPC-self (author / write_board / GP per action) + **#785 ADDED at the semantic layer** (a gap in the raw tools).

### `card_search` (R)
- **Intent:** find cards. **`mode`:** `board` (board_id) · `text` (query + tribe_id/initiative_id) · `mine` · `orphans` (admin).
- **Absorbs:** `list_board_cards`, `search_board_cards`, `get_my_assigned_cards`, `list_orphan_card_assignments`.
- **Gate:** #785 fail-fast on `board`/`text`; `mine`/`orphans` RLS/authority-scoped.

### `card_get` (R)
- **Intent:** one card, 360°. **`detail_level`:** `summary` · `standard` (default: + checklist + comments + timeline) · `full` (+ drive files + cross-entity history).
- **Absorbs:** `get_card_detail`, `get_card_timeline`, `get_card_full_history`, `list_card_comments`, `list_card_checklist`, `list_card_drive_files`.
- **Gate:** #785 (`rls_can_see_item`) fail-fast. Closes the `board_item_checklists` read gap.

### `board_overview` (R)
- **Intent:** boards. **`scope`:** `list` (all visible boards) · `board` (board_id → fields+members+tags+activities) · `initiative` (initiative_id/tribe_id → initiative + board + sample cards + engagement count).
- **Absorbs:** `list_boards`, `get_board_detail`, `get_board_activities`; folds in the `get_board_or_initiative_context` bridge tool.
- **Gate:** #785 — `list` via RLS (`project_boards_confidential_visibility`); `board`/`initiative` fail-fast.

### `platform_context` (R)
- **Intent:** current cycle + release + cycles list. Tier-1 read, no PII, no per-resource gate.
- **Absorbs:** `get_current_cycle`, `get_current_release`, `list_cycles`.

### `portfolio_report` (R)
- **Intent:** PMO rollups. **`report`:** `overview` (default) · `items` · `health` · `timeline` · `planned_vs_actual` · `board_summary`.
- **Absorbs:** `get_portfolio_overview`, `get_portfolio_items`, `get_portfolio_health`, `get_portfolio_timeline`, `get_portfolio_planned_vs_actual`, `exec_portfolio_board_summary`.
- **Gate:** `manage_member` OR `view_partner` (admin/sponsor). Confidential initiatives excluded inline by the RPCs.

---

## Wave plan (usage-validated order)

| Wave | Family | Status |
|---|---|---|
| 0 | Bridge (`get_my_context`, `search_nucleo_knowledge`, `get_board_or_initiative_context`, `get_operational_status`) | shipped (SPEC-280) |
| **1** | **Boards & cards** | **shipped 2026-07-15** |
| 2 | Members / engagements / initiatives | planned |
| 3 | Events / attendance / meetings | planned |
| 4 | Selection & evaluation | planned |
| 5 | Governance / docs / certificates | planned |
| 6 | Comms / drive / partners / knowledge / gamification / ops | planned |

Per-wave exit criteria (all 8 must tick): authority/RLS audited · envelope contract test green ·
256-cap headroom · deprecation wiring (no breakage) · docs shipped (this file + matrix + `rules/mcp.md` + wiki) ·
usage healthy ≥2 weeks post-deploy · security regression scan clean · grounding discipline (numbers re-queried live).

_Cross-ref: EPIC #1383, SPEC-280, ADR-0105 (#785), ADR-0007 (can/can_by_member), `.claude/rules/mcp.md`._
