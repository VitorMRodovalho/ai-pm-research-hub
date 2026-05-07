-- p113 fix Bug A: submit_interview_scores stops overwriting final_score with broken formula.
--
-- Bug: function used `final_score = COALESCE(objective_score_avg, 0) + v_pert_score`,
-- but objective_score_avg is a legacy column that stays NULL when scoring goes through
-- compute_application_scores (which writes to research_score). Result: final_score
-- was clobbered with just the interview pert (e.g. Matheus: should be 153, was 48).
--
-- Trigger trg_recompute_application_scores (AFTER INSERT/UPDATE/DELETE on
-- selection_evaluations) already recomputes final_score correctly via
-- compute_application_scores. The explicit UPDATE in submit_interview_scores was both
-- redundant AND wrong.
--
-- Fix:
-- 1. Remove `final_score = ...` from the UPDATE — keep interview_score + status.
-- 2. Re-fetch v_app after the trigger has run, so notification uses the corrected research_score.
--
-- Scope: bug only affected 1 candidate in production (Matheus Teixeira, cycle3-2026-b2),
-- pre-decision (no rank/decision/promotion). Already manually recomputed via
-- compute_application_scores during diagnosis. This migration prevents recurrence for
-- future interview submissions.
--
-- Rollback: re-create the function with the buggy formula (NOT recommended).

CREATE OR REPLACE FUNCTION public.submit_interview_scores(
  p_interview_id uuid,
  p_scores jsonb,
  p_theme text DEFAULT NULL::text,
  p_notes text DEFAULT NULL::text,
  p_criterion_notes jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_interview record;
  v_app record;
  v_cycle record;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_score numeric;
  v_weight numeric;
  v_weighted_sum numeric := 0;
  v_eval_id uuid;
  v_all_interviewers_submitted boolean;
  v_all_subtotals numeric[];
  v_pert_score numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get interview + application + cycle
  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF v_interview IS NULL THEN
    RAISE EXCEPTION 'Interview not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- 3. V4 authorization: interviewer (resource) or platform admin
  IF NOT (v_caller.id = ANY(v_interview.interviewer_ids))
     AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not an assigned interviewer';
  END IF;

  -- 4. Get interview criteria and calculate weighted subtotal
  v_criteria := v_cycle.interview_criteria;

  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);

    IF NOT (p_scores ? v_key) THEN
      RAISE EXCEPTION 'Missing score for criterion: %', v_key;
    END IF;

    v_score := (p_scores ->> v_key)::numeric;
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  -- 5. Upsert evaluation (interview type) — trigger trg_recompute_application_scores
  -- fires AFTER this and writes correct research_score + final_score.
  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at
  ) VALUES (
    v_interview.application_id, v_caller.id, 'interview',
    p_scores, ROUND(v_weighted_sum, 2), p_notes, COALESCE(p_criterion_notes, '{}'::jsonb), now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    criterion_notes = EXCLUDED.criterion_notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  -- 6. Update interview theme if provided
  IF p_theme IS NOT NULL THEN
    UPDATE public.selection_interviews
    SET theme_of_interest = p_theme
    WHERE id = p_interview_id;
  END IF;

  -- 7. Check if all interviewers submitted
  v_all_interviewers_submitted := NOT EXISTS (
    SELECT 1 FROM unnest(v_interview.interviewer_ids) iid
    WHERE NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations
      WHERE application_id = v_interview.application_id
        AND evaluator_id = iid
        AND evaluation_type = 'interview'
        AND submitted_at IS NOT NULL
    )
  );

  -- 8. If all submitted: PERT + advance status (final_score handled by trigger)
  IF v_all_interviewers_submitted THEN
    UPDATE public.selection_interviews
    SET status = 'completed', conducted_at = now()
    WHERE id = p_interview_id;

    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal)
    INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = v_interview.application_id
      AND evaluation_type = 'interview'
      AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);

    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    -- final_score is recomputed by trg_recompute_application_scores via
    -- compute_application_scores when the interview evaluation INSERT fires.
    -- We only update interview_score (display column) and status here.
    UPDATE public.selection_applications
    SET interview_score = v_pert_score,
        status = 'final_eval',
        updated_at = now()
    WHERE id = v_interview.application_id;

    -- Re-fetch app after trigger has run, so notification reflects the corrected
    -- research_score / final_score.
    SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;

    PERFORM public.create_notification(
      sc.member_id,
      'selection_evaluation_complete',
      'Avaliação completa: ' || v_app.applicant_name,
      'Todas as avaliações (objetiva + entrevista) de ' || v_app.applicant_name || ' foram concluídas. Nota final: ' || ROUND(COALESCE(v_app.final_score, v_app.research_score, 0), 2),
      '/admin/selection',
      'selection_application',
      v_app.id
    )
    FROM public.selection_committee sc
    WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'evaluation_id', v_eval_id,
    'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_interviewers_submitted', v_all_interviewers_submitted,
    'pert_interview_score', v_pert_score
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
