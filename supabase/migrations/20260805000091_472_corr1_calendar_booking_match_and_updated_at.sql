-- ============================================================================
-- #472 correction #1 (re-scoped) — calendar→interview matching robustness
-- + the updated_at 42703 bug, on sync_calendar_booking_to_interview.
-- ----------------------------------------------------------------------------
-- Context: Approach A (a Google-Calendar PULL EF) is INFEASIBLE — no credential
-- carries a Calendar scope and Domain-Wide Delegation is blocked (ADR-0064: PM
-- is not Workspace Admin of pmigo.org.br). So corr-1 is re-scoped to harden the
-- existing booking-sync path. (The durable B1 fix for off-platform interviews
-- moves to corr-3 = admin "record offline interview"; the detection cron to
-- corr-5.) This migration is DB-only.
--
-- NOTE ON LIVENESS: the LIVE booking ingress is the API route
-- src/pages/api/calendar-webhook.ts (header-auth). This RPC (payload-secret) is
-- the older issue-#116 surface, currently only referenced by generated types —
-- so this fix is hygiene + a forward-defended canonical SQL surface; mirroring
-- the matching into the webhook (TS) is the follow-up that gives PRODUCTION
-- effect.
--
-- Two changes (minimum-diff CREATE OR REPLACE; everything else byte-faithful):
--   1) updated_at 42703 fix — the idempotent re-fire branch did
--      `UPDATE selection_interviews SET ... updated_at = now()`, but
--      selection_interviews has NO updated_at column → 42703 undefined_column,
--      so re-firing for an existing calendar_event_id always threw. Removed.
--   2) Robust invitee matching — was PRIMARY-email only
--      (lower(trim(a.email)) = guest). A candidate's calendar invite may carry a
--      PERSONAL email while the application holds the PMI-import email. We now
--      also match when guest and application email PROVABLY belong to the SAME
--      member (via member_emails) — an alternate-email bridge with zero
--      cross-candidate risk (the bridge requires same member_id on both sides).
--      The direct primary match is always preferred (ORDER BY).
--
-- Idempotency key unchanged (calendar_event_id). Secret gate, status promotion,
-- audit trail unchanged. New: metadata.matched_by ('primary'|'alternate').
--
-- ROLLBACK: restore the prior body from migration
--   20260516920000_issue116_calendar_booking_sync_to_interview.sql
--   (re-introduces the updated_at bug + primary-only match).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sync_calendar_booking_to_interview(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_expected_secret text;
  v_provided_secret text;
  v_guest_email text;
  v_guest_member_id uuid;          -- #472 corr.1: alternate-email bridge
  v_scheduled_at timestamptz;
  v_calendar_event_id text;
  v_event_title text;
  v_app record;
  v_interview_id uuid;
  v_existing_id uuid;
  v_status_changed boolean := false;
  v_matched_by text := 'primary';  -- #472 corr.1: which email path matched (audit)
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

  -- #472 corr.1 — robust invitee matching. The calendar invite may go to a
  -- candidate's PERSONAL email while the application carries the PMI-import
  -- email. Bridge the two ONLY when they provably belong to the SAME member
  -- (member_emails), so an alternate-email candidate is matched with no
  -- cross-candidate risk. The direct primary match is always preferred.
  SELECT me.member_id INTO v_guest_member_id
  FROM public.member_emails me
  WHERE me.email = v_guest_email::citext
  LIMIT 1;

  SELECT a.*, c.status AS cycle_status INTO v_app
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE c.status IN ('open','active')
    AND (
      LOWER(TRIM(a.email)) = v_guest_email
      OR (
        v_guest_member_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.member_emails me2
          WHERE me2.member_id = v_guest_member_id
            AND me2.email = LOWER(TRIM(a.email))::citext
        )
      )
    )
  -- prefer: (1) the direct primary-email match, then (2) the most-recently-opened
  -- cycle (so a returning member with apps in >1 simultaneously open/active cycle
  -- resolves to the current cycle's application, not merely the newest row), then
  -- (3) newest application as a final deterministic tie-break.
  ORDER BY (LOWER(TRIM(a.email)) = v_guest_email) DESC, c.open_date DESC NULLS LAST, a.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'arm116.calendar_booking_unmatched', 'system', NULL,
      jsonb_build_object('guest_email', v_guest_email, 'scheduled_at', v_scheduled_at),
      jsonb_build_object('calendar_event_id', v_calendar_event_id, 'event_title', v_event_title, 'reason', 'no matching application in open/active cycle')
    );
    RETURN jsonb_build_object('warning','no matching application found', 'guest_email', v_guest_email);
  END IF;

  IF LOWER(TRIM(v_app.email)) <> v_guest_email THEN
    v_matched_by := 'alternate';
  END IF;

  SELECT id INTO v_existing_id
  FROM public.selection_interviews
  WHERE calendar_event_id = v_calendar_event_id;

  IF v_existing_id IS NOT NULL THEN
    -- #472 corr.1: removed `updated_at = now()` — selection_interviews has no
    -- updated_at column, so the prior write threw 42703 on every re-fire.
    UPDATE public.selection_interviews
    SET scheduled_at = v_scheduled_at
    WHERE id = v_existing_id;
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true, 'interview_id', v_existing_id,
      'application_id', v_app.id, 'matched_by', v_matched_by, 'message', 'updated existing interview'
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
    jsonb_build_object('calendar_event_id', v_calendar_event_id, 'event_title', v_event_title, 'source', 'apps_script_calendar_webhook', 'matched_by', v_matched_by)
  );

  RETURN jsonb_build_object(
    'success', true, 'idempotent', false,
    'interview_id', v_interview_id, 'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'previous_app_status', v_app.status,
    'status_changed', v_status_changed,
    'matched_by', v_matched_by
  );
END $function$;

NOTIFY pgrst, 'reload schema';
