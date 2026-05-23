# Selection Reliability Prioritization Plan

**Date:** 2026-05-23
**Status:** Proposed for dev handoff
**Tracking issue:** #292
**Scope:** Cycle 4 selection, onboarding, PERT, interview booking, and candidate communications.

## Recommendation

Run a short **P0 Selection Reliability Sprint** before dispatching lower-risk feature work. The issues are related by one operational risk: the candidate lifecycle can become partial between VEP import, dashboard visibility, evaluation, PERT cutoff, interview booking, final approval, onboarding, and volunteer agreement issuance.

Do not treat this as one large implementation issue. Use this plan as a sequencing layer and dispatch only narrow child tasks when their evidence and lane are clear.

## Current Issue Map

| Issue | Current recommendation | Why |
|---|---|---|
| #260 | P0 active, first workstream | Candidate-facing selection notifications, cutoff booking, stale interviews, and Resend replay safety can affect live applicants. |
| #251 | Ready investigation leaf, run before fixes | Henrique visibility and William dual-track evaluation state need production read-only evidence before data/code remediation. |
| #116 | QA / close-candidate unless smoke fails | Calendar webhook/token gate appears mostly shipped; needs real booking evidence or a narrow failure fix. |
| #179 | QA/spec gate for approval contract | Canonical approval orchestration is the contract that prevents approved candidates from becoming partial members. |
| #230 | Active lifecycle bug, sequence after #179 evidence | Herlon shows the volunteer agreement generation/nudge path can be missing after selection approval. |
| #229 | Phase 2 active/defer after P0 trust work | Phase 1 PERT leader_extra separation shipped; remaining UI/analytics/MCP cleanup is important but should follow communications and visibility fixes. |
| #254 | Spec-only, blocked by #221/#218 stance | Video screening reconciliation is valid, but AI/video work must stay behind LGPD Art. 11 consent remediation. |
| #243 | Spec-only, not implementation now | Calibration profile is valuable, but should not delay Cycle 4 operational fixes. |
| #217 | Close-candidate | Audit log and contract tests show the `/iniciativas/` welcome-link bug was fixed. Needs final issue close/comment only. |
| #227 | Close-candidate | Storage policy fix and forward test exist; only PM CV-button smoke remains. |
| #224 | Closed, remove from active dispatch | JSON import observability already shipped and issue is closed. |

## Workstream Sequence

### 1. Read-Only Evidence Pack

**Issues:** #251 + #260 audit section
**Lane:** QA / Foundation
**Do first. No writes.**

Deliver:
- SQL evidence for Henrique Diniz and William Junio across `selection_applications`, linked applications, status, role, cycle, and VEP raw fields.
- Evaluation-state evidence for William: submitted evaluator, missing evaluator/invite, objective vs leader_extra, and pending RPC behavior.
- Notification audit for `selection_*`: candidate-facing vs admin-facing, digest consumed vs transactional sent, weekly digest linkage, and rows eligible for replay/manual closure.
- Stale interview audit: past scheduled rows with no conducted/completed/cancelled state.

Exit criteria:
- Root causes split into data fix, code fix, PM decision, or close-candidate.
- No production mutation before PM approves the remediation list.

### 2. Selection Communications Fix

**Issue:** #260
**Lane:** Foundation / Integration / QA / Governance
**Start after Workstream 1 evidence.**

PM decisions required:
- Which `selection_*` types are transactional candidate-facing, transactional admin-facing, digest/in-app only, or suppressed.
- Whether candidate-facing operational emails bypass `notify_delivery_mode_pref = suppress_all`.
- Whether to adopt `selection_cutoff_approved`: 2 objective evaluations + PERT above cutoff -> invite to interview booking.

Deliver:
- `_delivery_mode_for()` and `ADR-0022` catalog parity for selected types.
- Contract test preventing catalog/helper drift.
- Safe replay plan capped under Resend 100/day, with explicit skip reasons and idempotency.
- `selection_cutoff_approved` type/template/trigger if approved.
- Interview overdue/no-show visibility and cleanup path.
- Health signal for selection emails pending >24h and digest-consumed candidate-facing rows.

Exit criteria:
- Existing affected rows are replayed, manually closed, or explicitly waived with evidence.
- Future selection communications cannot silently enter the wrong delivery path.

### 3. Interview Booking End-To-End Closure

**Issue:** #116
**Lane:** QA first, Integration only if smoke fails
**Can run in parallel with Workstream 2 only as read-only/smoke.**

Deliver:
- Real booking smoke: Calendar event -> webhook -> `selection_interviews.calendar_event_id` populated.
- If smoke fails, split a narrow Integration leaf with exact failing boundary: Apps Script, secret, route, RPC, or DB write.

Exit criteria:
- #116 becomes close-candidate or a single ready-leaf failure fix.

### 4. Approval, Onboarding, and Agreement Issuance

**Issues:** #179 + #230
**Lane:** Foundation first, Frontend/Integration only after contract decision
**Start after #260 policy is known.**

