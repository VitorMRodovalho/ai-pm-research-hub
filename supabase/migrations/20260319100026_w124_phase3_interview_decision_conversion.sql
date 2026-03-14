-- W124 Phase 3: Interview + Decision + Conversion RPCs
-- ============================================================
-- RPCs: schedule_interview, submit_interview_scores,
--        mark_interview_status, finalize_decisions
-- + Notification triggers for selection events
-- ============================================================

-- ============================================================
-- 1. SCHEDULE_INTERVIEW
--    Creates interview record, advances application status.
-- ============================================================
CREATE OR REPLACE FUNCTION public.schedule_interview(
  p_application_id uuid,
  p_interviewer_ids uuid[],
  p_scheduled_at timestamptz,
  p_duration_minutes int DEFAULT 30,
  p_calendar_event_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_interview_id uuid;
  v_interviewer_id uuid;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get application
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- 3. Committee lead or superadmin
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or superadmin';
  END IF;

  -- 4. Validate application is ready for interview
  IF v_app.status NOT IN ('interview_pending', 'interview_scheduled') THEN
    RAISE EXCEPTION 'Application status % does not allow scheduling interview', v_app.status;
  END IF;

  -- 5. Create interview record
  INSERT INTO public.selection_interviews (
    application_id, interviewer_ids, scheduled_at,
    duration_minutes, status, calendar_event_id
  ) VALUES (
    p_application_id, p_interviewer_ids, p_scheduled_at,
    p_duration_minutes, 'scheduled', p_calendar_event_id
  )
  RETURNING id INTO v_interview_id;

  -- 6. Update application status
  UPDATE public.selection_applications
  SET status = 'interview_scheduled', updated_at = now()
  WHERE id = p_application_id;

  -- 7. Notify interviewers
  FOREACH v_interviewer_id IN ARRAY p_interviewer_ids
  LOOP
    PERFORM public.create_notification(
      v_interviewer_id,
      'selection_interview_scheduled',
      'Entrevista agendada: ' || v_app.applicant_name,
      'Entrevista com ' || v_app.applicant_name || ' (' || COALESCE(v_app.chapter, '') || ') agendada para ' || to_char(p_scheduled_at, 'DD/MM/YYYY HH24:MI'),
      '/admin/selection',
      'selection_interview',
      v_interview_id
    );
  END LOOP;

  -- 8. Notify candidate if they are a member
  PERFORM public.create_notification(
    m.id,
    'selection_interview_scheduled',
    'Sua entrevista foi agendada',
    'Entrevista agendada para ' || to_char(p_scheduled_at, 'DD/MM/YYYY HH24:MI') || '. Prepare-se!',
    NULL,
    'selection_interview',
    v_interview_id
  )
  FROM public.members m
  WHERE m.email = v_app.email;

  RETURN jsonb_build_object(
    'success', true,
    'interview_id', v_interview_id,
    'scheduled_at', p_scheduled_at,
    'application_status', 'interview_scheduled'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.schedule_interview(uuid, uuid[], timestamptz, int, text) TO authenticated;

-- ============================================================
-- 2. SUBMIT_INTERVIEW_SCORES
--    Each interviewer submits independently.
--    When all submit: calculate interview_score, final_score,
--    recalculate rankings, auto-advance to final_eval.
-- ============================================================
CREATE OR REPLACE FUNCTION public.submit_interview_scores(
  p_interview_id uuid,
  p_scores jsonb,
  p_theme text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- 3. Verify caller is one of the interviewers or superadmin
  IF NOT (v_caller.id = ANY(v_interview.interviewer_ids)) AND v_caller.is_superadmin IS NOT TRUE THEN
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

  -- 5. Upsert evaluation (interview type)
  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, submitted_at
  ) VALUES (
    v_interview.application_id, v_caller.id, 'interview',
    p_scores, ROUND(v_weighted_sum, 2), p_notes, now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
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

  -- 8. If all submitted: PERT + final score + advance
  IF v_all_interviewers_submitted THEN
    -- Mark interview completed
    UPDATE public.selection_interviews
    SET status = 'completed', conducted_at = now()
    WHERE id = p_interview_id;

    -- PERT on interview subtotals
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

    -- Update application scores
    UPDATE public.selection_applications
    SET interview_score = v_pert_score,
        final_score = COALESCE(objective_score_avg, 0) + v_pert_score,
        status = 'final_eval',
        updated_at = now()
    WHERE id = v_interview.application_id;

    -- Notify committee lead
    PERFORM public.create_notification(
      sc.member_id,
      'selection_evaluation_complete',
      'Avaliação completa: ' || v_app.applicant_name,
      'Todas as avaliações (objetiva + entrevista) de ' || v_app.applicant_name || ' foram concluídas. Nota final: ' || ROUND(COALESCE(v_app.objective_score_avg, 0) + v_pert_score, 2),
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
$$;

GRANT EXECUTE ON FUNCTION public.submit_interview_scores(uuid, jsonb, text, text) TO authenticated;

-- ============================================================
-- 3. MARK_INTERVIEW_STATUS
--    noshow, cancelled, rescheduled
-- ============================================================
CREATE OR REPLACE FUNCTION public.mark_interview_status(
  p_interview_id uuid,
  p_status text,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_interview record;
  v_app record;
  v_new_app_status text;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Validate status
  IF p_status NOT IN ('noshow', 'cancelled', 'rescheduled', 'completed') THEN
    RAISE EXCEPTION 'Invalid interview status: %', p_status;
  END IF;

  -- 3. Get interview
  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF v_interview IS NULL THEN
    RAISE EXCEPTION 'Interview not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;

  -- 4. Committee lead, interviewer, or superadmin
  IF NOT (
    v_caller.id = ANY(v_interview.interviewer_ids)
    OR v_caller.is_superadmin IS TRUE
    OR EXISTS (
      SELECT 1 FROM public.selection_committee
      WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
    )
  ) THEN
    RAISE EXCEPTION 'Unauthorized: must be interviewer, committee lead, or superadmin';
  END IF;

  -- 5. Update interview
  UPDATE public.selection_interviews
  SET status = p_status,
      notes = COALESCE(p_notes, notes),
      conducted_at = CASE WHEN p_status = 'completed' THEN now() ELSE conducted_at END
  WHERE id = p_interview_id;

  -- 6. Update application status based on interview outcome
  v_new_app_status := CASE p_status
    WHEN 'noshow' THEN 'interview_noshow'
    WHEN 'cancelled' THEN 'interview_pending'
    WHEN 'rescheduled' THEN 'interview_pending'
    WHEN 'completed' THEN 'interview_done'
    ELSE v_app.status
  END;

  UPDATE public.selection_applications
  SET status = v_new_app_status, updated_at = now()
  WHERE id = v_interview.application_id
    AND status IN ('interview_scheduled', 'interview_done');

  -- 7. Notify GP on no-show
  IF p_status = 'noshow' THEN
    PERFORM public.create_notification(
      sc.member_id,
      'selection_interview_noshow',
      'No-show: ' || v_app.applicant_name,
      v_app.applicant_name || ' (' || COALESCE(v_app.chapter, '') || ') não compareceu à entrevista agendada.',
      '/admin/selection',
      'selection_interview',
      p_interview_id
    )
    FROM public.selection_committee sc
    WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'interview_status', p_status,
    'application_status', v_new_app_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_interview_status(uuid, text, text) TO authenticated;

-- ============================================================
-- 4. FINALIZE_DECISIONS (bulk)
--    GP sets final decisions for multiple applications.
--    For approved: auto-creates member record if not exists.
--    For converted: tracks conversion flow.
--    Triggers notifications + onboarding.
-- ============================================================
CREATE OR REPLACE FUNCTION public.finalize_decisions(
  p_cycle_id uuid,
  p_decisions jsonb  -- [{application_id, decision, feedback, convert_to}]
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
  v_decision jsonb;
  v_app record;
  v_member_id uuid;
  v_existing_member record;
  v_approved_count int := 0;
  v_rejected_count int := 0;
  v_waitlisted_count int := 0;
  v_converted_count int := 0;
  v_created_members int := 0;
  v_step jsonb;
  v_sla_days int;
  v_onboarding_steps jsonb;
BEGIN
  -- 1. Auth: committee lead or superadmin
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF v_cycle IS NULL THEN
    RAISE EXCEPTION 'Cycle not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = p_cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or superadmin';
  END IF;

  v_onboarding_steps := v_cycle.onboarding_steps;

  -- 2. Process each decision
  FOR v_decision IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    SELECT * INTO v_app
    FROM public.selection_applications
    WHERE id = (v_decision ->> 'application_id')::uuid
      AND cycle_id = p_cycle_id;

    IF v_app IS NULL THEN
      CONTINUE;
    END IF;

    -- 2a. Handle conversion (researcher → leader)
    IF (v_decision ->> 'convert_to') IS NOT NULL AND v_decision ->> 'convert_to' != '' THEN
      UPDATE public.selection_applications
      SET status = 'converted',
          converted_from = v_app.role_applied,
          converted_to = v_decision ->> 'convert_to',
          conversion_reason = COALESCE(v_decision ->> 'feedback', 'Score above 90th percentile threshold'),
          feedback = v_decision ->> 'feedback',
          updated_at = now()
      WHERE id = v_app.id;

      v_converted_count := v_converted_count + 1;

      -- Notify candidate about conversion offer
      PERFORM public.create_notification(
        m.id,
        'selection_conversion_offer',
        'Proposta de conversão de papel',
        'Parabéns! Com base no seu desempenho, gostaríamos de convidá-lo(a) para o papel de ' || (v_decision ->> 'convert_to') || '.',
        '/workspace',
        'selection_application',
        v_app.id
      )
      FROM public.members m WHERE m.email = v_app.email;

      CONTINUE;
    END IF;

    -- 2b. Update application with decision
    UPDATE public.selection_applications
    SET status = v_decision ->> 'decision',
        feedback = v_decision ->> 'feedback',
        updated_at = now()
    WHERE id = v_app.id;

    -- 2c. Handle approved candidates
    IF v_decision ->> 'decision' = 'approved' THEN
      v_approved_count := v_approved_count + 1;

      -- Check if member already exists
      SELECT * INTO v_existing_member
      FROM public.members WHERE email = v_app.email;

      IF v_existing_member IS NULL THEN
        -- Auto-create member record
        INSERT INTO public.members (
          name, email, chapter, pmi_id, phone, linkedin_url,
          operational_role, is_active, current_cycle_active,
          cycles, country, state, created_at
        ) VALUES (
          v_app.applicant_name,
          v_app.email,
          v_app.chapter,
          v_app.pmi_id,
          v_app.phone,
          v_app.linkedin_url,
          COALESCE(v_app.role_applied, 'researcher'),
          true,
          true,
          ARRAY[v_cycle.cycle_code],
          v_app.country,
          v_app.state,
          now()
        )
        RETURNING id INTO v_member_id;

        v_created_members := v_created_members + 1;
      ELSE
        v_member_id := v_existing_member.id;

        -- Reactivate if inactive
        UPDATE public.members
        SET is_active = true,
            current_cycle_active = true,
            operational_role = COALESCE(
              CASE WHEN v_app.role_applied = 'leader' THEN 'tribe_leader' ELSE operational_role END,
              v_app.role_applied
            ),
            cycles = CASE
              WHEN cycles IS NULL THEN ARRAY[v_cycle.cycle_code]
              WHEN NOT (v_cycle.cycle_code = ANY(cycles)) THEN cycles || v_cycle.cycle_code
              ELSE cycles
            END,
            updated_at = now()
        WHERE id = v_member_id;
      END IF;

      -- Create onboarding steps
      FOR v_step IN SELECT * FROM jsonb_array_elements(v_onboarding_steps)
      LOOP
        v_sla_days := COALESCE((v_step ->> 'sla_days')::int, 7);

        INSERT INTO public.onboarding_progress (
          application_id, member_id, step_key, status, sla_deadline
        ) VALUES (
          v_app.id,
          v_member_id,
          v_step ->> 'key',
          'pending',
          now() + (v_sla_days || ' days')::interval
        )
        ON CONFLICT (application_id, step_key) DO NOTHING;
      END LOOP;

      -- Notify approved member
      PERFORM public.create_notification(
        v_member_id,
        'selection_approved',
        'Parabéns! Você foi aprovado(a)!',
        'Você foi aprovado(a) na seleção do ' || v_cycle.title || '. Complete seu onboarding para começar.',
        '/workspace',
        'selection_application',
        v_app.id
      );

    ELSIF v_decision ->> 'decision' = 'rejected' THEN
      v_rejected_count := v_rejected_count + 1;

    ELSIF v_decision ->> 'decision' = 'waitlist' THEN
      v_waitlisted_count := v_waitlisted_count + 1;
    END IF;
  END LOOP;

  -- 3. Take diversity snapshot
  INSERT INTO public.selection_diversity_snapshots (cycle_id, snapshot_type, metrics)
  SELECT p_cycle_id, 'approved', jsonb_build_object(
    'total', COUNT(*),
    'by_chapter', COALESCE((
      SELECT jsonb_object_agg(chapter, cnt)
      FROM (SELECT chapter, COUNT(*) AS cnt FROM public.selection_applications
            WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY chapter) sub
    ), '{}'::jsonb),
    'by_role', COALESCE((
      SELECT jsonb_object_agg(role_applied, cnt)
      FROM (SELECT role_applied, COUNT(*) AS cnt FROM public.selection_applications
            WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY role_applied) sub
    ), '{}'::jsonb),
    'by_gender', COALESCE((
      SELECT jsonb_object_agg(COALESCE(gender, 'undeclared'), cnt)
      FROM (SELECT gender, COUNT(*) AS cnt FROM public.selection_applications
            WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY gender) sub
    ), '{}'::jsonb)
  )
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id AND status = 'approved';

  RETURN jsonb_build_object(
    'success', true,
    'approved', v_approved_count,
    'rejected', v_rejected_count,
    'waitlisted', v_waitlisted_count,
    'converted', v_converted_count,
    'members_created', v_created_members,
    'decisions_processed', jsonb_array_length(p_decisions)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.finalize_decisions(uuid, jsonb) TO authenticated;
