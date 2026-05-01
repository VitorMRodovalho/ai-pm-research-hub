-- ============================================================================
-- p87 Phase 2 Sprint A.3 — gate_attempts audit + RPC integration
-- ADR-0066 Amendment 2026-05-01 / Issue #117
-- ============================================================================
-- Captura cada tentativa de schedule_interview / issue_interview_booking_token
-- (success + fail), permite que comissão veja attempts via admin panel ou MCP
-- e identifique candidatos que tentaram bookar sem passar gate.
--
-- Components:
--   1. table gate_attempts (audit rows, RLS V4)
--   2. helper _log_gate_attempt (SECDEF, swallows errors — audit must never
--      block business logic)
--   3. RPC get_application_gate_attempts (committee/manage_member SELECT)
--   4. schedule_interview rewrite — logs every gate check + final outcome
--   5. issue_interview_booking_token rewrite — same pattern
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.gate_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid REFERENCES public.selection_applications(id) ON DELETE CASCADE,
  rpc_name text NOT NULL,
  caller_id uuid REFERENCES public.members(id) ON DELETE SET NULL,
  gate_passed boolean NOT NULL,
  gate_failed_code text,
  gate_failed_reason text,
  bypass_requested boolean DEFAULT false,
  bypass_granted boolean DEFAULT false,
  payload jsonb DEFAULT '{}'::jsonb,
  attempted_at timestamptz DEFAULT now(),
  organization_id uuid
);

CREATE INDEX IF NOT EXISTS idx_gate_attempts_application ON public.gate_attempts(application_id, attempted_at DESC);
CREATE INDEX IF NOT EXISTS idx_gate_attempts_caller ON public.gate_attempts(caller_id, attempted_at DESC);
CREATE INDEX IF NOT EXISTS idx_gate_attempts_failed ON public.gate_attempts(gate_failed_code, attempted_at DESC) WHERE gate_passed = false;

