# Cycle 3 b2 Late-Evaluation Audit — WATCH-240.B (p244)

**Sessão:** p244 (2026-05-24)
**Branch:** `agent/p244-watch-240-b-cycle3-b2-late-eval-audit`
**Scope:** Read-only audit. No migrations, no schema changes, no app status writes, no email dispatch.
**Gate:** PM Option A — audit doc closes WATCH-240.B as **audit-only / no remediation**. No dispatch packet (cycle3-b2 apps already `approved`).

## Executive summary

WATCH-240.B was carried from p240 close with the framing *"4 cycle3-b2 rows in the p240 backfill — PM should verify these are legitimate late-evaluations or backfill long-tail."* The carry text propagated through p241/p242/p243 handoffs without live verification.

Live audit findings (2026-05-24 ≈17:00 UTC):

1. **The p240 backfill touched 0 (zero) cycle3-2026-b2 rows.** All 14 backfill audit entries (`action='p240_251_backfill_interview_status'`) target `cycle4-2026` exclusively (10 → `interview_done` + 4 → `interview_scheduled`). The P162 #208 line stating "10 cycle4 + 4 cycle3-b2" was an attribution error; the canonical CTE in migration `20260805000025` has scope `cycle4 + cycle3-b2`, but the idempotency guard `f.target_status <> a.status` filtered cycle3-b2 to 0 candidates because both cycle3-b2 apps were already past `interview_done` (`status='approved'`) by the time the trigger landed.
2. **cycle3-2026-b2 has exactly 2 applications, both already `approved`.** Both were administrative pre-cycle4 onboarding cases: **Herlon Alves de Sousa** (`d1d72a91…`, leader track, `objective_score_avg=252.00`) + **João Uzejka dos Santos** (`a06b9a26…`, researcher track, `objective_score_avg=137.00`). Both advanced via `application.status_manual_advance` on 2026-05-09 (p129-s1 session) per PM directive *"extend formal acceptance pre-Cycle 4"*.
3. **"4 late-evaluation" reframed**: the only late evaluation pattern present in cycle3-b2 is **Herlon's 4 non-interview evaluation rows** submitted 2.4–3.2 days *after* his interview was conducted on 2026-05-09 16:46 UTC. Specifically: 2 `objective` evals (Vitor + Fabricio) + 2 `leader_extra` evals (Vitor synchronous + Fabricio late). All 4 are **legitimate PM/curator post-hoc submissions** in an administrative onboarding window — not data corruption.
4. **No structural remediation needed.** cycle3-b2's standard funnel ordering (objective → screening → interview → leader_extra → decision) does not apply because both apps bypassed the funnel via `application.status_manual_advance`. The "out-of-canonical-phase" evaluations are an artifact of administrative path, not a system bug.

