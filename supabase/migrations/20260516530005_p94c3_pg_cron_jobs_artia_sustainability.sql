-- p94 Phase C.3: schedule 2 new pg_cron jobs for Artia sustainability
-- Existing: sync-artia-weekly (Sunday 05:30 UTC) — KPIs (13 total)
-- New: sync-artia-monitoring-daily (06:00 UTC) — Project.lastInformations + atas tribos
-- New: sync-artia-status-report-monthly (1st day 07:00 UTC) — status report + 11 risks
-- Plus: AFTER UPDATE OF current_ratified_at trigger on governance_documents

DO $$
DECLARE
  existing_id INT;
BEGIN
  SELECT jobid INTO existing_id FROM cron.job WHERE jobname = 'sync-artia-monitoring-daily';
  IF existing_id IS NOT NULL THEN
    PERFORM cron.unschedule(existing_id);
  END IF;
END $$;

SELECT cron.schedule(
  'sync-artia-monitoring-daily',
  '0 6 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/sync-artia?mode=cron-daily',
    body := '{"source":"pg_cron","mode":"cron-daily"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    timeout_milliseconds := 60000
  );
  $cron$
);

DO $$
DECLARE
  existing_id INT;
BEGIN
  SELECT jobid INTO existing_id FROM cron.job WHERE jobname = 'sync-artia-status-report-monthly';
  IF existing_id IS NOT NULL THEN
    PERFORM cron.unschedule(existing_id);
  END IF;
END $$;

SELECT cron.schedule(
  'sync-artia-status-report-monthly',
  '0 7 1 * *',
  $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/sync-artia?mode=cron-monthly',
    body := '{"source":"pg_cron","mode":"cron-monthly"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    timeout_milliseconds := 120000
  );
  $cron$
);

CREATE OR REPLACE FUNCTION trg_artia_sync_govdoc_ratified()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_service_key TEXT;
BEGIN
  IF (OLD.current_ratified_at IS DISTINCT FROM NEW.current_ratified_at) THEN
    BEGIN
      SELECT decrypted_secret INTO v_service_key
      FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

      PERFORM net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/sync-artia?mode=cron-daily',
        body := jsonb_build_object('source', 'trigger_govdoc', 'doc_id', NEW.id, 'event', 'ratified'),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_key
        ),
        timeout_milliseconds := 30000
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Artia sync trigger failed: %', SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_artia_sync_on_govdoc_ratified ON governance_documents;
CREATE TRIGGER trg_artia_sync_on_govdoc_ratified
  AFTER UPDATE OF current_ratified_at ON governance_documents
  FOR EACH ROW EXECUTE FUNCTION trg_artia_sync_govdoc_ratified();

COMMENT ON FUNCTION trg_artia_sync_govdoc_ratified IS 'Phase C.3 event-driven: when governance_documents.current_ratified_at changes (ratification event), enqueue Artia cron-daily refresh to update Project.lastInformations + relevant folder activities. Async via net.http_post (non-blocking).';
