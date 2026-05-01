-- ============================================================================
-- p87 Phase 2 Sprint A.1 — schedule_interview workflow gate
-- ADR-0066 Amendment 2026-05-01 / Issue #117
-- ============================================================================
-- Adds 3-layer precondition gate (AI + 2 peer evals + score) with bypass for
-- manage_member admins. Preserves existing committee-lead/manage_platform
-- authorization. Drop+Create due to new optional param p_bypass_gate.
--
-- Gates:
--   P0001 GATE_NO_AI         — consent_ai_analysis_at IS NULL OR ai_analysis IS NULL
--   P0002 GATE_NO_PEER_REVIEW — fewer than 2 selection_evaluations rows
--   P0003 GATE_NO_SCORE      — objective_score_avg IS NULL
--
-- Bypass: p_bypass_gate=true effective only if caller has manage_member.
-- Audit trail: return jsonb includes gate_bypassed boolean.
--
-- Rollback: re-DROP and recreate old signature (5 args) without gate body.
-- ============================================================================

DROP FUNCTION IF EXISTS public.schedule_interview(uuid, uuid[], timestamptz, integer, text);

CREATE OR REPLACE FUNCTION public.schedule_interview(
  p_application_id uuid,
  p_interviewer_ids uuid[],
  p_scheduled_at timestamptz,
  p_duration_minutes integer DEFAULT 30,
  p_calendar_event_id text DEFAULT NULL,
  p_bypass_gate boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_interview_id uuid;
  v_interviewer_id uuid;
  v_eval_count int;
  v_can_bypass boolean;
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

  -- 3. V4 authorization: committee lead (resource) or platform admin
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or platform admin';
  END IF;

  -- 4. Determine bypass eligibility (only manage_member can bypass)
  v_can_bypass := p_bypass_gate AND public.can_by_member(v_caller.id, 'manage_member'::text);

  -- 5. Workflow gate (ADR-0066 Amendment 2026-05-01, Issue #117)
  IF NOT v_can_bypass THEN
    -- Gate 1: AI analysis done
    IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
      RAISE EXCEPTION 'GATE_NO_AI: candidate has no AI analysis (consent=%, ai_analysis=%). Use p_bypass_gate=true with manage_member to override.',
        (v_app.consent_ai_analysis_at IS NOT NULL),
        (v_app.ai_analysis IS NOT NULL)
        USING ERRCODE = 'P0001';
    END IF;

    -- Gate 2: 2+ peer reviews
    SELECT COUNT(*) INTO v_eval_count
    FROM public.selection_evaluations
    WHERE application_id = p_application_id;

    IF v_eval_count < 2 THEN
      RAISE EXCEPTION 'GATE_NO_PEER_REVIEW: candidate has % peer evaluations (minimum 2 required). Use p_bypass_gate=true with manage_member to override.', v_eval_count
        USING ERRCODE = 'P0002';
    END IF;

    -- Gate 3: objective score computed
    IF v_app.objective_score_avg IS NULL THEN
      RAISE EXCEPTION 'GATE_NO_SCORE: objective_score_avg not computed. Run compute_application_scores first. Use p_bypass_gate=true with manage_member to override.'
        USING ERRCODE = 'P0003';
    END IF;
  END IF;

  -- 6. Validate application is ready for interview
  IF v_app.status NOT IN ('interview_pending', 'interview_scheduled') THEN
    RAISE EXCEPTION 'Application status % does not allow scheduling interview', v_app.status;
  END IF;

  -- 7. Create interview record
  INSERT INTO public.selection_interviews (
    application_id, interviewer_ids, scheduled_at,
    duration_minutes, status, calendar_event_id
  ) VALUES (
    p_application_id, p_interviewer_ids, p_scheduled_at,
    p_duration_minutes, 'scheduled', p_calendar_event_id
  )
  RETURNING id INTO v_interview_id;

  -- 8. Update application status
  UPDATE public.selection_applications
  SET status = 'interview_scheduled', updated_at = now()
  WHERE id = p_application_id;

  -- 9. Notify interviewers
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

  -- 10. Notify candidate if member
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
    'application_status', 'interview_scheduled',
    'gate_bypassed', v_can_bypass
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
