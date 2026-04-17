-- ============================================================
-- Log Retention Policy (ADR-0014 implementation)
--
-- Implements per-category archive/purge windows defined in ADR-0014:
--   Cat A admin_audit_log: 5y ativo → z_archive; 7y total → drop da archive
--   Cat B *_lifecycle_events: indefinido (não tocado por este job)
--   Cat C mcp_usage_log / *_ingestion_log / data_anomaly_log: 90-180d drop
--   Cat D pii_access_log: 5y → anonymize accessor; 6y → drop
--   Cat E email_webhook_events: 180d; broadcast_log: 2y drop
--
-- Mecanismo: RPC public.purge_expired_logs(p_dry_run, p_limit) + pg_cron
-- mensal 'log-retention-monthly' (0 4 1 * * — dia 1º, 04:00 UTC, após
-- anonymization jobs).
--
-- Auth: SECURITY DEFINER + system context gate (postgres / supabase_admin
-- / service_role). Dry-run disponível via service_role para preview manual.
--
-- Idempotent: safe to re-apply (IF NOT EXISTS + CREATE OR REPLACE +
-- unschedule before schedule).
--
-- Rollback:
--   DROP FUNCTION IF EXISTS public.purge_expired_logs(boolean, integer);
--   SELECT cron.unschedule('log-retention-monthly');
--   DROP TABLE IF EXISTS z_archive.admin_audit_log;
-- ============================================================

-- 1. Archive schema + table for admin_audit_log (Cat A)
-- ------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS z_archive;

