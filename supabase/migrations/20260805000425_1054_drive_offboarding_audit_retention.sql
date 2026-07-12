-- ============================================================
-- #1054 — LGPD retention for drive_offboarding_audit (ADR-0014 extension)
--
-- Pre-GO-LIVE follow-up of #1039 (drive auto-revoke kill-switch). Council
-- Tier-3 2026-07-02 / legal COND-3 gate the flip of
-- platform_settings.drive_auto_revoke_enabled on this retention rule existing.
--
-- Adds a 9th category to public.purge_expired_logs:
--   drive_offboarding_audit: 5y (1825d) anonymize of permission_email
--   (email of the ex-member whose Drive access was revoked) on TERMINAL
--   rows (status in revoked/failed/already_absent/skipped). The email is
--   replaced by 'sha256:' || SHA-256(email || fixed_salt) in hex — a stable
--   pseudonym that preserves statistical uniqueness for the compliance trail
--   (evidence that offboarding ran) while removing the plaintext PII.
--   drive_file_id / drive_file_name / permission_role stay (not ex-member PII).
--
-- Idempotent: the 'sha256:' sentinel prefix is excluded from the WHERE, so a
-- re-run never re-hashes an already-anonymized value.
--
-- D1 (owner 2026-07-11): hash + fixed salt constant (not NULL — the column is
--   citext NOT NULL, and the trail keeps evidentiary value). Threat model:
--   casual re-identification after 5y is acceptable for a fixed documented salt.
-- ROPA: docs/legal/RoPA_1054_DRIVE_OFFBOARDING.md (D2, owner 2026-07-11).
--
-- Reuses the existing cron 'log-retention-monthly' (pg_cron jobid 22) — NO new
-- cron. Signature unchanged (CREATE OR REPLACE preserves grants); base is the
-- LIVE body (pg_get_functiondef), only the drive_offboarding_audit block +
-- retention constants are added.
--
-- Rollback: re-apply 20260427010000_log_retention_policy.sql (prior body).
-- ============================================================

