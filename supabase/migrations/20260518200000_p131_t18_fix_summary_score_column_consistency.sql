-- p131 #22 fix: get_pert_cutoff_summary usa mesma coluna do RPC compute
-- Bug: comparava distribution (below/within/above band) usando final_score
-- mas target/banda foi calculado em objective_score_avg pelo compute_pert_cutoff
-- (default p131 fix). Resultado funcionava mas semanticamente inconsistente.

CREATE OR REPLACE FUNCTION public.get_pert_cutoff_summary(
  p_cycle_id uuid,
  p_score_column text DEFAULT 'objective_score_avg'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_summary record;
  v_cycle record;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL OR NOT public.can_by_member(v_member_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'access_denied');
  END IF;

  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score') THEN
    RETURN jsonb_build_object('error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg','final_score','research_score'));
  END IF;

  SELECT id, cycle_code INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF v_cycle.id IS NULL THEN RETURN jsonb_build_object('error', 'cycle_not_found'); END IF;

  SELECT
    COUNT(*) AS apps_total,
    COUNT(*) FILTER (WHERE pert_target_score IS NOT NULL) AS apps_with_pert,
    MAX(pert_calc_at) AS last_calc_at,
    MAX(pert_cohort_n) AS cohort_n,
    MAX(pert_target_score) AS target_score,
    MAX(pert_band_lower) AS band_lower,
    MAX(pert_band_upper) AS band_upper,
    MAX(pert_cutoff_method) AS method,
    COUNT(*) FILTER (
      WHERE CASE p_score_column
              WHEN 'objective_score_avg' THEN objective_score_avg IS NOT NULL AND objective_score_avg < pert_band_lower
              WHEN 'final_score' THEN final_score IS NOT NULL AND final_score < pert_band_lower
              WHEN 'research_score' THEN research_score IS NOT NULL AND research_score < pert_band_lower
            END
    ) AS below_band,
    COUNT(*) FILTER (
      WHERE CASE p_score_column
              WHEN 'objective_score_avg' THEN objective_score_avg IS NOT NULL AND objective_score_avg > pert_band_upper
              WHEN 'final_score' THEN final_score IS NOT NULL AND final_score > pert_band_upper
              WHEN 'research_score' THEN research_score IS NOT NULL AND research_score > pert_band_upper
            END
    ) AS above_band,
    COUNT(*) FILTER (
      WHERE CASE p_score_column
              WHEN 'objective_score_avg' THEN objective_score_avg IS NOT NULL AND objective_score_avg BETWEEN pert_band_lower AND pert_band_upper
              WHEN 'final_score' THEN final_score IS NOT NULL AND final_score BETWEEN pert_band_lower AND pert_band_upper
              WHEN 'research_score' THEN research_score IS NOT NULL AND research_score BETWEEN pert_band_lower AND pert_band_upper
            END
    ) AS within_band,
    COUNT(*) FILTER (
      WHERE CASE p_score_column
              WHEN 'objective_score_avg' THEN objective_score_avg IS NULL
              WHEN 'final_score' THEN final_score IS NULL
              WHEN 'research_score' THEN research_score IS NULL
            END
    ) AS not_yet_scored
  INTO v_summary
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code,
    'score_column_used', p_score_column,
    'apps_total', v_summary.apps_total,
    'apps_with_pert', v_summary.apps_with_pert,
    'last_calc_at', v_summary.last_calc_at,
    'cohort_n', v_summary.cohort_n,
    'target_score', v_summary.target_score,
    'band_lower', v_summary.band_lower,
    'band_upper', v_summary.band_upper,
    'method', v_summary.method,
    'distribution', jsonb_build_object(
      'below_band', v_summary.below_band,
      'within_band', v_summary.within_band,
      'above_band', v_summary.above_band,
      'not_yet_scored', v_summary.not_yet_scored
    )
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