CREATE TABLE IF NOT EXISTS z_archive.admin_audit_log (
  id uuid NOT NULL,
  actor_id uuid,
  action text NOT NULL,
  target_type text NOT NULL,
  target_id uuid,
  changes jsonb,
  metadata jsonb,
  created_at timestamptz,
  _archived_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT admin_audit_log_archive_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS admin_audit_log_archive_created_at_idx
  ON z_archive.admin_audit_log (created_at);

COMMENT ON TABLE z_archive.admin_audit_log IS
  'Archive for admin_audit_log rows older than 5 years (ADR-0014). Rows with created_at < now() - 7y are permanently dropped by purge_expired_logs.';

-- 2. Main RPC: purge_expired_logs
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_expired_logs(
  p_dry_run boolean DEFAULT true,
  p_limit integer DEFAULT 10000
)
RETURNS TABLE (
  table_name text,
  purge_mode text,
  rows_affected bigint,
  oldest_row_kept timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  -- Retention constants (days). Change here to adjust policy.
  v_mcp_retention_days          constant integer := 90;
  v_email_webhook_retention_days constant integer := 180;
  v_broadcast_retention_days    constant integer := 730;   -- 2 years
  v_data_anomaly_resolved_days  constant integer := 180;
  v_comms_ingestion_retention_days constant integer := 90;
  v_knowledge_ingestion_retention_days constant integer := 90;
  v_pii_access_anonymize_days   constant integer := 1825;  -- 5 years
  v_pii_access_drop_days        constant integer := 2190;  -- 6 years
  v_admin_audit_archive_days    constant integer := 1825;  -- 5 years
  v_admin_audit_drop_days       constant integer := 2555;  -- 7 years

  v_count bigint;
  v_oldest timestamptz;
BEGIN
  -- Auth: GRANT-based only. Function EXECUTE is granted to service_role
  -- exclusively (see GRANT at migration tail). Callers without the grant
  -- receive Postgres-level 'permission denied for function' error directly.
  -- This is an infrastructure RPC (log retention) — ADR-0011 can_by_member
  -- pattern applies to domain RPCs with user-level authority derivation.

  -- ========================================================
  -- Category C — mcp_usage_log (90d drop)
  -- ========================================================
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count
      FROM public.mcp_usage_log
      WHERE created_at < now() - (v_mcp_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.mcp_usage_log
        WHERE id IN (
          SELECT id FROM public.mcp_usage_log
          WHERE created_at < now() - (v_mcp_retention_days || ' days')::interval
          LIMIT p_limit
        )
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.mcp_usage_log;
    RETURN QUERY SELECT 'mcp_usage_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'mcp_usage_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'mcp_usage_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- ========================================================
  -- Category C — comms_metrics_ingestion_log (90d drop)
  -- ========================================================
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count
      FROM public.comms_metrics_ingestion_log
      WHERE created_at < now() - (v_comms_ingestion_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.comms_metrics_ingestion_log
        WHERE id IN (
          SELECT id FROM public.comms_metrics_ingestion_log
          WHERE created_at < now() - (v_comms_ingestion_retention_days || ' days')::interval
          LIMIT p_limit
        )
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.comms_metrics_ingestion_log;
    RETURN QUERY SELECT 'comms_metrics_ingestion_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'comms_metrics_ingestion_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'comms_metrics_ingestion_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- ========================================================
  -- Category C — knowledge_insights_ingestion_log (90d drop)
  -- ========================================================
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count
      FROM public.knowledge_insights_ingestion_log
      WHERE created_at < now() - (v_knowledge_ingestion_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.knowledge_insights_ingestion_log
        WHERE id IN (
          SELECT id FROM public.knowledge_insights_ingestion_log
          WHERE created_at < now() - (v_knowledge_ingestion_retention_days || ' days')::interval
          LIMIT p_limit
        )
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.knowledge_insights_ingestion_log;
    RETURN QUERY SELECT 'knowledge_insights_ingestion_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'knowledge_insights_ingestion_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'knowledge_insights_ingestion_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- ========================================================
  -- Category C — data_anomaly_log (180d after resolved; keep unresolved)
  -- ========================================================
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count
      FROM public.data_anomaly_log
      WHERE fixed_at IS NOT NULL
        AND fixed_at < now() - (v_data_anomaly_resolved_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.data_anomaly_log
        WHERE id IN (
          SELECT id FROM public.data_anomaly_log
          WHERE fixed_at IS NOT NULL
            AND fixed_at < now() - (v_data_anomaly_resolved_days || ' days')::interval
          LIMIT p_limit
        )
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(detected_at) INTO v_oldest FROM public.data_anomaly_log;
    RETURN QUERY SELECT 'data_anomaly_log'::text, 'drop_resolved'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'data_anomaly_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'data_anomaly_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- ========================================================
  -- Category E — email_webhook_events (180d drop; contains recipient_email PII)
  -- ========================================================
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count
      FROM public.email_webhook_events
      WHERE created_at < now() - (v_email_webhook_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.email_webhook_events
        WHERE id IN (
          SELECT id FROM public.email_webhook_events
          WHERE created_at < now() - (v_email_webhook_retention_days || ' days')::interval
          LIMIT p_limit
        )
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.email_webhook_events;
    RETURN QUERY SELECT 'email_webhook_events'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'email_webhook_events purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'email_webhook_events'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- ========================================================
  -- Category E — broadcast_log (2y drop; body contains full email/whatsapp text)
  -- ========================================================
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count
      FROM public.broadcast_log
      WHERE sent_at < now() - (v_broadcast_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.broadcast_log
        WHERE id IN (
          SELECT id FROM public.broadcast_log
          WHERE sent_at < now() - (v_broadcast_retention_days || ' days')::interval
          LIMIT p_limit
        )
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(sent_at) INTO v_oldest FROM public.broadcast_log;
    RETURN QUERY SELECT 'broadcast_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'broadcast_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'broadcast_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- ========================================================
  -- Category D — pii_access_log: 5y → anonymize accessor_id + reason
  -- ========================================================
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count
      FROM public.pii_access_log
      WHERE accessed_at < now() - (v_pii_access_anonymize_days || ' days')::interval
        AND accessed_at >= now() - (v_pii_access_drop_days || ' days')::interval
        AND accessor_id IS NOT NULL;
    ELSE
      WITH upd AS (
        UPDATE public.pii_access_log
        SET accessor_id = NULL,
            reason = CASE WHEN reason IS NOT NULL THEN 'anonymized' ELSE reason END
        WHERE id IN (
          SELECT id FROM public.pii_access_log
          WHERE accessed_at < now() - (v_pii_access_anonymize_days || ' days')::interval
            AND accessed_at >= now() - (v_pii_access_drop_days || ' days')::interval
            AND accessor_id IS NOT NULL
          LIMIT p_limit
        )
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM upd;
    END IF;
    SELECT min(accessed_at) INTO v_oldest FROM public.pii_access_log;
    RETURN QUERY SELECT 'pii_access_log'::text, 'anonymize'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'pii_access_log anonymize failed: %', SQLERRM;
    RETURN QUERY SELECT 'pii_access_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- ========================================================
  -- Category D — pii_access_log: 6y → drop
  -- ========================================================
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count
      FROM public.pii_access_log
      WHERE accessed_at < now() - (v_pii_access_drop_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.pii_access_log
        WHERE id IN (
          SELECT id FROM public.pii_access_log
          WHERE accessed_at < now() - (v_pii_access_drop_days || ' days')::interval
          LIMIT p_limit
        )
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    RETURN QUERY SELECT 'pii_access_log'::text, 'drop'::text, v_count, NULL::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'pii_access_log drop failed: %', SQLERRM;
    RETURN QUERY SELECT 'pii_access_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- ========================================================
  -- Category A — admin_audit_log: 5y → archive to z_archive
  -- ========================================================
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count
      FROM public.admin_audit_log
      WHERE created_at < now() - (v_admin_audit_archive_days || ' days')::interval;
    ELSE
      WITH moved AS (
        INSERT INTO z_archive.admin_audit_log
          (id, actor_id, action, target_type, target_id, changes, metadata, created_at)
        SELECT id, actor_id, action, target_type, target_id, changes, metadata, created_at
        FROM public.admin_audit_log
        WHERE id IN (
          SELECT id FROM public.admin_audit_log
          WHERE created_at < now() - (v_admin_audit_archive_days || ' days')::interval
          LIMIT p_limit
        )
        ON CONFLICT (id) DO NOTHING
        RETURNING id
      ), del AS (
        DELETE FROM public.admin_audit_log
        WHERE id IN (SELECT id FROM moved)
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.admin_audit_log;
    RETURN QUERY SELECT 'admin_audit_log'::text, 'archive'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_audit_log archive failed: %', SQLERRM;
    RETURN QUERY SELECT 'admin_audit_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- ========================================================
  -- Category A — admin_audit_log archive: 7y → permanent drop
  -- ========================================================
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count
      FROM z_archive.admin_audit_log
      WHERE created_at < now() - (v_admin_audit_drop_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM z_archive.admin_audit_log
        WHERE id IN (
          SELECT id FROM z_archive.admin_audit_log
          WHERE created_at < now() - (v_admin_audit_drop_days || ' days')::interval
          LIMIT p_limit
        )
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM z_archive.admin_audit_log;
    RETURN QUERY SELECT 'z_archive.admin_audit_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'z_archive.admin_audit_log drop failed: %', SQLERRM;
    RETURN QUERY SELECT 'z_archive.admin_audit_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- ========================================================
  -- Meta-log: record the run itself in admin_audit_log
  -- ========================================================
  IF NOT p_dry_run THEN
    BEGIN
      INSERT INTO public.admin_audit_log (
        actor_id, action, target_type, target_id, changes, metadata
      ) VALUES (
        NULL,
        'platform.log_retention_run',
        'system',
        NULL,
        NULL,
        jsonb_build_object(
          'executed_at', now(),
          'p_limit', p_limit,
          'source', 'purge_expired_logs'
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'meta-log insert failed: %', SQLERRM;
    END;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.purge_expired_logs(boolean, integer) IS
  'ADR-0014: Per-category log retention. p_dry_run=true for preview (read-only). System context only (postgres/supabase_admin/service_role). Returns row per table with purge_mode in (drop|archive|anonymize|drop_resolved|error).';

-- 3. GRANT: no public/authenticated execute (system only)
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION public.purge_expired_logs(boolean, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_expired_logs(boolean, integer) FROM anon;
REVOKE ALL ON FUNCTION public.purge_expired_logs(boolean, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_logs(boolean, integer) TO service_role;

-- 4. pg_cron schedule (idempotent: unschedule + schedule)
-- ------------------------------------------------------------
DO $$
BEGIN
  PERFORM cron.unschedule('log-retention-monthly');
EXCEPTION WHEN OTHERS THEN
  NULL;  -- first run: job doesn't exist yet
END $$;

SELECT cron.schedule(
  'log-retention-monthly',
  '0 4 1 * *',   -- 1st of month, 04:00 UTC (after 03:30/03:45 anonymize jobs)
  $cron$
  SELECT public.purge_expired_logs(p_dry_run := false, p_limit := 50000);
  $cron$
);

-- 5. Register migration in schema_migrations (MCP apply_migration workaround)
-- ------------------------------------------------------------
INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
VALUES (
  '20260427010000',
  'log_retention_policy',
  ARRAY['-- see file for full content']
)
ON CONFLICT (version) DO NOTHING;

NOTIFY pgrst, 'reload schema';
