# Cycle 4 PERT Cutoff State + Cron Posture — WATCH-240.C audit (p242)

**Sessão:** p242 (2026-05-24)
**Branch:** `agent/p242-watch-240-c-pert-cutoff-audit`
**Scope:** Read-only audit + one PM-authorized live invocation of `recompute_all_active_pert_cutoffs()`. No migrations, no schema changes, no app status writes.
**Gate:** PM Option A — audit doc closes WATCH-240.C as informational; status advance for the 8 cycle4 apps in `screening` remains a PM committee decision via `finalize_decisions(cycle4, [...])` at the next meeting.

## Executive summary

WATCH-240.C was carried from p241 with the framing: *"11 cycle4 apps advanced from `screening` directly to `interview_*` via the p240 backfill (skipping `objective_eval`/`objective_cutoff`/`interview_pending`). Separate cluster issue (p230 fast-follow carry already exists for selection_cutoff_approved cron schedule)."* The PM reframed in p242 boot as *"11 apps cycle4 precisam do avanço/cálculo PERT cutoff."*

Audit findings:

1. **PERT cutoff calculation was never run live for cycle4-2026 until 2026-05-24 15:40:38 UTC** (this audit's manual invocation). The cron `recompute-pert-cutoffs-weekly` (jobid 47) was installed in p228 (2026-05-23 Sat); its first scheduled fire is **Mon 2026-05-25 13:00 UTC** ≈ 22h from this audit's invocation. `cron.job_run_details` confirms 0 runs in 30d, `last_run` IS NULL — *not a bug*, just a brand-new cron that hasn't had its first window yet.
2. **Manual recompute populated all 38 cycle4 apps + 2 cycle3-b2 apps** with `pert_target_score` / `pert_band_lower` / `pert_band_upper` / `pert_calc_at`. cycle4 researcher target=155.42, band=[139.88, 170.96], cohort_n=19; cycle3-b2 target=155.78, band=[140.20, 171.36], cohort_n=18. Both leader_extra tracks `method=disabled` (cohort_n=6 < 10 threshold — expected per p219 Phase 1 design).
3. **11 cycle4 apps are above-target** (matches PM's "11 apps" framing). 6 already in `interview_*` status (advancing correctly); **5 still in `screening`** — these need explicit PM committee advance via `finalize_decisions` because the canonical path requires committee role to satisfy auth gate.
4. **0/38 cycle4 apps have `cutoff_approved_email_sent_at` set** — the notification dispatch hook (p228 W2 Leaf 4 foundation) hasn't fired for any cycle4 app yet. Orthogonal to WATCH-240.C; will fire naturally once apps transition through the canonical workflow.

**Disposition**: WATCH-240.C closes as **informational**. Calculation gap is closed (manual recompute + tomorrow's cron). Advance gap is governance-by-design (PM committee owns `finalize_decisions`).

## Cycle 4 PERT Cutoff State (post-recompute, 2026-05-24 15:40:38 UTC)

| Track | Method | Target | Band Lower | Band Upper | Cohort N | Cohort Avg | Rows Updated |
|---|---|---|---|---|---|---|---|
| researcher (objective_score_avg) | dynamic | **155.42** | 139.88 | 170.96 | 19 | 149.84 | 38 |
| leader (leader_extra_pert_score) | disabled | — | — | — | 6 | 57.50 | 38 |

For cycle3-2026-b2 (also in `phase=evaluating`):

| Track | Method | Target | Band Lower | Band Upper | Cohort N | Cohort Avg | Rows Updated |
|---|---|---|---|---|---|---|---|
| researcher | dynamic | 155.78 | 140.20 | 171.36 | 18 | 150.56 | 2 |
| leader | disabled | — | — | — | 6 | 57.50 | 2 |

(cycle3-b2 had only 2 apps still in scope — most cycle3 candidates already in terminal status.)

## Cycle 4 Status × Band Crosstab

| Status | Total | Above Target | In Band (Below Target) | Below Band | Email Sent |
|---|---|---|---|---|---|
| interview_done | 10 | 1 | 2 | 7 | 0 |
| interview_pending | 13 | 3 | 1 | 9 | 0 |
| interview_scheduled | 4 | 1 | 1 | 2 | 0 |
| objective_cutoff | 1 | 0 | 0 | 1 | 0 |
| rejected | 2 | 1 | 0 | 0 | 0 |
| screening | **8** | **5** | **1** | **2** | 0 |
| **Total** | **38** | **11** | **5** | **21** | **0** |

The 11 above-target apps (PM's "11 apps cycle4") break down as 1 + 3 + 1 + 1 + 5 = 11. The 6 already in `interview_*` will progress through the canonical interview workflow (p240 trigger + p241 hoist now keep them moving). **The 5 still in `screening` are the actionable backlog for PM committee.**

## Detail of the 8 Cycle 4 Apps in `screening`

| Applicant | obj_avg | Band Position | Suggested Next Action |
|---|---|---|---|
| Henrique Diniz S. Silva | 227.00 | above_target | committee approves → `objective_done` (top performer) |
| João Coelho Júnior | 171.00 | above_target | committee approves → `objective_done` |
| Francisleila Melo Santos | 164.00 | above_target | committee approves → `objective_done` |
| Cristiano de Oliveira Santos Filho | 163.00 | above_target | committee approves → `objective_done` |
| Edinan Soares | 157.50 | above_target | committee approves → `objective_done` |
| Hector Rigon | 140.50 | in_band_below_target | **committee judgment call** — within ±10% band but below 155.42 target |
| Alexandre Fortes | 119.50 | below_band | committee approves → `objective_cutoff` (below band lower) |
| Carla Rosa | 117.50 | below_band | committee approves → `objective_cutoff` (below band lower) |

Suggested `finalize_decisions(cycle4, …)` JSON skeleton for PM (PM amends per committee discussion):

```json
{
  "approve": [
    "bcc54dfc-ac79-4a26-a05f-eeb571d48fd9", // Henrique
    "cef2b25e-4bc0-4e0e-a642-a3f3fec68549", // João
    "72ea1a45-8dc8-4b0b-b4cb-f1427968ff22", // Francisleila
    "f82f5ec7-1a76-4960-8c0d-5a94b502ffc3", // Cristiano
    "77fdb870-5398-4c52-abda-b292b594b558"  // Edinan
  ],
  "in_band_review": [
    "c78b885b-95e6-4cb8-91e6-a026423b6c78"  // Hector — committee judgment
  ],
  "below_cutoff": [
    "c5b8be87-17f2-4cc4-a104-3838d9cbc435", // Alexandre
    "afb35307-6693-4fd4-82d0-7d5a49c3572e"  // Carla
  ]
}
```

Exact `finalize_decisions` signature: `finalize_decisions(p_cycle_id uuid, p_decisions jsonb)` — PM should consult the RPC body or invoke from an authenticated MCP-Claude session to construct the canonical `p_decisions` shape per its parser. The above is per-app classification; the RPC may expect a different keying.

## Cron Posture — `recompute-pert-cutoffs-weekly`

| Field | Value |
|---|---|
| jobid | 47 |
| jobname | `recompute-pert-cutoffs-weekly` |
| schedule | `0 13 * * 1` (Mondays 13:00 UTC = 10:00 BRT) |
| active | true |
| command | `SELECT public.recompute_all_active_pert_cutoffs()` |
| runs_30d | **0** |
| last_run | **NULL** |
| next scheduled fire | **2026-05-25 13:00 UTC ≈ 22h from this audit** |
| installed | p228 (2026-05-23 Sat, ≈22:00 UTC) — install time post-dates last Mon 13:00 window |

**Not a bug.** The 0-runs reading is consistent with the install date: between install (Sat 2026-05-23 ~22:00 UTC) and the next scheduled fire (Mon 2026-05-25 13:00 UTC), no Monday-13:00-UTC window has elapsed. Tomorrow's fire will be the first execution.

**Verify-after-first-fire recipe** (run after Mon 2026-05-25 13:00 UTC):

```sql
SELECT runid, start_time, end_time, status,
  CASE WHEN length(return_message) > 200 THEN left(return_message,200)||'…' ELSE return_message END AS msg
FROM cron.job_run_details
WHERE jobid = 47
ORDER BY start_time DESC LIMIT 3;

-- Confirm pert_calc_at advanced on cycle4 + cycle3-b2 (proxy: max pert_calc_at across all apps in those cycles)
SELECT c.cycle_code, max(a.pert_calc_at) AS most_recent_recompute, count(*) AS apps
FROM public.selection_applications a
JOIN public.selection_cycles c ON c.id = a.cycle_id
WHERE c.cycle_code IN ('cycle4-2026', 'cycle3-2026-b2')
GROUP BY c.cycle_code;
```

If cron runs cleanly and `most_recent_recompute` matches the run start_time within ~1 minute, the cron is healthy and WATCH-240.C is fully closed.

## Audit Method (Reproducibility)

```sql
-- 1. Confirm cycle state + phase
SELECT cycle_code, phase, status, created_at, leads_auto_promoted_at
FROM public.selection_cycles WHERE cycle_code IN ('cycle4-2026', 'cycle3-2026-b2');

-- 2. Manual recompute (idempotent — re-runs OK)
SELECT public.recompute_all_active_pert_cutoffs();

-- 3. Crosstab status × band positioning
SELECT status,
  count(*) AS n,
  count(*) FILTER (WHERE pert_target_score IS NOT NULL) AS has_target,
  count(*) FILTER (WHERE objective_score_avg >= 155.42) AS above_target,
  count(*) FILTER (WHERE objective_score_avg >= 139.88 AND objective_score_avg < 155.42) AS in_band_below_target,
  count(*) FILTER (WHERE objective_score_avg < 139.88) AS below_band,
  count(*) FILTER (WHERE cutoff_approved_email_sent_at IS NOT NULL) AS email_sent
FROM public.selection_applications
WHERE cycle_id = (SELECT id FROM public.selection_cycles WHERE cycle_code='cycle4-2026')
GROUP BY status ORDER BY status;

-- 4. Detail of stuck-in-screening apps
SELECT id, applicant_name, status, objective_score_avg, pert_target_score, pert_band_lower, pert_band_upper,
  CASE
    WHEN objective_score_avg >= pert_target_score THEN 'above_target'
    WHEN objective_score_avg >= pert_band_lower THEN 'in_band_below_target'
    ELSE 'below_band'
  END AS band_pos
FROM public.selection_applications
WHERE cycle_id = (SELECT id FROM public.selection_cycles WHERE cycle_code='cycle4-2026') AND status='screening'
ORDER BY objective_score_avg DESC NULLS LAST;

-- 5. Cron health (whole platform)
SELECT j.jobid, j.jobname, j.schedule, j.active,
  count(jrd.runid) FILTER (WHERE jrd.start_time > now() - interval '30 days') AS runs_30d,
  max(jrd.start_time) AS last_run
FROM cron.job j
LEFT JOIN cron.job_run_details jrd ON jrd.jobid = j.jobid
WHERE j.jobname IN ('recompute-pert-cutoffs-weekly', 'selection-interview-overdue-daily')
GROUP BY j.jobid, j.jobname, j.schedule, j.active;
```

## Open follow-ups (not blocking WATCH-240.C close)

1. **0/38 emails for cutoff_approved**: The `cutoff_approved_email_sent_at` column exists (p228 W2 Leaf 4 foundation) but no app has ever been dispatched. The dispatch trigger is gated on `selection_cutoff_approved` notification, which itself fires after `finalize_decisions` advances apps to `objective_done`. Since `finalize_decisions` was never run for cycle4, the chain never started. Will resolve naturally once PM committee runs `finalize_decisions`.
2. **In-band judgment**: Hector Rigon (140.50) is within ±10% band but below target. The current `recompute_all_active_pert_cutoffs()` output doesn't encode a band-resolution policy (committee call vs auto-approve vs auto-reject). PM may want a written policy memo for future band candidates — not urgent (1 borderline case in cycle4).
3. **Cycle3-b2 minor**: only 2 cycle3-b2 apps still in scope for cutoff updates. PM may want to verify these 2 are the late-evaluation candidates from p240 backfill (`WATCH-240.B`) before next session.
4. **Cron observability**: jobid 47 has no health-check RPC; the verify-after-first-fire recipe above is manual. A `get_selection_cron_health()` MCP tool could surface this in the admin dashboard — defer until PM signals demand.

## Cross-ref

- WATCH-240.C in `memory/handoff_p241_post_p240_close.md` (origin) and `memory/handoff_p240_post_p239b_close.md` (precursor framing)
- P162 entry #208 RESOLVED-#251 (p240 trigger that backfilled the 11 above-target apps into `interview_*` status)
- P162 entry #209 RESOLVED-WATCH-240.A (p241 `submit_interview_scores` hoist — defense-in-depth for the partial-submission path the 5 stuck-in-screening apps will travel after committee approval)
- p219 Phase 1 (`leader_extra` cohort separation; established `cohort_n=10` threshold for `method=dynamic` vs `method=disabled`)
- p228 W2 Leaf 4 (`selection_cutoff_approved` notification foundation + cron `recompute-pert-cutoffs-weekly` installed)
- p230 fast-follow carries (auto-trigger design for `selection_cutoff_approved` — still open as enhancement, not a bug)
- `selection_applications.cutoff_approved_email_sent_at` column (notification dispatch tracking — currently 0/38 for cycle4, will fire naturally post-`finalize_decisions`)
