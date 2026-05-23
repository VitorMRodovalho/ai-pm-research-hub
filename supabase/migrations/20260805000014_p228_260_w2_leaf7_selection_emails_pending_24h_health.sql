-- p228 #260 W2 Leaf 7: 24h health signal for selection email dispatcher silence
--
-- PM Policy Matrix Amendment D D-sel-5 (#260, 2026-05-23). p227 audit Section
-- "Proposed Child Ready-Leaf Issues" item 7 + PM D-sel-5: "automatic +
-- idempotent peer-review dispatch with manual override and 24h health signal."
--
-- This RPC surfaces selection_* notification dispatcher silence — the gap
-- between INSERT-ed transactional rows and actually-sent emails. Healthy state:
-- send-notification-email cron picks up rows within ~5min, so the 24h-pending
-- count should be near 0 except for transient race windows.
--
-- Signal triggers admin investigation when the count exceeds the threshold
-- (default 10) — likely root causes are:
--   - send-notification-email EF cron paused or erroring
--   - Resend API quota exhaustion (100/day limit)
--   - notify_delivery_mode_pref=suppress_all opt-out blocking many rows (now
--     mostly resolved for the 4 candidate-facing types by Leaf 6)
--   - delivery_mode mis-routing despite catalog/helper parity (Leaf 1 case)
--
-- Surfaces:
--   - MCP tool `get_selection_emails_pending_24h` (p229 follow-up — fast-follow
--     from this scaffolding)
--   - Admin dashboard widget (can call directly)
--   - Future cron escalation to admin Slack/PagerDuty
--
-- Authority: read-only RPC, accessible to authenticated members with
-- can_by_member('manage_member') OR can_by_member('manage_platform') for
-- admin dashboard surfacing; service_role for cron auto-monitoring.

CREATE OR REPLACE FUNCTION public.get_selection_emails_pending_24h(
  p_alert_threshold integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_caller record;
  v_total_pending int;
  v_by_type jsonb;
  v_oldest_pending timestamptz;
  v_oldest_age_minutes int;
  v_alert_triggered boolean;
BEGIN
  -- Authority gate: admin path
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
  -- service_role bypasses auth gate (for cron auto-monitoring).

  -- Count selection_* notifications with transactional_immediate routing that
  -- have NOT been emailed AND are older than 24h. This is the dispatcher silence
  -- signal — healthy state is ~0 (5min cron picks rows up quickly).
  SELECT count(*)::int INTO v_total_pending
  FROM public.notifications n
  WHERE n.type LIKE 'selection_%'
    AND n.delivery_mode = 'transactional_immediate'
    AND n.email_sent_at IS NULL
    AND n.created_at < now() - interval '24 hours';

  -- Per-type breakdown for triage
  SELECT COALESCE(jsonb_object_agg(t.type, t.count_pending), '{}'::jsonb)
  INTO v_by_type
  FROM (
    SELECT type, count(*)::int AS count_pending
    FROM public.notifications
    WHERE type LIKE 'selection_%'
      AND delivery_mode = 'transactional_immediate'
      AND email_sent_at IS NULL
      AND created_at < now() - interval '24 hours'
    GROUP BY type
    ORDER BY count_pending DESC
  ) t;

  -- Oldest pending row — useful for admin triage to see if backlog is stale or fresh
  SELECT min(created_at) INTO v_oldest_pending
  FROM public.notifications
  WHERE type LIKE 'selection_%'
    AND delivery_mode = 'transactional_immediate'
    AND email_sent_at IS NULL
    AND created_at < now() - interval '24 hours';

  v_oldest_age_minutes := CASE
    WHEN v_oldest_pending IS NULL THEN NULL
    ELSE EXTRACT(EPOCH FROM (now() - v_oldest_pending))::int / 60
  END;

  v_alert_triggered := v_total_pending > p_alert_threshold;

  RETURN jsonb_build_object(
    'success', true,
    'total_pending', v_total_pending,
    'by_type', v_by_type,
    'oldest_pending_at', v_oldest_pending,
    'oldest_age_minutes', v_oldest_age_minutes,
    'alert_threshold', p_alert_threshold,
    'alert_triggered', v_alert_triggered,
    'computed_at', now(),
    'rpc_version', 'p228_w2_leaf7'
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.get_selection_emails_pending_24h(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_selection_emails_pending_24h(integer) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_selection_emails_pending_24h(integer) IS
'p228 #260 W2 Leaf 7: 24h dispatcher silence health signal for selection_* '
'notifications. Returns jsonb with total_pending count + per-type breakdown + '
'oldest_age_minutes + alert_triggered (when total > p_alert_threshold, default '
'10). Healthy state ~0 (send-notification-email cron picks up within 5min). '
'Authority: manage_member or manage_platform admin path; service_role bypass '
'for cron auto-monitoring. Future MCP tool registration in p229 follow-up.';

NOTIFY pgrst, 'reload schema';
