-- ═══════════════════════════════════════════════════════════════
-- W94 Sprint 3: Token expiry alerts for comms channels
-- Creates alert table + check RPC that generates alerts
-- ═══════════════════════════════════════════════════════════════

-- 1. Alerts table for persistent notifications
CREATE TABLE IF NOT EXISTS public.comms_token_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel text NOT NULL REFERENCES public.comms_channel_config(channel) ON DELETE CASCADE,
  alert_type text NOT NULL CHECK (alert_type IN ('warning', 'urgent', 'resolved')),
  message text NOT NULL,
  days_until_expiry int,
  acknowledged boolean DEFAULT false,
  acknowledged_by uuid,
  created_at timestamptz DEFAULT now()
);

COMMENT ON TABLE public.comms_token_alerts IS
  'W94: Persistent token expiry alerts for comms channels';

ALTER TABLE public.comms_token_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comms_token_alerts_admin" ON public.comms_token_alerts
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid()
        AND (
          is_superadmin
          OR operational_role IN ('manager', 'deputy_manager')
          OR designations && ARRAY['comms_leader']
        )
    )
  );

-- 2. RPC: check token expiry and create alerts
CREATE OR REPLACE FUNCTION public.comms_check_token_expiry()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_channel record;
  v_days int;
  v_alerts_created int := 0;
  v_alerts jsonb := '[]'::jsonb;
BEGIN
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
$$;

GRANT EXECUTE ON FUNCTION public.comms_check_token_expiry() TO authenticated;

-- 3. RPC: acknowledge an alert
CREATE OR REPLACE FUNCTION public.comms_acknowledge_alert(p_alert_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
BEGIN
  SELECT auth.uid() INTO v_uid;

  UPDATE public.comms_token_alerts
  SET acknowledged = true, acknowledged_by = v_uid
  WHERE id = p_alert_id AND acknowledged = false;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'alert_not_found');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.comms_acknowledge_alert(uuid) TO authenticated;