**Disposition**: WATCH-240.B closes as **audit-only**. No remediation, no dispatch, no migration. One small ISSUE_REGISTRY narrative correction (P162 #208 attribution).

## Cycle 3 b2 Application State

```
cycle_id = d28313d4-569a-4c58-9eae-7e84c5da29b1
cycle_code = cycle3-2026-b2
status = open
phase = evaluating
open_date = 2026-03-28
close_date = 2026-05-31
interview_booking_url = NULL (not used; both apps bypassed standard funnel)
objective_cutoff_formula = (2*min + 4*avg + 2*max) / 6 * 0.75
scoring_formula.version = v1.0-cr047
```

| Applicant | Track | Status | obj_avg | leader_extra_pert | PERT target | Band Position | cutoff_email_sent_at |
|---|---|---|---|---|---|---|---|
| Herlon Alves de Sousa | leader | approved | 252.00 | (backfilled p219) | 155.78 | above_band (252 > 171.36) | NULL — never dispatched |
| João Uzejka dos Santos | researcher | approved | 137.00 | n/a | 155.78 | below_band (137 < 140.20) | NULL — never dispatched |

Both `cutoff_approved_email_sent_at IS NULL` is **expected**: these apps bypassed the standard funnel where `notify_selection_cutoff_approved(app_id)` would have fired. They were administratively advanced to `approved` after manual evaluation.

## p240 Backfill Audit — Live Breakdown

Query:
```sql
SELECT
  target_type,
  metadata->>'cycle_code' AS cycle_code,
  metadata->>'new_status' AS new_status,
  count(*) AS rows
FROM public.admin_audit_log
WHERE action = 'p240_251_backfill_interview_status'
GROUP BY 1,2,3
ORDER BY 1,2;
```

Result:

| target_type | cycle_code | new_status | rows |
|---|---|---|---|
| selection_application | cycle4-2026 | interview_done | 10 |
| selection_application | cycle4-2026 | interview_scheduled | 4 |
| **(none)** | **cycle3-2026-b2** | — | **0** |

The CTE scope in migration `20260805000025` includes both cycles in `phase='evaluating'`, but cycle3-b2 had 0 apps matching the evidence ladder (no `interview_pending` apps with submitted interview evals — both apps already past `interview_done` via the `approved` terminal status). Idempotency guard `f.target_status <> a.status` correctly filtered them out.

**Correction**: P162 #208 line 2466/2576 (and the propagation through p241/p242/p243 handoffs) misattributed 4 of the 14 rows to cycle3-b2. Actual breakdown: **14/14 are cycle4-2026**.

## Herlon's 5 Evaluations — Timeline

PM manual advance: `application.status_manual_advance` @ 2026-05-09 15:08 UTC ("extend formal acceptance pre-Cycle 4 — already running CPMAI study group operationally").

Interview row: `selection_interviews.scheduled_at=2026-05-09 16:46:44`, `conducted_at=2026-05-09 16:47:16`, single interviewer_ids=[Vitor].

| # | Eval | Evaluator | submitted_at | Δ vs Interview | Classification |
|---|---|---|---|---|---|
| 1 | leader_extra | Vitor | 2026-05-09 16:46:28 | −16s pre | LEGIT — live PM submission alongside interview (p219 leader_extra dimension intro) |
| 2 | interview | Vitor | 2026-05-09 16:47:16 | 0s synchronous | NORMAL — canonical interview eval (Vitor single interviewer) |
| 3 | leader_extra | Fabricio | 2026-05-12 00:57:58 | +2.4d post | LEGIT-LATE — curator post-hoc for p219 leader_extra (Vitor + Fabricio both on cycle3-b2 committee) |
| 4 | objective | Fabricio | 2026-05-12 00:58:06 | +2.4d post | **OUT-OF-PHASE** — objective should be pre-interview canonically; submitted 2.4d post by curator |
| 5 | objective | Vitor | 2026-05-12 19:18:33 | +3.2d post | **OUT-OF-PHASE** — same as #4, PM post-hoc submission |

**"4 late-eval" reconciliation**: count of non-interview evals (rows #1, #3, #4, #5) = 4. Two of those (#1, #3) are leader_extra (a separate dimension, not "late" in the canonical sense), and two (#4, #5) are objective evals submitted post-interview (technically out-of-phase but legitimate for an administrative onboarding case).

## João Uzejka's 3 Evaluations — Timeline

PM manual advance: `application.status_manual_advance` @ 2026-05-09 14:43 UTC ("João is cycle 3 active researcher (test journey user)… manual advance unblocks UI interview tab + onboarding workflow test").

Interview row: `selection_interviews.scheduled_at=2026-05-09 16:47:39`, `conducted_at=2026-05-09 16:48:25`, single interviewer_ids=[Vitor].

| # | Eval | Evaluator | submitted_at | Δ vs Interview | Classification |
|---|---|---|---|---|---|
| 6 | objective | Vitor | 2026-04-01 13:38 | −38d pre | NORMAL — early submission, canonical screening phase |
| 7 | objective | Fabricio | 2026-04-14 23:06 | −24d pre | NORMAL — second screening eval |
| 8 | interview | Vitor | 2026-05-09 16:48 | 0s synchronous | NORMAL — canonical interview eval |

João's path matches the standard funnel ordering. No out-of-phase evaluations.

## Why "out-of-canonical-phase" is acceptable here

The `cycle3-2026-b2` cycle was opened 2026-03-28 as a **test journey window** for 2 pre-existing PMI volunteers who needed formal platform onboarding before cycle4 opened. PM Vitor's session p129-s1 (2026-05-09) used `application.status_manual_advance` to bypass the standard funnel because:

- Herlon was *"already running CPMAI study group operationally; formalizing platform position"* — a known leader candidate, not a competitive selection.
- João was *"cycle 3 active researcher (test journey user)"* — being onboarded post-cycle3 for cycle4 readiness via UI workflow testing.

In this administrative path, the canonical objective → screening → interview → leader_extra ordering is not enforced because the app didn't compete through normal selection. PM + Fabricio submitted evaluations live during the interview (synchronous) and post-hoc (2-3 days later) to **anchor a score record** for governance audit, not to compete against a PERT cutoff.

The PERT cutoff calculation that ran in p242 (`recompute_all_active_pert_cutoffs()`) populated `cycle3-b2.pert_target_score=155.78` for both apps, but the cutoff was never used to gate dispatch — both apps had already moved to `approved` outside the standard cutoff workflow.

## Implications for future administrative windows

If PM opens another administrative "extend formal acceptance" window for non-competitive candidates (similar pre-cycle bridging), the same out-of-canonical-phase pattern will recur. **Recommendation** (deferred, not in scope this PR):

- Consider an ADR documenting the "administrative onboarding cycle" pattern as a recognized exception to the standard selection funnel. Tag with criteria: PM directive, single-candidate or small-batch, no competitive PERT gating.
- Optionally, add a `selection_cycles.cycle_kind` enum (`competitive` vs `administrative`) so the standard cutoff workflow can be selectively disabled per cycle. **Not blocking** — current behavior tolerates the manual bypass cleanly.

## Disposition

WATCH-240.B closes as **audit-only**. No remediation needed.

| Item | Status |
|---|---|
| 4 alleged late-eval rows | **Reclassified**: Herlon's 4 non-interview evals, all legitimate PM/curator submissions |
| p240 backfill cycle3-b2 attribution | **Corrected**: 0 cycle3-b2 rows (14/14 cycle4) — P162 #208 line 2466 propagation error |
| Dispatch packet for cycle3-b2 apps | **N/A** — both apps already `approved` via administrative path; cutoff_approved email moot |
| cycle3-b2 PERT cutoff state | **Populated p242** (target=155.78, band=[140.20, 171.36], cohort_n=18) — informational only |
| `cycle3-b2.interview_booking_url` | **Remains NULL** — not needed for administrative path (both apps' interviews already conducted via manual flow) |
| Structural fix needed | **None** |

## Carries forward (post-p244)

- **WATCH-240.B itself**: CLOSE as resolved-no-remediation. P162 entry to be updated.
- **P162 #208 attribution correction**: Add NEW P162 entry RESOLVED-WATCH-240.B + footnote on #208 noting the live attribution discrepancy.
- **SEDIMENT-244.A NEW**: handoff narrative propagation drift — when a P162 entry says "N rows in cycle X", live-query before propagating count through subsequent handoffs. Mirrors SEDIMENT-242.A (probe RPC body before runbook) in the handoff-text domain.
- **OPP-244.A**: documenting the "administrative onboarding cycle" pattern as ADR-candidate (optional, deferred).

## Verify-after-this-PR

```sql
-- cycle3-b2 apps still 2, both approved, no dispatch
SELECT count(*) FROM public.selection_applications sa
JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
WHERE sc.cycle_code = 'cycle3-2026-b2'; -- 2

SELECT count(*) FROM public.selection_applications sa
JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
WHERE sc.cycle_code = 'cycle3-2026-b2'
  AND sa.status = 'approved'; -- 2

-- p240 backfill audit attribution remains cycle4-only
SELECT metadata->>'cycle_code' AS cycle, count(*)
FROM public.admin_audit_log
WHERE action = 'p240_251_backfill_interview_status'
GROUP BY 1; -- cycle4-2026: 14
```

## Cross-refs

- WATCH-240.B origin: P162 #208 (p240 close, 2026-05-24) line 2466
- p240 migration: `supabase/migrations/20260805000025_p240_251_interview_status_transition_trigger.sql`
- p241 migration: `supabase/migrations/20260805000026_p241_watch_240_a_submit_interview_scores_relax_status_gate.sql`
- p242 cycle4 sibling: `docs/audit/CYCLE4_PERT_CUTOFF_P242_WATCH_240_C.md`
- p243 cycle4 dispatch packet (carry that triggered this sibling): `docs/ops/CYCLE4_CUTOFF_DISPATCH_P243.md`
- p129-s1 administrative advance audit rows: `admin_audit_log WHERE action='application.status_manual_advance'`
- p219 leader_extra Phase 1 backfill: `admin_audit_log WHERE action='p219_229_phase1_leader_extra_pert_score_backfill'`
- SEDIMENT-242.A (probe RPC body before runbook): live-smoke discipline carried into this audit
- SEDIMENT-244.A NEW (handoff narrative propagation drift): mirrors 242.A in different domain
