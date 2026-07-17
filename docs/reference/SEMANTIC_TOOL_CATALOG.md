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

`get_agenda_smart` (ADR-0049) is **dropped** — RPC + MCP tool, migration `20260805000457`. It carried the
same unassigned-record bug and, across its entire lifetime, logged **1 call, which failed** (2026-05-22):
it never once returned successfully. Zero DB dependents, zero application call sites. `meeting_minutes
action='prepare'` is its replacement. `/mcp` 343 → 342.
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
- **Absorbs:** `create_meeting_notes` (38) · `meeting_close` · `get_meeting_notes` · `get_meeting_preparation`. Replaces the dropped `get_agenda_smart`.
- **Gate:** `eventWriteGate()` on `write`/`close`; #785 on reads. `write` warns when `action_items` are appended as Markdown checkboxes instead of structured rows.

### `meeting_actions` (R/W)
- **Intent:** what the meeting decided and who does what. **`action`:** `create` · `resolve` (incl. `carry_to_event_id`) · `list` · `convert_to_card` · `decision` · `decision_log`.
- **Absorbs:** `create_action_item` (21) · `resolve_action_item` (CHECK fix) · `list_meeting_action_items` · `convert_action_to_card` · `register_decision` (15) · `get_decision_log`.
- **Gate:** `eventWriteGate()` on every write; the **carry-forward target is gated independently** (carrying into another initiative is the same cross-initiative write); `convert_to_card` additionally requires `write_board` + `canSee(board)`.

---

## Wave 4 — Selection & evaluation (shipped 2026-07-17)

