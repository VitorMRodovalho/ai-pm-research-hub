-- #1450 — VEP candidates were invited to schedule the interview BEFORE the objective phase.
--
-- Root cause: two ungated surfaces let a candidate reach interview scheduling without a
-- computed objective score, bypassing the gate that schedule_interview and
-- issue_interview_booking_token already enforce (P0003: objective_score_avg IS NULL → reject):
--
--   1. notify_selection_cutoff_approved(uuid) — the "schedule your interview" invite. It sends
--      the RAW booking URL (a committee/cycle Google Calendar page), not a gated token. The
--      _selection_cutoff_pending_cron caller already filters `objective_score_avg IS NOT NULL`,
--      but the MANUAL / bulk dispatch path (admin/selection F1 + F3 buttons) selects candidates
--      by STATUS only (screening / interview_pending), so a status-advanced-but-scoreless row
--      could be emailed the booking link.
--
--   2. sync_calendar_booking_to_interview(jsonb) — the raw-calendar webhook. A candidate who
--      books directly on the committee's Google Calendar link is matched by guest email and gets
--      a selection_interviews row created + status promoted (submitted / interview_pending →
--      interview_scheduled) with NO objective gate. This is the write that actually bypassed
--      schedule_interview (observed live: one researcher self-booked at 00:07 on 2026-07-21 with
--      objective_score_avg IS NULL).
--
-- Fix: gate BOTH surfaces on `objective_score_avg IS NOT NULL` — the canonical "objective phase
-- complete" signal used across the selection pipeline. The invite is refused before the score
-- exists (so the raw booking link never reaches a premature candidate), and the webhook refuses
-- to materialize an interview for a scoreless application (defense in depth; the booking is
-- logged + dropped, idempotently re-bookable once the score lands).
--
-- Scope note: only the objective_score_avg gate is mirrored (not the AI-analysis / >=2-peer-eval
-- gates of schedule_interview). Requiring AI analysis on the invite would false-reject the
-- legitimate cutoff-cron dispatches — many approved candidates have no ai_analysis row — and
-- objective_score_avg IS NOT NULL already implies enough objective evaluations to have produced
-- an average. The cutoff cron's own filter is unchanged, so no legitimate dispatch is blocked.

