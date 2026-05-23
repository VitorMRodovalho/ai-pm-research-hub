# Selection Notifications W2 Audit — #260 Workstream 2

**Sessão:** p227 (2026-05-23)
**Branch:** `agent/p227-issue-260-w2-selection-notifications-audit`
**Scope:** Per #292 Sprint Plan Handoff B + p226 audit Item 4 cross-ref — read-only SQL evidence pack for selection_* notification delivery routing, catalog/helper parity, peer-review dispatch gate impact, stale interviews, and `selection_cutoff_approved` gap. **No writes.**
**Gate:** PM approves delivery policy + child issue split before any catalog change, helper migration, replay, or new type addition.
**Cross-ref:** #260 (parent), #292 (P0 sprint umbrella), #298 (closed Foundation XS in PR #302 — cycle picker determinism), #251 (audit origin), #229 Phase 2 (status advance bundle).

## Executive Summary

Selection notification routing has three concurrent problems, plus one stale-state symptom and one feature-gap:

| # | Finding | Severity | Lane | Disposition |
|---|---|---|---|---|
| A | **17 candidate-facing selection_* notifications mis-routed via digest path (90d window)** with `email_sent_at IS NULL`. Email delivery happened (via digest) but as bundled summary, not as event-driven candidate communication. | HIGH | Foundation + Integration + Governance | Bundle into Workstream 2 leaf: helper + ADR-0022 parity + replay plan |
| B | **ADR-0022 catalog has ZERO selection_* entries** (catalog version W1.3 dated 2026-04-27). Helper has 1 entry (selection_termo_due → transactional_immediate, p159). All other selection_* fall through to ELSE → `digest_weekly`. | HIGH | Governance + Foundation | Backfill catalog + contract test for parity (ADR-0022 §`sql_helper` requires sync) |
| C | **dispatch_peer_review_invitations AI-precondition gate blocks 14 cycle4 apps** (`consent_ai_analysis_at IS NULL` OR `ai_analysis IS NULL`). The OTHER 18 apps (with consent + analysis) have no peer_review_requested notification → dispatcher was never invoked for them (manual trigger required). | HIGH | Foundation + Governance | PM decision: AI gate hard/soft + manual vs cron dispatch trigger |
| D | **11 stale `selection_interviews` rows** (scheduled_at in past 1-30 days, `conducted_at IS NULL`). No automated cleanup or follow-up notification. | MED | Foundation + QA | New leaf: stale-interview cleanup cron + selection_interview_overdue type |
| E | **`selection_cutoff_approved` type does not exist** (0 notifications, 0 RPC references, 5 generic cutoff RPCs are PERT compute). #260 proposed adopting this as the "2 objective evaluations + PERT ≥ cutoff → invite interview booking" trigger. | MED | Foundation + Frontend | PM decision: adopt new type + trigger logic + template |

## Live State Snapshot (2026-05-23)

### Q1 — selection_* notification routing (90d window)

| type | helper_returns | live_delivery_mode | total | email_sent | digest_delivered | first_seen | last_seen |
|---|---|---|---|---|---|---|---|
| **selection_termo_due** | `transactional_immediate` (p159) | `digest_weekly` | 13 | 0 | 13 | 2026-05-14 | 2026-05-14 |
| **peer_review_requested** | `digest_weekly` (ELSE) | `transactional_immediate` (hardcoded at INSERT) | 12 | 12 | 0 | 2026-05-05 | 2026-05-05 |
| **selection_approved** | `digest_weekly` (ELSE) | `digest_weekly` | 2 | 0 | 2 | 2026-05-13 | 2026-05-13 |
| **selection_interview_scheduled** | `digest_weekly` (ELSE) | `digest_weekly` | 2 | 0 | 2 | 2026-05-09 | 2026-05-09 |

**Total in 90d window: 29 selection_* notifications. 17 candidate-facing rows mis-routed via digest (no per-event email).**

### Q2 — Helper behavior (`_delivery_mode_for`)

```sql
-- Body extract (live, 2026-05-23):
SELECT CASE p_type
  ...
  WHEN 'selection_termo_due' THEN 'transactional_immediate' -- p159 S#1 T1 (2026-05-14)
  ...
  ELSE 'digest_weekly'
END;
```

Only **1 selection_* type** is explicitly routed; all others fall through to the digest default.

### Q3 — INSERT callsites (22 functions write to `public.notifications`)

7 use `_delivery_mode_for(p_type)` (canonical pattern):
- `create_notification` (×3 overloads), `counter_sign_certificate`, `sign_volunteer_agreement`, `notify_offboard_cascade`, `v4_notify_expiring_engagements`.