Deliver:
- Confirm whether #179 implementation is complete enough to close spec work or needs child leaves.
- For #230, audit active/approved members lacking volunteer agreement certificates.
- Decide auto-generate agreement on approval vs explicit manual queue.
- Implement either canonical trigger/queue or visible admin nudge.
- Add stale agreement/countersign nudge cron with idempotency if approved.

Exit criteria:
- Approved candidates have an observable path to member/person/engagement/onboarding/agreement state.
- Herlon and any similar backlog are handled by batch plan, not one-off hidden fixes.

### 5. PERT / leader_extra Phase 2

**Issue:** #229
**Lane:** Frontend / Foundation / MCP-AI / QA depending on split
**Run after live Cycle 4 trust blockers are stable.**

Deliver:
- `/admin/selection` displays objective and leader_extra cutoff bands separately.
- Analytics RPCs expose leader_extra dimension where needed.
- MCP tools expose leader_extra separately in dashboard/rankings/breakdown.
- Decide whether pre-`fe80842c` inflated `objective_score_avg` cleanup is needed; if yes, use PM-reviewed migration and audit log.

Exit criteria:
- Evaluators and PM can interpret objective vs leader_extra PERT without conflation.

## Explicit Deferrals

Do not dispatch these as implementation before the P0 sprint gates:

- #243 calibration framework: spec and child split only.
- #254 video screening reconciliation: read-only audit only until #221/#218 consent stance is resolved.
- New AI/video/transcription features: blocked by #221/#218.
- Broad notification-preference redesign: out of scope for #260 first fix.

## Handoff Blocks

### Handoff A — #251 Read-Only Audit

```md
Issue: #251
Registry status: ready-leaf
Lane: QA / Foundation
Branch/worktree: agent/selection-cycle4-trust-audit
In scope: read-only SQL evidence for Henrique visibility, William dual-track rows, evaluation assignments, pending RPC cycle selection, and UI filter hypothesis.
Out of scope: production data writes, UI changes, notification replay.
Acceptance evidence: SQL result summary; root cause classification; remediation issue split if data/code fix is needed.
Required gate: no writes; redact candidate PII in public comments.
Known blockers: production read-only DB access.
Do not touch: migrations, frontend files, edge functions.
Handoff expected: comment on #251 + registry update recommendation.
```

### Handoff B — #260 Notification Policy And Replay Plan

```md
Issue: #260
Registry status: active, promote child leaves after audit
Lane: Foundation / Integration / QA / Governance
Branch/worktree: agent/selection-notification-routing-audit
In scope: audit selection_* notification routing, define policy matrix, identify replay candidates, propose catalog/helper/test changes.
Out of scope: blind replay, marketing email redesign, bulk historical digest replay.
Acceptance evidence: policy matrix; exact affected-row list; Resend-safe replay plan; proposed child ready-leaf implementation tasks.
Required gate: PM decisions on transactional vs digest and suppress_all behavior.
Known blockers: PM delivery policy decisions, Resend quota.
Do not touch: send replay or mutate rows before PM approval.
Handoff expected: #260 comment with evidence + child issue bodies or implementation plan.
```

### Handoff C — #116 Booking Smoke

```md
Issue: #116
Registry status: qa-window / close-candidate
Lane: QA
Branch/worktree: agent/selection-calendar-booking-smoke
In scope: trigger or observe one real booking; verify selection_interviews row with calendar_event_id.
Out of scope: calendar architecture rewrite, #92 broad calendar integration.
Acceptance evidence: SQL row evidence or exact failing boundary.
Required gate: PM/live booking coordination.
Known blockers: availability of a real or controlled Calendar booking.
Do not touch: schedule_interview RPC unless smoke identifies a bug.
Handoff expected: close recommendation or single ready-leaf fix.
```

### Handoff D — #179/#230 Lifecycle Contract

```md
Issue: #179 + #230
Registry status: active after #260/#251 evidence
Lane: Foundation / Governance
Branch/worktree: agent/selection-approval-agreement-lifecycle
In scope: approval-to-member/person/engagement/onboarding/agreement state audit; Herlon-like backlog count; auto-generate vs manual queue decision.
Out of scope: broad certificate redesign, unrelated engagement kinds.
Acceptance evidence: lifecycle audit; PM decision; migration or UI queue plan; rollback/runbook if implementation proceeds.
Required gate: serialize Foundation migrations; PM approval for agreement-generation behavior.
Known blockers: decision on auto vs manual agreement issuance.
Do not touch: selection notification replay from #260.
Handoff expected: child implementation issue(s) or close/spec decision for #179.
```

### Handoff E — #229 Phase 2

```md
Issue: #229
Registry status: defer until P0 selection trust stabilizes
Lane: split Frontend / Foundation / MCP-AI / QA
Branch/worktree: TBD after split
In scope: objective vs leader_extra cutoff display, analytics/MCP surface, optional audited cleanup.
Out of scope: changing PERT math already fixed in Phase 1 unless audit proves drift.
Acceptance evidence: UI shows two bands; RPC/MCP outputs separate dimensions; contract tests cover no objective-score mutation.
Required gate: PM approves timing after #260/#251.
Known blockers: live Cycle 4 trust blockers.
Do not touch: notification routing or video consent.
Handoff expected: split into lane-specific leaves.
```
