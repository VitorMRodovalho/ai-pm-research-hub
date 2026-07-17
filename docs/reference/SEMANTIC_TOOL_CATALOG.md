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

## Wave 2 — Members, engagements & initiatives (shipped 2026-07-16)

9 tools absorbing the members/engagements/initiatives raw surface (423 calls/180d; `search_members` is
the #2 tool at 167). `/semantic` 12 → 21 (`nucleo-ia-semantic@0.4.0`, `ef_version 2.82.0`). LGPD is the
theme: `member_search`/`member_get`/`member_emails` are the PII surface and mask sensitive columns unless
the caller has `view_pii`. Two raw-RPC failure fixes are baked in (migration `20260805000454`):
`get_person` now accepts a `members.id` OR a `persons.id` (killed the raw #2-failure class, 17/20
"Person not found") and `get_active_engagements` no longer references the non-existent `initiatives.name`
(was `i.title`; killed 3/3 failures).

### `member_search` (R)
- **Intent:** the member directory — the #2 tool (167 calls/180d). Filter by `query` (name), `tribe_id`, `tier`, `status`.
- **Absorbs:** `search_members` (→ `admin_list_members`).
- **Gate:** `manage_member`. **LGPD:** redacts `email` + `auth_id` unless the caller has `view_pii` (`audit.pii_level` = `high`/`low` reflects the actual disclosure).

### `member_get` (R)
- **Intent:** one person, 360° (profile + active engagements). Resolve by `person_id`, `member_id`, or `email` (email → `manage_member`, anti-enumeration); omit all for your own record.
- **Absorbs:** `get_person` (member_id-resolution fix) + `get_active_engagements` (i.title fix).
- **Gate:** self always; PII masked by `get_person` per `view_pii` (+ chapter-scope); engagements of others require `manage_member` (surfaced in `warnings` if absent).

### `member_emails` (R/W)
- **`action`:** `list` · `add` · `remove` · `set_primary` · `update_kind` · `resolve` (email → member_id).
- **Absorbs:** `member_list_emails`/`add`/`remove`/`set_primary`/`update_kind`/`resolve`.
- **Gate:** per-record self-OR-`manage_member` (RPC-enforced; +`view_pii` on list). **`resolve` ADDS a `manage_member` gate here** to close the email-existence oracle (raw `member_resolve_email` was auth-only).

### `member_lifecycle` (W)
- **Intent:** GP-only member lifecycle (LGPD Art.18 invariant). **`action`:** offboard* · reissue_agreement* · record_offboarding · get_offboarding_record · list_offboarding · offboarding_dashboard · onboarding_dashboard · pending_agreements · explain_authority · stage_alumni · invite_alumni · respond_re_engagement · cancel_re_engagement · list_re_engagement · promote_to_leader · detect_inactive. (*destructive → `confirm=true`.)
- **Absorbs:** 16 raw lifecycle/offboarding/re-engagement tools.
- **Gate:** `manage_member` for admin verbs (`promote_to_leader` → `promote`; `respond_re_engagement`/`get_offboarding_record` are RPC self-gated). **Warns Camada-5 on reissue** (reissue supersedes the agreement → demotes authority; a re-accept must use Camada-5, never batch-reissue).

### `engagement_write` (W)
- **`action`:** `add`* · `remove`* · `update_role` · `invite` · `respond_invitation` · `request_join` · `review_request` · `withdraw`*. (*destructive → `confirm=true`.)
- **Absorbs:** `manage_initiative_engagement`, `invite_to_initiative`, `respond_to_initiative_invitation`, `request_to_join_initiative`, `review_initiative_request`, `withdraw_from_initiative`.
- **Gate:** authority is RPC-enforced (admin-of-initiative OR owner for admin verbs; caller-scoped for self verbs); the semantic layer ADDS the #785 confidential fail-fast (`canSee(initiative)`) on the target. dual-write (`members.tribe_id↔initiative_id`) is server-side (#1270). `create_external_speaker_engagement` stays raw this wave (heavyweight bootstrap).

### `initiative_roster` (R)
- **`scope`:** `initiative` (#785-gated) · `by_kind` · `my_tribe` · `invitations_for_my_initiatives` · `invitations_received` · `invitations_sent`.
- **Absorbs:** `list_initiative_engagements(_by_kind)`, `get_my_tribe_members`, `list_invitations_*` ×3.
- **Gate:** `canSee(initiative)` on the `initiative` scope; other scopes are RLS/self-scoped. Confidential excluded.

### `initiative_directory` (R)
- **`mode`:** `all` (kind/status filters) · `open` (joinable).
- **Absorbs:** `list_initiatives`, `list_open_initiatives`.
- **Gate:** confidential excluded inline by the RPCs (`rls_can_see_initiative`, #785).

### `initiative_report` (R)
- **`report`:** `dashboard` · `stats` · `housekeeping` · `deliverables` · `credly` · `members_credly` (per-initiative, #785-gated) · `comparison` (cross-initiative, `manage_platform`/`view_chapter_dashboards`) · `pilots`.
- **Absorbs:** `get_tribe_dashboard`/`stats_ranked`/`housekeeping`/`deliverables`/`credly`/`members_with_credly` + `tribes_comparison` + `pilots_summary`.
- **Gate:** `canSee(initiative)` mandatory on per-initiative reports; aggregate reports carry their own authority.

### `my_status` (R)
- **Intent:** "where am I?" — SELF-only. **`scope`:** `all` (default) · `profile` · `committee` · `board` · `application` · `notifications` · `onboarding` · `selection_result` · `credly`.
- **Absorbs:** `get_my_profile`/`committee_assignments`/`board_status`/`application_status`/`notifications`/`onboarding`/`selection_result`/`credly`. Supersedes the `get_my_context` bridge (which stays registered).
- **Gate:** self (auth.uid → member); `pii_level: "self"`; zero admin surface.

---

## Wave 3 — Events, attendance & meetings (shipped 2026-07-16)

6 tools absorbing the event domain (393 calls/180d; `register_attendance` is the #3 tool overall at 132).
`/semantic` 21 → 27 (`nucleo-ia-semantic@0.5.0`, `ef_version 2.83.0`). Authority is the theme: the Wave-0
CONFIRMED finding was a **resourceless `can_by_member(caller, 'manage_event')`** — any manage_event holder
could write to every initiative's events. Migration 444 (#1384) scoped four paths; this wave re-verified
them live and extended the same helper (`_manage_event_scope_ok`) to **five more** in migration
`20260805000455`: `create_action_item`, `register_decision`, `resolve_action_item`, `update_event_instance`
and `drop_event_instance`. Proven live before/after with an impersonated, rolled-back probe: an
initiative-scoped leader writing into another initiative's meeting went from `success: true` to denied,
while the same leader's own initiative and an org-scoped holder stayed allowed.

Two live failure fixes ride along: `resolve_action_item` wrote `status` values (`carried_forward`,
`completed`) that the live CHECK constraint rejects — every call failed; it now writes `done` /
`carried_over`. (The historical `register_decision` 8F / `create_action_item` 6F were the same
constraint class, already fixed in their live bodies — the failure log is 180d wide and predates the fix.)

`get_agenda_smart` is **retired** from the semantic surface (it raises `record "v_initiative" is not
assigned yet` for any event with no initiative — the RPC keeps that bug and stays retired).
`get_meeting_preparation` had the identical bug and is **fixed** in migration `20260805000456`: its
`SELECT ... INTO v_initiative` was guarded by `IF initiative_id IS NOT NULL` while `v_initiative.id` was
read unconditionally, so it raised for **every** org-wide event (`geral`/`kickoff`/`lideranca` — 243 live,
23 upcoming). An unassigned plpgsql `record` does not read as NULL. Running the SELECT INTO
unconditionally assigns it all-NULLs, which is exactly what the read expects (verified live).
Before → after: org-wide event raised → returns with `initiative: null`; an initiative-linked event is
byte-for-byte unchanged (same initiative, same 3 expected attendees).

### `event_search` (R)
- **Intent:** find events. **`scope`:** `upcoming` (next 7 days) · `near` (check-in window, self) · `initiative` (filtered list + pagination) · `detail` (one event).
- **Absorbs:** `list_initiative_events` (41) · `get_event_detail` (31) · `get_upcoming_events` (12) · `get_near_events` (7).
- **Gate:** authenticated; #785 already lives in the source RPCs and is re-checked fail-fast for `detail`/`initiative`.

### `event_write` (W)
- **Intent:** the event lifecycle. **`action`:** `create` · `update` (reschedule/link/agenda) · `drop` (DESTRUCTIVE → `confirm=true`, ADR-0018).
- **Absorbs:** `create_tribe_event` · `update_event_instance` (29) · `drop_event_instance`.
- **Gate:** `eventWriteGate()` = `canSee(initiative)` + **`can(manage_event, resource=event.initiative_id)`** — fixes the cross-initiative edit/delete bypass.

### `attendance_record` (W)
- **Intent:** who was there. **`action`:** `register` (batch-capable; the #3 tool) · `excuse` · `bulk_excuse` (date range) · `showcase` (15-25 XP).
- **Absorbs:** `register_attendance` (132) · `mark_member_excused` · `bulk_mark_excused` · `register_showcase` (17).
- **Gate:** `eventWriteGate()` (initiative-scoped `manage_event` + #785). `bulk_excuse` is member-scoped, not event-scoped: the RPC gates it inline (org-scope OR shares an active initiative with the target) and is passed through.
- **Attribution:** the RPC records `registered_by`/`marked_by` — that, NOT `checked_in_at`, is what distinguishes a self check-in from a leader's batch (#1322).

### `attendance_report` (R)
- **Intent:** attendance analytics. **`scope`:** `mine` (default) · `tribe` (grid) · `ranking` · `hours` · `health` · `cycle`.
- **Absorbs:** `get_my_attendance_history` · `get_my_tribe_attendance` · `get_attendance_ranking` · `get_my_attendance_hours` · `get_event_attendance_health` · `get_cycle_attendance_overview`.
- **Gate:** self scopes free; cross-member/cross-cohort requires `view_internal_analytics`. **`scope='tribe'` ADDS the #785 gate** — `get_initiative_attendance_grid` has none of its own.

### `meeting_minutes` (R/W)
- **Intent:** the minutes lifecycle. **`action`:** `read` (recent minutes) · `prepare` (briefing) · `write` · `close` (posts minutes + returns action/decision counts + drift signal).
- **Absorbs:** `create_meeting_notes` (38) · `meeting_close` · `get_meeting_notes` · `get_meeting_preparation`. **NOT** `get_agenda_smart` (retired).
- **Gate:** `eventWriteGate()` on `write`/`close`; #785 on reads. `write` warns when `action_items` are appended as Markdown checkboxes instead of structured rows.

### `meeting_actions` (R/W)
- **Intent:** what the meeting decided and who does what. **`action`:** `create` · `resolve` (incl. `carry_to_event_id`) · `list` · `convert_to_card` · `decision` · `decision_log`.
- **Absorbs:** `create_action_item` (21) · `resolve_action_item` (CHECK fix) · `list_meeting_action_items` · `convert_action_to_card` · `register_decision` (15) · `get_decision_log`.
- **Gate:** `eventWriteGate()` on every write; the **carry-forward target is gated independently** (carrying into another initiative is the same cross-initiative write); `convert_to_card` additionally requires `write_board` + `canSee(board)`.

---

## Wave plan (usage-validated order)

| Wave | Family | Status |
|---|---|---|
| 0 | Bridge (`get_my_context`, `search_nucleo_knowledge`, `get_board_or_initiative_context`, `get_operational_status`) | shipped (SPEC-280) |
| **1** | **Boards & cards** | **shipped 2026-07-15** |
| **2** | **Members / engagements / initiatives** | **shipped 2026-07-16** |
| **3** | **Events / attendance / meetings** | **shipped 2026-07-16** |
| 4 | Selection & evaluation | planned |
| 5 | Governance / docs / certificates | planned |
| 6 | Comms / drive / partners / knowledge / gamification / ops | planned |

Per-wave exit criteria (all 8 must tick): authority/RLS audited · envelope contract test green ·
256-cap headroom · deprecation wiring (no breakage) · docs shipped (this file + matrix + `rules/mcp.md` + wiki) ·
usage healthy ≥2 weeks post-deploy · security regression scan clean · grounding discipline (numbers re-queried live).

_Cross-ref: EPIC #1383, SPEC-280, ADR-0105 (#785), ADR-0007 (can/can_by_member), `.claude/rules/mcp.md`._
