# Recurring Meeting Agenda — Source of Truth & Reconciliation Routine

> Governance reference for the integrated recurring-agenda model of tribes and initiatives.
> Satisfies **#676** acceptance criterion #8 ("Docs de governança explicam fonte de verdade e
> rotina de reconciliação"). Implemented by migrations `…164`–`…167`, `…170` (#676 Foundation +
> Slice 4) and the leader self-service panel `#696` (Slice B).

## 1. Canonical source of truth

`public.recurring_meeting_rules` is the **single canonical model** for the weekday/time/frequency
of every recurring tribe and initiative meeting. It is authoritative over both `events` and
`tribe_meeting_slots`.

| Concern | Where it lives | Authority |
|---|---|---|
| The recurrence **rule** (weekday, time, duration, frequency, parity, link, status) | `recurring_meeting_rules` | **Authoritative** |
| Materialized future occurrences (presence, atas, timeline, artefatos) | `events` | **Derived** — generated/reconciled from the rule |
| Weekly visual slot per tribe | `tribe_meeting_slots` | **Derived cache** — one slot per `(tribe_id, day_of_week)`, synced from the rule (PM decision, #676) |

Key columns of `recurring_meeting_rules`:

- `scope_type ∈ {tribe, initiative, general, leadership}` (+ `initiative_id` / `tribe_id` refs, enforced by `rmr_scope_refs`).
- `day_of_week` is **ISO** (1=Mon … 7=Sun), matching `extract(isodow)`.
- `frequency ∈ {weekly, biweekly}`; **biweekly parity is stored explicitly** via `anchor_date`
  (a real occurrence; every occurrence is `anchor_date + 14·k`). This removes the historical
  ambiguity where quinzenais had no stored parity.
- `status ∈ {active, paused, archived}` — only `active` rules generate events.
- `meeting_link` — the canonical Meet link (replaces the WhatsApp/Calendar-confirmed link drift).

All changes to a rule are captured in `public.recurring_meeting_rule_audit` (insert/update/delete
trigger; RLS admin-read).

## 2. Reconciliation routine

Events are never hand-seeded into the future anymore (that was the #630 ad-hoc-migration
anti-pattern). They are **generated and rolled forward idempotently** from the rules:

| RPC | Who | What |
|---|---|---|
| `reconcile_recurring_meeting(rule_id, horizon_end)` | Leader-scoped (V4) | Generate/extend `events` for **one** rule up to the horizon. Idempotent — never duplicates an existing occurrence; respects biweekly parity from `anchor_date`. |
| `reconcile_all_recurring_meetings(horizon_end)` | GP / cron | Loop over all `active` rules. Default horizon = `current_date + 60`. |
| `reconcile_recurring_meetings_cron()` | `service_role` only | Cron wrapper; logs a run summary. |
| `get_recurring_meeting_drift(...)` | Admin/leader | Compares a rule against its materialized events and reports drift / duplicates. |
| `get_recurring_meeting_admin_list()` | Leader-scoped | Admin "Agenda recorrente" list: rule, próxima ocorrência, link, status, `last_reconciled_at`. |

**Automatic roll-forward:** pg_cron job **`reconcile-recurring-meetings-weekly`** runs
`reconcile_recurring_meetings_cron()` once a week, extending the operational calendar to
`current_date + 60` without any manual reconcile. Each run is recorded in the audit log
(`recurring_meeting.cron_reconcile`).

**Manual reconcile:** a leader editing their own scope (via the #696 self-service panel or
`create_recurring_meeting_rule` / `update_recurring_meeting_rule`) can run
`reconcile_recurring_meeting` for the affected rule immediately; the per-rule reconcile is logged
with `action='reconcile'` and feeds `last_reconciled_at`.

## 3. Authority (V4)

Write/reconcile of a rule is gated by V4 authority, scoped to the rule's tribe/initiative:

- A **tribe/initiative leader** may create, edit, pause, archive and reconcile **only the rules of
  their own scope** (enforced by the leader-scoped gate in `…167`/`…170`).
- **GP** (`manage_platform`) sees and reconciles all scopes, plus `general`/`leadership` rules.
- The cron path runs as `service_role` (no `auth.uid()` → GP-equivalent reconcile path).

The auth gate uses the canonical V4 helpers, not a bespoke check — see
[`V4_AUTHORITY_MODEL.md`](./V4_AUTHORITY_MODEL.md).

## 4. Operating rules (do / don't)

- **DO** create future recurrence by adding/updating a `recurring_meeting_rules` row, then letting
  the cron (or a manual `reconcile_recurring_meeting`) materialize events.
- **DO** treat `get_recurring_meeting_drift` as the alarm: any drift between a rule and its events,
  or any duplicate occurrence, is a reconciliation bug — fix the rule and re-reconcile, never patch
  `events` by hand.
- **DON'T** seed recurring `events` via ad-hoc migrations (the #630 stopgap). One-off non-recurring
  events are still created normally; recurring series go through the rule.
- **DON'T** edit `tribe_meeting_slots` directly to change a meeting time — it is a derived cache and
  will be overwritten on the next sync; change the rule.
- **DON'T** store the Meet link only in WhatsApp/Calendar — the canonical link is `meeting_link` on
  the rule; the homepage/agenda reads it (or a view derived from it), not a hardcode.

## 5. Cross-reference

- Issues: **#676** (this model), **#696** (leader self-service panel — Slice B), **#630** (the
  manual reconciliation that motivated the structural model).
- Migrations: `…164` (foundation: table + audit + derived-slot constraint + backfill),
  `…165` (admin list RPC), `…166` (write path V4), `…167` (security-fixed auth gate + reconcile
  cron), `…170` (leader-scoped initiative filter).
- Authority model: `docs/reference/V4_AUTHORITY_MODEL.md`.
