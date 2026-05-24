# OPP-246.A Audit — Francisleila `final_score=309` drift + structural race in `submit_evaluation`

**Date**: 2026-05-24 (p247 follow-up)
**Author**: agent (PM-dispatched audit-only — no DB writes, no remediation without PM ratification)
**Trigger**: PM call-out post-p246 close: "auditar Francisleila final_score=309 versus fórmula esperada, porque isso pode indicar drift antigo no cálculo do score final" + p247 close reaffirmation: "ponto de atenção real agora é o carry OPP-246.A: auditar o final_score=309 da Francisleila antes de o cohort líder chegar em n>=10, porque isso pode contaminar uma futura régua dinâmica de líderes se for drift antigo."
**Scope**: **audit-only**, **no remediation in this doc**. Any structural fix requires PM ratification of one of the 4 options below.

---

## TL;DR (3 lines)

1. **Drift is real and structural** — `submit_evaluation` writes `final_score = obj + interview + leader_extra` (naïve sum), which contradicts canonical `compute_application_scores` writing `COALESCE(leader_score, research_score)` where `leader_score = research × 0.7 + leader_extra × 0.3` (CR-047). Same RPC's INSERT fires `_trg_recompute_application_scores` → canonical value gets written → then submit_evaluation's own UPDATE **overwrites** it with the naïve sum.
2. **Drift currently isolated to 1 row** — Francisleila (cycle4-2026 leader, `status=screening`, `final_score=309.00` vs canonical `158.30`, delta `+150.70`). She is **NOT in the leader cohort** (cohort only includes `status=approved`). All 8 currently-approved leaders across all cycles have **0 drift** because their approval path runs through `submit_interview_scores` which calls `compute_application_scores` explicitly.
3. **Self-heal exists** but is conditional — once Francisleila's interview is submitted via `submit_interview_scores`, her `final_score` reconciles to canonical. Risk window: if she (or any in-flight leader) is **approved without going through `submit_interview_scores`** (e.g., manual status advance, dual-track decision), the naïve sum survives into the cohort and contaminates the eventual dynamic régua when `cohort_n >= 10`.

---

## Canonical formula (CR-047 v1.0, approved 2026-04-10)

From `selection_cycles.scoring_formula` (identical across cycle4-2026, cycle3-2026-b2, cycle3-2026):

```jsonc
{
  "version": "v1.0-cr047",
  "approved_by_cr": "CR-047",
  "research_score": {
    "formula": "objective_pert + interview_pert",
    "components": ["objective", "interview"]
  },
  "leader_score": {
    "formula": "research_score * 0.7 + leader_extra_pert * 0.3",
    "weights": { "research_share": 0.7, "leader_extra_share": 0.3 },
    "components": ["objective", "interview", "leader_extra"],
    "description": "Score do líder: ponderação de 70% no research_score + 30% no leader_extra — normaliza a escala vs pesquisadores e evita vantagem artificial por ter mais dimensões"
  },
  "tracks": {
    "researcher": { "rank_by": "research_score DESC" },
    "leader":     { "rank_by": "leader_score DESC" }
  }
}
```

**Notice**: scoring_formula defines `research_score` and `leader_score` as the **track-resolved rank keys**. **`final_score` is NOT defined here** — its semantics are buried in code.

---

## Canonical writer: `compute_application_scores(p_application_id)`

```sql
-- compute_application_scores body (excerpt):
IF v_obj_avg IS NOT NULL AND v_int_avg IS NOT NULL THEN
  v_research := round(v_obj_avg + v_int_avg, 2);
ELSIF v_obj_avg IS NOT NULL THEN
  v_research := round(v_obj_avg, 2);  -- partial: objective only
ELSE
  v_research := NULL;
END IF;

IF v_app.role_applied = 'leader' OR v_app.promotion_path = 'triaged_to_leader' THEN
  IF v_research IS NOT NULL AND v_lead_avg IS NOT NULL THEN
    v_leader := round(v_research * 0.7 + v_lead_avg * 0.3, 2);  -- CR-047 weighted
  ELSIF v_research IS NOT NULL THEN
    v_leader := v_research;
  ELSE
    v_leader := NULL;
  END IF;
END IF;

UPDATE selection_applications
SET research_score = v_research,
    leader_score = v_leader,
    final_score = COALESCE(v_leader, v_research),  -- display fallback
    updated_at = now()
WHERE id = p_application_id;
```

**This is the source of truth**. `final_score := COALESCE(leader_score, research_score)`.

