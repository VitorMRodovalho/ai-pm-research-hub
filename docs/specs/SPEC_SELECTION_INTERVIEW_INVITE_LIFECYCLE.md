# SPEC — Selection Interview Invite Lifecycle (UI wiring + automation)

**Status:** draft · awaiting PM ratification
**Created:** 2026-05-26 (session p270)
**Origin:** PM identified two production bugs on /admin/selection during cycle4-2026 dispatch:
1. The RPC `notify_selection_cutoff_approved` (shipped p228 W2 leaf 4 + p251 #355) has **zero UI call sites**. Only invocable via DO-block manual dispatch — that's why 7 above_band researchers sat with welcome-email-only for 21 days.
2. Candidates whose scheduled interview lapses (evaluator never accepted Google Calendar invite) get **no automatic re-invite** — they stay in `interview_scheduled` with `conducted_at IS NULL` indefinitely. Found 3 such cases in cycle4 (Rafael, Bruna, Luciana — interviews scheduled 2026-05-14, none conducted, no cancel/reschedule, candidates in the dark for 12 days).

Both gaps were closed in-session as one-shot DO-blocks (10 candidates total: 7 above_band + 3 stuck-scheduled). This SPEC codifies the permanent UI + automation layer so the manual path is no longer load-bearing.

---

## Scope (locked)

Four user-facing features + two crons. Wave-1 features (F1–F4) all live in `src/pages/admin/selection.astro` (no migrations); Wave-2 is the cron layer.

| Feature | Where | Backend already exists? |
|---|---|---|
| **F1.** Single-candidate "📧 Enviar convite p/ agendar" button in modal `Entrevista` tab | selection.astro modal | ✅ `notify_selection_cutoff_approved(uuid)` |
| **F2.** New filter chips on toolbar: "Sem entrevista" + "Stuck scheduled" | selection.astro toolbar | ✅ derived from existing fields |
| **F3.** Bulk-action "📧 Enviar convite (N)" alongside bulk-approve/reject | selection.astro bulk bar | ✅ loop over F1 RPC |
| **F4.** Single-candidate "🔄 Reenviar (cancela agendamento perdido)" button — visible when interview lapsed | selection.astro modal | ✅ `mark_interview_status(cancelled)` + clear `cutoff_approved_email_sent_at` + `notify_selection_cutoff_approved` |
| **V2.a** Cron `selection-cutoff-pending-daily` (daily 14:00 UTC) | new migration + pg_cron | ✅ wraps F1 RPC |
| **V2.b** Cron `selection-stuck-scheduled-rescue-daily` (daily 15:00 UTC, after cutoff cron) | new migration + pg_cron | ✅ wraps F4 pattern |

**Out of scope (explicit):**
- Per-evaluator booking_url admin UI → already roadmapped at #348 Steps 2–4
- In-band auto-invite policy → PM/GP decision, never automated
- New email templates → existing `selection_cutoff_approved` reused for both fresh + re-dispatch
- Touching `request_interview_reschedule` flow (that's for candidate-initiated reschedule, different semantics)

---

## Waves & gates (QA/QC tracking)

Each wave is a separable PR with its own merge gate. Sub-issues per wave for visibility.

### Wave 1a — Modal single-dispatch (F1)
**Smallest viable slice — gates the rest.**

| Gate | Pass criteria |
|---|---|
| Build | `npx astro build` ✓ 0 new errors |
| i18n | 5 new keys added to all 3 dictionaries (`admin.selection.modal.cutoffInvite{Btn,Sent,Toast,Error,Confirm}`) |
| Render gate | Button visible iff `status IN ('screening','interview_pending') AND cutoff_approved_email_sent_at IS NULL AND no active interview row` |
| Sent state | When `cutoff_approved_email_sent_at IS NOT NULL`, button replaced with badge `✓ Convite enviado em DD/MM HH:mm` |
| RPC binding | Click calls `sb.rpc('notify_selection_cutoff_approved', {p_application_id: row.id})` |
| Idempotency | Pre-sent state respects RPC's `already_sent` early-return; UI does NOT re-call without explicit override |
| Override | 2-click confirm flow for explicit re-send (sets `cutoff_approved_email_sent_at = NULL` via separate admin RPC `admin_reset_cutoff_dispatch` — TBD: ship in Wave 1a or defer to Wave 4) |
| Toast | Success: "Convite enviado para X" / Error surfaces RPC raise message |
| Contract test | New `tests/contracts/cutoff-approved-modal-button.test.mjs` — assert button selector + RPC name + render predicate + 3 i18n parity |

### Wave 1b — Toolbar filter chips (F2)
**Independent UI work; no RPC.**

| Gate | Pass criteria |
|---|---|
| Two new chips | "Sem entrevista" (default OFF) + "Stuck scheduled" (default OFF) following the `filter-hide-decided` / `filter-interview-today` pattern at selection.astro:297-299 |
| Sem entrevista predicate | `interview_status IN ('none','needs_reschedule') AND status NOT IN ('rejected','approved','interview_done','final_eval')` |
| Stuck scheduled predicate | `app.status = 'interview_scheduled' AND latest_interview.scheduled_at < now() AND latest_interview.conducted_at IS NULL AND latest_interview.status = 'scheduled'` (computed client-side from row data already returned by `get_selection_dashboard`) |
| i18n | 4 new keys × 3 dictionaries |
| Filter chip stack | Combines additively with researcher/leader/myEval filters |
| Empty-state msg | When stuck-scheduled selected and 0 results: "Nenhum candidato com agendamento expirado" |
| Contract test | Predicate isolation test + i18n parity |

### Wave 1c — Bulk dispatch (F3)
**Depends on Wave 1a being shipped (uses same RPC).**

| Gate | Pass criteria |
|---|---|
| Bulk button | "📧 Enviar convite (N)" appears in bulk bar when ≥1 selected (alongside existing bulk-approve/reject/waitlist at selection.astro:374-377) |
| Pre-confirm | `confirm()` shows count + first 3 names (e.g., "Enviar convite para 5 candidatos: LUIZ, Luana, Andre, e mais 2?") |
| Loop | Iterates selection, calls F1 RPC per app, aggregates `{sent, skipped_already_sent, error_count}` |
| Result toast | Aggregate: "Enviados: X · Já dispatchados: Y · Erros: Z" |
| Idempotency safety | Skipped already-sent rows do NOT count as errors (delegated to RPC's `already_sent` reason) |
| Error isolation | One failure does NOT abort the loop (try/catch per-iteration) |
| Race | Disables button + shows "Enviando…" during loop |
| Contract test | Aggregate handler shape + RPC call count assertion |

### Wave 1d — Stuck-scheduled rescue (F4)
**Depends on Wave 1a (uses same dispatch RPC after pre-cleanup).**

| Gate | Pass criteria |
|---|---|
| Visibility predicate | Button on modal `Entrevista` tab when `latest_interview.scheduled_at < now() AND conducted_at IS NULL AND interview.status = 'scheduled'` |
| Pre-confirm | "Cancelar entrevista perdida e reenviar convite a [name]? — A entrevista anterior será marcada como cancelled e o candidato receberá novo email." |
| Pattern | Atomic 3-step: `mark_interview_status(intv_id, 'cancelled', '[admin re-dispatch — invite not accepted]')` → `admin_reset_cutoff_dispatch(app_id)` → `notify_selection_cutoff_approved(app_id)` |
| Atomic helper | One new SECDEF RPC `selection_rescue_stuck_interview(p_application_id)` wrapping all 3 steps with try/rollback, so UI calls once and gets aggregate result. Migration scope. |
| canV4 gate | RPC validates committee lead OR `manage_member` (same ladder as `notify_selection_cutoff_approved`) |
| Audit | Single new action `selection.stuck_interview_rescued` with metadata `{interview_id, prior_scheduled_at, new_dispatch_path, resolved_evaluator_id}` |
| Toast | "Entrevista anterior cancelada · novo convite enviado" |
| Contract test | RPC existence + 3-step body + audit action literal + canV4 gate + forward-defense against omitting `cutoff_approved_email_sent_at = NULL` reset |

### Wave 2a — Cron `selection-cutoff-pending-daily`
**Independent of Wave 1; can ship in parallel.**

| Gate | Pass criteria |
|---|---|
| Migration | Wrapping function `_selection_cutoff_pending_cron()` — SELECT apps where `status IN ('screening','interview_pending') AND objective_score_avg >= pert_target_score AND cutoff_approved_email_sent_at IS NULL AND cycle.status = 'open'` LIMIT 50 |
| pg_cron schedule | Daily 14:00 UTC (after PERT recompute weekly cron `47` finishes) — register in `cron.job` |
| Policy | **Strict above-target only**, NOT in_band (in_band requires GP decision per PM directive) |
| Idempotency | Each iteration delegates to `notify_selection_cutoff_approved` whose own idempotency gate (`cutoff_approved_email_sent_at IS NOT NULL`) handles already-sent |
| Cap | LIMIT 50/day defends against runaway dispatch |
| Aggregate audit | Single `admin_audit_log` row per run: action `selection.cutoff_pending_cron_run` with metadata `{dispatched_count, skipped_count, error_count, cycle_codes_touched}` |
| Per-app audit | Existing `selection.cutoff_approved_email_dispatched` rows from RPC (no change) |
| Observability | New MCP tool `get_cutoff_dispatch_health` returns last 7d runs + dispatched_count trend + zero-dispatch warning |
| Contract test | Cron registration + SELECT predicate + LIMIT clause + skip-in_band forward-defense regex |

### Wave 2b — Cron `selection-stuck-scheduled-rescue-daily`
**Depends on Wave 1d (re-uses F4 SECDEF RPC).**

| Gate | Pass criteria |
|---|---|
| Migration | Wrapping function `_selection_stuck_scheduled_rescue_cron()` — SELECT apps with `latest_interview.scheduled_at < now() - interval '48 hours' AND conducted_at IS NULL AND status = 'scheduled' AND cycle.status = 'open'` LIMIT 20 |
| pg_cron schedule | Daily 15:00 UTC (after cutoff-pending cron) |
| Threshold | 48-hour grace window after `scheduled_at` (covers same-day reschedules, holidays) |
| Cap | LIMIT 20/day — stuck-scheduled is a smaller cohort |
| Loop body | Calls `selection_rescue_stuck_interview(app_id)` per row (from Wave 1d) |
| Aggregate audit | `selection.stuck_rescue_cron_run` with `{rescued_count, error_count}` |
| Observability | Extend `get_cutoff_dispatch_health` to include stuck rescue stats |
| Contract test | Cron registration + SELECT predicate + 48h grace clause + LIMIT |

### Wave 3 — Hardening + ratchet
**Cross-cutting; ships after Wave 1 + Wave 2.**

| Gate | Pass criteria |
|---|---|
| MCP exposure | `notify_selection_cutoff_approved` + `selection_rescue_stuck_interview` registered as MCP tools (per SEDIMENT-239b.A: contract tests assert source of every FK column when SECDEF) |
| Forward-defense | `mcp-rpc-coverage.test.mjs` ratchet: assert both RPCs have call sites in `src/` AND `supabase/functions/nucleo-mcp/index.ts` |
| Sediment guard | `tests/contracts/cutoff-rpc-not-orphan.test.mjs` — fails CI if `notify_selection_cutoff_approved` ever drops from grep over `src/` (locks the original regression class) |
| i18n parity ratchet | Updated `tests/contracts/i18n-key-parity.test.mjs` to include all new keys |
| Test baseline | Bump offline + with-DB counts in `.claude/rules/deploy.md` |

---

## Acceptance criteria (PM sign-off)

PM accepts each wave when:

1. **Wave 1a:** Open the modal of any apt-test cycle4 candidate in `screening` / `interview_pending` with no `cutoff_approved_email_sent_at` → click the new button → real email lands in test inbox within 30s → re-opening modal shows the badge with timestamp.
2. **Wave 1b:** Toggle "Sem entrevista" → list narrows to candidates without active interview. Toggle "Stuck scheduled" → list shows only candidates with overdue scheduled interview (the 3 cases we hit today would appear here).
3. **Wave 1c:** Select 3+ rows + click bulk dispatch → confirm dialog quotes names → aggregate toast matches actual DB state.
4. **Wave 1d:** Modal of a candidate with overdue interview shows the rescue button → click → confirm → previous interview row goes to `cancelled` + new dispatch row in `selection_dispatch_url_log` + candidate receives new email.
5. **Wave 2a:** After deploy, wait 24h → `get_cutoff_dispatch_health` shows the cron's first run with non-zero `dispatched_count` matching any newly-eligible cohort.
6. **Wave 2b:** Same, with `rescued_count` matching stuck-scheduled cohort.

---

## Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Bulk dispatch spam (PM clicks bulk by accident) | M | 2-step confirm with named preview + LIMIT 50 cap |
| Cron re-sends to candidate who already booked outside platform | L | RPC's idempotency gate (`cutoff_approved_email_sent_at IS NOT NULL`) blocks; new gate also checks `latest_interview.status = 'scheduled' AND scheduled_at > now()` before rescue cron acts |
| F4 atomic rescue partial-fails (cancel succeeds but notify fails) | L | RPC `selection_rescue_stuck_interview` wraps in PL/pgSQL block; on notify failure, savepoint rollback so cancel doesn't persist orphaned |
| Cron LRD picker dispatches all to one evaluator (LRD bug) | L | LRD already proved working today: 7 above_band split between 2 evaluators (Vitor 6 + Fabricio 1) on first dispatch |
| In_band candidates accidentally invited | M | Strict `>= pert_target_score` predicate in cron; in_band requires explicit PM bulk-action via F3 |
| New SECDEF RPC missing FK source assertions | M | SEDIMENT-239b.A applied: contract test for `selection_rescue_stuck_interview` asserts `actor_id := v_caller.id` (not `auth.uid()`), preserving FK to `members(id)` |

---

## Sediment lessons applied

- **SEDIMENT-235.A** — PR body must NOT contain "close|fix|resolve + #N" in any form including negated. Sub-issues per wave use `Refs #NNN` not `Closes #NNN`.
- **SEDIMENT-239b.A** — SECDEF RPCs writing to FK-constrained tables get contract tests asserting every FK column source.
- **SEDIMENT-186.C** — every new contract test added to BOTH `"test"` + `"test:contracts"` whitelists.
- **SEDIMENT-238.C** — preserve every parameter DEFAULT clause on `CREATE OR REPLACE FUNCTION`.
- **SEDIMENT-269.A** — md5/diff apply_migration payload vs file before applying.
- **SEDIMENT-269.B** — verify `schema_migrations` count after MCP `apply_migration`; clean shadow rows row-by-row via exact `WHERE version =`.
- **GC-097** — pre-commit FK validation + i18n triple-dict + RPC signature DROP+CREATE (not REPLACE) if param types change.

---

## Cross-references

- p228 #260 W2 Leaf 4 — original `notify_selection_cutoff_approved` RPC ship
- p251 #355 SPEC #348 Child #2 — LRD routing extension (PR #354 base)
- p243 — first live dispatch (DO-block; 5 candidates manual)
- p270 (this session) — 10 candidates dispatched via DO-block (7 above_band + 3 stuck-scheduled)
- #348 — booking_url roadmap (Steps 2–4 will populate `selection_committee.interview_booking_url`)
- `.claude/rules/deploy.md` — test baseline bump per wave
- `.claude/rules/mcp.md` — MCP tool count ratchet for Wave 3 exposure