6 tools absorbing the selection domain (367 calls/180d; `submit_evaluation` is the #5 tool overall at 124).
`/semantic` 27 → 33 (`nucleo-ia-semantic@0.6.0`, `ef_version 2.84.0`). Every absorbed RPC **self-gates
authority internally** (audited live via `pg_get_functiondef`): candidate-data reads require
`view_internal_analytics` / `manage_member` / committee-of-cycle membership PLUS **ADR-0109
conflict-of-interest recusal** (an active candidate in the cycle is blocked from selection surfaces);
writes require `manage_platform` (GP) / `manage_member` / `promote` / committee-scoping. There is **no
resourceless-`can()` shape** here — the W3 bypass class was audited and is absent. The semantic layer passes
through and surfaces each RPC's own `{error}`/RAISE in the `ok:false` envelope; write tools add a proactive
`canV4()` fail-fast that mirrors the RPC gate.

Raw-side hardening rode along in migration `20260805000458`, proven live with an impersonated, rolled-back
probe: **`get_application_interviews`** was widened from GP-only (`manage_platform`) to **committee-of-cycle
OR platform admin**, per the tool's own docstring ("used by committee to coordinate"), with an added COI
recusal so a candidate seated on the committee stays blocked — a pure committee member went from
`Unauthorized: requires manage_platform` to seeing the interviews. And an **anon `EXECUTE` grant drift on
`recalculate_cycle_rankings`** was revoked (its body was already fail-closed; defense-in-depth).

The Wave-0 top failure `get_selection_health` (3/3F, `column t.created_at does not exist`) was **already fixed
in the live body** (it reads `t.issued_at`; the log is 180d and predates the fix) — no change, re-grounding
avoided a false correction. Deliberately **kept raw** (not surfaced semantically): `compute_application_scores`
(dormant `service_role`-only helper, 0 MCP calls ever), `generate_interview_briefing` (inline-Haiku, `view_pii`),
`capture_visitor_lead` (public anon site entry — rate-limited + LGPD-consent-gated).

### `selection_dashboard` (R)
- **Intent:** the selection-cycle command surface. **`scope`:** `dashboard` (cycle_code) · `cycles` · `rankings` · `cutoff` (cycle_id) · `calibration` · `health` · `pipeline` (cycle_id) · `committee` (cycle_id) · `dispatch`.
- **Absorbs:** `get_selection_dashboard` (24) · `get_selection_cycles` · `get_selection_rankings` · `get_pert_cutoff_summary` · `get_evaluator_calibration_stats` · `get_selection_health` · `get_selection_pipeline_metrics` · `get_selection_committee` · `get_cutoff_dispatch_health`.
- **Gate:** each RPC self-gates on `view_internal_analytics`/`view_aggregate_analytics` + ADR-0109 COI recusal; candidate PII stays behind those gates. Pass-through.

### `application_get` (R)
- **Intent:** one application, 360°. **`scope`:** `scores` · `interviews` · `gate_attempts` · `returning` · `onboarding` (all keyed by `application_id`).
- **Absorbs:** `get_application_score_breakdown` (47) · `get_application_interviews` (26, now committee-visible) · `get_application_gate_attempts` · `get_application_returning_context` · `get_application_onboarding_pct`.
- **Gate:** committee-of-cycle OR `manage_member`/`curate_content` + ADR-0109 COI (all RPC-internal). PII: high.

### `evaluation_submit` (R/W)
- **Intent:** the evaluator loop. **`mode`:** `queue` · `form` · `submit` (idempotent: a locked evaluation cannot re-submit) · `interview_scores` · `results` · `feedback`.
- **Absorbs:** `submit_evaluation` (124, #5 tool) · `get_evaluation_form` (73) · `get_my_pending_evaluations` (21) · `submit_interview_scores` · `get_evaluation_results` · `get_my_evaluation_feedback`.
- **Gate:** committee membership of the cycle (self-scoped; `manage_platform` bypass) — RPC-internal.

### `interview_manage` (W)
- **Intent:** interview scheduling lifecycle. **`action`:** `schedule` · `mark` · `rescue`.
- **Absorbs:** `schedule_interview` · `mark_interview_status` · `selection_rescue_stuck_interview`. (`generate_interview_briefing` stays raw — inline-Haiku, `view_pii`.)
- **Gate:** committee lead of the cycle OR platform admin (RPC-internal); the no-AI-analysis gate on `schedule` is bypassable only with `manage_member` + `bypass_gate=true`.

### `selection_decide` (W)
- **Intent:** cycle-level decisions. **`action`:** `approve` (DESTRUCTIVE → `confirm=true`, ADR-0018) · `notify_cutoff` · `compute_cutoff` · `recalc_rankings` (DESTRUCTIVE → `confirm=true`) · `committee` (add/remove) · `update_contact`.
- **Absorbs:** `approve_selection_application` · `notify_selection_cutoff_approved` · `compute_pert_cutoff` · `recalculate_cycle_rankings` · `manage_selection_committee` · `update_application_contact`. (`compute_application_scores` stays raw — dormant service-role helper.)
- **Gate:** proactive `canV4()` mirroring each RPC gate — `approve`/`recalc_rankings` = `manage_platform` (GP), `compute_cutoff`/`notify_cutoff`/`update_contact` = `manage_member`, `committee` = `promote`.

### `visitor_leads` (R/W)
- **Intent:** pre-consent lead triage for operators. **`action`:** `list` · `ghosts` · `dismiss` · `promote` (→ application).
- **Absorbs:** `list_visitor_leads` · `get_ghost_visitors` · `dismiss_visitor_lead` · `promote_lead_to_application`. (Public `capture_visitor_lead` stays raw.)
- **Gate:** `canV4(manage_member)` (ghosts = `manage_platform`). Leads are pre-consent PII — LGPD-minimal.

---

## Wave 5 — Governance, documents & certificates (shipped 2026-07-17)

7 tools absorbing the governance domain — the **worst-failure domain** in the window (117 calls/180d but ~40%
failure). `/semantic` 33 → 40 (`nucleo-ia-semantic@0.7.0`, `ef_version 2.85.0`). The wave is justified by fix
density, not volume: three of the top failures were **enum/contract bugs masked as `ok:true`** by the raw tools.

Every absorbed RPC **self-gates authority internally** (audited live via `pg_get_functiondef`): the governance
READ RPCs enforce a **`visibility_class` ceiling** (`get_document_detail` / `get_version_diff` /
`get_governance_document_reader` — migrations 450/451, already live; a `legal_scoped` doc needs `manage_member`
or a current signature); version writes require `manage_member`; the manual-version 2-of-N flow +
change-request writes require `manage_platform` / `curate_content`; the certificate + ip-exclusion RPCs resolve
the caller and self-gate. **All are fail-closed for anon.** The semantic layer passes through and surfaces each
RPC's own `{error}`/RAISE in `ok:false`; `document_version_write` adds a proactive `canV4()` fail-fast.

**Contract fixes baked in (root cause of the failure rate):**
- `document_comment` uses the RPC-validated visibility enum `curator_only | submitter_only | change_notes`.
  The raw `add_document_comment` documented `public`/`signers_only`/`private` — all rejected by
  `create_document_comment` on **every** call, then masked as `ok:true`. The raw tool's schema was also corrected.
- `change_request` uses `cr_type` `editorial | operational | structural | emergency`. The raw
  `submit_change_request` documented `manual_edit`/`gc_override`/`policy_update` — likewise always rejected + masked.
- `certificate_manage` validates issue inputs **before** dispatch (title required, `type`/`language` enums,
  `cycle` as int) — the root cause of the 18/27 `issue_certificate` failures (null-title NOT-NULL crash;
  `"cycle_3"` → integer-cast crash). This turns a raw DB constraint error into a clean `invalid_input`.

**Raw-side hardening rode along in migration `20260805000459`, proven live (impersonated, rolled back):**
`submit_change_request` set `priority = impact_level`, but `priority`'s CHECK is `high|medium|low` while
`impact_level` allows `critical` — a `critical`-impact CR **always** failed the `priority` CHECK. Clamped
`critical → high` (impact_level keeps the true value). And the dead **anon/PUBLIC `EXECUTE` drift on 14
governance/certificate write RPCs** was REVOKEd (all already fail-closed; defense-in-depth, #965 trap).

**Deliberately kept raw (not surfaced semantically):**
- `counter_sign_certificate` — countersign is the **Dir. de Voluntariados' exclusive act** (never automated via MCP).

**Remediated (#1397, migration `20260805000462`) — `review_change_request` / `approve_change_request` now
absorbed into `change_request` (`review`/`approve`):** the unilateral `implement` branch was **retired**
(the `approved→implemented` transition is 2-of-N only, via `document_version_write propose_manual/confirm_manual`,
ADR-0044); the hardcoded `manual_version_to='R3'` is gone; the quorum numerator is now **sponsor-only** (a
non-sponsor governance voter no longer inflates it against the sponsor-only denominator); and two latent
crashers were fixed (a `submitted_by` field reference that had made the RPC non-functional and rolled back
every action, plus a `create_notification` overload ambiguity). Owner decision (Option A): both approval paths
are kept — `review` drives the CR lifecycle, `approve` records the sponsor-quorum vote; both write
`status='approved'`, which only makes a CR eligible for the 2-of-N Manual publication.

### `document_get` (R)
- **Intent:** read governance documents. **`mode`:** `list` · `detail` · `body` (sanitized HTML + Markdown + section anchors of the current LOCKED version) · `versions` · `diff` · `changelog` · `manual`.
- **Absorbs:** `get_governance_docs` · `get_document_detail` · `get_governance_document_body` · `list_document_versions` · `get_version_diff` · `get_governance_change_log` · `get_manual_section`.
- **Gate:** RPC-internal `visibility_class` ceiling on `detail`/`body`/`diff`; the MCP `body` channel serves only `public`/`active_members` classes + locked versions. Read-only.

### `document_version_write` (W)
- **Intent:** author document versions + the manual-version 2-of-N flow. **`action`:** `create` · `edit` (both → `upsert_document_version`) · `delete` (→ confirm) · `lock` · `propose_manual` · `confirm_manual` (→ confirm) · `cancel_manual` · `recirculate` (`dry_run` default true).
- **Absorbs:** `propose_new_version` + `edit_document_version_draft` (alias split collapsed) · `delete_document_version_draft` · `lock_document_version` · `propose_manual_version` · `confirm_manual_version` · `cancel_manual_version_proposal` · `recirculate_governance_doc`.
- **Gate:** proactive `canV4()` — `manage_member` for version drafts/lock/recirculate, `manage_platform` for the manual-version flow. `delete` + `confirm_manual` confirm-gated (ADR-0018).

### `document_comment` (W)
- **Intent:** clause-anchored review comments. **`action`:** `add` · `resolve` · `list`.
- **Absorbs:** `add_document_comment` (→ `create_document_comment`) · `resolve_document_comment` · `list_document_comments`.
- **Gate:** `participate_in_governance_review` (add) / author-or-review (resolve), RPC-internal. Visibility enum corrected (see above).

### `change_request` (W)
- **Intent:** CR submission, listing, lifecycle review, and quorum signoff. **`action`:** `submit` · `list` · `review` (`review_action` = `approve|reject|request_changes|withdraw|resubmit` — **no `implement`**; publish via the 2-of-N Manual flow) · `approve` (`vote` = `approved|rejected|abstained`, sponsor-quorum).
- **Absorbs:** `submit_change_request` · `list_change_requests` (→ `get_change_requests`) · `review_change_request` · `approve_change_request` (review/approve absorbed post-#1397, migration `20260805000462`).
- **Gate (RPC-internal, all fail-closed):** submit = `curate_content`/manager/tribe_leader/superadmin; review = `manage_platform`/`curate_content`/`sponsor`/`chapter_liaison`; approve = `participate_in_governance_review` (only sponsor×sponsor approvals count toward quorum). `cr_type` + `impact_level` enums corrected.

### `signature_flow` (W)
- **Intent:** IP-ratification / cooperation-agreement approval-chain signing. **`action`:** `sign` · `pending` · `my_signatures` · `chain_audit`.
- **Absorbs:** `sign_ratification_gate` (→ `sign_ip_ratification`) · `get_pending_ratifications` · `list_my_signatures` (→ `get_my_signatures`) · `get_chain_audit_report`.
- **Gate:** RPC-internal `_can_sign_gate` + sequential-gate order + EU Art. 49(1)(a) consent for external_signer gates.

### `certificate_manage` (R/W)
- **Intent:** certificate lifecycle. **`action`:** `issue` (→ confirm) · `update` (→ confirm) · `verify` (public) · `list` · `my` · `timeline`.
- **Absorbs:** `issue_certificate` · `update_certificate` · `verify_certificate` · `get_all_certificates` · `get_my_certificates` · `exec_cert_timeline`. (`counter_sign_certificate` stays raw — Lorena-only.)
- **Gate:** `curate_content` / manager / superadmin (issue/update/list/timeline), RPC-internal; `verify` is public + rate-limited. Inputs validated before dispatch (see above).

### `ip_exclusion` (R/W)
- **Intent:** PI-exclusion declarations + Anexo I (doc7 / ADR-0101). **`action`:** `list` · `get` · `create` · `add_asset` (digest-only SHA-256) · `revoke` (→ confirm, terminal) · `export`.
- **Absorbs:** `list_my_exclusion_declarations` · `get_exclusion_declaration` · `create_exclusion_declaration` · `register_exclusion_asset` · `revoke_exclusion_declaration` · `export_anexo_i`.
- **Gate:** declarant self-service (RPC-internal); a `view_pii` admin gets an org-fenced read, logged to `pii_access_log`.

---

## Wave 6a — Comms / drive / partners (7 tools, `nucleo-ia-semantic` v0.8.0, ef 2.86.0)

The first half of the long tail (§2.6). Authority audited live 2026-07-17 (`pg_get_functiondef`): the comms
readers gate on comms authority (`manage_comms|manage_member|write_board`), partner reads on `view_partner`,
partner/webinar/idea/drive writes on the RPC's own internal gate (`manage_comms`/`manage_event`/`manage_partner`/
`manage_platform`). The semantic layer passes through and surfaces the RPC's own `{error}`/RAISE in `ok:false`.

**Raw-side hardening rode along in migration `20260805000460`, proven live (impersonated, rolled back):**
- `search_partner_cards` was SECURITY DEFINER with **no `EXECUTE` grant to authenticated** (unreachable) **and no
  confidential filter** on the `board_items` join. Added the #785 gate (`rls_can_see_item(bi.id)`, ADR-0105) and
  granted it to `authenticated` (REVOKE anon/PUBLIC) so `partner_crm` search is reachable AND confidential-safe.
- The webinar/idea write RPCs (`create/update/review_webinar_proposal`, `convert_proposal_to_webinar`,
  `update_webinar_comms_assets`, `advance_idea_stage`, `fork_idea_to_channel`, `link_idea_to_series`,
  `propose_publication_idea`) had drifted onto a **PUBLIC/anon `EXECUTE` grant**. All already reject a caller
  whose `auth.uid()` has no member (fail-closed), so this was defense-in-depth: REVOKE anon/PUBLIC + re-GRANT
  authenticated (the PUBLIC-default trap, #965).
- **Enum correction:** the raw `log_partner_interaction` advertised `document`/`other`, which fail the live
  `partner_interactions_interaction_type_check` on every call. Both the raw tool schema and `partner_crm` now use
  the live CHECK enum (`email|whatsapp|linkedin|call|meeting|note|status_change`).
- **Ownership gate:** the Service-Account Drive writers `upload_text_to_drive_folder` + `create_drive_subfolder`
  were gated only by `rls_is_member` (any authenticated member could write to any named folder). They now require
  `write_board`/`manage_event`/`manage_member`.

**Deliberately kept raw (not surfaced semantically):** `upload_text_to_drive_folder` + `create_drive_subfolder`
(Service-Account operations — but hardened above); `provision_initiative_drive` + `reconcile_initiative_drive_access`
(multi-step SA orchestrations, #1376/ADR-0124; the auto-grant cron uses the ADR-0028 bypass, not this path);
`create_notification` (shared low-level helper; the authenticated-user spoofing surface is tracked as a follow-up,
not patched mid-wave).

### `comms_report` (R)
- **Intent:** comms dashboards/metrics/pipeline/member-card. **`scope`:** `dashboard` · `metrics_by_channel` · `pipeline` · `pending_webinars` · `member_card` (query|person_id) · `campaign` (send_id) · `notifications` (window_days).
- **Absorbs:** `get_comms_dashboard` (→ `get_comms_dashboard_metrics`) · `get_comms_metrics_by_channel` (→ `comms_metrics_latest_by_channel`) · `get_comms_pipeline` · `get_comms_pending_webinars` (→ `webinars_pending_comms`) · `get_member_comms_card` · `get_campaign_analytics` · `get_notifications_analytics`.
- **Gate:** comms authority (`manage_comms|manage_member|write_board`); confidential rows excluded by RPC-internal filters (mig 447 / comms_pipeline). Read-only.

### `comms_post` (W)
- **Intent:** scheduled social posts + tribe notifications. **`action`:** `schedule` · `cancel` · `list` · `notify_tribe`.
- **Absorbs:** `schedule_comms_post` · `cancel_scheduled_comms_post` · `list_scheduled_comms_posts` · `send_notification_to_tribe` (→ loops `create_notification`).
- **Gate:** `manage_comms` for schedule/cancel/list; `write` for notify_tribe (tribe-scoped). Warns that IG collab/user-tags/story link-stickers + LinkedIn mentions are manual-only (#1374).

### `webinar_manage` (W)
- **Intent:** webinar proposal lifecycle. **`action`:** `create` · `update` · `review` · `convert` · `list` · `list_tribe` · `update_assets`.
- **Absorbs:** `create/update/review_webinar_proposal` · `convert_proposal_to_webinar` · `list_webinar_proposals` · `list_tribe_webinars` (→ `list_webinars_v2`) · `update_webinar_comms_assets`.
- **Gate:** `manage_event` for review/convert; `write_board|manage_event|manage_member` for update_assets; create/update open to active members (RPC scopes proposer/committee). `format_type` is a Zod enum.

### `idea_pipeline` (R/W)
- **Intent:** publication/content idea funnel + research pipeline. **`action`:** `list` · `propose` · `advance` · `fork` · `link_series` · `research`.
- **Absorbs:** `get_idea_pipeline` · `propose_publication_idea` · `advance_idea_stage` · `fork_idea_to_channel` · `link_idea_to_series` · `get_research_pipeline` (→ `get_global_research_pipeline`).
- **Gate:** any active member proposes; advance-to-approved/published + research are RPC/committee-gated. Enforces the `source_type` XOR `source_id` pairing before dispatch; `source_type`/`new_stage` are Zod enums of the live CHECKs.

### `drive_links` (R/W)
- **Intent:** link/register Drive folders & files. **`action`:** `link_initiative` · `unlink_initiative` · `list_initiative` · `link_board` · `unlink_board` · `list_board` · `register_file` · `list_files` · `discoveries`.
- **Absorbs:** `link/unlink/get_initiative_drive_links` · `link/unlink/get_board_drive_links` · `register_card_drive_file` · `list_card_drive_files` · `list_drive_discoveries`.
- **Gate:** RPC-internal (`manage_member` OR `write`/`board_admin` for links; #785 on reads). SA text-upload + subfolder-create stay raw (hardened above).

### `drive_access_admin` (W)
- **Intent:** ADR-0124 provisioning ledger + revocations (#1376). **`action`:** `list_grants` · `grant_health` · `approve_revocation` · `bulk_approve_revocation` · `revocation_pending` · `discovery_health`.
- **Absorbs:** `admin_list_membership_drive_grants` · `get_membership_drive_grant_health` · `approve/bulk_approve_drive_revocations` · `list_drive_revocation_pending` (→ `admin_list_drive_revocation_audit`) · `get_drive_discovery_health`.
- **Gate:** `manage_platform` OR `manage_member` (GP/DPO), each RPC re-enforces. `provision_initiative_drive`/`reconcile_initiative_drive_access` stay raw (SA orchestrations).

### `partner_crm` (R/W)
- **Intent:** partner entities, interactions, pipeline, card links. **`action`:** `search` · `list_cards` · `card_partners` · `pipeline` · `followups` · `interactions` · `manage` (entity_action) · `log_interaction` · `link_card` · `unlink_card`.
- **Absorbs:** all 11 partner tools (`manage_partner` → `admin_manage_partner_entity` · `log_partner_interaction` → `add_partner_interaction` · `list_partner_interactions` → `get_partner_interactions` · `get_partner_pipeline` · `get_partner_followups` · `search_partner_cards` · `link/unlink_partner_to_card` · `list_partner_cards` · `list_card_partners`).
- **Gate:** reads `view_partner`, writes `manage_partner`; #785 on the card joins. `interaction_type`/`entity_type`/`status`/`link_role` are Zod enums (interaction_type = the live CHECK).

---

## Wave 6b — Knowledge / gamification / admin / audit / lgpd (5 tools + `knowledge_search` intent, `nucleo-ia-semantic` v0.9.0, ef 2.87.0)

The second half of the long tail (§2.6) — the final wave. Authority audited live 2026-07-17 (`pg_get_functiondef`):
every absorbed reader self-gates internally (`manage_platform` / `view_internal_analytics` / `view_chapter_dashboards`
/ `manage_member` / self-scope); the semantic layer passes through and surfaces the RPC's own `{error}`/RAISE in
`ok:false`. Public feeds (`get_public_impact_data`, `get_public_trail_ranking`, `get_cpmai_leaderboard`) stay anon by
design. The `knowledge_search` intent is delivered by **expanding the existing `search_nucleo_knowledge` bridge
in place** (kept name — connectors pin it; the additive/never-break principle) with a `mode` discriminator.

**Raw-side hardening rode along in migration `20260805000461`, proven live (impersonated, rolled back):**
- `knowledge_assets_latest` was SECURITY DEFINER with **only `service_role` EXECUTE**, so authenticated MCP callers
  hit `permission denied` (2/2 fails/180d). Its content is non-personal narrative knowledge (ADR-0010) — GRANT
  authenticated. Proven: authenticated call now returns rows.
- REVOKE the #965 anon/PUBLIC `EXECUTE` drift on **10 fail-closed admin/audit/lgpd RPCs**
  (`exec_cycle_report`, `export_audit_log_csv`, `get_admin_dashboard`, `get_audit_log`, `get_my_pii_access_log`,
  `get_vep_divergence_report`, `get_volunteer_funnel_stats`, `list_ai_suggestions`,
  `lgpd_execute_retroactive_deletion`, `lgpd_record_retroactive_notification`). Each already RAISEs / returns
  `Unauthorized` for a caller with no member or without the capability (fail-closed), so this is defense-in-depth
  (the PUBLIC-default trap, #965). Proven: anon EXECUTE now false on `get_admin_dashboard` +
  `lgpd_execute_retroactive_deletion`; the public feeds remain anon-true.

**Re-grounding discipline (failure-in-log ≠ live bug):** `lgpd_record_retroactive_notification`'s
`pii_access_log_accessor_id_fkey` failure (1/2, 180d) was **already fixed in the live body** (the p239b hotfix uses
`members.id` for `accessor_id`, not `auth.uid()`) — NOT re-fixed. `award_champion`'s `invalid_criteria` (2/5) is a
**legitimate user error** (a criterion slug outside `champion_criteria_catalog` for the surface), not a masked bug.
`get_cycle_report`/`exec_cycle_report` statement-timeouts are surfaced as-is (pass-through), not materialized.

**Deliberately kept raw/frozen (not surfaced):** `knowledge_insights_overview`/`knowledge_insights_backlog_candidates`
(internal ops-improvement backlog, dead, service-role — not narrative knowledge); `counter_sign_certificate`
(Lorena-only, W5). `create_notification` authenticated-user spoofing stays a follow-up.

### `search_nucleo_knowledge` (R) — the `knowledge_search` intent
- **Intent:** unified knowledge search + page fetch + latest assets. **`mode`:** `search` (default; hub/wiki/knowledge_assets full-text) · `page` (`path` → one wiki page in full) · `latest` (`asset_source?` → most-recent knowledge_assets).
- **Absorbs (new in W6b):** `get_wiki_page` (mode=page) · `knowledge_assets_latest` (mode=latest). Search modes unchanged (`search_hub_resources`/`search_wiki_pages`/`knowledge_search_text`).
- **Gate:** Tier-1 authenticated read; wiki = narrative only (ADR-0010). PII-clean. Kept the bridge name (no break).

### `gamification_report` (R)
- **Intent:** XP / rankings / champions / rules. **`scope`:** `mine` · `member_xp` (member_id) · `member_pillars` (member_id [+ cycle_code, xp_scope]) · `member_champions` (member_id) · `champions_ranking` ([scope_kind, scope_id, cycle_code, limit]) · `rules` · `initiative` (initiative_id) · `tribe` (tribe_id) · `cpmai_leaderboard` ([course_id]) · `trail_ranking`.
- **Absorbs:** `get_my_gamification_stats` · `get_member_cycle_xp` · `get_member_xp_pillars` · `get_member_champions_history` · `get_champions_ranking` · `get_gamification_rules_catalog` · `get_initiative_gamification` · `get_tribe_gamification` · `get_cpmai_leaderboard` · `get_public_trail_ranking`.
- **Gate:** self free; cross-member XP requires `view_pii` (RPC-internal); aggregates + leaderboards public-safe by design (LGPD `gamification_opt_out` respected). Read-only.

### `champion_award` (W)
- **Intent:** award / revoke a champion. **`action`:** `award` (recipient_id + surface + context_kind + context_id + criteria_met[] + justification≥50) · `revoke` (champion_id + reason).
- **Absorbs:** `award_champion` · `revoke_champion`.
- **Gate:** RPC-internal — `general` surface requires an org-scope `award_champion` grantor; `tribe`/`deliverable` require `award_champion` on the target initiative; revoke = grantor-within-window OR platform admin. **Merit-immutability:** a champion recognizes work the recipient DID; awards are additive and never transfer completed-work credit.

### `admin_dashboard` (R)
- **Intent:** GP / analytics cockpit. **`scope`:** `admin` · `annual_kpis` · `chapter` · `chapter_needs` · `in_dashboard` · `vep_divergence` · `volunteer_funnel` · `volunteer_funnel_stats` · `role_transitions` · `cycle_report` · `exec_cycle_report` · `cycle_evolution` · `public_impact` · `ai_suggestions` · `ai_processing_log`.
- **Absorbs:** `get_admin_dashboard` · `get_annual_kpis` · `get_chapter_dashboard` · `get_chapter_needs` · `get_in_dashboard` · `get_vep_divergence_report` · `get_volunteer_funnel` (→ `volunteer_funnel_summary`) · `get_volunteer_funnel_stats` · `get_role_transitions` (→ `exec_role_transitions`) · `get_cycle_report` · `exec_cycle_report` · `get_cycle_evolution` · `get_public_impact_data` · `list_ai_suggestions` · `list_ai_processing_log`.
- **Gate:** RPC-internal (`manage_platform` / `view_internal_analytics` / `view_chapter_dashboards`; COI recusal on `vep_divergence`). Numbers come from the live RPC (grounding rule — never recited). Read-only.

### `audit_log` (R)
- **Intent:** audit + PII-access logs. **`scope`:** `my_pii_access` (self, free) · `audit` (org trail) · `pii_access_admin` (DPO PII-access review) · `export_csv` (audit CSV).
- **Absorbs:** `get_my_pii_access_log` · `get_audit_log` · `get_pii_access_log_admin` · `export_audit_log_csv`.
- **Gate:** self-view free; admin views `manage_platform`; export = `view_pii` + GP/sede (the RPC returns an `Unauthorized` TEXT string on deny — surfaced as `ok:false`). Read-only.

### `lgpd_admin` (W, DESTRUCTIVE)
- **Intent:** LGPD Art.18 retroactive operations. **`action`:** `record_notification` (application_id + template_version + lang [+ method, dispatched_at]) · `execute_deletion` (application_id + video_id + deletion_reason≥8 [+ drive_deletion_ref]; **confirm-gated**).
- **Absorbs:** `lgpd_record_retroactive_notification` · `lgpd_execute_retroactive_deletion`.
- **Gate:** PROACTIVE `canV4(manage_member)` fail-fast (GP/DPO) + the RPC's own `manage_member` gate. `execute_deletion` returns a preview unless `confirm=true` (ADR-0018) — it clears a video-screening transcription (irreversible, Art.18 §IV); Drive-file removal is a separate operator step. Every call writes a `pii_access_log` row.

---

## Wave plan (usage-validated order)

| Wave | Family | Status |
|---|---|---|
| 0 | Bridge (`get_my_context`, `search_nucleo_knowledge`, `get_board_or_initiative_context`, `get_operational_status`) | shipped (SPEC-280) |
| **1** | **Boards & cards** | **shipped 2026-07-15** |
| **2** | **Members / engagements / initiatives** | **shipped 2026-07-16** |
| **3** | **Events / attendance / meetings** | **shipped 2026-07-16** |
| **4** | **Selection & evaluation** | **shipped 2026-07-17** |
| **5** | **Governance / docs / certificates** | **shipped 2026-07-17** |
| **6a** | **Comms / drive / partners** | **shipped 2026-07-17** |
| **6b** | **Knowledge / gamification / admin / audit / lgpd** | **shipped 2026-07-17 (final wave)** |

Per-wave exit criteria (all 8 must tick): authority/RLS audited · envelope contract test green ·
256-cap headroom · deprecation wiring (no breakage) · docs shipped (this file + matrix + `rules/mcp.md` + wiki) ·
usage healthy ≥2 weeks post-deploy · security regression scan clean · grounding discipline (numbers re-queried live).

_Cross-ref: EPIC #1383, SPEC-280, ADR-0105 (#785), ADR-0007 (can/can_by_member), `.claude/rules/mcp.md`._
