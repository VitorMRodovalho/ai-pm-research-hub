# ADR-0049: Meeting↔Board Traceability — Onda 2 closure (4 of 4 final RPCs)

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-27 (session p73) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | `20260514110000` (4 RPCs) + `20260514120000` (drift hotfix) |
| Cross-ref | ADR-0045 (schema), ADR-0046/0047/0048 (Onda 2 partials) |
| Closes | #84 Onda 2 (11/11, ~100%) |

## Context

#84 (Meeting↔Board traceability gap) was decomposed into 3 ondas
(documented in ADR-0045). Onda 1 hardened schema. Onda 2 was planned
as 10 RPCs and incrementally shipped through ADRs 0046/0047/0048
(7 RPCs, ~64%). This ADR closes the remaining 4 to take Onda 2
to 11/11 (the original "10 RPCs" plan was refined to 11 once
`get_meeting_preparation` was split out as ADR-0048 standalone).

Closing Onda 2 unlocks frontend integration:
* `MeetingMode` modal can now drive `update_card_during_meeting` for
  status mutations during live meetings (with traceability via
  `board_item_event_links`).
* Dashboard PM can populate "Tribe contributions to annual goals"
  via `get_tribe_housekeeping`.
* Tribe leader's pre-meeting prep page can render `get_agenda_smart`
  (substitutes the dumb `generate_agenda_template`).
* Calendar sync can trigger `meeting_close` automatically when a
  meeting ends — counting drift signals at the moment the leader
  posts minutes.

## Decision

Ship 4 RPCs in a single ADR + one migration. All are SECURITY DEFINER
with `search_path=public, pg_temp` (mirrors p72 ADRs 0046/0047/0048).

### RPC 1 — `get_agenda_smart(p_event_id)`

**Audience**: authenticated read.

Returns a smarter analogue of `generate_agenda_template`:
* `event` + `initiative` (metadata)
* `carry_forward_actions[]` — unresolved action items from prior
  meetings (90d window, kind `action`/`followup`, ordered overdue-first)
* `at_risk_cards[]` — cards in the initiative's boards with forecast
  slip (>7d after baseline) OR staleness (no update for 14d AND not
  done/archived). `risk_reasons` field surfaces *why* (forecast_slip
  in days, or stale_days)
* `relevant_kpis[]` — annual KPIs the initiative contributes to
  (via `tribe_kpi_contributions` JOIN), filtered to RED/YELLOW only
  (current < target * 0.9). Includes attainment_pct + status_color
* `showcase_candidates[]` — initiative members with recent (60d)
  completed cards AND at least one unshowcased artifact (no
  `event_showcases.board_item_id` link to that card in the past 90d)
* `at_risk_deliverables[]` — `tribe_deliverables` for the initiative
  with status NOT IN done/cancelled AND due ≤14d (or no due_date)

The function does NOT replace `generate_agenda_template`; PM may
choose to deprecate the latter once frontend migrates.

### RPC 2 — `update_card_during_meeting(p_card_id, p_event_id, p_new_status, p_fields, p_note)`

**Audience**: V4 `write_board`. Wraps existing canonical mutators.

Three input modes:
1. **Status change**: `p_new_status` provided AND different from current
   → `PERFORM public.move_board_item(...)` (handles auth + lifecycle event)
   → `link_type = 'status_changed'`
2. **Field update**: `p_fields` provided (non-empty jsonb) → `PERFORM
   public.update_board_item(...)` (handles auth + baseline lock + lifecycle)
   → `link_type = 'discussed'` (unless status was also changed)
3. **Discussion only**: both nil → just creates a `link_type='discussed'`
   row with `p_note` for traceability ("we mentioned this card")

ALL three modes always insert (or update on conflict) a row in
`board_item_event_links`. ON CONFLICT updates the `note` so re-mentions
in the same meeting overwrite with the latest context.

The auto-derived `link_note` chooses a sensible message based on what
was actually mutated. Caller may override via `p_note`.

### RPC 3 — `meeting_close(p_event_id, p_summary)`

**Audience**: V4 `manage_event`. Idempotent close.

Logic:
1. Read event + check `minutes_posted_at` (already-closed flag)
2. Count structured action items by kind (`action`/`decision`) +
   unresolved (`action`+`followup`)
3. Best-effort regex count of `- [ ]` patterns in `minutes_text`
   to compare with structured action count → `structured_drift`
   (markdown items that DON'T have a corresponding `meeting_action_items`
   row, suggesting the leader wrote checklist items in markdown but
   didn't run `create_action_item`)
4. Count `board_item_event_links` for the event + `event_showcases`
5. If not already closed: UPDATE `minutes_posted_at = now()` +
   `minutes_posted_by = caller`. Optional `p_summary` is appended to
   `events.notes` with a header `## Meeting close summary (timestamp)`
6. Returns the full counter set + flags (`already_closed`,
   `drift_signal`, `summary_appended`)

The drift signal (`structured_drift > 0`) is a TODO-list for the
GP/leader: they should either ratify the markdown items into
structured rows (next session) or accept the divergence.

### RPC 4 — `get_tribe_housekeeping(p_initiative_id, p_legacy_tribe_id)`

**Audience**: authenticated read. Closes #84 GAP 7 (annual_kpi_targets
↔ tribe linkage).

Initiative-resolution priority:
1. `p_initiative_id` (explicit, preferred — ADR-0015 native)
2. `p_legacy_tribe_id` (legacy, fallback)
3. NULL → returns `error: initiative_not_found`

Returns:
* `initiative` metadata
* `current_cycle` (best-effort: most recent active deliverable's
  `cycle_code`, falls back to `cycle3-2026`)
* `kpis_contributed[]` — full KPIs the initiative contributes to
  (via `tribe_kpi_contributions`) with attainment + status_color +
  weight + contribution_query
