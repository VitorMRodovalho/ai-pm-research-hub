-- Issue #116: Calendar booking → selection_interviews sync
-- RPC anon-callable de Apps Script (Calendar trigger) com shared secret check.
-- Cria selection_interviews row + updates selection_applications.status quando candidate
-- books via Calendar link. Bypassa gates do schedule_interview (booking é informational,
-- comissão valida depois). Idempotente em (calendar_event_id).

INSERT INTO public.site_config (key, value)
VALUES (
  'arm116_calendar_webhook_secret',
  to_jsonb('CHANGE_ME_IN_PRODUCTION_' || md5(random()::text))
)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.sync_calendar_booking_to_interview(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_expected_secret text;
  v_provided_secret text;
  v_guest_email text;
  v_scheduled_at timestamptz;
  v_calendar_event_id text;
  v_event_title text;
  v_app record;
  v_interview_id uuid;
  v_existing_id uuid;
  v_status_changed boolean := false;
BEGIN
  SELECT (value::text) INTO v_expected_secret
  FROM public.site_config WHERE key = 'arm116_calendar_webhook_secret';
  v_expected_secret := TRIM(BOTH '"' FROM v_expected_secret);

  v_provided_secret := p_payload->>'secret';
  IF v_provided_secret IS NULL OR v_provided_secret <> v_expected_secret THEN
    RETURN jsonb_build_object('error','invalid secret');
  END IF;

  v_guest_email := NULLIF(LOWER(TRIM(p_payload->>'guest_email')), '');
  v_scheduled_at := (p_payload->>'scheduled_at')::timestamptz;
  v_calendar_event_id := NULLIF(TRIM(p_payload->>'calendar_event_id'), '');
  v_event_title := NULLIF(TRIM(p_payload->>'event_title'), '');

  IF v_guest_email IS NULL OR v_scheduled_at IS NULL OR v_calendar_event_id IS NULL THEN
    RETURN jsonb_build_object('error','required: guest_email, scheduled_at, calendar_event_id');
  END IF;

  SELECT a.*, c.status AS cycle_status INTO v_app
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE LOWER(TRIM(a.email)) = v_guest_email
    AND c.status IN ('open','active')
  ORDER BY a.created_at DESC LIMIT 1;

  IF NOT FOUND THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'arm116.calendar_booking_unmatched', 'system', NULL,
      jsonb_build_object('guest_email', v_guest_email, 'scheduled_at', v_scheduled_at),
      jsonb_build_object('calendar_event_id', v_calendar_event_id, 'event_title', v_event_title, 'reason', 'no matching application in open/active cycle')
    );
    RETURN jsonb_build_object('warning','no matching application found', 'guest_email', v_guest_email);
  END IF;

  SELECT id INTO v_existing_id
  FROM public.selection_interviews
  WHERE calendar_event_id = v_calendar_event_id;

  IF v_existing_id IS NOT NULL THEN
    UPDATE public.selection_interviews
    SET scheduled_at = v_scheduled_at, updated_at = now()
    WHERE id = v_existing_id;
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true, 'interview_id', v_existing_id,
      'application_id', v_app.id, 'message', 'updated existing interview'
    );
  END IF;

  INSERT INTO public.selection_interviews (
    application_id, interviewer_ids, scheduled_at, duration_minutes,
    status, calendar_event_id
  ) VALUES (
    v_app.id, ARRAY[]::uuid[], v_scheduled_at, 30,
    'scheduled', v_calendar_event_id
  ) RETURNING id INTO v_interview_id;

  IF v_app.status IN ('submitted','in_review','interview_pending') THEN
    UPDATE public.selection_applications
    SET status = 'interview_scheduled', updated_at = now()
    WHERE id = v_app.id;
    v_status_changed := true;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'arm116.calendar_booking_synced', 'selection_interview', v_interview_id,
    jsonb_build_object(
      'application_id', v_app.id, 'guest_email', v_guest_email,
      'scheduled_at', v_scheduled_at, 'previous_app_status', v_app.status,
      'status_changed', v_status_changed
    ),
    jsonb_build_object('calendar_event_id', v_calendar_event_id, 'event_title', v_event_title, 'source', 'apps_script_calendar_webhook')
  );

  RETURN jsonb_build_object(
    'success', true, 'idempotent', false,
    'interview_id', v_interview_id, 'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'previous_app_status', v_app.status,
    'status_changed', v_status_changed
  );
END $$;

REVOKE ALL ON FUNCTION public.sync_calendar_booking_to_interview(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_calendar_booking_to_interview(jsonb) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.sync_calendar_booking_to_interview(jsonb) IS
'Issue #116. Apps Script calendar webhook RPC. Authenticates via shared secret in payload. Lookup application by email + creates selection_interviews row (bypassing schedule_interview gates — booking is informational, gates apply at score-submission time). Idempotent on calendar_event_id. Audit log entry per call. PM should rotate site_config.arm116_calendar_webhook_secret periodically.';

NOTIFY pgrst, 'reload schema';
