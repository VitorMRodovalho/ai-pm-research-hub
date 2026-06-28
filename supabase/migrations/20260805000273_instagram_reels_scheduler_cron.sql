-- Instagram Reels scheduler — the drain cron.
-- Pings publish-scheduled every 15 min; the EF claims due rows (scheduled_at passed) and
-- publishes them through publish-instagram. Idempotent: the EF only acts on status='pending'
-- and claims each row atomically, so overlapping runs are safe.
--
-- NOTE (apply order): apply this ONLY after publish-scheduled is deployed and a dry-run
-- confirmed it drains correctly (mirrors the #209 drive-cron gate). Until then the POST
-- would hit a non-existent function. cron.schedule upserts by name -> idempotent.
-- Bearer = vault service_role_key (the token publish-scheduled verifies).

select cron.schedule(
  'publish-scheduled-social',
  '*/15 * * * *',
  $cron$
  select net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/publish-scheduled',
    body := '{"source":"pg_cron"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key' limit 1)
    ),
    timeout_milliseconds := 150000
  );
  $cron$
);
