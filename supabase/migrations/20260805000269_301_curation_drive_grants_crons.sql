-- #301 / ADR-0108: schedule the curation Drive grant/revoke drains + TTL safety-net.
-- cron.schedule(name, ...) upserts by name → idempotent. Bearer = vault service_role_key
-- (the token the EF verifies via isServiceRoleToken / current_caller_role — #738/#850).
--
-- NOTE (apply order): apply this migration ONLY after the EF manage-curation-drive-grant is
-- deployed — until then the drains would POST to a non-existent function (harmless 404, but no-op).
-- There is no synchronous human path for the eager auto-grant, so these drains are the PRIMARY
-- executor (≠ #209 where the MCP approve was primary and the drain was a safety net).

-- Grant drain — every 2 minutes. Picks pending_grant rows and POSTs each to the grant EF.
-- The EF only acts on status='pending_grant' (idempotent); a re-dispatch of an already-terminal
-- row is a graceful no-op.
SELECT cron.schedule(
  'curation-grant-drain',
  '*/2 * * * *',
  $cron$
  DO $drain$
  DECLARE r record;
  BEGIN
    FOR r IN
      SELECT id FROM public.drive_curation_grants
      WHERE status = 'pending_grant'
      ORDER BY requested_at
      LIMIT 50
    LOOP
      PERFORM net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/manage-curation-drive-grant',
        body := jsonb_build_object('grant_id', r.id, 'action', 'grant'),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        timeout_milliseconds := 30000
      );
    END LOOP;
  END
  $drain$;
  $cron$
);

-- Revoke drain — every 2 minutes. Picks pending_revoke rows and POSTs each to the EF (action=revoke).
SELECT cron.schedule(
  'curation-revoke-drain',
  '*/2 * * * *',
  $cron$
  DO $drain$
  DECLARE r record;
  BEGIN
    FOR r IN
      SELECT id FROM public.drive_curation_grants
      WHERE status = 'pending_revoke'
      ORDER BY updated_at
      LIMIT 50
    LOOP
      PERFORM net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/manage-curation-drive-grant',
        body := jsonb_build_object('grant_id', r.id, 'action', 'revoke'),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        timeout_milliseconds := 30000
      );
    END LOOP;
  END
  $drain$;
  $cron$
);

-- TTL safety-net — hourly at :23. Backstop for the FSM-exit trigger (item left curation but the
-- grant is still 'granted'), plus an absolute 30-day cap so temporary access never lingers
-- indefinitely on a stuck-in-curation item. Marks rows pending_revoke; the revoke drain executes.
-- Deliberately does NOT revoke active reviews on overdue-but-still-pending items (would strand a
-- mid-review curator) — only on leave-of-curation or the absolute cap.
SELECT cron.schedule(
  'curation-grant-ttl-expiry',
  '23 * * * *',
  $cron$
  UPDATE public.drive_curation_grants g
     SET status = 'pending_revoke', updated_at = now()
  FROM public.board_items bi
  WHERE g.board_item_id = bi.id
    AND g.status = 'granted'
    AND (bi.curation_status IS DISTINCT FROM 'curation_pending'
         OR g.granted_at < now() - interval '30 days');
  $cron$
);
