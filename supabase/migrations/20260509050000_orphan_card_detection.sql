-- Migration: #91 G7 — orphan card detection for offboarded members
-- Issue: admin_offboard_member has optional p_reassign_to. When admin forgets,
--        board_items with assignee=offboarded member remain active without alert.
-- Design: RPC detect_orphan_assignees_from_offboards(uuid?) that scans inactive members'
--         cards (status NOT IN done/archived) and emits board_taxonomy_alerts
--         (alert_code='orphan_assignee_offboard'). Idempotent: skips items that
--         already have unresolved alerts.
-- Integration:
--   1. Extend notify_offboard_cascade trigger: invoke per-member at offboard time
--   2. pg_cron daily catch-up (05:30 UTC = 02:30 BRT): wide scan
-- Rollback:
--   SELECT cron.unschedule('orphan-card-detection-daily');
--   DROP FUNCTION public.detect_orphan_assignees_from_offboards(uuid);

-- ============================================================================
-- 1. RPC: orphan card detection (idempotent, single-member or wide-scan)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.detect_orphan_assignees_from_offboards(
  p_member_id uuid DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH offenders AS (
    SELECT bi.id AS item_id, bi.board_id, bi.assignee_id, bi.title,
           m.id AS member_id, m.name AS member_name, m.member_status
    FROM public.board_items bi
    JOIN public.members m ON m.id = bi.assignee_id
    WHERE bi.assignee_id IS NOT NULL
      AND bi.status NOT IN ('archived','done')
      AND m.is_active = false
      AND m.member_status IN ('alumni','observer','inactive')
      AND (p_member_id IS NULL OR bi.assignee_id = p_member_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.board_taxonomy_alerts a
        WHERE a.alert_code = 'orphan_assignee_offboard'
          AND (a.payload->>'board_item_id') = bi.id::text
          AND a.resolved_at IS NULL
      )
  )
  INSERT INTO public.board_taxonomy_alerts (alert_code, severity, board_id, payload)
  SELECT 'orphan_assignee_offboard', 'warning', o.board_id,
         jsonb_build_object(
           'board_item_id', o.item_id,
           'item_title', o.title,
           'assignee_id', o.assignee_id,
           'assignee_name', o.member_name,
           'assignee_status', o.member_status,
           'detected_at', now()
         )
  FROM offenders o;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.detect_orphan_assignees_from_offboards(uuid) IS
  '#91 G7 — detects board_items assigned to inactive/alumni/observer members with open status; emits board_taxonomy_alerts. Idempotent (skips items with unresolved alerts). NULL=wide scan, uuid=single-member.';

REVOKE ALL ON FUNCTION public.detect_orphan_assignees_from_offboards(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.detect_orphan_assignees_from_offboards(uuid) TO authenticated, service_role;

-- ============================================================================
-- 2. Extend notify_offboard_cascade: after notifications, also scan for orphans
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_offboard_cascade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_actor         uuid;
  v_title         text;
  v_body          text;
  v_link          text;
  v_stakeholders  uuid[];
BEGIN
  IF NEW.member_status NOT IN ('alumni','observer','inactive') THEN
    RETURN NEW;
  END IF;

  v_actor := NEW.offboarded_by;

  v_title := CASE NEW.member_status
    WHEN 'alumni'   THEN COALESCE(NEW.name,'Membro') || ' saiu da equipe (alumni)'
    WHEN 'observer' THEN COALESCE(NEW.name,'Membro') || ' passou a observador(a)'
    WHEN 'inactive' THEN COALESCE(NEW.name,'Membro') || ' foi desativado(a)'
  END;
  v_body := NULLIF(TRIM(COALESCE(NEW.status_change_reason,'')), '');
  v_link := '/admin/members/' || NEW.id::text;

  SELECT array_agg(DISTINCT m.id)
  INTO v_stakeholders
  FROM public.members m
  WHERE m.is_active = true
    AND m.id <> NEW.id
    AND m.id IS DISTINCT FROM v_actor
    AND (
      m.operational_role IN ('manager','deputy_manager')
      OR (
        NEW.tribe_id IS NOT NULL
        AND m.tribe_id = NEW.tribe_id
        AND m.operational_role IN ('tribe_leader','co_leader')
      )
    );

  IF v_stakeholders IS NOT NULL AND cardinality(v_stakeholders) > 0 THEN
    INSERT INTO public.notifications
      (recipient_id, type, title, body, link, source_type, source_id, actor_id)
    SELECT rid, 'member_offboarded', v_title, v_body, v_link, 'member', NEW.id, v_actor
    FROM unnest(v_stakeholders) AS rid;
  END IF;

  -- #91 G7: scan this member's orphaned cards after status transition
  PERFORM public.detect_orphan_assignees_from_offboards(NEW.id);

  RETURN NEW;
END;
$$;

-- ============================================================================
-- 3. pg_cron: daily catch-up for manual DB edits or missed triggers
-- ============================================================================
-- 09:30 UTC = 06:30 BRT — quiet slot after nightly syncs, before business hours
SELECT cron.schedule(
  'orphan-card-detection-daily',
  '30 9 * * *',
  $job$SELECT public.detect_orphan_assignees_from_offboards()$job$
);
