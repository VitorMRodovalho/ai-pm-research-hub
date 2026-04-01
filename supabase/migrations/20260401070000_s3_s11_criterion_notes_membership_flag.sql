-- S3: Per-criterion notes for interview scoring
-- S11: Membership flagging (frontend only, data already in RPC from S1)
-- ================================================================

-- S3: Add criterion_notes column
ALTER TABLE selection_evaluations ADD COLUMN IF NOT EXISTS criterion_notes jsonb DEFAULT '{}';

-- S3: Update submit_interview_scores to accept per-criterion notes
DROP FUNCTION IF EXISTS submit_interview_scores(uuid, jsonb, text, text);
DROP FUNCTION IF EXISTS submit_interview_scores(uuid, jsonb, text, text, jsonb);

CREATE FUNCTION submit_interview_scores(
  p_interview_id uuid,
  p_scores jsonb,
  p_theme text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_criterion_notes jsonb DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller record; v_interview record; v_app record; v_cycle record;
  v_criteria jsonb; v_criterion jsonb; v_key text; v_score numeric; v_weight numeric;
  v_weighted_sum numeric := 0; v_eval_id uuid;
  v_all_interviewers_submitted boolean; v_all_subtotals numeric[];
  v_pert_score numeric; v_min_sub numeric; v_max_sub numeric; v_avg_sub numeric;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF v_interview IS NULL THEN RAISE EXCEPTION 'Interview not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  IF NOT (v_caller.id = ANY(v_interview.interviewer_ids)) AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: not an assigned interviewer';
  END IF;

  v_criteria := v_cycle.interview_criteria;
  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);
    IF NOT (p_scores ? v_key) THEN RAISE EXCEPTION 'Missing score for criterion: %', v_key; END IF;
    v_score := (p_scores ->> v_key)::numeric;
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at
  ) VALUES (
    v_interview.application_id, v_caller.id, 'interview',
    p_scores, ROUND(v_weighted_sum, 2), p_notes, COALESCE(p_criterion_notes, '{}'::jsonb), now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores, weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes, criterion_notes = EXCLUDED.criterion_notes, submitted_at = now()
  RETURNING id INTO v_eval_id;

  IF p_theme IS NOT NULL THEN
    UPDATE public.selection_interviews SET theme_of_interest = p_theme WHERE id = p_interview_id;
  END IF;

  v_all_interviewers_submitted := NOT EXISTS (
    SELECT 1 FROM unnest(v_interview.interviewer_ids) iid
    WHERE NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations
      WHERE application_id = v_interview.application_id AND evaluator_id = iid
        AND evaluation_type = 'interview' AND submitted_at IS NOT NULL
    )
  );

  IF v_all_interviewers_submitted THEN
    UPDATE public.selection_interviews SET status = 'completed', conducted_at = now() WHERE id = p_interview_id;

    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal) INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = v_interview.application_id AND evaluation_type = 'interview' AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);
    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    UPDATE public.selection_applications
    SET interview_score = v_pert_score, final_score = COALESCE(objective_score_avg, 0) + v_pert_score,
        status = 'final_eval', updated_at = now()
    WHERE id = v_interview.application_id;

    PERFORM public.create_notification(
      sc.member_id, 'selection_evaluation_complete',
      'Avaliação completa: ' || v_app.applicant_name,
      'Todas as avaliações de ' || v_app.applicant_name || ' concluídas. Nota final: ' || ROUND(COALESCE(v_app.objective_score_avg, 0) + v_pert_score, 2),
      '/admin/selection', 'selection_application', v_app.id
    ) FROM public.selection_committee sc WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'evaluation_id', v_eval_id,
    'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_interviewers_submitted', v_all_interviewers_submitted,
    'pert_interview_score', v_pert_score
  );
END;
$$;

-- S3: Update get_evaluation_form to return criterion_notes in draft
DROP FUNCTION IF EXISTS get_evaluation_form(uuid, text);

CREATE FUNCTION get_evaluation_form(p_application_id uuid, p_evaluation_type text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller record; v_app record; v_cycle record; v_committee record; v_draft record; v_criteria jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found: %', p_application_id; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member for this cycle';
  END IF;

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  SELECT * INTO v_draft FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluator_id = v_caller.id AND evaluation_type = p_evaluation_type;

  RETURN jsonb_build_object(
    'application', jsonb_build_object(
      'id', v_app.id, 'applicant_name', v_app.applicant_name, 'email', v_app.email,
      'chapter', v_app.chapter, 'role_applied', v_app.role_applied,
      'certifications', v_app.certifications, 'linkedin_url', v_app.linkedin_url,
      'resume_url', v_app.resume_url, 'motivation_letter', v_app.motivation_letter,
      'non_pmi_experience', v_app.non_pmi_experience, 'areas_of_interest', v_app.areas_of_interest,
      'availability_declared', v_app.availability_declared, 'proposed_theme', v_app.proposed_theme,
      'leadership_experience', v_app.leadership_experience, 'academic_background', v_app.academic_background,
      'membership_status', v_app.membership_status, 'status', v_app.status
    ),
    'criteria', v_criteria,
    'evaluation_type', p_evaluation_type,
    'draft', CASE WHEN v_draft IS NOT NULL THEN jsonb_build_object(
      'id', v_draft.id, 'scores', v_draft.scores, 'notes', v_draft.notes,
      'criterion_notes', COALESCE(v_draft.criterion_notes, '{}'::jsonb),
      'weighted_subtotal', v_draft.weighted_subtotal, 'submitted_at', v_draft.submitted_at
    ) ELSE NULL END,
    'is_locked', CASE WHEN v_draft.submitted_at IS NOT NULL THEN true ELSE false END
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
