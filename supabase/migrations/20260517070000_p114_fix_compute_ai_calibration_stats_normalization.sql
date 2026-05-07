-- p114 Bug B fix: compute_ai_calibration_stats normalizes final_score by cycle max.
--
-- Bug: function used `(a.final_score::numeric / 10.0) AS human_score_normalized`,
-- assuming final_score is on 0-100 scale. Real scale is sum of (criterion.max ×
-- weight) per scoring_formula CR-047, which for cycle3-2026-b2 yields max=414
-- (objective max=284 + interview max=130). Result: deltas inflated ~4x — Marcio
-- showed delta=18.2 (correct: ~5x lower under proper scaling).
--
-- Fix: derive max_research dynamically from the cycle's objective_criteria +
-- interview_criteria jsonb. Normalize as (final_score / max_research) * 10 so
-- it sits in the same 0-10 scale as ai_triage_score. drift_threshold=2.0
-- keeps semantic of "delta > 2 points on 0-10 scale = high drift".
--
-- TODO (next iteration, not in scope): leader-track normalization uses
-- 0.7*research + 0.3*leader_extra — currently treats all as researcher track
-- (cycle3-2026-b2 has no leader candidates yet). Plus: AI sees pre-interview
-- info only, but final_score post-interview includes int_pert — semantically
-- imperfect comparison. Keeping current behavior for v1.
--
-- Rollback: restore old `(final_score / 10.0)` formula.

