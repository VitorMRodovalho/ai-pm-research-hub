-- W124 Phase 2: Blind Evaluation + Scoring Engine RPCs
-- ============================================================
-- RPCs: get_evaluation_form, submit_evaluation,
--        get_evaluation_results, calculate_rankings
-- ============================================================

-- ============================================================
-- 1. GET_EVALUATION_FORM
--    Returns application data + criteria config for evaluator.
--    Blind: only returns caller's own draft scores (if any).
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_evaluation_form(
  p_application_id uuid,
  p_evaluation_type text DEFAULT 'objective'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_draft record;
  v_criteria jsonb;
BEGIN
  -- 1. Auth: caller must be a committee member for this cycle
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get application + cycle
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found: %', p_application_id;
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- 3. Verify caller is on the committee
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member for this cycle';
  END IF;

  -- 4. Pick the right criteria set
  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  -- 5. Get caller's own draft/submitted evaluation (blind: only own scores)
  SELECT * INTO v_draft
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluator_id = v_caller.id
    AND evaluation_type = p_evaluation_type;

  -- 6. Return form data
  RETURN jsonb_build_object(
    'application', jsonb_build_object(
      'id', v_app.id,
      'applicant_name', v_app.applicant_name,
      'email', v_app.email,
      'chapter', v_app.chapter,
      'role_applied', v_app.role_applied,
      'certifications', v_app.certifications,
      'linkedin_url', v_app.linkedin_url,
      'resume_url', v_app.resume_url,
      'motivation_letter', v_app.motivation_letter,
      'non_pmi_experience', v_app.non_pmi_experience,
      'areas_of_interest', v_app.areas_of_interest,
      'availability_declared', v_app.availability_declared,
      'proposed_theme', v_app.proposed_theme,
      'leadership_experience', v_app.leadership_experience,
      'academic_background', v_app.academic_background,
      'membership_status', v_app.membership_status,
      'status', v_app.status
    ),
    'criteria', v_criteria,
    'evaluation_type', p_evaluation_type,
    'draft', CASE WHEN v_draft IS NOT NULL THEN jsonb_build_object(
      'id', v_draft.id,
      'scores', v_draft.scores,
      'notes', v_draft.notes,
      'weighted_subtotal', v_draft.weighted_subtotal,
      'submitted_at', v_draft.submitted_at
    ) ELSE NULL END,
    'is_locked', CASE WHEN v_draft.submitted_at IS NOT NULL THEN true ELSE false END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_evaluation_form(uuid, text) TO authenticated;

-- ============================================================
-- 2. SUBMIT_EVALUATION
--    Validates scores, calculates weighted subtotal, locks eval.
--    If all evaluators submitted: PERT-consolidate + auto-advance.
-- ============================================================
CREATE OR REPLACE FUNCTION public.submit_evaluation(
  p_application_id uuid,
  p_evaluation_type text,
  p_scores jsonb,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_score numeric;
  v_weight numeric;
  v_weighted_sum numeric := 0;
  v_eval_id uuid;
  v_total_evaluators int;
  v_submitted_count int;
  v_all_subtotals numeric[];
  v_pert_score numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
  v_cutoff numeric;
  v_median numeric;
  v_new_status text;
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

  -- 3. Committee check
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- 4. Check not already locked
  IF EXISTS (
    SELECT 1 FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluator_id = v_caller.id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Evaluation already submitted and locked';
  END IF;

  -- 5. Get criteria and validate scores
  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  -- Validate each criterion has a score and calculate weighted subtotal
  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);

    IF NOT (p_scores ? v_key) THEN
      RAISE EXCEPTION 'Missing score for criterion: %', v_key;
    END IF;

    v_score := (p_scores ->> v_key)::numeric;

    IF v_score IS NULL THEN
      RAISE EXCEPTION 'Score for % must be numeric', v_key;
    END IF;

    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  -- 6. Upsert evaluation (insert or update draft)
  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, submitted_at
  ) VALUES (
    p_application_id, v_caller.id, p_evaluation_type,
    p_scores, ROUND(v_weighted_sum, 2), p_notes, now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  -- 7. Check if all evaluators have submitted for this application + type
  SELECT COUNT(*) INTO v_total_evaluators
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND role IN ('evaluator', 'lead');

  SELECT COUNT(*) INTO v_submitted_count
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = p_evaluation_type
    AND submitted_at IS NOT NULL;

  -- 8. If all submitted: PERT consolidation + auto-advance
  IF v_submitted_count >= v_cycle.min_evaluators THEN
    -- Gather all subtotals for this application + type
    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal)
    INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);

    -- PERT: (2*min + 4*avg + 2*max) / 8
    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    -- Update application score based on evaluation type
    IF p_evaluation_type = 'objective' THEN
      UPDATE public.selection_applications
      SET objective_score_avg = v_pert_score,
          updated_at = now()
      WHERE id = p_application_id;

      -- Calculate cutoff: 75% of median across all apps in cycle with objective scores
      SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY objective_score_avg)
      INTO v_median
      FROM public.selection_applications
      WHERE cycle_id = v_app.cycle_id
        AND objective_score_avg IS NOT NULL;

      v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);

      -- Auto-advance status
      IF v_pert_score < v_cutoff AND v_cutoff > 0 THEN
        v_new_status := 'objective_cutoff';
      ELSE
        v_new_status := 'interview_pending';
      END IF;

      UPDATE public.selection_applications
      SET status = v_new_status, updated_at = now()
      WHERE id = p_application_id
        AND status IN ('submitted', 'screening', 'objective_eval');

    ELSIF p_evaluation_type = 'interview' THEN
      UPDATE public.selection_applications
      SET interview_score = v_pert_score,
          final_score = COALESCE(objective_score_avg, 0) + v_pert_score,
          status = 'final_eval',
          updated_at = now()
      WHERE id = p_application_id;

    ELSIF p_evaluation_type = 'leader_extra' THEN
      -- Leader extra adds to objective score
      UPDATE public.selection_applications
      SET objective_score_avg = COALESCE(objective_score_avg, 0) + v_pert_score,
          final_score = COALESCE(objective_score_avg, 0) + v_pert_score + COALESCE(interview_score, 0),
          updated_at = now()
      WHERE id = p_application_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'evaluation_id', v_eval_id,
    'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score,
    'new_status', v_new_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_evaluation(uuid, text, jsonb, text) TO authenticated;