For Francisleila (leader, role_applied='leader', objective=164, leader_extra=145, no interview):
- `v_research = round(164 + 0, 2) = 164` (partial: objective only branch)

  Wait — actually `v_research = round(164, 2) = 164` because `v_int_avg` is NULL → ELSIF branch. So research = 164.
- `v_leader = round(164 × 0.7 + 145 × 0.3, 2) = round(114.8 + 43.5, 2) = 158.30`
- `final_score = COALESCE(158.30, 164) = 158.30`

Live row: `research_score=164, leader_score=158.30, final_score=309.00`. **research_score and leader_score match canonical perfectly**; only `final_score` is drifted (+150.70).

---

## Drifted writer: `submit_evaluation` (live RPC)

```sql
-- submit_evaluation body, leader_extra branch (excerpt):
ELSIF p_evaluation_type = 'leader_extra' THEN
  UPDATE public.selection_applications SET
    leader_extra_pert_score = v_pert_score,
    final_score = COALESCE(objective_score_avg, 0)
                + COALESCE(interview_score, 0)
                + v_pert_score,  -- naïve sum, NOT weighted
    updated_at = now()
  WHERE id = p_application_id;

-- And interview branch (same RPC):
ELSIF p_evaluation_type = 'interview' THEN
  UPDATE public.selection_applications SET interview_score = v_pert_score,
    final_score = COALESCE(objective_score_avg, 0)
                + v_pert_score
                + COALESCE(leader_extra_pert_score, 0),  -- naïve sum
    status = 'final_eval', updated_at = now()
  WHERE id = p_application_id;
```