CREATE OR REPLACE FUNCTION public.compute_ai_calibration_stats(
  p_cycle_id uuid,
  p_drift_threshold numeric DEFAULT 2.0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cron_context boolean;
  v_n integer;
  v_mean_signed numeric;
  v_mean_abs numeric;
  v_drift_high integer;
  v_sample_payload jsonb;
  v_validator_breakdown jsonb;
  v_run_id uuid;
  v_triggered_by text;
  v_window_start timestamptz := now() - interval '4 weeks';
  v_cycle record;
  v_max_research numeric;
BEGIN
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF v_cron_context THEN
    v_triggered_by := 'cron';
  ELSE
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RETURN jsonb_build_object('error','Not authenticated');
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
      RETURN jsonb_build_object('error','Not authorized: requires view_internal_analytics');
    END IF;
    v_triggered_by := 'admin_request';
  END IF;

  -- Load cycle for normalization scale
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF v_cycle IS NULL THEN
    RETURN jsonb_build_object('error','Cycle not found');
  END IF;

  -- Compute max_research = sum(max × weight) for objective + interview criteria
  v_max_research := COALESCE((
    SELECT SUM((c->>'max')::numeric * COALESCE((c->>'weight')::numeric, 1))
    FROM jsonb_array_elements(v_cycle.objective_criteria) c
  ), 0) + COALESCE((
    SELECT SUM((c->>'max')::numeric * COALESCE((c->>'weight')::numeric, 1))
    FROM jsonb_array_elements(v_cycle.interview_criteria) c
  ), 0);

  -- Guard: if criteria are missing/empty, fall back to legacy /10 to avoid div-by-zero
  IF v_max_research IS NULL OR v_max_research <= 0 THEN
    v_max_research := 100;  -- legacy fallback, equivalent to /10 normalization
  END IF;

  -- ====================================================================
  -- BLOCO 1: delta ai_triage_score vs final_score (normalized to 0-10)
  -- ====================================================================
  WITH paired AS (
    SELECT
      a.id AS application_id,
      a.applicant_name,
      a.ai_triage_score::numeric AS ai_score,
      ROUND((a.final_score::numeric / v_max_research) * 10, 2) AS human_score_normalized,
      ROUND(((a.final_score::numeric / v_max_research) * 10) - a.ai_triage_score::numeric, 2) AS delta_signed
    FROM public.selection_applications a
    WHERE a.cycle_id = p_cycle_id
      AND a.ai_triage_score IS NOT NULL
      AND a.final_score IS NOT NULL
  )
  SELECT
    COUNT(*),
    ROUND(AVG(delta_signed), 3),
    ROUND(AVG(ABS(delta_signed)), 3),
    COUNT(*) FILTER (WHERE ABS(delta_signed) > p_drift_threshold)
  INTO v_n, v_mean_signed, v_mean_abs, v_drift_high
  FROM paired;

  -- Top-5 outliers
  SELECT jsonb_agg(jsonb_build_object(
    'application_id', application_id,
    'applicant_name', applicant_name,
    'ai_score', ai_score,
    'human_score_normalized', human_score_normalized,
    'delta_signed', delta_signed
  ) ORDER BY ABS(delta_signed) DESC)
  INTO v_sample_payload
  FROM (
    SELECT
      a.id AS application_id,
      a.applicant_name,
      a.ai_triage_score::numeric AS ai_score,
      ROUND((a.final_score::numeric / v_max_research) * 10, 2) AS human_score_normalized,
      ROUND(((a.final_score::numeric / v_max_research) * 10) - a.ai_triage_score::numeric, 2) AS delta_signed
    FROM public.selection_applications a
    WHERE a.cycle_id = p_cycle_id
      AND a.ai_triage_score IS NOT NULL
      AND a.final_score IS NOT NULL
    ORDER BY ABS(((a.final_score::numeric / v_max_research) * 10) - a.ai_triage_score::numeric) DESC
    LIMIT 5
  ) top;

  -- ====================================================================
  -- BLOCO 2: validator breakdown (unchanged from p110)
  -- ====================================================================
  WITH cycle_validations AS (
    SELECT v.*, m.name AS validator_name
    FROM public.ai_score_validations v
    JOIN public.selection_applications a ON a.id = v.application_id
    LEFT JOIN public.members m ON m.id = v.validator_id
    WHERE a.cycle_id = p_cycle_id
      AND v.validated_at >= v_window_start
  ),
  global_agg AS (
    SELECT jsonb_build_object(
      'total_validations', COUNT(*),
      'agree_n', COUNT(*) FILTER (WHERE validation_action = 'agree'),
      'disagree_n', COUNT(*) FILTER (WHERE validation_action = 'disagree'),
      'override_n', COUNT(*) FILTER (WHERE validation_action = 'override'),
      'mean_override_delta', ROUND(AVG(override_score - ai_score) FILTER (WHERE validation_action = 'override' AND override_score IS NOT NULL), 3),
      'window_start', v_window_start,
      'window_end', now()
    ) AS payload
    FROM cycle_validations
  ),
  by_validator AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'validator_id', validator_id,
      'name', validator_name,
      'validations_n', validations_n,
      'agreement_rate', ROUND(agreement_rate, 3),
      'bias_signal', ROUND(bias_signal, 3),
      'override_n', override_n
    ) ORDER BY validations_n DESC), '[]'::jsonb) AS payload
    FROM (
      SELECT
        validator_id,
        validator_name,
        COUNT(*) AS validations_n,
        COUNT(*) FILTER (WHERE validation_action = 'agree')::numeric / NULLIF(COUNT(*), 0) AS agreement_rate,
        AVG(override_score - ai_score) FILTER (WHERE validation_action = 'override' AND override_score IS NOT NULL) AS bias_signal,
        COUNT(*) FILTER (WHERE validation_action = 'override') AS override_n
      FROM cycle_validations
      WHERE validator_id IS NOT NULL
      GROUP BY validator_id, validator_name
    ) v
  ),
  by_purpose AS (
    SELECT COALESCE(jsonb_object_agg(ai_purpose, purpose_payload), '{}'::jsonb) AS payload
    FROM (
      SELECT
        ai_purpose,
        jsonb_build_object(
          'total', COUNT(*),
          'agree_n', COUNT(*) FILTER (WHERE validation_action = 'agree'),
          'disagree_n', COUNT(*) FILTER (WHERE validation_action = 'disagree'),
          'override_n', COUNT(*) FILTER (WHERE validation_action = 'override'),
          'mean_override_delta', ROUND(AVG(override_score - ai_score) FILTER (WHERE validation_action = 'override' AND override_score IS NOT NULL), 3)
        ) AS purpose_payload
      FROM cycle_validations
      WHERE ai_purpose IS NOT NULL
      GROUP BY ai_purpose
    ) p
  )
  SELECT jsonb_build_object(
    'global', (SELECT payload FROM global_agg),
    'by_validator', (SELECT payload FROM by_validator),
    'by_purpose', (SELECT payload FROM by_purpose),
    'normalization_max', v_max_research
  )
  INTO v_validator_breakdown;

  -- INSERT
  INSERT INTO public.ai_calibration_runs (
    cycle_id, n_compared, mean_delta_signed, mean_delta_abs, drift_count_high,
    drift_threshold, triggered_by, sample_payload, validator_breakdown
  ) VALUES (
    p_cycle_id, COALESCE(v_n, 0),
    v_mean_signed, v_mean_abs,
    COALESCE(v_drift_high, 0),
    p_drift_threshold, v_triggered_by,
    v_sample_payload, v_validator_breakdown
  )
  RETURNING id INTO v_run_id;

  RETURN jsonb_build_object(
    'run_id', v_run_id,
    'cycle_id', p_cycle_id,
    'n_compared', COALESCE(v_n, 0),
    'mean_delta_signed', v_mean_signed,
    'mean_delta_abs', v_mean_abs,
    'drift_count_high', COALESCE(v_drift_high, 0),
    'drift_threshold', p_drift_threshold,
    'triggered_by', v_triggered_by,
    'top_outliers', COALESCE(v_sample_payload, '[]'::jsonb),
    'validator_breakdown', v_validator_breakdown,
    'normalization_max', v_max_research,
    'ran_at', now()
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
