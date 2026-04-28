-- ADR-0065 Drive Phase 4: pg_cron daily schedule for drive-discover-atas EF.
-- 03:00 UTC = 00:00 BRT — quiet slot (between LGPD crons at 03:30 and morning).
-- Idempotent: skip if already exists.

DO $$
DECLARE
  v_existing_id int;
BEGIN
  SELECT jobid INTO v_existing_id FROM cron.job
  WHERE command ILIKE '%drive-discover-atas%';
  IF v_existing_id IS NOT NULL THEN
    RAISE NOTICE 'Cron entry for drive-discover-atas already exists (jobid=%); skipping.', v_existing_id;
    RETURN;
  END IF;

  PERFORM cron.schedule(
    'drive-discover-atas-daily',
    '0 3 * * *',  -- daily at 03:00 UTC
    $cron$
    SELECT net.http_post(
      url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/drive-discover-atas',
      body := '{"source": "pg_cron"}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      )
    );
    $cron$
  );
END $$;
