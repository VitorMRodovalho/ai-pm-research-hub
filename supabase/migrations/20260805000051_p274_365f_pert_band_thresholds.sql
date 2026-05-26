-- p274 #365f - CR-042 PERT band thresholds
--
-- WHAT:
--   Corrects the classification band around the PERT target. CR-042 uses PERT
--   as the cutoff: scores above PERT are above the rule, scores from 75% of
--   PERT through PERT are in-band, and scores below 75% of PERT are below.
--
-- WHY:
--   p273 fixed the cohort source but kept the older +/-10% band semantics
--   (target*0.90..target*1.10). That made candidates just below PERT show
--   inconsistently with the PM rule. This migration preserves the current-cycle
--   cohort, preserves the formula, and only changes band bounds.
--
-- NON-ACTIONS:
--   No status writes, no automatic approvals/rejections, no score changes. The
--   committee remains human-in-the-loop.

CREATE OR REPLACE FUNCTION public._compute_pert_cutoff_core(
  p_cycle_id uuid,
  p_role text DEFAULT 'researcher'::text,
  p_filter_active_only boolean DEFAULT true,
  p_score_column text DEFAULT 'objective_score_avg'::text,
  p_actor_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_cycle record;
  v_cohort record;
  v_target numeric;
  v_band_lower numeric;
  v_band_upper numeric;
  v_method text;
  v_n int;
  v_updated_rows int;
  v_fallback_target numeric;
  v_is_leader_extra boolean;
  v_is_final_score boolean;
BEGIN
  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score', 'leader_extra_pert_score') THEN
    RETURN jsonb_build_object(
      'error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg', 'final_score', 'research_score', 'leader_extra_pert_score'),
      'received', p_score_column
    );
  END IF;

  v_is_leader_extra := (p_score_column = 'leader_extra_pert_score');
  v_is_final_score := (p_score_column = 'final_score');

  SELECT sc.id, sc.cycle_code INTO v_cycle FROM public.selection_cycles sc WHERE sc.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('error', 'cycle_not_found', 'cycle_id', p_cycle_id);
  END IF;

  WITH cohort_apps AS (
    SELECT
      CASE p_score_column
        WHEN 'objective_score_avg' THEN sa.objective_score_avg
        WHEN 'final_score' THEN sa.final_score
        WHEN 'research_score' THEN sa.research_score
        WHEN 'leader_extra_pert_score' THEN sa.leader_extra_pert_score
      END AS s
    FROM public.selection_applications sa
    WHERE sa.cycle_id = p_cycle_id
      AND sa.role_applied = p_role
      AND CASE p_score_column
            WHEN 'objective_score_avg' THEN sa.objective_score_avg IS NOT NULL
            WHEN 'research_score' THEN sa.research_score IS NOT NULL
            WHEN 'leader_extra_pert_score' THEN sa.leader_extra_pert_score IS NOT NULL
            WHEN 'final_score' THEN
              sa.final_score IS NOT NULL
              AND sa.interview_score IS NOT NULL
              AND (
                p_role != 'leader'
                OR sa.leader_extra_pert_score IS NOT NULL
              )
          END
  )
  SELECT COUNT(*)::int AS n, MIN(s) AS s_min, MAX(s) AS s_max, AVG(s) AS s_avg
  INTO v_cohort FROM cohort_apps;

  v_n := COALESCE(v_cohort.n, 0);

  IF v_n >= 10 THEN
    v_target := (2 * v_cohort.s_min + 4 * v_cohort.s_avg + 2 * v_cohort.s_max) / 8;
    v_method := 'dynamic';
  ELSE
    IF v_is_final_score THEN
      SELECT MAX(final_score_pert_target)
      INTO v_fallback_target
      FROM public.selection_applications
      WHERE cycle_id != p_cycle_id
        AND role_applied = p_role
        AND final_score_pert_target IS NOT NULL;
    ELSE
      SELECT MAX(CASE WHEN v_is_leader_extra THEN leader_extra_pert_target ELSE pert_target_score END)
      INTO v_fallback_target
      FROM public.selection_applications
      WHERE cycle_id != p_cycle_id
        AND CASE WHEN v_is_leader_extra THEN leader_extra_pert_target IS NOT NULL ELSE pert_target_score IS NOT NULL END;
    END IF;
    IF v_fallback_target IS NULL THEN
      v_target := NULL; v_method := 'disabled';
    ELSE
      v_target := v_fallback_target; v_method := 'historical_fallback';
    END IF;
  END IF;

  IF v_target IS NOT NULL THEN
    v_band_lower := v_target * 0.75;
    v_band_upper := v_target;
  END IF;

  IF v_is_leader_extra THEN
    UPDATE public.selection_applications
    SET leader_extra_pert_target = v_target,
        leader_extra_pert_band_lower = v_band_lower,
        leader_extra_pert_band_upper = v_band_upper,
        leader_extra_pert_cutoff_method = v_method,
        leader_extra_pert_cohort_n = v_n,
        leader_extra_pert_calc_at = now()
    WHERE cycle_id = p_cycle_id;
  ELSIF v_is_final_score THEN
    UPDATE public.selection_applications
    SET final_score_pert_target = v_target,
        final_score_pert_band_lower = v_band_lower,
        final_score_pert_band_upper = v_band_upper,
        final_score_pert_cutoff_method = v_method,
        final_score_pert_cohort_n = v_n,
        final_score_pert_calc_at = now()
    WHERE cycle_id = p_cycle_id
      AND role_applied = p_role;
  ELSE
    UPDATE public.selection_applications
    SET pert_target_score = v_target,
        pert_band_lower = v_band_lower,
        pert_band_upper = v_band_upper,
        pert_cutoff_method = v_method,
        pert_cohort_n = v_n,
        pert_calc_at = now()
    WHERE cycle_id = p_cycle_id;
  END IF;
  GET DIAGNOSTICS v_updated_rows = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    p_actor_id, 'pert_cutoff_computed', 'selection_cycle', p_cycle_id,
    jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'role', p_role,
      'score_column_used', p_score_column,
      'filter_active_only_legacy_arg', p_filter_active_only,
      'cohort_scope', 'current_cycle_applications_by_role',
      'final_score_requires_complete_components', v_is_final_score,
      'cohort_n', v_n,
      'cohort_min', v_cohort.s_min,
      'cohort_max', v_cohort.s_max,
      'cohort_avg', v_cohort.s_avg,
      'target_score', v_target,
      'band_lower', v_band_lower,
      'band_upper', v_band_upper,
      'method', v_method,
      'rows_updated', v_updated_rows
    ),
    jsonb_build_object('source', '_compute_pert_cutoff_core', 'actor_kind', CASE WHEN p_actor_id IS NULL THEN 'system' ELSE 'human' END, 'cr', 'CR-042')
  );

  RETURN jsonb_build_object(
    'success', true, 'cycle_id', p_cycle_id, 'cycle_code', v_cycle.cycle_code,
    'role', p_role, 'score_column_used', p_score_column,
    'cohort_scope', 'current_cycle_applications_by_role',
    'cohort_n', v_n,
    'cohort_stats', jsonb_build_object('min', v_cohort.s_min, 'max', v_cohort.s_max, 'avg', v_cohort.s_avg),
    'target_score', v_target, 'band_lower', v_band_lower, 'band_upper', v_band_upper,
    'method', v_method, 'rows_updated', v_updated_rows, 'computed_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public._compute_pert_cutoff_core(uuid, text, boolean, text, uuid) IS
  'p274 #365f: CR-042 current-cycle PERT cutoff core. Cohort = applications in the same cycle and role with the requested score dimension populated. Formula remains (2*min + 4*avg + 2*max)/8. Band semantics: below < 75% of PERT, in-band = 75% of PERT through PERT, above > PERT. No status/decision writes.';

COMMENT ON COLUMN public.selection_applications.pert_band_lower IS
  'p274 #365f: lower PERT band bound = target * 0.75. Score below this value is below the rule.';
COMMENT ON COLUMN public.selection_applications.pert_band_upper IS
  'p274 #365f: upper PERT band bound = target. Score above this value is above the rule; score between lower and target is in-band.';
COMMENT ON COLUMN public.selection_applications.leader_extra_pert_band_lower IS
  'p274 #365f: lower PERT band bound for leader_extra = target * 0.75.';
COMMENT ON COLUMN public.selection_applications.leader_extra_pert_band_upper IS
  'p274 #365f: upper PERT band bound for leader_extra = target.';
COMMENT ON COLUMN public.selection_applications.final_score_pert_band_lower IS
  'p274 #365f: lower PERT band bound for final_score = target * 0.75.';
COMMENT ON COLUMN public.selection_applications.final_score_pert_band_upper IS
  'p274 #365f: upper PERT band bound for final_score = target.';

DO $$
BEGIN
  PERFORM public.recompute_all_active_pert_cutoffs();
END $$;

NOTIFY pgrst, 'reload schema';
