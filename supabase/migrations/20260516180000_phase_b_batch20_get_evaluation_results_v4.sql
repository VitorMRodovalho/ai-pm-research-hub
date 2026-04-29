-- Phase B'' batch 20.2: get_evaluation_results V3 sa-bypass → V4 can_by_member('manage_platform')
-- V3 composite: committee member (resource) OR is_superadmin
-- V4: replace is_superadmin IS TRUE with can_by_member('manage_platform')
-- Resource-scoped check (selection_committee membership) preserved
-- Impact: V3=2 sa, V4=2 manage_platform
CREATE OR REPLACE FUNCTION public.get_evaluation_results(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_min_evaluators int;
  v_evaluations jsonb;
  v_calibration_alerts jsonb := '[]'::jsonb;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_scores_for_key numeric[];
  v_divergence numeric;
  v_pert_objective numeric;
  v_pert_interview numeric;
  v_pert_leader numeric;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get application + cycle
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- 3. V4 authorization: committee member (resource) or platform admin
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- 4. Blind enforcement: check all required evaluators submitted for at least objective
  v_min_evaluators := v_cycle.min_evaluators;

  IF (
    SELECT COUNT(*) FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluation_type = 'objective'
      AND submitted_at IS NOT NULL
  ) < v_min_evaluators THEN
    RAISE EXCEPTION 'Blind review: not all evaluators have submitted yet';
  END IF;

  -- 5. Gather all evaluations with evaluator names
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'evaluator_id', e.evaluator_id,
      'evaluator_name', m.name,
      'evaluation_type', e.evaluation_type,
      'scores', e.scores,
      'weighted_subtotal', e.weighted_subtotal,
      'notes', e.notes,
      'submitted_at', e.submitted_at
    ) ORDER BY m.name, e.evaluation_type
  ), '[]'::jsonb)
  INTO v_evaluations
  FROM public.selection_evaluations e
  JOIN public.members m ON m.id = e.evaluator_id
  WHERE e.application_id = p_application_id
    AND e.submitted_at IS NOT NULL;

  -- 6. Calibration alerts: check divergence > 3 points per criterion
  -- Check objective criteria
  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_cycle.objective_criteria)
  LOOP
    v_key := v_criterion ->> 'key';

    SELECT ARRAY_AGG((e.scores ->> v_key)::numeric)
    INTO v_scores_for_key
    FROM public.selection_evaluations e
    WHERE e.application_id = p_application_id
      AND e.evaluation_type = 'objective'
      AND e.submitted_at IS NOT NULL
      AND e.scores ? v_key
      AND (e.scores ->> v_key) IS NOT NULL;

    IF v_scores_for_key IS NOT NULL AND array_length(v_scores_for_key, 1) >= 2 THEN
      v_divergence := (SELECT MAX(v) - MIN(v) FROM unnest(v_scores_for_key) v);
      IF v_divergence > 3 THEN
        v_calibration_alerts := v_calibration_alerts || jsonb_build_object(
          'criterion', v_key,
          'type', 'objective',
          'divergence', ROUND(v_divergence, 2),
          'scores', to_jsonb(v_scores_for_key)
        );
      END IF;
    END IF;
  END LOOP;

  -- Check interview criteria
  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_cycle.interview_criteria)
  LOOP
    v_key := v_criterion ->> 'key';

    SELECT ARRAY_AGG((e.scores ->> v_key)::numeric)
    INTO v_scores_for_key
    FROM public.selection_evaluations e
    WHERE e.application_id = p_application_id
      AND e.evaluation_type = 'interview'
      AND e.submitted_at IS NOT NULL
      AND e.scores ? v_key
      AND (e.scores ->> v_key) IS NOT NULL;

    IF v_scores_for_key IS NOT NULL AND array_length(v_scores_for_key, 1) >= 2 THEN
      v_divergence := (SELECT MAX(v) - MIN(v) FROM unnest(v_scores_for_key) v);
      IF v_divergence > 3 THEN
        v_calibration_alerts := v_calibration_alerts || jsonb_build_object(
          'criterion', v_key,
          'type', 'interview',
          'divergence', ROUND(v_divergence, 2),
          'scores', to_jsonb(v_scores_for_key)
        );
      END IF;
    END IF;
  END LOOP;

  -- Check leader extra criteria
  IF v_cycle.leader_extra_criteria IS NOT NULL AND jsonb_array_length(v_cycle.leader_extra_criteria) > 0 THEN
    FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_cycle.leader_extra_criteria)
    LOOP
      v_key := v_criterion ->> 'key';

      SELECT ARRAY_AGG((e.scores ->> v_key)::numeric)
      INTO v_scores_for_key
      FROM public.selection_evaluations e
      WHERE e.application_id = p_application_id
        AND e.evaluation_type = 'leader_extra'
        AND e.submitted_at IS NOT NULL
        AND e.scores ? v_key
        AND (e.scores ->> v_key) IS NOT NULL;

      IF v_scores_for_key IS NOT NULL AND array_length(v_scores_for_key, 1) >= 2 THEN
        v_divergence := (SELECT MAX(v) - MIN(v) FROM unnest(v_scores_for_key) v);
        IF v_divergence > 3 THEN
          v_calibration_alerts := v_calibration_alerts || jsonb_build_object(
            'criterion', v_key,
            'type', 'leader_extra',
            'divergence', ROUND(v_divergence, 2),
            'scores', to_jsonb(v_scores_for_key)
          );
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- 7. Compute PERT per type from subtotals
  SELECT ROUND((2 * MIN(weighted_subtotal) + 4 * AVG(weighted_subtotal) + 2 * MAX(weighted_subtotal)) / 8, 2)
  INTO v_pert_objective
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'objective'
    AND submitted_at IS NOT NULL;

  SELECT ROUND((2 * MIN(weighted_subtotal) + 4 * AVG(weighted_subtotal) + 2 * MAX(weighted_subtotal)) / 8, 2)
  INTO v_pert_interview
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'interview'
    AND submitted_at IS NOT NULL
    AND weighted_subtotal IS NOT NULL;

  SELECT ROUND((2 * MIN(weighted_subtotal) + 4 * AVG(weighted_subtotal) + 2 * MAX(weighted_subtotal)) / 8, 2)
  INTO v_pert_leader
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'leader_extra'
    AND submitted_at IS NOT NULL
    AND weighted_subtotal IS NOT NULL;

  -- 8. Return results
  RETURN jsonb_build_object(
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'chapter', v_app.chapter,
    'role_applied', v_app.role_applied,
    'status', v_app.status,
    'evaluations', v_evaluations,
    'consolidated', jsonb_build_object(
      'objective_pert', v_pert_objective,
      'interview_pert', v_pert_interview,
      'leader_extra_pert', v_pert_leader,
      'objective_score_avg', v_app.objective_score_avg,
      'interview_score', v_app.interview_score,
      'final_score', v_app.final_score,
      'rank_chapter', v_app.rank_chapter,
      'rank_overall', v_app.rank_overall
    ),
    'calibration_alerts', v_calibration_alerts,
    'has_calibration_issues', jsonb_array_length(v_calibration_alerts) > 0
  );
END;
$function$;
