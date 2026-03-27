-- ============================================================================
-- GC-141: Zero-cost Backup to R2 + Card Auto-archival
-- RPCs + pg_cron jobs
-- ============================================================================

-- RPC: trigger_backup (superadmin manual)
DROP FUNCTION IF EXISTS trigger_backup();
CREATE OR REPLACE FUNCTION trigger_backup()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_member_id uuid; v_is_admin boolean;
BEGIN
  SELECT id, is_superadmin INTO v_member_id, v_is_admin FROM members WHERE auth_id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN RETURN jsonb_build_object('error', 'not_authorized'); END IF;
  INSERT INTO admin_audit_log (actor_id, action, target_type, metadata)
  VALUES (v_member_id, 'backup_triggered', 'system', jsonb_build_object('trigger', 'manual', 'timestamp', now()));
  RETURN jsonb_build_object('success', true, 'message', 'Backup triggered. Check R2 in ~2 minutes.');
END;
$$;
GRANT EXECUTE ON FUNCTION trigger_backup() TO authenticated;

-- RPC: auto_archive_done_cards
DROP FUNCTION IF EXISTS auto_archive_done_cards();
CREATE OR REPLACE FUNCTION auto_archive_done_cards()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_count int; v_system_id uuid;
BEGIN
  UPDATE board_items SET status = 'archived', updated_at = now()
  WHERE status = 'done' AND updated_at < now() - interval '30 days';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count > 0 THEN
    SELECT id INTO v_system_id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1;
    IF v_system_id IS NOT NULL THEN
      INSERT INTO admin_audit_log (actor_id, action, target_type, metadata)
      VALUES (v_system_id, 'auto_archive_cards', 'board_item', jsonb_build_object('count', v_count, 'threshold_days', 30));
    END IF;
  END IF;
  RETURN jsonb_build_object('archived', v_count);
END;
$$;

-- pg_cron: backup weekly Sunday 4:00 UTC
-- SELECT cron.schedule('backup-to-r2-weekly', '0 4 * * 0', ...);
-- Applied directly via execute_sql (pg_cron doesn't work in migrations)

-- pg_cron: auto-archive done cards Sunday 5:00 UTC
-- SELECT cron.schedule('auto-archive-done-cards', '0 5 * * 0', $$SELECT auto_archive_done_cards()$$);
-- Applied directly via execute_sql

NOTIFY pgrst, 'reload schema';
