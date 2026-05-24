-- WHAT: Defense-in-depth hardening of submit_interview_scores. Hoist
--       `UPDATE selection_interviews SET conducted_at = now()` to BEFORE the
--       IF v_all_interviewers_submitted check (with idempotency guard
--       `IF v_interview.conducted_at IS NULL`). Drop the now-redundant
--       `conducted_at = now()` from inside the all-submitted branch (kept only
--       `status = 'completed'`).
-- WHY:  WATCH-240.A surfaced by p240 #251 close. The p240 trigger
--       `trg_sync_interview_to_app_status` (migration 20260805000025) keys on
--       changes to selection_interviews.conducted_at OR .status and is the
--       canonical owner of selection_applications.status sync to
--       'interview_done'. Pre-WATCH-240.A, submit_interview_scores only set
--       conducted_at inside the all-submitted branch, so partial submissions
--       (1-of-N interviewers) never fired the trigger → app stuck in
--       'interview_pending' (the exact #251 manifestation that the trigger +
--       backfill healed in p240 for cycle4 + cycle3-b2). This change closes
--       the residual fragility going forward.
-- SCOPE: defense-in-depth only. No data side-effects — past affected rows
--       were healed by the p240 backfill. This prevents NEW interviews from
--       getting stuck when partial-submit happens (e.g., 1 of 2 evaluators
--       submits and the other never does).
-- ROLLBACK: re-apply migration
--           20260517060000_p113_fix_submit_interview_scores_final_score.sql
--           which carries the pre-WATCH-240.A body. No data to reverse.
-- CROSS-REF: WATCH-240.A in memory/handoff_p240_post_p239b_close.md;
--            p240 trigger migration 20260805000025;
--            previous owner of body: migration 20260517060000 (p113).

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

  -- 7. WATCH-240.A (p241): mark interview as conducted as soon as ANY interviewer
  -- submits scores. The act of submitting a scored evaluation is canonical evidence
  -- that the interview took place. Pre-WATCH-240.A this UPDATE only fired inside
  -- the all-submitted branch below, leaving partial-submit apps stuck in
  -- 'interview_pending'. The p240 trigger _trg_sync_interview_to_app_status
  -- (migration 20260805000025) keys on conducted_at + status changes of
  -- selection_interviews and is the canonical owner of app status sync to
  -- 'interview_done' (idempotent + terminal-guarded). Idempotency guard below
  -- prevents overwriting an earlier conducted_at (e.g., set by mark_interview_status
  -- or a previous submit_interview_scores call from a different evaluator).
  IF v_interview.conducted_at IS NULL THEN
    UPDATE public.selection_interviews
    SET conducted_at = now()
    WHERE id = p_interview_id;
  END IF;

  -- 8. Check if all interviewers submitted
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

  -- 9. If all submitted: mark interview row complete + PERT + advance app to
  -- final_eval. (final_score recomputed by trg_recompute_application_scores via
  -- compute_application_scores when the interview evaluation INSERT fires.)
  -- conducted_at was already set in step 7 (idempotent) — only the interview
  -- lifecycle status moves to 'completed' here, signalling the row is sealed.
  IF v_all_interviewers_submitted THEN
    UPDATE public.selection_interviews
    SET status = 'completed'
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