-- ============================================================================
-- 1. notify_selection_cutoff_approved — objective gate before dispatch
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_selection_cutoff_approved(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_first_name text;
  v_objective_done int;
  -- v1 routing locals (#355)
  v_resolved_url text;
  v_resolution_path text;
  v_resolved_evaluator_id uuid;
  -- p282 #411 W2a: cron/service context flag (ADR-0028)
  v_is_cron boolean := false;
BEGIN
  -- Authority gate — same as dispatch_peer_review_invitations (committee lead OR
  -- manage_member). PM may use this manually; the Wave 2a/2b crons use the ADR-0028
  -- cron bypass below.
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    -- ADR-0028 cron/service bypass: a no-JWT (pg_cron) or service_role session is the
    -- automated dispatch path. An authenticated ghost (JWT present, no members row) has a
    -- non-null auth.uid() + present claims, so it skips this branch and RAISEs below.
    IF current_setting('request.jwt.claims', true) IS NULL OR auth.role() = 'service_role' THEN
      v_is_cron := true;  -- v_caller stays NULL → actor_id NULL (system row)
    ELSE
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- Per-caller authority gate — skipped in cron/service context (the service_role-only
  -- cron wrapper is itself the gate).
  IF NOT v_is_cron THEN
    SELECT * INTO v_committee
    FROM public.selection_committee
    WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

    IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
      RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
    END IF;
  END IF;

  -- Idempotency: single-fire per application
  IF v_app.cutoff_approved_email_sent_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'application_id', p_application_id,
      'email_sent', false,
      'reason', 'already_sent',
      'previously_sent_at', v_app.cutoff_approved_email_sent_at
    );
  END IF;

  IF v_app.email IS NULL THEN
    RAISE EXCEPTION 'Application has no email — cannot dispatch';
  END IF;

  -- #1450 — objective-phase gate. NEVER dispatch the interview-scheduling invite (which
  -- carries the raw booking URL) before the candidate has cleared the objective phase.
  -- Mirrors schedule_interview / issue_interview_booking_token P0003. Placed AFTER the
  -- already_sent idempotency return so a prior legitimate send is still reported
  -- idempotently, and enforced for BOTH the manual/bulk path and any direct call. The
  -- _selection_cutoff_pending_cron already filters objective_score_avg IS NOT NULL, so no
  -- legitimate cron dispatch is blocked by this gate.
  IF v_app.objective_score_avg IS NULL THEN
    RAISE EXCEPTION 'GATE_NO_SCORE: objective_score_avg not computed for application % — the interview-scheduling invite must not be sent before the objective phase completes (#1450).', p_application_id
      USING ERRCODE = 'P0003';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- ============================================================
  -- SPEC #348 v1 (#355): track-aware booking URL routing
  -- ------------------------------------------------------------
  -- Researcher → LRD round-robin over committee evaluators/leads with a
  -- resolvable URL (committee_override > member_global).
  -- Leader → cycle.interview_booking_url (group/dual interview semantics;
  -- never queries committee per PM directive).
  -- Fallback → cycle.interview_booking_url when researcher branch yields no
  -- candidate (preserves p243 Cycle 4 behavior while committee unseeded).
  -- ============================================================
  IF v_app.role_applied = 'leader' THEN
    v_resolved_url := v_cycle.interview_booking_url;
    v_resolution_path := 'cycle_fallback';
    v_resolved_evaluator_id := NULL;

  ELSIF v_app.role_applied = 'researcher' THEN
    -- LRD picker — pick the committee member with the oldest last-dispatched
    -- timestamp (NULLS FIRST so never-used evaluators come first). Tiebreak
    -- by member_id for stable ordering. Live-schema filter per PM-ratified
    -- Option A (2026-05-24 p251): role IN ('evaluator','lead') excludes
    -- observer; committee POSITION is independent of candidate TRACK.
    SELECT
      sc.member_id,
      COALESCE(sc.interview_booking_url, m.interview_booking_url),
      CASE
        WHEN sc.interview_booking_url IS NOT NULL THEN 'committee_override'
        ELSE 'member_global'
      END
    INTO
      v_resolved_evaluator_id,
      v_resolved_url,
      v_resolution_path
    FROM public.selection_committee sc
    JOIN public.members m ON m.id = sc.member_id
    LEFT JOIN LATERAL (
      SELECT MAX(dispatched_at) AS last_dispatched
      FROM public.selection_dispatch_url_log l
      WHERE l.cycle_id = v_cycle.id
        AND l.track = 'researcher'
        AND l.resolved_evaluator_id = sc.member_id
    ) lrd ON true
    WHERE sc.cycle_id = v_cycle.id
      AND sc.role IN ('evaluator', 'lead')
      AND sc.can_interview = true
      AND COALESCE(sc.interview_booking_url, m.interview_booking_url) IS NOT NULL
    ORDER BY lrd.last_dispatched NULLS FIRST, sc.member_id
    LIMIT 1;

    -- Fallback: no committee member with a URL → cycle URL.
    IF v_resolved_url IS NULL THEN
      v_resolved_url := v_cycle.interview_booking_url;
      v_resolution_path := 'cycle_fallback';
      v_resolved_evaluator_id := NULL;
    END IF;

  ELSE
    -- Defensive fallback for any unknown role_applied (today: only
    -- 'researcher' and 'leader' exist in production data).
    v_resolved_url := v_cycle.interview_booking_url;
    v_resolution_path := 'cycle_fallback';
    v_resolved_evaluator_id := NULL;
  END IF;

  -- Single gate: raise only if BOTH per-evaluator and cycle URLs are absent.
  IF v_resolved_url IS NULL OR length(trim(v_resolved_url)) = 0 THEN
    RAISE EXCEPTION 'CUTOFF_NO_BOOKING_URL: no resolvable booking URL for application % (cycle %, role %); set selection_cycles.interview_booking_url or seed selection_committee with per-evaluator URLs',
      p_application_id, v_app.cycle_id, v_app.role_applied USING ERRCODE = 'P0020';
  END IF;

  -- Dispatch audit row BEFORE campaign_send_one_off — captures which URL +
  -- which precedence path produced it. Becomes the LRD lookback source for
  -- subsequent researcher-track dispatches in the same cycle.
  INSERT INTO public.selection_dispatch_url_log (
    application_id,
    cycle_id,
    track,
    resolved_url,
    resolution_path,
    resolved_evaluator_id,
    organization_id
  ) VALUES (
    p_application_id,
    v_app.cycle_id,
    v_app.role_applied,
    v_resolved_url,
    v_resolution_path,
    v_resolved_evaluator_id,
    v_app.organization_id
  );

  -- Threshold sanity (advisory).
  SELECT count(*)::int INTO v_objective_done
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'objective';

  v_first_name := COALESCE(
    NULLIF(trim(v_app.first_name), ''),
    NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
    'candidato(a)'
  );

  -- Dispatch via campaign_send_one_off — pass the RESOLVED URL.
  PERFORM public.campaign_send_one_off(
    p_template_slug := 'selection_cutoff_approved',
    p_to_email := v_app.email,
    p_variables := jsonb_build_object(
      'first_name', v_first_name,
      'interview_booking_url', v_resolved_url
    ),
    p_metadata := jsonb_build_object(
      'source', 'notify_selection_cutoff_approved',
      'application_id', p_application_id,
      'cycle_id', v_app.cycle_id,
      'cycle_code', v_cycle.cycle_code,
      'objective_done', v_objective_done,
      'research_score', v_app.research_score,
      'resolution_path', v_resolution_path,
      'resolved_evaluator_id', v_resolved_evaluator_id
    )
  );

  -- Mark idempotency post-send.
  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = now(),
      updated_at = now()
  WHERE id = p_application_id;

  -- Audit log — canonical action preserved; metadata gains dispatch_source (p282 W2a).
  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.cutoff_approved_email_dispatched',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'cutoff_approved_email_sent_at_before', NULL,
      'cutoff_approved_email_sent_at_after', now(),
      'recipient_email', v_app.email
    ),
    jsonb_build_object(
      'cycle_id', v_app.cycle_id,
      'cycle_code', v_cycle.cycle_code,
      'objective_done', v_objective_done,
      'research_score', v_app.research_score,
      'interview_booking_url', v_resolved_url,
      'resolution_path', v_resolution_path,
      'resolved_evaluator_id', v_resolved_evaluator_id,
      'role_applied', v_app.role_applied,
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
      'rpc_version', 'p282_411'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'cycle_id', v_app.cycle_id,
    'email_sent', true,
    'recipient_email_redacted', LEFT(v_app.email, 2) || '***' || RIGHT(v_app.email, 4),
    'objective_done', v_objective_done,
    'research_score', v_app.research_score,
    'resolution_path', v_resolution_path,
    'resolved_evaluator_id', v_resolved_evaluator_id
  );