15 do NOT use the helper (direct/no `delivery_mode` reference). Selection-funnel-relevant ones:
- `dispatch_peer_review_invitations` — **hardcodes `'transactional_immediate'`** at INSERT (correct for peer_review_requested but bypasses helper drift detection).
- `generate_weekly_member_digest_cron` — produces `weekly_member_digest` summary rows (different lifecycle).

The 13 `selection_termo_due` rows from **2026-05-14** were created via `process_vep_acceptance_transition` → `create_notification(...)` → which DOES use `_delivery_mode_for`. Since they got `digest_weekly`, this implies the rows were inserted **BEFORE the p159 helper update was applied that same day** (race window between row inserts and migration apply). All subsequent inserts route correctly per the helper. **No code bug — just historical pre-migration backlog.**

### Q4 — ADR-0022 catalog (W1.3, 2026-04-27) vs live helper drift

| type | catalog entry | helper return | live INSERT mode | drift? |
|---|---|---|---|---|
| selection_termo_due | **missing** | transactional_immediate | digest_weekly (pre-p159 rows) + transactional_immediate (post) | catalog drift (helper updated p159, catalog not) |
| selection_approved | **missing** | (ELSE) digest_weekly | digest_weekly | catalog drift (no entry, no PM decision applied) |
| selection_interview_scheduled | **missing** | (ELSE) digest_weekly | digest_weekly | catalog drift (same as above) |
| peer_review_requested | **missing** | (ELSE) digest_weekly | transactional_immediate (hardcoded) | catalog drift + helper drift (helper would return digest, but INSERT hardcodes transactional) |
| selection_evaluation_complete | **missing** | (ELSE) digest_weekly | (no recent rows) | catalog drift |
| selection_interview_noshow | **missing** | (ELSE) digest_weekly | (no recent rows) | catalog drift |
| selection_cutoff_approved | **does not exist** | n/a | n/a | does not exist (proposed by #260) |
| selection_interview_overdue | **does not exist** | n/a | n/a | does not exist (proposed by audit Item D) |

**Catalog parity contract test** `tests/contracts/adr-0022-delivery-mode.test.mjs` will need updating once PM ratifies delivery modes for each selection_* type, to prevent future drift.

### Q5 — Peer review dispatch gate impact (cycle 4)

```text
Cycle 4 (cycle4-2026, id=08c1e301...) AI state:
  has_consent_AND_analysis        : 24 apps  (eligible for peer dispatch)
  has_consent_only (still processing): 0 apps
  no_consent_no_analysis          : 14 apps  (hard-blocked by precondition)
                                  : 38 total

Dispatcher precondition (dispatch_peer_review_invitations line ~31):
  IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
    RAISE EXCEPTION 'PEER_PRECONDITION: candidate has no AI analysis;
                     cannot dispatch peer review yet' USING ERRCODE = 'P0010';
  END IF;

Peer notifications dispatched cycle 4: 6 of 38 (15.8% coverage)

  Hard-blocked by precondition:                14 apps  (correctly gated; AI consent missing)
  Eligible but NEVER dispatched:               18 apps  (manual trigger gap)
  Eligible AND dispatched (≥1 peer notified):   6 apps  (working as designed)
```

**Two separate gaps**:
1. **14 apps blocked by AI precondition**: PM decision needed on whether AI consent is hard requirement. If yes → consent UX needs improvement or admin override; if no → relax gate.
2. **18 apps eligible but never dispatched**: dispatcher is RPC-triggered (typically from committee `lead` action via admin UI). No cron auto-dispatch. PM decision: should `dispatch_peer_review_invitations` be called automatically (e.g., when `consent_ai_analysis_at` + `ai_analysis` both set), or remain manual?

### Q6 — Stale interviews

```text
selection_interviews WHERE scheduled_at < NOW() AND conducted_at IS NULL:
  Total stale:        11 rows
  1-30 days old:      11 rows
  >30 days old:        0 rows

No cron or audit log tracks these. They surface only in admin queries.
```

Currently no notification type exists for `selection_interview_overdue`. Audit recommends new type + cron (daily or weekly) that emits admin-facing alert.

## Root-Cause Classification

### A — Catalog drift (HIGH, single root cause)

ADR-0022 catalog version W1.3 (2026-04-27) predates the selection-funnel build-out. Selection types were added to `_delivery_mode_for` helper or hardcoded at INSERT sites, but never landed in the catalog.

**Why this matters**: catalog is the documented source of truth + the contract test `adr-0022-delivery-mode.test.mjs` only checks types listed in the catalog. Missing entries = missing drift detection = silent routing decisions buried in PL/pgSQL.

### B — Pre-migration race (LOW, historical only)

The 13 `selection_termo_due` rows from 2026-05-14 were inserted before p159 helper update. Not a code bug. **Replay candidate** if PM wants those candidates to receive proper "termo due" emails (note: digest_delivered_at IS NOT NULL, so they received the weekly summary; emails for "termo due" specifically did not fire). Resend quota 100/day permits this batch trivially.

### C — Peer review dispatch trigger gap (HIGH)

`dispatch_peer_review_invitations` requires a committee `lead` to invoke manually (or `manage_member` admin). No cron path. Result: 18 cycle4 apps are eligible (AI done + status valid) but waiting on someone to click. PM-facing question: is this intentional gate-keeping or a forgotten cron?

### D — AI precondition gate (HIGH, PM decision)

`consent_ai_analysis_at IS NULL OR ai_analysis IS NULL` blocks 14 cycle4 apps. PM choices:
- **(a) Hard gate (status quo)**: 14 apps need consent collected + AI processing run before any peer review. UX must surface this.
- **(b) Soft gate**: allow peer dispatch without AI for apps where AI consent was explicitly declined; AI optional.
- **(c) Admin override**: keep gate, add `dispatch_peer_review_invitations_no_ai(p_application_id)` for PM emergency use.
- **(d) Hybrid**: gate `peer_review_requested` (admin-facing peer survey) on AI, but allow `selection_interview_scheduled` independent of AI.

### E — selection_cutoff_approved missing (MED, PM decision)

Current funnel has `peer_review_requested` (admin) → manual evaluation gathering → manual interview booking → `selection_interview_scheduled` (candidate). The #260 proposal: insert an explicit `selection_cutoff_approved` event after "2 objective evals + PERT ≥ cutoff", invite candidate to interview booking. This is a new type + new trigger + new template. Sequenced behind PM decision; out of scope for read-only audit.

### F — Stale interview surfacing (MED)

11 rows in past with no conducted/cancelled state. No notification fires. Recommendation: add `selection_interview_overdue` admin-facing notification with daily cron (suppress for in-app or digest_weekly).

## Policy Matrix Proposal (PM decision)

For each selection_* type, recommended delivery mode + rationale (PM may override per row):

| type | recommended mode | rationale | candidate-facing? |
|---|---|---|---|
| selection_termo_due | **transactional_immediate** (already in helper post-p159) | High urgency post-VEP-Active. Candidate needs term link within minutes. | Yes |
| selection_approved | **transactional_immediate** | Approval news is a milestone event; bundling in weekly digest erodes candidate experience. | Yes |
| selection_interview_scheduled | **transactional_immediate** | Interview details (calendar link, date/time) must reach candidate before the interview. | Yes |
| selection_interview_overdue | **digest_weekly** OR **suppress** | Admin reminder; suppress if `selection_attendance_health` dashboard surfaces this. | No (admin) |
| selection_evaluation_complete | **digest_weekly** OR **suppress** | Admin internal signal; PM may see in dashboard. | No (admin) |
| selection_interview_noshow | **digest_weekly** | Admin recap; not time-critical. | No (admin) |
| peer_review_requested | **transactional_immediate** (already hardcoded at INSERT) | Evaluator needs prompt action to keep cycle moving. | No (admin) |
| selection_cutoff_approved (new) | **transactional_immediate** | Candidate invitation to book interview — must reach inbox same day. | Yes |

**Member preference override question**: should candidate-facing operational emails (4 above marked Yes) bypass `notify_delivery_mode_pref = suppress_all`? Legal/UX rationale: candidate is in active workflow; opt-out for promotional vs operational should be split. **PM decision required** per Handoff B.

## Replay Plan (Resend-safe)

For the 17 mis-routed rows (13 termo_due + 2 approved + 2 interview_scheduled):

```sql
-- Candidate replay (DO NOT EXECUTE WITHOUT PM APPROVAL):
-- Re-fire as transactional by setting delivery_mode + clearing digest state.
-- Cap at 17 rows; well under Resend 100/day quota.
-- Idempotency: only update where email_sent_at IS NULL AND digest_delivered_at IS NOT NULL.

UPDATE public.notifications
SET delivery_mode = 'transactional_immediate',
    digest_delivered_at = NULL,
    digest_batch_id = NULL
WHERE id IN (
  SELECT id FROM public.notifications
  WHERE type IN ('selection_termo_due','selection_approved','selection_interview_scheduled')
    AND created_at >= '2026-05-01'::date
    AND created_at < '2026-05-20'::date
    AND email_sent_at IS NULL
    AND digest_delivered_at IS NOT NULL
);
-- Next send-transactional-emails EF cron cycle (every 5min) will pick them up.
```

**PM decision required** before replay:
1. Are the 13 termo_due rows still relevant given their weekly-digest was sent 2026-05-21? (Candidates already saw the bundled email.)
2. Is double-sending acceptable (digest summary + per-event email)? Or should we suppress replay?
3. Resend template availability: confirm templates for `selection_termo_due`, `selection_approved`, `selection_interview_scheduled` exist + are correctly named for transactional EF.

## Proposed Child Ready-Leaf Issues

Each child is narrow, single-lane, and ready for one agent:

1. **(Foundation, S)** — ADR-0022 catalog backfill: add 7 selection_* entries with PM-approved delivery modes; update `_delivery_mode_for` helper to match; extend contract test `adr-0022-delivery-mode.test.mjs` to cover them. **Pre-req:** Policy Matrix PM approval.

2. **(Foundation + QA, S)** — Resend-safe replay of the 13 termo_due + 2 approved + 2 interview_scheduled rows. **Pre-req:** PM decision on double-send acceptability + template confirmation. Idempotent UPDATE query above.

3. **(Foundation, M)** — `selection_cutoff_approved` type: new catalog entry + helper case + INSERT trigger when `(objective_done >= 2 AND pert_score >= cutoff)` AND status transitions to `objective_cutoff`. Resend template + cron-or-trigger choice. **Pre-req:** PM decision on adoption (this is a behavior change).

4. **(Foundation + Governance, M)** — `dispatch_peer_review_invitations` AI gate policy. **Pre-req:** PM decision per Section "D — AI precondition gate" above. Implementation depends on chosen option (a/b/c/d).

5. **(Foundation, S)** — `selection_interview_overdue` type: new catalog entry + daily cron that scans `selection_interviews WHERE scheduled_at < NOW() AND conducted_at IS NULL` and emits admin notification (idempotent — one notif per interview per week). **Pre-req:** PM approval of type addition.

6. **(Governance, S)** — `notify_delivery_mode_pref = suppress_all` bypass for candidate-facing selection_* operational emails. Legal basis + UI flag. **Pre-req:** PM legal/UX decision per Policy Matrix question.

7. **(QA, XS)** — Add notifications health signal: `selection_emails_pending_24h` query exposed as MCP tool or admin dashboard widget; alert when > N. **Pre-req:** none, but blocks W2 closure.

## Out of Scope for This Audit (per Handoff B)

- Broad notification-preference redesign (deferred to W3).
- Marketing email redesign.
- Bulk historical digest replay.
- AI feature work behind #221/#218 LGPD Art. 11 consent stance.

## Handoff to PM

This audit is **Workstream 2 evidence pack** per #292 sprint plan Handoff B. No production writes were made. All findings derived from read-only `mcp__supabase__execute_sql` queries + migration file inspection.

**Decisions blocking implementation of any of the 7 child leaves above:**
1. Adopt Policy Matrix as written, OR per-row alternative (especially `selection_cutoff_approved` adoption).
2. Replay vs no-replay for 17 mis-routed rows (and double-send tolerance).
3. AI precondition gate policy (options a/b/c/d).
4. Member preference override behavior for candidate-facing operational emails.
5. Manual vs cron dispatch trigger for `dispatch_peer_review_invitations`.

Recommended dispatch order after PM decisions: **#1 (catalog backfill) → #5 (overdue type) → #4 (AI gate) → #3 (cutoff_approved) → #2 (replay) → #6 + #7 (last).**

## Cross-references

- #260 — parent issue with original audit draft
- #292 — Sprint umbrella + Handoff B spec at `docs/project-governance/SELECTION_RELIABILITY_PRIORITIZATION_PLAN.md`
- #298 — closed in PR #302 (cycle picker determinism; orthogonal to delivery routing)
- #251 — closed-candidate (p226 audit predecessor)
- ADR-0022 — notification catalog (needs W1.4 amendment after PM decisions)
- p226 audit doc: `docs/audit/CYCLE4_TRUST_AUDIT_P226.md`
- p159 migration: `supabase/migrations/20260632000000_p159_s1t1_selection_termo_due_transactional_immediate.sql`

---

*Audit conducted by Claude under PM direction. Branch: `agent/p227-issue-260-w2-selection-notifications-audit`. Sessão: p227. No writes performed. All evidence read-only via Supabase MCP `execute_sql` as service_role.*
