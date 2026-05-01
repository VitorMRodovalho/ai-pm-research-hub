-- ============================================================================
-- p87 Phase 2 Sprint A.2 — interview_booking token substrate
-- ADR-0066 Amendment 2026-05-01 / Issue #117
-- ============================================================================
-- 2 RPCs:
--   1. issue_interview_booking_token: gate-aware token issuance (committee
--      lead OR manage_platform). Reusa onboarding_tokens com scope
--      'interview_booking'. TTL 14d. Bypass via manage_member.
--   2. validate_interview_booking_token: anon-grant SECDEF wrapper for
--      frontend page to validate + display booking page (returns minimal
--      payload, increments access_count).
--
-- Frontend page /interview-booking/[token] (separate file) consumes
-- validate_interview_booking_token + embeds Calendar booking link with
-- applicant context preserved.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. issue_interview_booking_token
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

  -- 3. V4 authorization: committee lead OR manage_platform
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or platform admin';
  END IF;

  -- 4. Bypass eligibility
  v_can_bypass := p_bypass_gate AND public.can_by_member(v_caller.id, 'manage_member'::text);

  -- 5. Workflow gate (3-layer, mesma de schedule_interview)
  IF NOT v_can_bypass THEN
    IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
      RAISE EXCEPTION 'GATE_NO_AI: candidate has no AI analysis. Use p_bypass_gate=true with manage_member to override.'
        USING ERRCODE = 'P0001';
    END IF;

    SELECT COUNT(*) INTO v_eval_count
    FROM public.selection_evaluations
    WHERE application_id = p_application_id;

    IF v_eval_count < 2 THEN
      RAISE EXCEPTION 'GATE_NO_PEER_REVIEW: candidate has % peer evaluations (minimum 2 required).', v_eval_count
        USING ERRCODE = 'P0002';
    END IF;

    IF v_app.objective_score_avg IS NULL THEN
      RAISE EXCEPTION 'GATE_NO_SCORE: objective_score_avg not computed.'
        USING ERRCODE = 'P0003';
    END IF;
  END IF;

  -- 6. Generate URL-safe base64 token
  v_token := encode(gen_random_bytes(32), 'base64');
  v_token := translate(v_token, '+/=', '-_');

  INSERT INTO public.onboarding_tokens (
    token, source_type, source_id, scopes,
    issued_at, expires_at, issued_by, organization_id
  ) VALUES (
    v_token,
    'pmi_application',
    p_application_id::text,
    ARRAY['interview_booking']::text[],
    now(),
    now() + interval '14 days',
    v_caller.id,
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

REVOKE ALL ON FUNCTION public.issue_interview_booking_token(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.issue_interview_booking_token(uuid, boolean) TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. validate_interview_booking_token (anon-grant for frontend page)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_interview_booking_token(
  p_token text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_token_row record;
  v_app record;
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 THEN
    RAISE EXCEPTION 'Invalid token format';
  END IF;

  SELECT * INTO v_token_row FROM public.onboarding_tokens WHERE token = p_token;
  IF v_token_row IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF v_token_row.expires_at < now() THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF NOT (v_token_row.scopes @> ARRAY['interview_booking']::text[]) THEN
    RAISE EXCEPTION 'Token does not have interview_booking scope';
  END IF;

  -- Increment access tracking
  UPDATE public.onboarding_tokens
  SET access_count = COALESCE(access_count, 0) + 1,
      last_accessed_at = now()
  WHERE token = p_token;

  -- Lookup application (minimal fields, safe for anon display)
  SELECT id, applicant_name, first_name, email, status
  INTO v_app FROM public.selection_applications
  WHERE id::text = v_token_row.source_id;

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'first_name', COALESCE(NULLIF(trim(v_app.first_name), ''), split_part(v_app.applicant_name, ' ', 1)),
    'application_status', v_app.status,
    'expires_at', v_token_row.expires_at,
    'access_count', COALESCE(v_token_row.access_count, 0) + 1
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.validate_interview_booking_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_interview_booking_token(text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