ALTER TABLE public.gate_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS gate_attempts_select_v4 ON public.gate_attempts;
CREATE POLICY gate_attempts_select_v4 ON public.gate_attempts
  FOR SELECT TO authenticated
  USING (
    public.rls_can('manage_member')
    OR public.rls_can('view_internal_analytics')
    OR EXISTS (
      SELECT 1 FROM public.selection_applications sa
      JOIN public.selection_committee sc ON sc.cycle_id = sa.cycle_id
      JOIN public.members m ON m.id = sc.member_id
      WHERE sa.id = gate_attempts.application_id
        AND m.auth_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS gate_attempts_insert_deny ON public.gate_attempts;
CREATE POLICY gate_attempts_insert_deny ON public.gate_attempts
  FOR INSERT TO authenticated WITH CHECK (false);

COMMENT ON TABLE public.gate_attempts IS 'Audit log of schedule_interview/issue_interview_booking_token gate checks. RLS allows committee + manage_member SELECT; INSERT only via SECDEF helper.';

-- ----------------------------------------------------------------------------
-- helper _log_gate_attempt (SECDEF, swallows errors)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._log_gate_attempt(
  p_application_id uuid,
  p_rpc_name text,
  p_caller_id uuid,
  p_gate_passed boolean,
  p_gate_failed_code text,
  p_gate_failed_reason text,
  p_bypass_requested boolean,
  p_bypass_granted boolean,
  p_payload jsonb,
  p_organization_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.gate_attempts (
    application_id, rpc_name, caller_id, gate_passed,
    gate_failed_code, gate_failed_reason,
    bypass_requested, bypass_granted, payload, organization_id
  ) VALUES (
    p_application_id, p_rpc_name, p_caller_id, p_gate_passed,
    p_gate_failed_code, p_gate_failed_reason,
    p_bypass_requested, p_bypass_granted, p_payload, p_organization_id
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_log_gate_attempt failed: %', SQLERRM;
END;
$function$;

REVOKE ALL ON FUNCTION public._log_gate_attempt(uuid, text, uuid, boolean, text, text, boolean, boolean, jsonb, uuid) FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- RPC get_application_gate_attempts (committee/manage_member SELECT)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_application_gate_attempts(
  p_application_id uuid
) RETURNS TABLE (
  id uuid,
  rpc_name text,
  caller_name text,
  gate_passed boolean,
  gate_failed_code text,
  gate_failed_reason text,
  bypass_requested boolean,
  bypass_granted boolean,
  payload jsonb,
  attempted_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
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
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL
     AND NOT public.can_by_member(v_caller.id, 'manage_member'::text)
     AND NOT public.can_by_member(v_caller.id, 'view_internal_analytics'::text)
  THEN
    RAISE EXCEPTION 'Unauthorized: must be committee member or have manage_member/view_internal_analytics';
  END IF;

  RETURN QUERY
  SELECT ga.id, ga.rpc_name,
         m.name AS caller_name,
         ga.gate_passed, ga.gate_failed_code, ga.gate_failed_reason,
         ga.bypass_requested, ga.bypass_granted,
         ga.payload, ga.attempted_at
  FROM public.gate_attempts ga
  LEFT JOIN public.members m ON m.id = ga.caller_id
  WHERE ga.application_id = p_application_id
  ORDER BY ga.attempted_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_application_gate_attempts(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_application_gate_attempts(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- schedule_interview rewrite — logs every gate check
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.schedule_interview(uuid, uuid[], timestamptz, integer, text, boolean);

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

  IF v_app.status NOT IN ('interview_pending', 'interview_scheduled') THEN
    PERFORM public._log_gate_attempt(
      p_application_id, 'schedule_interview', v_caller.id, false,
      'P0004', 'INVALID_APP_STATUS:' || v_app.status, p_bypass_gate, v_can_bypass,
      v_gate_payload, v_app.organization_id
    );
    RAISE EXCEPTION 'Application status % does not allow scheduling interview', v_app.status;
  END IF;

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

-- ----------------------------------------------------------------------------
-- issue_interview_booking_token rewrite — logs every gate check
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.issue_interview_booking_token(
  p_application_id uuid,
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
  v_eval_count int;
  v_can_bypass boolean;
  v_token text;
  v_booking_url_base text := 'https://nucleoia.vitormr.dev/interview-booking/';
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
    'objective_score_avg', v_app.objective_score_avg
  );

  IF NOT v_can_bypass THEN
    IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'issue_interview_booking_token', v_caller.id, false,
        'P0001', 'GATE_NO_AI', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RAISE EXCEPTION 'GATE_NO_AI: candidate has no AI analysis.' USING ERRCODE = 'P0001';
    END IF;

    IF v_eval_count < 2 THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'issue_interview_booking_token', v_caller.id, false,
        'P0002', 'GATE_NO_PEER_REVIEW', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RAISE EXCEPTION 'GATE_NO_PEER_REVIEW: candidate has % peer evaluations.', v_eval_count USING ERRCODE = 'P0002';
    END IF;

    IF v_app.objective_score_avg IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'issue_interview_booking_token', v_caller.id, false,
        'P0003', 'GATE_NO_SCORE', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RAISE EXCEPTION 'GATE_NO_SCORE: objective_score_avg not computed.' USING ERRCODE = 'P0003';
    END IF;
  END IF;

  v_token := encode(gen_random_bytes(32), 'base64');
  v_token := translate(v_token, '+/=', '-_');

  INSERT INTO public.onboarding_tokens (
    token, source_type, source_id, scopes,
    issued_at, expires_at, issued_by, organization_id
  ) VALUES (
    v_token, 'pmi_application', p_application_id::text,
    ARRAY['interview_booking']::text[],
    now(), now() + interval '14 days',
    v_caller.id, v_app.organization_id
  );

  PERFORM public._log_gate_attempt(
    p_application_id, 'issue_interview_booking_token', v_caller.id, true,
    NULL, NULL, p_bypass_gate, v_can_bypass,
    v_gate_payload || jsonb_build_object('token_prefix', left(v_token, 8)),
    v_app.organization_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'token', v_token,
    'booking_url', v_booking_url_base || v_token,
    'expires_at', (now() + interval '14 days')::text,
    'gate_bypassed', v_can_bypass
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
