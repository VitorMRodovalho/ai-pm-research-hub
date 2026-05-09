# Issue B + E Resolution — Both NOT bugs (ADR-0073 design + PM let-proceed)

**Date:** 2026-05-09
**Sessão:** p126 E3 reduced (continuation)
**Status:** CLOSED (not-a-bug + let-proceed respectively)

## Updated framing

p125 pre-mortem listed:
- **Issue B (P1)**: "booking workflow disparado fora dos 3 gates do schedule_interview"
- **Issue E**: "10 interview_status≠none com score=0 (legacy bypass?)"

Live recon p126 + ADR-0073 review revealed BOTH are **expected behavior**, not actual bugs.

## Issue B — NOT a bug

`schedule_interview` RPC HAS 3 gates since p87 (migration `20260516380000_p87_workflow_gate_schedule_interview.sql`):
- **Gate 1**: `consent_ai_analysis_at IS NOT NULL` AND `ai_analysis IS NOT NULL`
- **Gate 2**: 2+ peer reviews via `selection_evaluations`
- **Gate 3**: `objective_score_avg IS NOT NULL`

Bypass possível via `p_bypass_gate=true` AND `manage_member` action.

**ADR-0073 (2026-05-06) deliberately introduces parallel path** `sync_calendar_booking_to_interview` que:
- Is anon-callable via shared secret
- BYPASSES schedule_interview gates intentionally
- Rationale: "booking via Calendar é informational — não significa decisão de avançar"
- Gates ainda aplicam at `submit_interview_scores` (score-submission, não scheduling)

**Conclusion**: Issue B reframed — não é gate bypass; é design intencional ADR-0073 distinguishing informational booking from formal advancement decision. Score-submission é o real gate.

## Issue E — manifestation, not separate

10 candidates cycle3-2026-b2 com `interview_status='scheduled'` sem `objective_score_avg`:
- Per ADR-0073 design, esses 10 entraram via Calendar booking path (Apps Script Web App OR direct API call OR admin UPDATE)
- Webhook_url=NULL impede Apps Script automatic flow (Issue A) → eles entraram via OUTRO path
- Investigation deferred (não materializou em risco material per Decision 10)

**PM Decision 10 (2026-05-09)**: let proceed — candidate journey > process purity. Documentado em `docs/council/decisions/2026-05-09-p126-decision-10-issue-e-let-proceed.md`.

## Closed status

| Item | Status | Resolution |
|---|---|---|
| Issue B | CLOSED — not-a-bug | ADR-0073 design intencional; gates apply at score-submission |
| Issue E | CLOSED — let-proceed | PM Decision 10; 10 candidates continue normal pipeline |

## What WAS shipped to address related concerns

### Decision 4 cycle freeze (Issue Decision 4 acceptance criteria)
- pmi-ai-triage EF: cycle_id added to SELECT_COLS, prompt_version logged
- Migration 9 (20260518090000): ai_processing_log.prompt_version column
- Cycle 4+ V2 enriched prompt path scaffold present (V1 logic active for Cycle 3)

### Issue C complete fix
- Migration 8 (20260518080000): backfill SQL UPDATE
- Migration 10 (20260518100000): canonical helper `compute_is_returning_member` + BEFORE INSERT trigger
- Drift risk closed forward — any INSERT path auto-corrects

### Issue A — separate doc
- See `docs/strategy/p126_issue_a_apps_script_deployment_guide.md` for PM action steps

## Items still pending (E3 full scope future)

- **Cron compliance D-60/D-30/D-7** (Decision 9 — chapter VP coordination async via Ivan T-3)
- **Apps Script deployment** (PM action — Issue A guide doc)
- **gate_attempts_log audit** of original 10 (deferred — let-proceed makes investigation low-priority; future-state invariant test could detect via grep on metadata)

## Tracking

- Issue B: closed in this session
- Issue E: closed via Decision 10
- Issue A: PM-action via Apps Script deployment guide
- Issue C: closed (Migrations 8 + 10)
- Issue D: delegated to worker E2 + Hotfix Wave 0 (already in flight)