For Francisleila after her last `submit_evaluation('leader_extra')` (Vitor's submission 2026-05-21 06:34:32 UTC):
- objective_score_avg = 164
- interview_score = NULL → COALESCE 0
- v_pert_score (le PERT) = 145
- `final_score = 164 + 0 + 145 = 309` ✓ **matches drift exactly**

---

## The structural race: trigger gets overridden by same RPC

`selection_evaluations` has trigger `trg_recompute_application_scores` (AFTER INSERT OR DELETE OR UPDATE) firing `_trg_recompute_application_scores()`:

```sql
-- _trg_recompute_application_scores body:
v_app_id := COALESCE(NEW.application_id, OLD.application_id);
IF v_app_id IS NOT NULL THEN
  PERFORM public.compute_application_scores(v_app_id);  -- writes canonical
END IF;
```

**Execution order inside a single `submit_evaluation('leader_extra')` call**:

1. `INSERT INTO selection_evaluations ... ON CONFLICT ... DO UPDATE SET ...` (with submitted_at = now())
2. **Trigger fires** → `compute_application_scores(p_application_id)` → `UPDATE selection_applications SET final_score = 158.30` (canonical)
3. **Same RPC continues** → its own `UPDATE selection_applications SET final_score = 309` (naïve sum, overwrites step 2)
4. RPC returns

So **every `submit_evaluation` call on leader_extra or interview leaves final_score in the drifted state** — until something else fires the trigger again (e.g., another evaluation INSERT) or calls `compute_application_scores` directly.

### Why William reconciled but Francisleila didn't

| Candidate | Status | Last RPC that touched final_score |
|---|---|---|
| **Francisleila** | screening | `submit_evaluation('leader_extra')` 2026-05-21 06:34 → naïve sum, no follow-up |
| **William Junio** | rejected | `submit_interview_scores(...)` (modern interview path) calls `compute_application_scores` explicitly → canonical |
| **Henrique Diniz** | interview_scheduled | trigger refire via subsequent evaluation INSERT (Vitor le 2nd submission) re-ran compute |
| All cycle3 leaders | approved/rejected | Same as William — modern interview path or post-decision orchestration ran compute |

---

## Drift scope: cross-cycle live audit

| Cycle | Role | Apps w/ final | Apps drifted | Drift > 0.5pt | Drift > 10pt |
|---|---|---|---|---|---|
| cycle3-2026 | researcher | 50 | 1 | 0 | 0 |
| cycle3-2026 | leader | 10 | 0 | 0 | 0 |
| cycle3-2026-b2 | researcher | 1 | 0 | 0 | 0 |
| cycle3-2026-b2 | leader | 1 | 0 | 0 | 0 |
| **cycle4-2026** | **leader** | **3** | **1** | **1** | **1** |
| cycle4-2026 | researcher | 34 | 0 | 0 | 0 |

The single cycle3-2026 researcher drift (Fabiano Bressiani, `final_score=35`) has `research_score=NULL` + `interview_score=5` + status=rejected — a separate edge case (partial evaluations on a rejected app, not part of any current/future cohort), not the same drift class.

Only **Francisleila** carries the structural race-condition drift.

---

## Cohort contamination risk

The leader cohort that feeds `compute_pert_cutoff(p_score_column='final_score', p_role='leader')` is `SELECT FROM selection_applications WHERE role_applied='leader' AND status='approved' AND final_score IS NOT NULL` (across all historical cycles).

**Current pool**: 8 approved leaders, all clean.
- 7 from cycle3-2026 (range 214.00 → 287.80)
- 1 from cycle3-2026-b2 (Herlon, final=316.00 — administrative manual_advance path; needs separate sanity check below)
- min=214.00 / max=316.00 / avg=264.73
- hypothetical PERT target if `cohort_n` already hit 10: **264.87** (target), band ≈ [238.38, 291.36]
- target with drifted-rows-excluded: **identical** (no drift in cohort yet)

**cohort_n=8 < 10 → currently `method=disabled`** per p219 Phase 1 threshold. Régua stays inert.

**When does cohort_n hit 10?** Needs 2 more approved leaders. From current cycle4-2026:
- 3 leaders with final_score (Francisleila screening, Henrique interview_scheduled, William rejected)
- If Henrique gets approved AND any other cycle4 leader gets approved (need to triage other in-flight) → cohort hits ≥10 → leader régua becomes dynamic.

**Contamination risk** if régua activates while Francisleila (or analogous in-flight leader) is approved with drifted final_score:

- Hypothetical scenario: cohort grows to 10 including Francisleila's drifted 309 (instead of canonical 158.30)
- Effective cohort_n=10, min=158→**309**? actually min would stay 214 since 309 > 214. But MAX shifts: max=316 → 316. AVG shifts: avg ≈ +15 points upward. PERT target shifts upward by ≈10 points.
- **Effect**: leader régua target inflates → subsequent cycle leaders need higher final_score to clear "Acima da banda" → harder to qualify → **artificial elitization** of leader pool downstream.

The risk is mitigated by the self-heal path (Francisleila will go through interview → submit_interview_scores → compute_application_scores → reconcile). **BUT** if she's approved via a path that doesn't call compute (e.g., manual admin_update_application without interview, or admin_decide_dual_track on a paired researcher app), the naïve sum survives into approval.

---

## Side-finding: Herlon's `final_score=316` (cycle3-2026-b2)

The cycle3-2026-b2 leader cohort row is Herlon, `final_score=316.00`. He was approved via `application.status_manual_advance` on 2026-05-09 (administrative pre-cycle4 onboarding per PM directive — see WATCH-240.B audit p244). His `research_score` is unknown from this query (need to re-query); his `final_score=316` looks high relative to cycle3 leaders (max 287.80). Worth verifying his row passes `final_score = COALESCE(leader_score, research_score)` test as part of any cohort sanity audit. **Not blocking** — he's already in the cohort either way; only relevant if his row also drifted.

---

## Remediation options (PM ratification required — no writes performed)

### Option A — Status quo + observation (lowest scope, accepts structural bug)

- **Action**: do nothing. Drift is currently isolated to 1 row not in cohort; let it self-heal via interview path.
- **Risk**: structural bug remains; future drifts possible (any le submission via submit_evaluation creates transient drift). If any leader is ever approved without going through submit_interview_scores, cohort contaminates.
- **Cost**: 0 lines code, 0 migrations.
- **When to revisit**: when leader cohort_n approaches 9 (next approval triggers dynamic régua); audit then; remediate if any drift in cohort.

### Option B — Manual one-shot fix for Francisleila (smallest surgical fix)

- **Action**: call `compute_application_scores(Francisleila.id)` via `execute_sql` from authenticated session (or admin RPC), with an `admin_audit_log` row documenting the canonical reconciliation.
- **Risk**: structural bug remains; another `submit_evaluation` call on her (e.g., re-submit le with edits) would re-drift.
- **Cost**: 1 RPC call + 1 audit row. ~5 min.
- **When**: any time. Removes the immediate visible drift on /admin/selection.

### Option C — Structural fix to `submit_evaluation` (recommended for permanent)

- **Action**: refactor `submit_evaluation` leader_extra + interview branches to **NOT** write final_score directly. Instead, after the evaluation INSERT, call `PERFORM compute_application_scores(p_application_id)`. The trigger already does this, but making it explicit + removing the inline UPDATE eliminates the race.
- **Risk**: small — `submit_evaluation` is a critical RPC; changes touch evaluator-facing flow. Need contract tests + canonical-formula assertions.
- **Cost**: 1 migration (~50-100 lines), ~10-15 contract assertions (no inline naïve sum write; canonical formula preserved; trigger order intact), ~2-3h.
- **Bonus**: kills the entire drift class, not just Francisleila. Forward-defense locks the regression.

### Option D — Auto-reconciliation cron (defense-in-depth, complements A or B)

- **Action**: schedule weekly `compute_application_scores` for all rows where `final_score != COALESCE(leader_score, research_score)`. Mirrors the `recompute-pert-cutoffs-weekly` pattern (cron jobid 47).
- **Risk**: low — idempotent; only updates drifted rows.
- **Cost**: 1 migration (cron job + helper RPC), ~50 lines, ~1h.
- **When**: pairs with A (catches stragglers without C's invasive refactor) or with C (defense-in-depth).

### Recommendation matrix

| Combo | Effect | Recommended? |
|---|---|---|
| **A only** | Tolerates ongoing drift; risk if leader cohort hits 10 with contamination | NOT recommended once cohort approaches 9 |
| **B only** | Removes Francisleila's drift now; structural bug remains | Quick visibility fix, but PM call before B should consider C |
| **C only** | Permanent fix; kills the class | **RECOMMENDED** (highest leverage) |
| **B + D** | Fixes Francisleila + autoheals future drift | Good middle ground if PM wants to delay C refactor |
| **C + B** | Permanent fix + immediate visibility cleanup | Highest assurance; B is trivial once C is in |

---

## What I did NOT do (and won't until PM ratifies)

- ❌ Did NOT call `compute_application_scores(Francisleila.id)` (Option B would do this)
- ❌ Did NOT modify `submit_evaluation` (Option C)
- ❌ Did NOT create any cron (Option D)
- ❌ Did NOT touch any other apps' `final_score`
- ❌ Did NOT investigate Herlon's `final_score=316` deeply (sidecar audit suggested, not blocking)

---

## Verify-on-re-audit

- Live: `Francisleila.final_score = 309.00` (cycle4-2026, leader, screening) — sediment of `submit_evaluation('leader_extra')` 2026-05-21 06:34:32 UTC, Vitor's submission
- Live: `Francisleila.leader_score = 158.30` (correct, written by compute_application_scores)
- Live: `Francisleila.research_score = 164.00` (correct)
- Live: `Francisleila.objective_score_avg = 164.00`
- Live: 4 evaluations submitted (Fabricio obj+le 2026-05-20, Vitor obj+le 2026-05-21)
- Live: 8 approved leaders all-time with final_score; 0 drift in cohort
- Live: hypothetical leader PERT target if cohort_n>=10 today = 264.87 (no drift impact)
- Live: cohort_n<10 → method=disabled — régua inert (no immediate cohort risk)

If a future session runs the same audit query (`WHERE final_score IS DISTINCT FROM COALESCE(leader_score, research_score)`) and finds zero rows, Option B or C has been applied. If multiple rows appear (especially cycle4 leaders moving toward approval), the structural bug is now contaminating live data and Option C is overdue.

---

## Cross-ref

- p246 #229b Foundation — added `final_score_pert_*` per-app fields; established cohort_n<10 disabled policy carrying over from p219 Phase 1
- p247 #229b Frontend — surfaced `finalScoreChip` on /admin/selection, making this drift visible to PM (rendered as "Régua final: n=6<10" disabled chip for cycle4 leader cohort)
- p245 #229a — `leaderExtraChip` precedent for disabled-state UX
- p219 Phase 1 — leader_extra cohort separation introduced the `cohort_n<10 → method=disabled` threshold
- `selection_cycles.scoring_formula` v1.0-cr047 (approved 2026-04-10) — canonical formula source of truth
- `pg_proc.compute_application_scores` — canonical writer (CR-047 formula)
- `pg_proc.submit_evaluation` — drifted writer (naïve sum, leader_extra + interview branches)
- `pg_proc._trg_recompute_application_scores` + `pg_trigger.trg_recompute_application_scores` — trigger that gets overridden
- `pg_proc.submit_interview_scores` — modern interview path; explicitly calls compute_application_scores, sidesteps the drift
- WATCH-240.B audit (p244) — established Herlon's `application.status_manual_advance` precedent for admin onboarding cycles