CREATE OR REPLACE FUNCTION public.purge_expired_logs(p_dry_run boolean DEFAULT true, p_limit integer DEFAULT 10000)
 RETURNS TABLE(table_name text, purge_mode text, rows_affected bigint, oldest_row_kept timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  -- Retention constants (days). Change here to adjust policy.
  v_mcp_retention_days          constant integer := 90;
  v_email_webhook_retention_days constant integer := 180;
  v_broadcast_retention_days    constant integer := 730;
  v_data_anomaly_resolved_days  constant integer := 180;
  v_comms_ingestion_retention_days constant integer := 90;
  v_knowledge_ingestion_retention_days constant integer := 90;
  v_pii_access_anonymize_days   constant integer := 1825;
  v_pii_access_drop_days        constant integer := 2190;
  v_admin_audit_archive_days    constant integer := 1825;
  v_admin_audit_drop_days       constant integer := 2555;
  -- #1054: drive_offboarding_audit permission_email anonymization (5y)
  v_drive_audit_anonymize_days  constant integer := 1825;
  v_drive_audit_salt            constant text := 'nucleoia-drive-offboarding-audit-anon-v1';
  v_count bigint;
  v_oldest timestamptz;
BEGIN
  -- Auth: GRANT-based only. Function EXECUTE is granted to service_role
  -- exclusively (see GRANT at migration tail). Callers without the grant
  -- receive Postgres-level 'permission denied for function' error directly.
  -- This is an infrastructure RPC (log retention) — ADR-0011 can_by_member
  -- pattern applies to domain RPCs with user-level authority derivation.

  -- mcp_usage_log (90d drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.mcp_usage_log
      WHERE created_at < now() - (v_mcp_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.mcp_usage_log WHERE id IN (
          SELECT id FROM public.mcp_usage_log
          WHERE created_at < now() - (v_mcp_retention_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.mcp_usage_log;
    RETURN QUERY SELECT 'mcp_usage_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'mcp_usage_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'mcp_usage_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- comms_metrics_ingestion_log (90d drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.comms_metrics_ingestion_log
      WHERE created_at < now() - (v_comms_ingestion_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.comms_metrics_ingestion_log WHERE id IN (
          SELECT id FROM public.comms_metrics_ingestion_log
          WHERE created_at < now() - (v_comms_ingestion_retention_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.comms_metrics_ingestion_log;
    RETURN QUERY SELECT 'comms_metrics_ingestion_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'comms_metrics_ingestion_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'comms_metrics_ingestion_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- knowledge_insights_ingestion_log (90d drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.knowledge_insights_ingestion_log
      WHERE created_at < now() - (v_knowledge_ingestion_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.knowledge_insights_ingestion_log WHERE id IN (
          SELECT id FROM public.knowledge_insights_ingestion_log
          WHERE created_at < now() - (v_knowledge_ingestion_retention_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.knowledge_insights_ingestion_log;
    RETURN QUERY SELECT 'knowledge_insights_ingestion_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'knowledge_insights_ingestion_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'knowledge_insights_ingestion_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- data_anomaly_log (180d after resolved)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.data_anomaly_log
      WHERE fixed_at IS NOT NULL
        AND fixed_at < now() - (v_data_anomaly_resolved_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.data_anomaly_log WHERE id IN (
          SELECT id FROM public.data_anomaly_log
          WHERE fixed_at IS NOT NULL
            AND fixed_at < now() - (v_data_anomaly_resolved_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(detected_at) INTO v_oldest FROM public.data_anomaly_log;
    RETURN QUERY SELECT 'data_anomaly_log'::text, 'drop_resolved'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'data_anomaly_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'data_anomaly_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- email_webhook_events (180d drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.email_webhook_events
      WHERE created_at < now() - (v_email_webhook_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.email_webhook_events WHERE id IN (
          SELECT id FROM public.email_webhook_events
          WHERE created_at < now() - (v_email_webhook_retention_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.email_webhook_events;
    RETURN QUERY SELECT 'email_webhook_events'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'email_webhook_events purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'email_webhook_events'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- broadcast_log (2y drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.broadcast_log
      WHERE sent_at < now() - (v_broadcast_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.broadcast_log WHERE id IN (
          SELECT id FROM public.broadcast_log
          WHERE sent_at < now() - (v_broadcast_retention_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(sent_at) INTO v_oldest FROM public.broadcast_log;
    RETURN QUERY SELECT 'broadcast_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'broadcast_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'broadcast_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- pii_access_log: 5y anonymize
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.pii_access_log
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
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM upd;
    END IF;
    SELECT min(accessed_at) INTO v_oldest FROM public.pii_access_log;
    RETURN QUERY SELECT 'pii_access_log'::text, 'anonymize'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'pii_access_log anonymize failed: %', SQLERRM;
    RETURN QUERY SELECT 'pii_access_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- pii_access_log: 6y drop
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.pii_access_log
      WHERE accessed_at < now() - (v_pii_access_drop_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.pii_access_log WHERE id IN (
          SELECT id FROM public.pii_access_log
          WHERE accessed_at < now() - (v_pii_access_drop_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    RETURN QUERY SELECT 'pii_access_log'::text, 'drop'::text, v_count, NULL::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'pii_access_log drop failed: %', SQLERRM;
    RETURN QUERY SELECT 'pii_access_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- admin_audit_log: 5y archive
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.admin_audit_log
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
        DELETE FROM public.admin_audit_log WHERE id IN (SELECT id FROM moved)
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.admin_audit_log;
    RETURN QUERY SELECT 'admin_audit_log'::text, 'archive'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_audit_log archive failed: %', SQLERRM;
    RETURN QUERY SELECT 'admin_audit_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- z_archive.admin_audit_log: 7y drop
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM z_archive.admin_audit_log
      WHERE created_at < now() - (v_admin_audit_drop_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM z_archive.admin_audit_log WHERE id IN (
          SELECT id FROM z_archive.admin_audit_log
          WHERE created_at < now() - (v_admin_audit_drop_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM z_archive.admin_audit_log;
    RETURN QUERY SELECT 'z_archive.admin_audit_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'z_archive.admin_audit_log drop failed: %', SQLERRM;
    RETURN QUERY SELECT 'z_archive.admin_audit_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- drive_offboarding_audit: 5y anonymize permission_email (#1054)
  -- Terminal rows only. SHA-256 + fixed salt (extensions.digest), hex,
  -- 'sha256:' sentinel prefix -> idempotent (re-run skips already-anonymized).
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.drive_offboarding_audit
      WHERE created_at < now() - (v_drive_audit_anonymize_days || ' days')::interval
        AND status IN ('revoked','failed','already_absent','skipped')
        AND permission_email NOT LIKE 'sha256:%';
    ELSE
      WITH upd AS (
        UPDATE public.drive_offboarding_audit
        SET permission_email = 'sha256:' || encode(extensions.digest(permission_email::text || v_drive_audit_salt, 'sha256'), 'hex')
        WHERE id IN (
          SELECT id FROM public.drive_offboarding_audit
          WHERE created_at < now() - (v_drive_audit_anonymize_days || ' days')::interval
            AND status IN ('revoked','failed','already_absent','skipped')
            AND permission_email NOT LIKE 'sha256:%'
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM upd;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.drive_offboarding_audit;
    RETURN QUERY SELECT 'drive_offboarding_audit'::text, 'anonymize'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'drive_offboarding_audit anonymize failed: %', SQLERRM;
    RETURN QUERY SELECT 'drive_offboarding_audit'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- Meta-log
  IF NOT p_dry_run THEN
    BEGIN
      INSERT INTO public.admin_audit_log (
        actor_id, action, target_type, target_id, changes, metadata
      ) VALUES (
        NULL, 'platform.log_retention_run', 'system', NULL, NULL,
        jsonb_build_object('executed_at', now(), 'p_limit', p_limit, 'source', 'purge_expired_logs')
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'meta-log insert failed: %', SQLERRM;
    END;
  END IF;
END;
$function$;

NOTIFY pgrst, 'reload schema';
