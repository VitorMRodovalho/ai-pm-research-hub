-- #963 (finding #3): comms_check_token_expiry() was SECURITY DEFINER with EXECUTE granted
-- to `authenticated` and NO permission gate. It is a writer+reader: it iterates
-- comms_channel_config, idempotently INSERTs into comms_token_alerts and UPDATEs
-- sync_status, then returns unacknowledged alerts. Any authenticated member (incl. ghost
-- users with no member record) could trigger the writes and read which channels have
-- expiring/expired tokens. This closes the last gateable comms-read RPC surface of #963,
-- reverting the p58/p59 "page-gate primary" accepted-risk to align it with the sibling
-- in-RPC gate (#961 get_comms_dashboard_metrics / #883 comms readers, ADR-0106: the
-- boundary is the RLS + SECDEF gate, not the admin-page client guard).
--
-- Non-regressive: the ONLY caller is src/pages/admin/comms.astro (loadTokenAlerts), which
-- calls it with a user-scoped client and hides the alerts section when active_alerts is
-- empty — so the denied return {alerts_created:0, active_alerts:[]} needs no frontend
-- change. There is NO cron/service caller (cron.job has none), so gating cannot break any
-- legitimate background path. The comms-page audience already passes this gate (the
-- #961/#883 RPCs on the same page use the same can_view_comms_analytics()).
--
-- Body-only CREATE OR REPLACE (identity args + result type unchanged) → the EXECUTE grants
-- (authenticated / service_role) and SECURITY DEFINER are preserved. The gate is placed at
-- the TOP, before the write loop, so a denied caller performs NO writes and NO reads.
CREATE OR REPLACE FUNCTION public.comms_check_token_expiry()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_channel record;
  v_days int;
  v_alerts_created int := 0;
  v_alerts jsonb := '[]'::jsonb;
BEGIN
  -- #963: token-expiry alerts are comms-ops data + this function performs writes.
  -- Restrict to the comms-analytics tier (comms team / managers / governance), same gate
  -- as the sibling comms-read RPCs. Denied → zero-shape (no writes, no reads); the
  -- /admin/comms page hides the alerts section on an empty active_alerts.
  IF NOT public.can_view_comms_analytics() THEN
    RETURN jsonb_build_object('alerts_created', 0, 'active_alerts', '[]'::jsonb);
  END IF;

  FOR v_channel IN
    SELECT channel, token_expires_at, sync_status, oauth_token, api_key
    FROM public.comms_channel_config
  LOOP
    -- YouTube uses API key (never expires) — skip
    IF v_channel.channel = 'youtube' THEN
      CONTINUE;
    END IF;

    -- No OAuth token configured — skip
    IF v_channel.oauth_token IS NULL THEN
      CONTINUE;
    END IF;

    -- No expiry date set — skip
    IF v_channel.token_expires_at IS NULL THEN
      CONTINUE;
    END IF;

    v_days := EXTRACT(day FROM v_channel.token_expires_at - now())::int;

    -- Token already expired
    IF v_days < 0 THEN
      -- Only create alert if no recent urgent alert exists for this channel
      IF NOT EXISTS (
        SELECT 1 FROM public.comms_token_alerts
        WHERE channel = v_channel.channel
          AND alert_type = 'urgent'
          AND created_at > now() - interval '1 day'
      ) THEN
        INSERT INTO public.comms_token_alerts (channel, alert_type, message, days_until_expiry)
        VALUES (
          v_channel.channel,
          'urgent',
          format('Token do %s expirou. Métricas não estão sendo atualizadas.', v_channel.channel),
          v_days
        );
        v_alerts_created := v_alerts_created + 1;
      END IF;

      -- Update sync_status
      UPDATE public.comms_channel_config
      SET sync_status = 'token_expired'
      WHERE channel = v_channel.channel AND sync_status != 'token_expired';

    -- Token expiring within 7 days
    ELSIF v_days <= 7 THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.comms_token_alerts
        WHERE channel = v_channel.channel
          AND alert_type = 'warning'
          AND created_at > now() - interval '1 day'
      ) THEN
        INSERT INTO public.comms_token_alerts (channel, alert_type, message, days_until_expiry)
        VALUES (
          v_channel.channel,
          'warning',
          format('Token do %s expira em %s dias. Renove em Admin → Comunicação.', v_channel.channel, v_days),
          v_days
        );
        v_alerts_created := v_alerts_created + 1;
      END IF;
    END IF;
  END LOOP;

  -- Return active (unacknowledged) alerts
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'channel', a.channel,
    'alert_type', a.alert_type,
    'message', a.message,
    'days_until_expiry', a.days_until_expiry,
    'created_at', a.created_at
  ) ORDER BY
    CASE a.alert_type WHEN 'urgent' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END,
    a.created_at DESC
  ), '[]'::jsonb)
  INTO v_alerts
  FROM public.comms_token_alerts a
  WHERE a.acknowledged = false;

  RETURN jsonb_build_object(
    'alerts_created', v_alerts_created,
    'active_alerts', v_alerts
  );
END;
$function$;

-- Restate the ACL intent explicitly (CREATE OR REPLACE on an identical signature already
-- preserves the live grants; this makes the intent auditable + the migration idempotent
-- even if the function were ever DROPped first). anon is intentionally NOT granted (it was
-- revoked in mig 20260426001848 and never restored for this fn).
GRANT EXECUTE ON FUNCTION public.comms_check_token_expiry() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
