-- ============================================================================
-- #472 correction #3 — admin "record offline interview" path (durable B1 fix)
-- ----------------------------------------------------------------------------
-- Off-platform interviews (a GP-created calendar event the Apps-Script push never
-- synced — e.g. João Coelho 08/05) leave the candidate with NO selection_interviews
-- row, stuck in a pre-interview status, unscoreable via the UI. Since a Calendar
-- PULL is infeasible (corr-1: no Calendar scope; DwD blocked by ADR-0064), the
-- ADMIN is the ingress for off-platform interviews.
--
-- schedule_interview already has p_bypass_gate, but the bypass only covered the
-- AI/peer-review/score gates (P0001/P0002/P0003). The P0004 status gate sat
-- OUTSIDE the `IF NOT v_can_bypass` block → even an admin (manage_member) +
-- p_bypass_gate=true was blocked for any status not in interview_pending/
-- interview_scheduled. That single branch is the whole B4 blocker.
--
-- THIS CHANGE (minimum-diff CREATE OR REPLACE — only the P0004 block differs):
-- make P0004 bypassable for the admin bypass path, but stay TERMINAL-SAFE: a
-- DECIDED application (approved/rejected/converted/withdrawn/cancelled/waitlist)
-- is never reopened by a re-schedule. interview_noshow is intentionally allowed
-- (recording a real interview after a no-show is a legitimate correction). The
-- bypass still requires p_bypass_gate AND manage_member (v_can_bypass) and is
-- audited via _log_gate_attempt on both the success and the still-blocked paths.
--
-- Everything else (auth, P0001-P0003 gates, INSERT, status→interview_scheduled,
-- notifications, return payload) is byte-faithful to the prior body
-- (migration 20260516380000 / its successors).
--
-- ROLLBACK: restore the prior body (P0004 unconditional) from the latest
--   schedule_interview migration before this one.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.schedule_interview(p_application_id uuid, p_interviewer_ids uuid[], p_scheduled_at timestamp with time zone, p_duration_minutes integer DEFAULT 30, p_calendar_event_id text DEFAULT NULL::text, p_bypass_gate boolean DEFAULT false)
 RETURNS jsonb
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
  v_gate_payload jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or platform admin';
  END IF;

  v_can_bypass := p_bypass_gate AND public.can_by_member(v_caller.id, 'manage_member'::text);

  SELECT COUNT(*) INTO v_eval_count FROM public.selection_evaluations WHERE application_id = p_application_id;
  v_gate_payload := jsonb_build_object(
    'has_consent', (v_app.consent_ai_analysis_at IS NOT NULL),
    'has_ai_analysis', (v_app.ai_analysis IS NOT NULL),
    'eval_count', v_eval_count,
    'objective_score_avg', v_app.objective_score_avg,
    'app_status', v_app.status
  );

  -- Workflow gate
  IF NOT v_can_bypass THEN
    IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'schedule_interview', v_caller.id, false,
        'P0001', 'GATE_NO_AI', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RAISE EXCEPTION 'GATE_NO_AI: candidate has no AI analysis. Use p_bypass_gate=true with manage_member to override.'
        USING ERRCODE = 'P0001';
    END IF;

    IF v_eval_count < 2 THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'schedule_interview', v_caller.id, false,
        'P0002', 'GATE_NO_PEER_REVIEW', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RAISE EXCEPTION 'GATE_NO_PEER_REVIEW: candidate has % peer evaluations (minimum 2 required).', v_eval_count
        USING ERRCODE = 'P0002';
    END IF;

    IF v_app.objective_score_avg IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'schedule_interview', v_caller.id, false,
        'P0003', 'GATE_NO_SCORE', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RAISE EXCEPTION 'GATE_NO_SCORE: objective_score_avg not computed.'
        USING ERRCODE = 'P0003';
    END IF;
  END IF;

  -- #472 corr.3 — P0004 status gate. The admin offline-interview bypass
  -- (v_can_bypass = p_bypass_gate AND manage_member) is allowed ONLY from a
  -- PRE-INTERVIEW status that genuinely has no interview yet — an ALLOW-LIST, not
  -- a block-list, so a later-stage status (interview_done / final_eval) or any
  -- decision/terminal can NEVER be regressed to interview_scheduled by the
  -- unconditional status UPDATE below. (A no-show second chance goes through
  -- reschedule_interview, the canonical path — not this bypass.)
  IF NOT (
       v_app.status IN ('interview_pending', 'interview_scheduled')
       OR ( v_can_bypass AND v_app.status IN ('screening', 'submitted', 'objective_eval', 'objective_cutoff') )
     ) THEN
    PERFORM public._log_gate_attempt(
      p_application_id, 'schedule_interview', v_caller.id, false,
      'P0004', 'INVALID_APP_STATUS:' || v_app.status, p_bypass_gate, v_can_bypass,
      v_gate_payload, v_app.organization_id
    );
    RAISE EXCEPTION 'Application status % does not allow scheduling interview', v_app.status;
  END IF;

  -- All gates passed → create interview
  INSERT INTO public.selection_interviews (
    application_id, interviewer_ids, scheduled_at,
    duration_minutes, status, calendar_event_id
  ) VALUES (
    p_application_id, p_interviewer_ids, p_scheduled_at,
    p_duration_minutes, 'scheduled', p_calendar_event_id
  )
  RETURNING id INTO v_interview_id;

  UPDATE public.selection_applications
  SET status = 'interview_scheduled', updated_at = now()
  WHERE id = p_application_id;

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

  PERFORM public._log_gate_attempt(
    p_application_id, 'schedule_interview', v_caller.id, true,
    NULL, NULL, p_bypass_gate, v_can_bypass,
    v_gate_payload, v_app.organization_id
  );

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
