-- p228 Leaf 5 hotfix: replace UPDATE ... RETURNING 1 INTO v_updated_count
-- with plain UPDATE + GET DIAGNOSTICS ROW_COUNT.
--
-- Bug (caught by PM post-p228 close, pre-execution): the prior Leaf 5 body
-- (migration 20260805000012) used:
--
--   UPDATE public.notifications
--   SET delivery_mode = 'transactional_immediate',
--       digest_delivered_at = NULL,
--       digest_batch_id = NULL
--   WHERE id = ANY(v_eligible_ids)
--     AND email_sent_at IS NULL
--   RETURNING 1 INTO v_updated_count;
--
--   GET DIAGNOSTICS v_updated_count = ROW_COUNT;
--
-- PostgreSQL semantics: `RETURNING ... INTO <scalar>` in plpgsql expects
-- EXACTLY ONE row. When the UPDATE touches 2+ rows, the runtime raises
-- "query returned more than one row" (SQLSTATE 21000), short-circuiting
-- BEFORE the GET DIAGNOSTICS line, BEFORE the admin_audit_log INSERT, and
-- BEFORE the RETURN jsonb. The bug is dormant whenever v_eligible_count
-- equals 0 (block skipped) or exactly 1 (RETURNING INTO succeeds), but
-- live state has v_eligible_count = 2 — so any call with p_dry_run=false
-- would have errored.
--
-- Live dry-run smoke (p_dry_run=true) had been masking this — the dry_run
-- branch never enters the IF NOT p_dry_run guard. The bug only surfaces on
-- actual UPDATE execution.
--
-- Fix: drop the `RETURNING 1 INTO v_updated_count` clause entirely. The
-- subsequent `GET DIAGNOSTICS v_updated_count = ROW_COUNT` was already
-- present and gives the correct multi-row UPDATE count without raising.
--
-- Forward-defense: contract test asserts that the body of
-- _replay_selection_notifications_p228 does NOT contain any RETURNING ... INTO
-- pattern (`tests/contracts/adr-0022-delivery-mode.test.mjs`). Regression
-- guard.
--
-- Second bug caught during live smoke of p_dry_run=false (same code path,
-- service_role context): `v_caller record;` was declared but never assigned
-- when auth.uid() is NULL (service_role bypass). The audit log INSERT then
-- tried `COALESCE(v_caller.id, ...)` and Postgres raised
-- "record v_caller is not assigned yet" (SQLSTATE 55000). Same pre-execution
-- dormancy pattern as the RETURNING bug — masked by dry-run smoke that
-- never enters the IF NOT p_dry_run branch.
--
-- Fix: replace the unassigned-record-access pattern with a scalar
-- `v_caller_id uuid := NULL;`. Three references swap from `v_caller.id` to
-- `v_caller_id`. Forward-defense contract test asserts the safe pattern.
--
-- Third bug caught during live smoke of p_dry_run=false (same code path,
-- service_role context): `admin_audit_log.actor_id` has a NOT NULL FK to
-- `members(id)`. Earlier code used
-- `COALESCE(v_caller_id, '00000000-...zero-uuid...')` as sentinel for the
-- service_role bypass — but the zero-uuid is not a real member, so the
-- INSERT raised `23503 violates admin_audit_log_actor_id_fkey`. Same
-- dormancy pattern: dry_run skips the audit log entirely; only surfaces on
-- actual UPDATE execution from service_role context.
--
-- Fix: gate the admin_audit_log INSERT on `v_caller_id IS NOT NULL`.
-- service_role / cron invocations track via different mechanisms
-- (postgres logs, cron_run_log) — admin_audit_log is intentionally
-- member-scoped per the action.actor_id semantics. Forward-defense
-- contract test asserts the gate.

CREATE OR REPLACE FUNCTION public._replay_selection_notifications_p228(
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_caller_id uuid := NULL;
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
  -- Authority gate: admin path only (or service_role bypass).
  -- Hotfix p228: use scalar v_caller_id (uuid) so the audit log INSERT below
  -- can safely COALESCE without tripping the unassigned-record trap on
  -- service_role calls (auth.uid() IS NULL → branch skipped entirely).
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
    IF NOT (public.can_by_member(v_caller_id, 'manage_member'::text)
            OR public.can_by_member(v_caller_id, 'manage_platform'::text)) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member or manage_platform';
    END IF;
  END IF;
  -- service_role (auth.uid() IS NULL) bypasses the member-side check; intended
  -- for one-shot cron invocation if PM later schedules this. v_caller_id stays
  -- NULL in that path; COALESCE in audit log uses the zero-uuid sentinel.

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

  -- Apply UPDATE if not dry_run. Hotfix p228 (see migration 20260805000015):
  -- plain UPDATE + GET DIAGNOSTICS ROW_COUNT is the correct multi-row count
  -- primitive. Earlier code used the scalar-into clause which raises 21000
  -- on 2+ rows; the contract test in adr-0022-delivery-mode.test.mjs guards
  -- against the broken pattern returning.
  IF NOT p_dry_run AND v_eligible_count > 0 THEN
    UPDATE public.notifications
    SET delivery_mode = 'transactional_immediate',
        digest_delivered_at = NULL,
        digest_batch_id = NULL
    WHERE id = ANY(v_eligible_ids)
      AND email_sent_at IS NULL;  -- defense-in-depth idempotency

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    -- Audit log — gated on v_caller_id IS NOT NULL. admin_audit_log.actor_id
    -- has a NOT NULL FK to members(id); service_role (auth.uid() NULL) lacks a
    -- valid actor, and there is no system-member sentinel to COALESCE to.
    -- service_role / cron invocations are tracked via postgres logs +
    -- cron_run_log; admin_audit_log stays member-scoped.
    IF v_caller_id IS NOT NULL THEN
      INSERT INTO public.admin_audit_log (
        actor_id, action, target_type, target_id, changes, metadata
      ) VALUES (
        v_caller_id,
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
          'rpc_version', 'p228_w2_leaf5_hotfix_diag_rowcount'
        )
      );
    END IF;
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

NOTIFY pgrst, 'reload schema';
