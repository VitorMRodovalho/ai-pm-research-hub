-- ADR-0022 W1 — pg_cron entry for send-weekly-member-digest EF.
--
-- Runs Saturday 12:00 UTC (= 09:00 BRT). The existing cron job 23
-- (`generate_weekly_card_digest_cron`) already runs at this slot to populate
-- `weekly_card_digest_member` notifications; this new entry runs after to
-- pick up the digest_weekly pending rows. Both can fire concurrently safely
-- — generate_weekly_card_digest_cron INSERTS and send-weekly-member-digest
-- only SELECTs (W1 stub) or UPDATEs digest_delivered_at (W2).
--
-- send-notification-email cron (job 9, every 5 min) is unchanged — it now
-- filters by delivery_mode = 'transactional_immediate' instead of
-- CRITICAL_TYPES (EF code change).

DO $$
DECLARE
  v_existing_id int;
  v_secret text;
BEGIN
  -- Skip if already exists (idempotent migration)
  SELECT jobid INTO v_existing_id FROM cron.job
  WHERE command ILIKE '%send-weekly-member-digest%';
  IF v_existing_id IS NOT NULL THEN
    RAISE NOTICE 'Cron entry for send-weekly-member-digest already exists (jobid=%); skipping.', v_existing_id;
    RETURN;
  END IF;

  PERFORM cron.schedule(
    'send-weekly-member-digest',
    '0 12 * * 6',  -- Saturday 12:00 UTC
    $cron$
    SELECT net.http_post(
      url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-weekly-member-digest',
      body := '{"source": "pg_cron"}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      )
    );
    $cron$
  );
END $$;