END;
$function$;

-- ============================================================================
-- 2. sync_calendar_booking_to_interview — objective gate on the raw-calendar backdoor
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

  -- #1450 — objective-phase gate on the RAW-calendar backdoor. The gated paths
  -- (schedule_interview / issue_interview_booking_token) already refuse a pre-objective
  -- interview; this webhook must not be the ungated path that materializes an interview
  -- and promotes submitted / interview_pending → interview_scheduled without a computed
  -- objective score. A booking that arrives before the score exists is logged and dropped;
  -- it is idempotently re-bookable once the objective phase completes (the candidate
  -- re-books, or the committee re-dispatches the invite). Placed AFTER the existing-event
  -- idempotency branch so a reschedule of an already-created interview is never blocked.
  IF v_app.objective_score_avg IS NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'arm116.calendar_booking_premature', 'selection_application', v_app.id,
      jsonb_build_object('guest_email', v_guest_email, 'scheduled_at', v_scheduled_at, 'app_status', v_app.status),
      jsonb_build_object('calendar_event_id', v_calendar_event_id, 'event_title', v_event_title, 'reason', 'objective phase not complete (objective_score_avg IS NULL) — #1450', 'matched_by', v_matched_by)
    );
    RETURN jsonb_build_object(
      'warning','application has not completed the objective phase',
      'application_id', v_app.id, 'guest_email', v_guest_email, 'matched_by', v_matched_by
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