-- ============================================================
-- 3. GET_EVALUATION_RESULTS
--    Post-blind: returns all evaluators' scores side by side.
--    Only available after all evaluators submit.
--    Flags divergence > 3 points per criterion.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_evaluation_results(
  p_application_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- 3. Committee or superadmin check
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN
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
$$;

GRANT EXECUTE ON FUNCTION public.get_evaluation_results(uuid) TO authenticated;

-- ============================================================
-- 4. CALCULATE_RANKINGS
--    Recalculates rank_chapter and rank_overall for all apps.
--    Returns sorted list with recommended decisions.
-- ============================================================
CREATE OR REPLACE FUNCTION public.calculate_rankings(
  p_cycle_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_cycle record;
  v_committee record;
  v_median numeric;
  v_cutoff numeric;
  v_p90 numeric;
  v_ranked jsonb;
  v_updated_count int := 0;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get cycle
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF v_cycle IS NULL THEN
    RAISE EXCEPTION 'Cycle not found';
  END IF;

  -- 3. Committee lead or superadmin check
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = p_cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or superadmin';
  END IF;

  -- 4. Calculate overall rankings (by final_score DESC)
  WITH scored AS (
    SELECT id, chapter, final_score
    FROM public.selection_applications
    WHERE cycle_id = p_cycle_id
      AND final_score IS NOT NULL
      AND status NOT IN ('withdrawn', 'cancelled')
  ),
  ranked_overall AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY final_score DESC) AS r_overall
    FROM scored
  ),
  ranked_chapter AS (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY chapter ORDER BY final_score DESC) AS r_chapter
    FROM scored
  )
  UPDATE public.selection_applications a
  SET rank_overall = ro.r_overall,
      rank_chapter = rc.r_chapter,
      updated_at = now()
  FROM ranked_overall ro
  JOIN ranked_chapter rc ON rc.id = ro.id
  WHERE a.id = ro.id;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  -- 5. Calculate median and cutoff for recommendations
  SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY final_score)
  INTO v_median
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id
    AND final_score IS NOT NULL
    AND status NOT IN ('withdrawn', 'cancelled');

  v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);

  -- 90th percentile for leader conversion recommendation
  SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY objective_score_avg)
  INTO v_p90
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id
    AND objective_score_avg IS NOT NULL
    AND role_applied = 'researcher'
    AND status NOT IN ('withdrawn', 'cancelled');

  -- 6. Build ranked results with recommendations
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'application_id', a.id,
      'applicant_name', a.applicant_name,
      'email', a.email,
      'chapter', a.chapter,
      'role_applied', a.role_applied,
      'objective_score_avg', a.objective_score_avg,
      'interview_score', a.interview_score,
      'final_score', a.final_score,
      'rank_chapter', a.rank_chapter,
      'rank_overall', a.rank_overall,
      'status', a.status,
      'tags', a.tags,
      'recommendation', CASE
        WHEN a.final_score >= v_median THEN 'approve'
        WHEN a.final_score >= v_cutoff THEN 'waitlist'
        ELSE 'reject'
      END,
      'flag_convert_to_leader', CASE
        WHEN a.role_applied = 'researcher'
          AND a.objective_score_avg IS NOT NULL
          AND v_p90 IS NOT NULL
          AND a.objective_score_avg >= v_p90
        THEN true
        ELSE false
      END
    ) ORDER BY a.rank_overall NULLS LAST
  ), '[]'::jsonb)
  INTO v_ranked
  FROM public.selection_applications a
  WHERE a.cycle_id = p_cycle_id
    AND a.status NOT IN ('withdrawn', 'cancelled');

  RETURN jsonb_build_object(
    'cycle_id', p_cycle_id,
    'updated_count', v_updated_count,
    'median_score', v_median,
    'cutoff_75pct', v_cutoff,
    'p90_objective', v_p90,
    'rankings', v_ranked
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.calculate_rankings(uuid) TO authenticated;
