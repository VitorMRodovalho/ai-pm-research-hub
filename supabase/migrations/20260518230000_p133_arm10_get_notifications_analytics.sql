-- p133 ARM-10 hygiene: get_notifications_analytics RPC
-- Last W3 deliverable substrate of ADR-0022. Complements get_digest_health (cron focus).
-- Scope: per-delivery_mode + per-type breakdown + send latency + time series.
-- LIMITATION: open/click/bounce data lives in campaign_recipients (campaign sends only),
-- NOT linked to per-notification email send via send-notification-email EF.
-- For open rate by campaign, use existing get_comms_metrics_by_channel MCP tool instead.
-- Authority: requires can_by_member('view_internal_analytics') — same gate as get_digest_health.

CREATE OR REPLACE FUNCTION public.get_notifications_analytics(p_window_days integer DEFAULT 28)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_window_start timestamptz;
  v_by_mode jsonb;
  v_by_type jsonb;
  v_timeseries jsonb;
  v_overall jsonb;
  v_clamped integer;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  v_clamped := GREATEST(1, LEAST(365, COALESCE(p_window_days, 28)));
  v_window_start := now() - (v_clamped || ' days')::interval;

  SELECT jsonb_build_object(
    'window_days', v_clamped,
    'window_start', v_window_start,
    'total_created', COUNT(*),
    'email_sent_count', COUNT(*) FILTER (WHERE email_sent_at IS NOT NULL),
    'email_sent_rate', ROUND(100.0 * COUNT(*) FILTER (WHERE email_sent_at IS NOT NULL) / NULLIF(COUNT(*),0), 2),
    'digest_pending', COUNT(*) FILTER (WHERE delivery_mode='digest_weekly' AND digest_delivered_at IS NULL),
    'digest_consumed', COUNT(*) FILTER (WHERE delivery_mode='digest_weekly' AND digest_delivered_at IS NOT NULL),
    'distinct_recipients', COUNT(DISTINCT recipient_id),
    'distinct_types', COUNT(DISTINCT type)
  )
  INTO v_overall
  FROM public.notifications
  WHERE created_at >= v_window_start;

  SELECT jsonb_object_agg(
    delivery_mode,
    jsonb_build_object(
      'total', total,
      'email_sent', email_sent,
      'send_rate_pct', ROUND(100.0 * email_sent / NULLIF(total,0), 2),
      'pending_digest', pending_digest,
      'avg_send_latency_minutes', ROUND(avg_send_latency_minutes::numeric, 1)
    )
  )
  INTO v_by_mode
  FROM (
    SELECT
      delivery_mode,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE email_sent_at IS NOT NULL) AS email_sent,
      COUNT(*) FILTER (WHERE delivery_mode='digest_weekly' AND digest_delivered_at IS NULL) AS pending_digest,
      AVG(EXTRACT(EPOCH FROM (email_sent_at - created_at)) / 60.0)
        FILTER (WHERE email_sent_at IS NOT NULL) AS avg_send_latency_minutes
    FROM public.notifications
    WHERE created_at >= v_window_start
    GROUP BY delivery_mode
  ) sub;

  SELECT jsonb_agg(
    jsonb_build_object(
      'type', type_name,
      'delivery_mode', delivery_mode_max,
      'total', total,
      'email_sent', email_sent,
      'send_rate_pct', ROUND(100.0 * email_sent / NULLIF(total,0), 2),
      'pending_digest', pending_digest
    )
    ORDER BY total DESC
  )
  INTO v_by_type
  FROM (
    SELECT
      type AS type_name,
      MAX(delivery_mode) AS delivery_mode_max,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE email_sent_at IS NOT NULL) AS email_sent,
      COUNT(*) FILTER (WHERE delivery_mode='digest_weekly' AND digest_delivered_at IS NULL) AS pending_digest
    FROM public.notifications
    WHERE created_at >= v_window_start
    GROUP BY type
    ORDER BY COUNT(*) DESC
    LIMIT 20
  ) ranked;

  SELECT jsonb_agg(jsonb_build_object(
    'day', day,
    'created', created,
    'email_sent', email_sent
  ) ORDER BY day ASC)
  INTO v_timeseries
  FROM (
    SELECT
      date_trunc('day', created_at)::date AS day,
      COUNT(*) AS created,
      COUNT(*) FILTER (WHERE email_sent_at IS NOT NULL) AS email_sent
    FROM public.notifications
    WHERE created_at >= GREATEST(v_window_start, now() - interval '30 days')
    GROUP BY date_trunc('day', created_at)
  ) daily;

  RETURN jsonb_build_object(
    'overall', v_overall,
    'by_delivery_mode', COALESCE(v_by_mode, '{}'::jsonb),
    'by_type', COALESCE(v_by_type, '[]'::jsonb),
    'timeseries_daily', COALESCE(v_timeseries, '[]'::jsonb),
    'note', 'Window=created_at within p_window_days. send_rate = email_sent/total. avg_send_latency only for sent rows. Open/click data lives in campaign_recipients (use get_comms_metrics_by_channel for campaign-level rates).',
    'fetched_at', now()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_notifications_analytics(integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