* `cards_linked_to_kpis[]` — best-effort heuristic: cards in the
  initiative's boards where `tags` overlap with any KPI's `kpi_key`
  registered in `tribe_kpi_contributions` for the initiative.
  `matched_kpi_keys[]` per card so frontend can render which KPI(s)
  the card serves
* `cycle_deliverables[]` — `tribe_deliverables` for the initiative
  in the current cycle, ordered: not-done first, by due date
* `rollup` — counters: kpis_total, kpis_red, kpis_yellow,
  cycle_deliverables_total, cycle_deliverables_done

The `cards_linked_to_kpis` heuristic (tag overlap) is intentionally
soft — it surfaces *candidates* but doesn't claim ground truth.
Future ADRs may introduce explicit `board_item_kpi_links` if the
heuristic proves insufficient.

## Drift hotfix (Migration `20260514120000`)

During smoke-testing, `i.name` references in 3 RPCs (this ADR's
`get_agenda_smart` + `get_tribe_housekeeping`, AND ADR-0048's
`get_meeting_preparation`) failed because `initiatives` schema
exposes `title`, not `name`. ADR-0048 had been broken in production
since p72 for any initiative-scoped event call.

Forward-only patch: `CREATE OR REPLACE FUNCTION` for all three with
`i.title` substituted. No data migration. ADR-0048's contract surface
field renames `'name'` → `'title'` in the returned `initiative`
sub-object — frontend callers reading `result.initiative.name` will
break. Since ADR-0048 was shipped <24h ago and `get_meeting_preparation`
returned NULL or errored on every initiative-scoped call (effectively
unused in production), this is a safe rename.

The pattern: when adopting a SECDEF RPC body from a sibling RPC
without per-column smoke-test (ADR-0048 → 0049 inheritance), drift
in column references propagates silently. Mitigation: smoke-test
new RPCs in DO blocks with set_config JWT before declaring done.

## Patterns sedimented

1. **Atomic close with drift counter**: `meeting_close` produces
   structural metrics + a drift signal. Pattern reusable for any
   "post-event" close where structured + freeform fields coexist.
2. **Status-derived link type**: when wrapping mutators, derive the
   linking semantic from *what was actually mutated*, not what the
   caller said they intended. `status_changed` > `discussed`.
3. **Heuristic vs ground truth (cards_linked_to_kpis)**: when explicit
   FKs are absent, surface "candidates" with the matching evidence
   (`matched_kpi_keys[]`). Frontend can render with caveats; future
   ADRs can promote to explicit FK.
4. **Smoke test via DO block + JWT injection**: `set_config('request.jwt.claims', ...)`
   simulates authenticated context for SECDEF RPCs without needing
   to run the full Worker stack. Catches column drift and auth
   logic before MCP layer adds.
5. **Forward-only column drift fix**: when sibling RPCs share body
   templates, `CREATE OR REPLACE` patch in a single migration covers
   all sibling drift. Migration timestamp must be > latest function
   redefinition for the contract test (tests/contracts/rpc-migration-coverage.test.mjs)
   to compare against.

## Consequences

**Positive**:
* #84 Onda 2 closes 11/11 (100%) → Onda 3 (UX + LLM extractor)
  becomes the sole remaining work item
* `get_meeting_preparation` regression from p72 fixed (was silent ERROR
  for any initiative-scoped event)
* Frontend `MeetingMode` modal unblocked: full traceability stack ready
* Dashboard GP "tribe contributions to annual goals" data layer ready

**Neutral**:
* `update_card_during_meeting` does NOT introduce new auth — it relies
  on the wrapped mutators' own gates (move_board_item + update_board_item).
  This means the wrapper's V4 `write_board` precheck is redundant but
  defense-in-depth doesn't hurt
* `get_agenda_smart` is *additive* — `generate_agenda_template` not
  yet deprecated; PM decides cutover timing

**Negative**:
* `cards_linked_to_kpis` is heuristic. False positives possible
  (tag overlap may not mean genuine KPI contribution). Mitigation
  documented in section above.
* ADR-0048 surface rename (`initiative.name` → `initiative.title`)
  is technically a breaking change. Rationale: function was broken
  on day-one and no production caller was actively succeeding on
  `result.initiative.name`.

## MCP layer

To be added in the same session (4 new tools, MCP v2.29.0 → v2.30.0):
* `get_agenda_smart` — authenticated
* `update_card_during_meeting` — V4 `write_board`
* `meeting_close` — V4 `manage_event`
* `get_tribe_housekeeping` — authenticated

Tool count: 153 → 157 (99R+58W).

## Rollback

```sql
DROP FUNCTION IF EXISTS public.get_tribe_housekeeping(uuid, integer);
DROP FUNCTION IF EXISTS public.meeting_close(uuid, text);
DROP FUNCTION IF EXISTS public.update_card_during_meeting(uuid, uuid, text, jsonb, text);
DROP FUNCTION IF EXISTS public.get_agenda_smart(uuid);
-- get_meeting_preparation cannot be rolled back via this ADR — the previous
-- broken body would also need restoration if rollback is required (low likelihood
-- since the ADR-0048 body was non-functional).
```

## References

* GitHub issue #84
* ADR-0045 (schema hardening) — `board_item_event_links`,
  `tribe_kpi_contributions`, `meeting_action_items` extension cols
* ADR-0046/0047/0048 — Onda 2 partial deliveries
* `docs/adr/ADR-0048-get-meeting-preparation.md` — body source
  for `get_meeting_preparation` (now hotfixed)
* `tests/contracts/rpc-migration-coverage.test.mjs` (Track Q-C) —
  ensures pg_proc bodies match latest migration definitions

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
