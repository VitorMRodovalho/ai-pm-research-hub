-- p82 CBGPL launch hardening: 2 cron-based retry mechanisms
-- N1: process_pending_email_queue — daily Resend throttle (100/day) with batched retry
-- N2: retry_pending_ai_analyses — picks consent-yes + ai_analysis-null apps for re-dispatch

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

  FOR v_pending IN
    SELECT cs.id AS send_id
    FROM campaign_sends cs
    WHERE cs.status IN ('pending_delivery', 'throttled')
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
    'today_start', v_today_start
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_pending_email_queue() TO service_role;

CREATE OR REPLACE FUNCTION public.retry_pending_ai_analyses()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_app record;
  v_dispatched int := 0;
  v_skipped int := 0;
  v_service_role_key text;
  v_pending_count int;
BEGIN
  SELECT count(*) INTO v_pending_count
  FROM selection_applications
  WHERE consent_ai_analysis_at IS NOT NULL
    AND consent_ai_analysis_revoked_at IS NULL
    AND ai_analysis IS NULL
    AND consent_ai_analysis_at < now() - interval '5 minutes';

  IF v_pending_count = 0 THEN
    RETURN jsonb_build_object('pending', 0, 'dispatched', 0);
  END IF;

  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  IF v_service_role_key IS NULL THEN
    RETURN jsonb_build_object('error', 'no_service_role_key', 'pending', v_pending_count);
  END IF;

  FOR v_app IN
    SELECT id
    FROM selection_applications
    WHERE consent_ai_analysis_at IS NOT NULL
      AND consent_ai_analysis_revoked_at IS NULL
      AND ai_analysis IS NULL
      AND consent_ai_analysis_at < now() - interval '5 minutes'
    ORDER BY consent_ai_analysis_at ASC
    LIMIT 50
  LOOP
    BEGIN
      PERFORM net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/pmi-ai-analyze',
        body := jsonb_build_object('application_id', v_app.id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        )
      );
      v_dispatched := v_dispatched + 1;
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      RAISE NOTICE 'retry_pending_ai_analyses dispatch failed app_id=%: %', v_app.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'pending_total', v_pending_count,
    'dispatched', v_dispatched,
    'skipped', v_skipped,
    'limit_per_run', 50
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.retry_pending_ai_analyses() TO service_role;

-- Schedule crons (idempotent)
DO $$
BEGIN
  PERFORM cron.unschedule('dispatch-pending-emails') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dispatch-pending-emails');
EXCEPTION WHEN OTHERS THEN NULL;
END$$;

DO $$
BEGIN
  PERFORM cron.unschedule('retry-pending-ai-analyses') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'retry-pending-ai-analyses');
EXCEPTION WHEN OTHERS THEN NULL;
END$$;

SELECT cron.schedule(
  'dispatch-pending-emails',
  '*/30 * * * *',
  $cron$SELECT public.process_pending_email_queue();$cron$
);

SELECT cron.schedule(
  'retry-pending-ai-analyses',
  '0 * * * *',
  $cron$SELECT public.retry_pending_ai_analyses();$cron$
);

NOTIFY pgrst, 'reload schema';
