-- #209 / ADR-0107: schedule the Drive offboarding cascade crons.
-- cron.schedule(name, ...) upserts by name → idempotent. Bearer = vault service_role_key
-- (the token EFs verify via isServiceRoleToken / current_caller_role — #738/#850).
--
-- NOTE (apply order): apply this migration ONLY after the detection EF is deployed and the
-- one-shot dry_run confirms permissions.list returns emailAddress under the SA scope/role
-- (ADR-0107 §dry-run gate). Until then the weekly job would POST to a non-existent function.

-- Weekly detection scan — Mondays 05:00 UTC.
SELECT cron.schedule(
  'audit-drive-offboarding-weekly',
  '0 5 * * 1',
  $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/audit-drive-offboarding-access',
    body := '{"source":"pg_cron"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    timeout_milliseconds := 150000
  );
  $cron$
);

-- Revoke drain (safety net) — hourly at :07. Drains GP-approved rows the synchronous MCP
-- path may have left behind (host disconnect / EF timeout). 5-min delay avoids racing the
-- synchronous approve. Each POST is idempotent (the EF only acts on status='approved').
SELECT cron.schedule(
  'revoke-drive-drain-hourly',
  '7 * * * *',
  $cron$
  DO $drain$
  DECLARE r record;
  BEGIN
    FOR r IN
      SELECT id FROM public.drive_offboarding_audit
      WHERE status = 'approved' AND approved_at < now() - interval '5 minutes'
      ORDER BY approved_at
      LIMIT 50
    LOOP
      PERFORM net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/revoke-drive-permission',
        body := jsonb_build_object('audit_id', r.id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        )
      );
    END LOOP;
  END
  $drain$;
  $cron$
);
