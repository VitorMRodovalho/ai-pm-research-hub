-- p695 #695 — Close the final_score PERT NULL window (no app may have final_score
--             set while final_score_pert_cutoff_method stays NULL).
--
-- WHAT: Add a row-level AFTER INSERT OR UPDATE OF final_score trigger on
--       selection_applications that re-stamps the track-resolved final_score PERT régua
--       (target/band/method/cohort_n) for every (cycle_id, role_applied) pair touched by
--       the write, by delegating to _compute_pert_cutoff_core(..., 'final_score', ...).
--       Plus a one-shot heal of the currently-open window via the canonical recompute.
--
-- WHY: #695 — compute_application_scores(p_application_id) writes
--      final_score = COALESCE(leader_score, research_score) per app, but does NOT touch the
--      final_score_pert_* columns. Those were only ever populated by the weekly cron
--      recompute_all_active_pert_cutoffs (p246) or the phase->evaluating trigger (p197c,
--      objective-only). So a freshly-scored app sits with final_score NOT NULL and
--      final_score_pert_cutoff_method NULL until the next Monday cron run — a window that
--      breaks the p246 invariant and the per-track PERT classification. The two bulk
--      writers (import_historical_evaluations, import_leader_evaluations) have the same gap.
--      A trigger is the single chokepoint covering all current + future final_score writers.
--
-- DESIGN NOTES:
--   * Row-level (FOR EACH ROW): Postgres forbids a transition table (REFERENCING NEW TABLE)
--     on a trigger with a column list (UPDATE OF final_score) OR with more than one event,
--     so a statement-level dedup is not available here. Row-level mirrors the existing PERT
--     trigger _trg_pert_on_phase_evaluating (p197c). The common writer
--     (compute_application_scores) is single-row per call, so this is one recompute per score.
--     A bulk import re-runs the (idempotent) recompute per row; imports are rare admin ops.
--   * Recursion-safe: _compute_pert_cutoff_core's final_score branch UPDATEs only the
--     final_score_pert_* columns (never final_score), and this trigger is scoped to
--     `UPDATE OF final_score`, so the core's own UPDATE cannot re-fire it.
--   * The final_score cohort is drawn from PRIOR cycles' approved apps only, so the régua
--     is stable across apps within the same (cycle, role) — recomputing per write is
--     idempotent, it just refreshes calc_at.
--
-- ROLLBACK:
--   DROP TRIGGER IF EXISTS trg_final_score_pert_refresh ON public.selection_applications;
--   DROP FUNCTION IF EXISTS public._trg_recompute_final_score_pert();

-- ============================================================================
-- 1. Trigger function: recompute final_score PERT per (cycle, role) touched
-- ============================================================================

CREATE OR REPLACE FUNCTION public._trg_recompute_final_score_pert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Re-stamp the track-resolved final_score PERT régua for this row's (cycle, role),
  -- closing the NULL window transactionally with the score write. The core re-stamps
  -- target/band/method/cohort_n for the whole (cycle, role); the value is cohort-from-
  -- prior-cycles, hence stable and idempotent across apps in the same (cycle, role).
  IF NEW.final_score IS NOT NULL
     AND NEW.cycle_id IS NOT NULL
     AND NEW.role_applied IS NOT NULL THEN
    PERFORM public._compute_pert_cutoff_core(NEW.cycle_id, NEW.role_applied, true, 'final_score', NULL);
  END IF;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public._trg_recompute_final_score_pert() IS
  'p695 #695: AFTER INSERT OR UPDATE OF final_score row trigger on selection_applications. Re-stamps the track-resolved final_score PERT régua (via _compute_pert_cutoff_core final_score branch) for the row''s (cycle, role), so no app sits with final_score set and final_score_pert_cutoff_method NULL until the weekly cron. Recursion-safe: the core UPDATEs only final_score_pert_* columns, never final_score.';

-- ============================================================================
-- 2. Trigger wiring (row-level; column list + multi-event are incompatible with
--    transition tables in Postgres, so no statement-level dedup here).
-- ============================================================================

DROP TRIGGER IF EXISTS trg_final_score_pert_refresh ON public.selection_applications;
CREATE TRIGGER trg_final_score_pert_refresh
  AFTER INSERT OR UPDATE OF final_score ON public.selection_applications
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_recompute_final_score_pert();

-- ============================================================================
-- 3. Heal the currently-open window (idempotent canonical recompute)
--    Stamps the régua for every active cycle (objective + leader_extra + final_score
--    both tracks), fixing any app scored since the last cron run.
-- ============================================================================

SELECT public.recompute_all_active_pert_cutoffs();
