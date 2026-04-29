-- p82 CBGPL launch hotfix: Resend rate limit is 5/s (not just 100/day).
-- Add pg_sleep(0.25) between dispatches → 4/s sustained, safe under 5/s.
-- Also retry rows with status='failed' that hit rate_limit_exceeded.

CREATE OR REPLACE FUNCTION public.process_pending_email_queue()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_today_count int;
  v_daily_limit int := 100;
  v_slots int;
  v_pending record;
  v_dispatched int := 0;
  v_skipped int := 0;
  v_service_role_key text;
  v_today_start timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo';
BEGIN
  SELECT count(*) INTO v_today_count
  FROM campaign_recipients
  WHERE delivered = true
    AND created_at >= v_today_start;

  v_slots := GREATEST(0, v_daily_limit - v_today_count);

  IF v_slots = 0 THEN
    RETURN jsonb_build_object('today_count', v_today_count, 'slots', 0, 'dispatched', 0, 'message', 'daily_limit_reached');
  END IF;

  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  IF v_service_role_key IS NULL THEN
    RAISE NOTICE 'process_pending_email_queue: no service_role_key in vault';
    RETURN jsonb_build_object('error', 'no_service_role_key');
  END IF;

  -- Pick: pending_delivery OR throttled OR failed-with-rate-limit
  -- (status='failed' may have transient rate_limit_exceeded; we retry those)
  FOR v_pending IN
    SELECT cs.id AS send_id
    FROM campaign_sends cs
    WHERE (
      cs.status IN ('pending_delivery', 'throttled')
      OR (cs.status = 'failed' AND cs.error_log ILIKE '%rate_limit_exceeded%')
    )
    AND EXISTS (
      SELECT 1 FROM campaign_recipients cr
      WHERE cr.send_id = cs.id AND cr.delivered = false AND cr.unsubscribed = false
    )
    ORDER BY cs.created_at ASC
    LIMIT v_slots
  LOOP
    BEGIN
      PERFORM net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-campaign',
        body := jsonb_build_object('send_id', v_pending.send_id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        )
      );
      v_dispatched := v_dispatched + 1;
      -- Serialize dispatches: Resend rate limit is 5 req/s, we sustain 4/s.
      PERFORM pg_sleep(0.25);
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      RAISE NOTICE 'process_pending_email_queue dispatch failed send_id=%: %', v_pending.send_id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'today_count_before', v_today_count,
    'daily_limit', v_daily_limit,
    'slots_available', v_slots,
    'dispatched', v_dispatched,
    'skipped', v_skipped,
    'today_start', v_today_start,
    'rate_limit_protection', '4_per_second'
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
