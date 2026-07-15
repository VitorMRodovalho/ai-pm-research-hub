-- #1376 / ADR-0124: schedule the Drive membership auto-grant reconcile.
-- cron.schedule(name, ...) upserts by name → idempotent.
--
-- APPLY ORDER (mirror of #209 §dry-run gate): schedule the reconcile cron ONLY after the
-- reconcile-initiative-drive-access EF is deployed AND the Workspace admin has confirmed the SA
-- holds organizer/fileOrganizer on the parent folder (ADR-0094 G4.1) — otherwise every POST
-- returns 403 and the ledger fills with `failed`. The weekly missing-folder alert is pure SQL and
-- safe to schedule immediately.

-- Daily membership grant reconcile — 04:00 UTC (after the 03:00 discovery cron, before business hours).
-- Full sweep: reconciles every active initiative that has a workspace link (self-heals grants that a
-- reorg / folder move / new member broke). Idempotent: a member already in the ACL is a no-op grant.
SELECT cron.schedule(
  'membership-drive-reconcile-daily',
  '0 4 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/reconcile-initiative-drive-access',
    body := '{"source":"pg_cron"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    timeout_milliseconds := 150000
  );
  $cron$
);

-- Weekly missing-folder alert — Mondays 06:00 UTC. Per the #1376 ownership decision the cron does
-- NOT create folders (ownership must fall to a human via the OAuth EF); it notifies the GP, who runs
-- provision_initiative_drive. Pure SQL, no EF dependency.
SELECT cron.schedule(
  'drive-workspace-missing-alert-weekly',
  '0 6 * * 1',
  $cron$ SELECT public.notify_missing_drive_workspaces(); $cron$
);
