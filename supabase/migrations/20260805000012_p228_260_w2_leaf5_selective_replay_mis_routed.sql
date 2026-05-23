-- p228 #260 W2 Leaf 5: selective replay/manual-close for 17 mis-routed selection notifications
--
-- PM Policy Matrix Amendment D D-sel-2 (#260, 2026-05-23). p227 audit Section
-- "Replay Plan (Resend-safe)" + Q1 identified 17 candidate-facing selection_*
-- notifications mis-routed via the digest path (13 selection_termo_due + 2
-- selection_approved + 2 selection_interview_scheduled), with email_sent_at IS NULL
-- and digest_delivered_at IS NOT NULL.
--
-- PM decision: SELECTIVE replay, NOT blind:
--   - replay selection_approved + selection_interview_scheduled when STILL RELEVANT
--   - replay selection_termo_due ONLY when candidate still has real pending term action
--   - otherwise manual-close/document; avoid useless double-send
--
-- This leaf ships a one-shot RPC `_replay_selection_notifications_p228(p_dry_run boolean)`
-- with safe defaults:
--
--   p_dry_run=true (default):
--     Returns jsonb breakdown of the 17 historical rows + classification:
--       - eligible_replay: rows that pass the selective criteria
--       - manual_close: rows that should be left as-is (not replayed)
--     NO writes. Safe to call repeatedly for analysis.
--
--   p_dry_run=false:
--     UPDATEs eligible rows to delivery_mode='transactional_immediate' AND
--     digest_delivered_at=NULL AND digest_batch_id=NULL. Idempotent on
--     email_sent_at IS NULL guard. Logs to admin_audit_log. After UPDATE, the
--     send-notification-email EF cron (every 5 min) will pick them up next cycle.
--
-- Selective criteria (per PM D-sel-2 + audit Section "Replay Plan"):
--
--   selection_termo_due:
--     Replay ONLY if recipient member has selection_applications.status='approved'
--     AND has not yet signed the volunteer agreement (tracked via certificates
--     row with type='volunteer_agreement' + status='issued' per sign_volunteer_agreement
--     RPC body, not a dedicated volunteer_agreements table). Conservative
--     match-criteria avoids double-emailing candidates who already moved through
--     the funnel.
--
--   selection_approved:
--     Replay if notification created_at within last 30 days AND member exists with
--     member_status='active' (signal: still in active onboarding window). Older
--     notifications without active members → manual_close.
--
--   selection_interview_scheduled:
--     Replay if associated interview row has scheduled_at > NOW() (interview
--     genuinely upcoming, not already happened). Past interviews → manual_close
--     since the date info is now stale.
--
-- Authority gate: callable only by service_role (cron) + members with
-- can_by_member('manage_member') OR can_by_member('manage_platform') — admin path.
--
-- This RPC is intentionally one-shot for the audited 17-row backlog window
-- (created_at >= 2026-05-01 AND < 2026-05-20). Future mis-routes that arise from
-- catalog drift get a separate replay window per W3 (or PM ratifies further use of
-- this RPC with adjusted window).

CREATE OR REPLACE FUNCTION public._replay_selection_notifications_p228(
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_caller record;
  v_window_start date := '2026-05-01';
  v_window_end   date := '2026-05-20';
  v_eligible_ids uuid[] := ARRAY[]::uuid[];
  v_eligible_count int := 0;
  v_manual_close_count int := 0;
  v_eligible_payload jsonb := '[]'::jsonb;
  v_manual_close_payload jsonb := '[]'::jsonb;
  v_updated_count int := 0;
  v_row record;
BEGIN
  -- Authority gate: admin path only (or service_role bypass)
  IF auth.uid() IS NOT NULL THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
    IF NOT (public.can_by_member(v_caller.id, 'manage_member'::text)
            OR public.can_by_member(v_caller.id, 'manage_platform'::text)) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member or manage_platform';
    END IF;
  END IF;
  -- service_role (auth.uid() IS NULL) bypasses the member-side check; intended
  -- for one-shot cron invocation if PM later schedules this.

  -- Classify the 17 historical rows
  FOR v_row IN
    SELECT n.id, n.type, n.recipient_id, n.source_id, n.created_at,
           n.delivery_mode, n.email_sent_at, n.digest_delivered_at,
           m.member_status,
           m.id AS member_id_exists
    FROM public.notifications n
    LEFT JOIN public.members m ON m.id = n.recipient_id
    WHERE n.type IN ('selection_termo_due', 'selection_approved', 'selection_interview_scheduled')
      AND n.created_at >= v_window_start::timestamptz
      AND n.created_at < v_window_end::timestamptz
      AND n.email_sent_at IS NULL
      AND n.digest_delivered_at IS NOT NULL
    ORDER BY n.created_at
  LOOP
    DECLARE
      v_should_replay boolean := false;
      v_reason text;
      v_pending_term boolean;
      v_future_interview boolean;
      v_app_record record;
    BEGIN
      IF v_row.type = 'selection_termo_due' THEN
        -- Replay only if member has a selection_application approved AND has not yet
        -- signed the volunteer agreement (tracked via certificates.type='volunteer_agreement'
        -- + status='issued' — see sign_volunteer_agreement() RPC body).
        SELECT EXISTS (
          SELECT 1
          FROM public.selection_applications sa
          JOIN public.members m ON lower(m.email) = lower(sa.email)
          WHERE m.id = v_row.recipient_id
            AND sa.status = 'approved'
            AND NOT EXISTS (
              SELECT 1 FROM public.certificates c
              WHERE c.member_id = m.id
                AND c.type = 'volunteer_agreement'
                AND c.status = 'issued'
            )
        ) INTO v_pending_term;

        v_should_replay := COALESCE(v_pending_term, false);
        v_reason := CASE WHEN v_should_replay
          THEN 'pending_term_action_exists'
          ELSE 'no_pending_term_or_already_signed'
        END;

      ELSIF v_row.type = 'selection_approved' THEN
        -- Replay if within 30d AND member is active (still in onboarding window)
        v_should_replay := (
          (now() - v_row.created_at) < interval '30 days'
          AND v_row.member_id_exists IS NOT NULL
          AND v_row.member_status = 'active'
        );
        v_reason := CASE WHEN v_should_replay
          THEN 'recent_and_active_member'
          ELSE 'stale_or_inactive'
        END;

      ELSIF v_row.type = 'selection_interview_scheduled' THEN
        -- Replay if associated interview is in the future (date info still actionable)
        SELECT EXISTS (
          SELECT 1
          FROM public.selection_interviews si
          WHERE si.application_id = v_row.source_id
            AND si.scheduled_at > now()
            AND si.conducted_at IS NULL
        ) INTO v_future_interview;

        v_should_replay := COALESCE(v_future_interview, false);
        v_reason := CASE WHEN v_should_replay
          THEN 'interview_still_upcoming'
          ELSE 'interview_past_or_completed'
        END;
      END IF;

      IF v_should_replay THEN
        v_eligible_ids := array_append(v_eligible_ids, v_row.id);
        v_eligible_count := v_eligible_count + 1;
        v_eligible_payload := v_eligible_payload || jsonb_build_object(
          'notification_id', v_row.id,
          'type', v_row.type,
          'created_at', v_row.created_at,
          'reason', v_reason
        );
      ELSE
        v_manual_close_count := v_manual_close_count + 1;
        v_manual_close_payload := v_manual_close_payload || jsonb_build_object(
          'notification_id', v_row.id,
          'type', v_row.type,
          'created_at', v_row.created_at,
          'reason', v_reason
        );
      END IF;
    END;
  END LOOP;

  -- Apply UPDATE if not dry_run
  IF NOT p_dry_run AND v_eligible_count > 0 THEN
    UPDATE public.notifications
    SET delivery_mode = 'transactional_immediate',
        digest_delivered_at = NULL,
        digest_batch_id = NULL
    WHERE id = ANY(v_eligible_ids)
      AND email_sent_at IS NULL  -- defense-in-depth idempotency
    RETURNING 1 INTO v_updated_count;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    -- Audit log
    INSERT INTO public.admin_audit_log (
      actor_id, action, target_type, target_id, changes, metadata
    ) VALUES (
      COALESCE(v_caller.id, '00000000-0000-0000-0000-000000000000'::uuid),
      'selection.notifications_replay_p228',
      'notifications',
      NULL,
      jsonb_build_object(
        'eligible_replay_count', v_eligible_count,
        'manual_close_count', v_manual_close_count,
        'updated_count', v_updated_count,
        'eligible_ids', v_eligible_ids
      ),
      jsonb_build_object(
        'window_start', v_window_start,
        'window_end', v_window_end,
        'dry_run', p_dry_run,
        'rpc_version', 'p228_w2_leaf5'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'window_start', v_window_start,
    'window_end', v_window_end,
    'eligible_replay_count', v_eligible_count,
    'manual_close_count', v_manual_close_count,
    'updated_count', v_updated_count,
    'eligible_replay', v_eligible_payload,
    'manual_close', v_manual_close_payload
  );
END;
$func$;

REVOKE ALL ON FUNCTION public._replay_selection_notifications_p228(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._replay_selection_notifications_p228(boolean) TO authenticated, service_role;

COMMENT ON FUNCTION public._replay_selection_notifications_p228(boolean) IS
'p228 #260 W2 Leaf 5: one-shot selective replay for 17 historical mis-routed '
'selection_* notifications (window 2026-05-01 .. 2026-05-20). p_dry_run=true '
'(default) returns analysis without writes. p_dry_run=false UPDATES eligible '
'rows to delivery_mode=transactional_immediate so send-notification-email cron '
'picks them up. Selective criteria per PM D-sel-2: replay only when still '
'relevant (pending term action / active onboarding / future interview). '
'Authority: manage_member or manage_platform.';

NOTIFY pgrst, 'reload schema';
