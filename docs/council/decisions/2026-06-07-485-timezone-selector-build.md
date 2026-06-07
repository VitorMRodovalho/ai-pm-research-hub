# Decision — #485 timezone selector: build (full slice), IANA-searchable + display badge

- **Date:** 2026-06-07
- **Issue:** #485 (Event scheduling: flexible recurrence + timezone selector + Google Calendar sync)
- **Decider:** PM (Vitor) — decision loop per [[working-agreement-decision-process-2026-06-07]]
- **Role split:** Council/grounding brought options; I (PL/CTO) recommended; PM decided.

## Context (grounded live before options — never assumed)

Live queries this turn (prod `ldrfrvwhxsmgaabwmaik`):

| Signal | Value | Source |
|---|---|---|
| Events by timezone | **384/384 = `America/Sao_Paulo`** (37 future, all BRT) | `SELECT timezone, count(*) FROM events GROUP BY 1` |
| Organizations | **1** (`nucleo-ia`), `country=BR`, `primary_language=pt-BR` | `organizations` |
| Federated chapters | `[PMI-GO, PMI-CE, PMI-DF, PMI-MG, PMI-RS]` — **all Brazilian, all UTC-3** (BR has no DST since 2019) | `organizations.federated_chapters` |
| `organizations.timezone` | **does not exist** | `information_schema.columns` |
| `members.timezone/locale/country` | **do not exist** | `information_schema.columns` |
| `events.timezone` column | exists, default `America/Sao_Paulo`, `events_timezone_check` requires a `/` | `pg_constraint` |
| Recurrence-frequency pain | **already shipped (#414)** — semanal/quinzenal/mensal | merged PR #558 |

Issue #485 has three parts: (1) flexible recurrence — **done via #414**; (2) explicit timezone selector — this decision; (3) Google Calendar sync — larger, depends on #472 webhook infra, stays backlog.

## Options presented

- **A — Defer the selector with an explicit trigger + close the loop** (no build). Restructure #485: part-1 done, part-2 deferred until first non-UTC-3 chapter / international session, part-3 stays linked to #472.
- **B — Minimal `p_timezone` param (backend-only)**, no UI. Pre-positions the data path.
- **C — Full build**: tz selector in all 3 event modals + `p_timezone` on both create RPCs + i18n + display.

## Recommendation (PL/CTO) → A

Grounding-first revealed **zero current demand**: single org, 5 federated chapters all UTC-3, 384/384 events BRT, no timezone on members/orgs, and `events.timezone` already defaults correctly. A selector 100% of users leave on the default is speculative complexity (YAGNI). The real user pain (recurrence frequency) shipped in #414. Counter-consideration flagged: if an international / non-UTC-3 chapter is already on the PM's radar (strategic info not in the data), the cheap hedge is B.

## Decision → **C (full build)**

PM chose the full build with the data on the table — an informed override, consistent with the platform's international positioning and the deliberate sequencing of #485 first. I accept (the data case for A was made; not re-litigated).

### Design forks (aligned via AskUserQuestion, same turn)

1. **Timezone list → IANA full, searchable.** `<input list>` + `<datalist>` populated from `Intl.supportedValuesOf('timeZone')` (no per-zone i18n; raw IANA values). Curated short-list was the alternative.
2. **Display → badge when tz ≠ `America/Sao_Paulo`.** Card + edit (detail) surface show `HH:MM (City)` for non-BRT events; BRT stays badge-free. Input-only was the alternative.

### Engineering constraints honored

- `events_timezone_check` regex requires a `/`, so bare `UTC`/`GMT` would violate it. The picker filters to slash-containing IANA zones (UTC users pick `Etc/UTC`); a client-side `isValidTimeZone()` (try/catch `Intl.DateTimeFormat`) guards all three write paths (create / recurring / edit) against free-typed garbage; the create RPCs additionally coerce NULL/PG-unknown zones to the `America/Sao_Paulo` default (fail-safe — never block event creation). No CHECK-constraint change needed.
- `get_events_with_attendance` did not return `timezone` → added (so the card badge + edit populate can read it).

## Execution

- Migration `20260805000126_p485_event_timezone_selector.sql` — DROP+CREATE `create_event`, `create_recurring_weekly_events` (+`p_timezone`), `get_events_with_attendance` (+returned `timezone`).
- Frontend: `NewEventModal` / `RecurringModal` / `EditEventModal` tz input + shared datalist; `attendance.astro` callsites, edit populate/save, card badge; `database.gen.ts` type patch; i18n ×3.
- PR: (filled at merge). 0 `--admin`.

## Council review (code-reviewer + data-architect + security-engineer)

- **BLOCKER (fixed in-PR):** `get_events_with_attendance` is SECURITY DEFINER with no body auth gate and bypasses RLS — it returns ALL events incl. `external_attendees` (PII), `meeting_link`, and `gp_only` events. The live ACL already carried `=X` (PUBLIC) + `anon` (pre-existing exposure, not introduced by this PR; my initial DROP+CREATE would have perpetuated it). Closed: `REVOKE EXECUTE … FROM PUBLIC, anon; GRANT … TO authenticated, service_role;`. Verified live (ACL = `postgres | authenticated | service_role`; sole caller is the authenticated `/attendance` page).
- **HIGH (fixed in-PR):** timezone now propagates to future siblings on the "this + future" edit scope (parity with how `time_start` propagates via `update_future_events_in_group`, which has no `p_timezone`) — a direct group-scoped `.update({timezone}).gt('date', date)`.
- **LOW (folded):** `escapeAttr` on the datalist option builder; edit save writes `timezone || DEFAULT_TZ` (clearing the field resets to BRT); rollback DROP signatures enumerated in the migration header.
- **Kept (not changed):** `create_event` / `create_recurring_weekly_events` retain the `anon` grant — both have the fail-closed `auth.uid()` body gate (anon → Unauthorized) and follow the documented #414 precedent; unlike `get_events_with_attendance`, they are not a data-read exposure.

## Follow-ups (backlog)

- **Pre-existing authz gap (security-engineer):** `events_v4_org_scope` (cmd=ALL, role=public, org-scope-only check) lets any authenticated member of the org UPDATE/DELETE events directly via PostgREST, bypassing `can_by_member('manage_event')`. Affects the whole events edit surface (every field the edit path writes), not just timezone — out of scope here; file a tracked security issue.
- **Edit-path server-side coerce:** add `p_timezone` to `update_event` / `update_future_events_in_group` so the edit path runs the same `pg_timezone_names` coerce as create (today edit relies on the column CHECK + client `isValidTimeZone`).
- **ADR-0011 inline-migrate** `create_recurring_weekly_events` auth (drop `is_superadmin` / raw `operational_role` checks → `can_by_member`) on its next touch.
- **INV-27 (data-architect):** optional `check_schema_invariants()` entry for `events.timezone` validity (`NOT EXISTS pg_timezone_names`) — needs the 3-file invariant-count bump.
- Part-3 Google Calendar sync (#485) stays open, linked to #472.
- If a non-UTC-3 chapter onboards, consider `organizations.default_timezone` to pre-seed the picker default per chapter.
