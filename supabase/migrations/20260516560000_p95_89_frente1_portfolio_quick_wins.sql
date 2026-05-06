-- p95 #89 Frente 1 (parcial SQL-only): portfolio quick wins per ADR-0019
-- ====================================================================
-- 3/4 light improvements proposed in #89 Frente 1 comment:
--   ✅ board_items.portfolio_kpi_refs col (this migration)
--   ✅ get_portfolio_items RPC (this migration)
--   ✅ stale portfolio items reminder cron (this migration)
--   ❌ MCP tool wrappers (4 tools) — split as #89.1 follow-up (requires nucleo-mcp redeploy)
--
-- Smoke validated p95 2026-05-05: 4/4 checks pass, cron RPC dry-run returns 0 stale today.

-- ============================================================
-- 1. board_items.portfolio_kpi_refs (light KPI link, overlap with #84)
-- ============================================================
ALTER TABLE public.board_items
  ADD COLUMN IF NOT EXISTS portfolio_kpi_refs text[] DEFAULT '{}';

CREATE INDEX IF NOT EXISTS ix_board_items_portfolio_kpi_refs
  ON public.board_items USING gin (portfolio_kpi_refs)
  WHERE is_portfolio_item = true;

COMMENT ON COLUMN public.board_items.portfolio_kpi_refs IS
  'p95 #89 ADR-0019: optional KPI keys this portfolio item contributes to (e.g., {webinars_count, member_growth}). Empty array for non-contributing items.';

-- ============================================================
-- 2. get_portfolio_items RPC (admin/sponsor read-only listing)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_portfolio_items(
  p_tribe_id integer DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_cycle_code text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  title text,
  status text,
  tribe_id integer,
  initiative_id uuid,
  baseline_date date,
  baseline_locked_at timestamptz,
  forecast_date date,
  due_date date,
  is_portfolio_item boolean,
  portfolio_kpi_refs text[],
  cycle_code text,
  updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (can_by_member(v_member_id, 'view_internal_analytics') OR can_by_member(v_member_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Access denied — requires view_internal_analytics or view_chapter_dashboards';
  END IF;

  RETURN QUERY
  SELECT bi.id, bi.title, bi.status,
         i.legacy_tribe_id AS tribe_id,
         pb.initiative_id,
         bi.baseline_date, bi.baseline_locked_at,
         bi.forecast_date, bi.due_date,
         bi.is_portfolio_item, bi.portfolio_kpi_refs,
         pb.cycle_code,
         bi.updated_at
  FROM board_items bi
  JOIN project_boards pb ON pb.id = bi.board_id
  LEFT JOIN initiatives i ON i.id = pb.initiative_id
  WHERE bi.is_portfolio_item = true
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    AND (p_status IS NULL OR bi.status = p_status)
    AND (p_cycle_code IS NULL OR pb.cycle_code = p_cycle_code)
  ORDER BY bi.due_date NULLS LAST, bi.updated_at DESC;
END $function$;

COMMENT ON FUNCTION public.get_portfolio_items(integer, text, text) IS
  'p95 #89 ADR-0019: list portfolio items (is_portfolio_item=true) with optional filters. Gated by can_by_member view_internal_analytics OR view_chapter_dashboards.';

-- ============================================================
-- 3. Stale portfolio items reminder cron (non-blocking, digest_weekly mode)
-- ============================================================
CREATE OR REPLACE FUNCTION public.detect_stale_portfolio_items_cron()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_inserted integer := 0;
  v_stale_threshold interval := '60 days';
BEGIN
  SELECT count(*) INTO v_count
  FROM board_items bi
  WHERE bi.is_portfolio_item = true
    AND bi.status NOT IN ('done', 'archived')
    AND bi.updated_at < now() - v_stale_threshold;

  IF v_count > 0 THEN
    INSERT INTO notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'portfolio_stale_reminder',
           format('%s portfolio item(s) precisam de update', v_count),
           format('%s itens marcados is_portfolio_item=true sem update há mais de 60 dias. Revise via /admin/portfolio.', v_count),
           'digest_weekly',
           now()
    FROM members m
    WHERE m.is_active = true
      AND m.operational_role IN ('manager', 'deputy_manager');

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'stale_count', v_count,
    'notifications_inserted', v_inserted,
    'threshold_days', 60,
    'run_at', now()
  );
END $function$;

REVOKE EXECUTE ON FUNCTION public.detect_stale_portfolio_items_cron() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.detect_stale_portfolio_items_cron() IS
  'p95 #89 ADR-0019: cron-only RPC. Detect portfolio items not updated for 60+ days, enqueue digest_weekly notification to GP+deputy. Smart-skip when 0 stale (per ADR-0022 W3 pattern).';

SELECT cron.schedule(
  'portfolio-stale-reminder-monthly',
  '0 14 1 * *',
  $$SELECT public.detect_stale_portfolio_items_cron();$$
);

NOTIFY pgrst, 'reload schema';
