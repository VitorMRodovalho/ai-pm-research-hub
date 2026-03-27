-- GC-155: Email notification delivery for critical events
-- Now that Resend DNS is verified, activate email for governance/certificate/attendance alerts

-- Track which notifications were emailed
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS email_sent_at timestamptz;

-- pg_cron: check every 5 minutes for critical notifications needing email
-- Edge Function send-notification-email handles: governance_cr_approved, governance_cr_vote,
-- governance_cr_new, volunteer_agreement_signed, certificate_ready, attendance_detractor
SELECT cron.schedule(
  'send-notification-emails',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('supabase.url', true) || '/functions/v1/send-notification-email',
    body := '{"source": "pg_cron"}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json')
  );
  $$
);

NOTIFY pgrst, 'reload schema';
