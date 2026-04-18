-- ============================================================================
-- ADR-0015 Phase 1 — project_boards reader cutover (10th C3 table, part A)
--
-- Scope: 3 reader RPCs with clean JOIN tribes → initiatives swap. No auth
-- gate changes (those RPCs have no auth gate). Phase 1b (follow-up commit)
-- will cover the 4 additional RPCs that require combined V4 auth + JOIN
-- refactor: get_curation_dashboard, get_portfolio_timeline,
-- list_curation_pending_board_items, list_legacy_board_items_for_tribe.
--
-- Dual-write integrity: 9 both + 3 init-only + 2 neither (total 14).
-- 3 init-only rows are boards for non-tribe initiatives (CPMAI, Hub Comms,
-- Publicações) — these already lack legacy tribe_id. LEFT JOIN initiatives
-- via initiative_id handles all cases cleanly.
--
-- Changed RPCs (3):
--   1. list_project_boards          — LEFT JOIN initiatives (i.title AS tribe_name)
--   2. exec_portfolio_board_summary — CTE `boards` joins initiatives
--   3. get_portfolio_dashboard      — by_tribe + artifacts CTEs join initiatives
--
-- Output shape preserved identically.
--
-- ADR: ADR-0015 Phase 1
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. list_project_boards — canonical reader
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.list_project_boards(
  p_tribe_id integer DEFAULT NULL
)
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      pb.id,
      pb.board_name,
      pb.tribe_id,
      i.title AS tribe_name,  -- ADR-0015 Phase 1
      pb.source,
      pb.columns,
      pb.is_active,
      pb.board_scope,
      pb.domain_key,
      pb.cycle_scope,
      pb.created_at,
      (SELECT count(*) FROM public.board_items bi WHERE bi.board_id = pb.id) AS item_count
    FROM public.project_boards pb
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id  -- ADR-0015 Phase 1
    WHERE pb.is_active IS TRUE
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)  -- ADR-0015 Phase 1
    ORDER BY
      CASE pb.board_scope WHEN 'global' THEN 0 WHEN 'operational' THEN 1 ELSE 2 END,
      pb.created_at DESC
  ) r;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. exec_portfolio_board_summary — aggregate by lane
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.exec_portfolio_board_summary(
  p_include_inactive boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
  WITH boards AS (
    SELECT
      pb.id AS board_id,
      pb.board_name,
      pb.board_scope,
      COALESCE(pb.domain_key, 'tribe_general') AS domain_key,
      pb.tribe_id,
      i.title AS tribe_name  -- ADR-0015 Phase 1
    FROM public.project_boards pb
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id  -- ADR-0015 Phase 1
    WHERE (p_include_inactive OR pb.is_active = true)
  ),
  items AS (
    SELECT
      b.board_scope,
      b.domain_key,
      count(bi.id) AS total_cards,
      count(*) FILTER (WHERE bi.status = 'backlog') AS backlog,
      count(*) FILTER (WHERE bi.status = 'todo') AS todo,
      count(*) FILTER (WHERE bi.status = 'in_progress') AS in_progress,
      count(*) FILTER (WHERE bi.status = 'review') AS review,
      count(*) FILTER (WHERE bi.status = 'done') AS done,
      count(*) FILTER (WHERE bi.status = 'archived') AS archived,
      count(*) FILTER (WHERE bi.assignee_id IS NULL AND bi.status <> 'archived') AS orphan_cards,
      count(*) FILTER (WHERE bi.due_date::date < current_date AND bi.status NOT IN ('done', 'archived')) AS overdue_cards
    FROM boards b
    LEFT JOIN public.board_items bi ON bi.board_id = b.board_id
    GROUP BY b.board_scope, b.domain_key
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'by_lane', COALESCE(jsonb_agg(jsonb_build_object(
      'board_scope', i.board_scope,
      'domain_key', i.domain_key,
      'total_cards', i.total_cards,
      'backlog', i.backlog,
      'todo', i.todo,
      'in_progress', i.in_progress,
      'review', i.review,
      'done', i.done,
      'archived', i.archived,
      'orphan_cards', i.orphan_cards,
      'overdue_cards', i.overdue_cards
    ) ORDER BY i.board_scope, i.domain_key), '[]'::jsonb)
  )
  FROM items i;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. get_portfolio_dashboard — artifacts + by_tribe aggregates
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_portfolio_dashboard(
  p_cycle integer DEFAULT 3
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
  v_artifacts jsonb;
  v_summary jsonb;
  v_by_tribe jsonb;
  v_by_type jsonb;
  v_by_month jsonb;
BEGIN
  -- All portfolio items for this cycle
  SELECT jsonb_agg(row_to_json(sub.*) ORDER BY sub.tribe_id, sub.baseline_date NULLS LAST)
  INTO v_artifacts
  FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.baseline_date, bi.forecast_date, bi.actual_completion_date,
      CASE
        WHEN bi.baseline_date IS NOT NULL AND bi.forecast_date IS NOT NULL
        THEN (bi.forecast_date - bi.baseline_date)
        ELSE NULL
      END AS variance_days,
      CASE
        WHEN bi.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN bi.baseline_date IS NULL OR bi.forecast_date IS NULL THEN 'no_baseline'
        WHEN bi.forecast_date < CURRENT_DATE AND bi.actual_completion_date IS NULL THEN 'overdue'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END AS health,
      pb.tribe_id,
      i.title AS tribe_name,  -- ADR-0015 Phase 1
      m.name AS leader_name,
      bi.tags AS legacy_tags,
      (SELECT jsonb_agg(jsonb_build_object('name', tg.name, 'label', tg.label_pt, 'color', tg.color))
       FROM board_item_tag_assignments bita
       JOIN tags tg ON tg.id = bita.tag_id
       WHERE bita.board_item_id = bi.id
       AND tg.name NOT IN ('entregavel_lider', 'ciclo_3')) AS unified_tags,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) AS checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) AS checklist_done,
      CASE
        WHEN bi.baseline_date IS NOT NULL THEN 'Q' || EXTRACT(QUARTER FROM bi.baseline_date)::text
        ELSE 'TBD'
      END AS quarter,
      CASE
        WHEN bi.baseline_date IS NOT NULL THEN to_char(bi.baseline_date, 'YYYY-MM')
        ELSE 'TBD'
      END AS baseline_month
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id  -- ADR-0015 Phase 1
    LEFT JOIN members m ON m.id = bi.assignee_id
    WHERE bi.status <> 'archived'
      AND bi.cycle = p_cycle
      AND bi.is_portfolio_item = true
  ) sub;

  -- Summary KPIs
  SELECT jsonb_build_object(
    'total_artifacts', count(*),
    'completed', count(*) FILTER (WHERE sub.health = 'completed'),
    'on_track', count(*) FILTER (WHERE sub.health = 'on_track'),
    'at_risk', count(*) FILTER (WHERE sub.health = 'at_risk'),
    'delayed', count(*) FILTER (WHERE sub.health = 'delayed'),
    'no_baseline', count(*) FILTER (WHERE sub.health = 'no_baseline'),
    'avg_variance_days', ROUND(AVG(sub.variance_days) FILTER (WHERE sub.variance_days IS NOT NULL), 1),
    'checklist_total', SUM(sub.checklist_total),
    'checklist_done', SUM(sub.checklist_done),
    'pct_with_baseline', ROUND(count(*) FILTER (WHERE sub.baseline_date IS NOT NULL)::numeric / NULLIF(count(*), 0) * 100, 1)
  )
  INTO v_summary
  FROM (
    SELECT bi.baseline_date, bi.forecast_date, bi.actual_completion_date,
      CASE
        WHEN bi.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN bi.baseline_date IS NULL OR bi.forecast_date IS NULL THEN 'no_baseline'
        WHEN bi.forecast_date < CURRENT_DATE AND bi.actual_completion_date IS NULL THEN 'overdue'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END AS health,
      (bi.forecast_date - bi.baseline_date) AS variance_days,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) AS checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) AS checklist_done
    FROM board_items bi
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND bi.is_portfolio_item = true
  ) sub;

  -- By tribe (aggregated via initiatives, preserving tribe_id/tribe_name shape)
  SELECT jsonb_agg(jsonb_build_object(
    'tribe_id', sub.tribe_id,
    'tribe_name', sub.tribe_name,
    'leader', sub.leader_name,
    'total', sub.total,
    'completed', sub.completed,
    'on_track', sub.on_track,
    'at_risk', sub.at_risk,
    'delayed', sub.delayed,
    'no_baseline', sub.no_baseline,
    'next_deadline', sub.next_deadline,
    'checklist_pct', sub.checklist_pct
  ) ORDER BY sub.tribe_id)
  INTO v_by_tribe
  FROM (
    SELECT
      pb.tribe_id,
      i.title AS tribe_name,  -- ADR-0015 Phase 1
      m.name AS leader_name,
      count(*) AS total,
      count(*) FILTER (WHERE bi.actual_completion_date IS NOT NULL) AS completed,
      count(*) FILTER (WHERE bi.forecast_date IS NOT NULL AND bi.forecast_date <= bi.baseline_date AND bi.actual_completion_date IS NULL) AS on_track,
      count(*) FILTER (WHERE bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL AND (bi.forecast_date - bi.baseline_date) BETWEEN 1 AND 7 AND bi.actual_completion_date IS NULL) AS at_risk,
      count(*) FILTER (WHERE bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL AND (bi.forecast_date - bi.baseline_date) > 7 AND bi.actual_completion_date IS NULL) AS delayed,
      count(*) FILTER (WHERE bi.baseline_date IS NULL) AS no_baseline,
      MIN(bi.forecast_date) FILTER (WHERE bi.actual_completion_date IS NULL AND bi.forecast_date >= CURRENT_DATE) AS next_deadline,
      CASE WHEN SUM(chk.total) > 0
        THEN ROUND(SUM(chk.done)::numeric / SUM(chk.total) * 100, 1)
        ELSE 0
      END AS checklist_pct
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id  -- ADR-0015 Phase 1
    LEFT JOIN members m ON m.id = bi.assignee_id
    LEFT JOIN LATERAL (
      SELECT count(*) AS total, count(*) FILTER (WHERE is_completed) AS done
      FROM board_item_checklists WHERE board_item_id = bi.id
    ) chk ON true
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND bi.is_portfolio_item = true
    GROUP BY pb.tribe_id, i.title, m.name
  ) sub;

  -- By artifact type
  SELECT jsonb_agg(jsonb_build_object(
    'type', sub.tag_name,
    'label', sub.tag_label,
    'color', sub.tag_color,
    'count', sub.cnt
  ) ORDER BY sub.cnt DESC)
  INTO v_by_type
  FROM (
    SELECT tg.name AS tag_name, tg.label_pt AS tag_label, tg.color AS tag_color, count(DISTINCT bi.id) AS cnt
    FROM board_items bi
    JOIN board_item_tag_assignments bita ON bita.board_item_id = bi.id
    JOIN tags tg ON tg.id = bita.tag_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND tg.name NOT IN ('entregavel_lider', 'ciclo_3')
      AND tg.tier = 'system'
      AND bi.is_portfolio_item = true
    GROUP BY tg.name, tg.label_pt, tg.color
  ) sub;

  -- By month
  SELECT jsonb_agg(jsonb_build_object(
    'month', sub.month,
    'count', sub.cnt,
    'tribes', sub.tribes
  ) ORDER BY sub.month)
  INTO v_by_month
  FROM (
    SELECT
      to_char(bi.baseline_date, 'YYYY-MM') AS month,
      count(*) AS cnt,
      jsonb_agg(DISTINCT pb.tribe_id) AS tribes
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND bi.baseline_date IS NOT NULL
      AND bi.is_portfolio_item = true
    GROUP BY to_char(bi.baseline_date, 'YYYY-MM')
  ) sub;

  v_result := jsonb_build_object(
    'cycle', p_cycle,
    'generated_at', now(),
    'summary', COALESCE(v_summary, '{}'::jsonb),
    'artifacts', COALESCE(v_artifacts, '[]'::jsonb),
    'by_tribe', COALESCE(v_by_tribe, '[]'::jsonb),
    'by_type', COALESCE(v_by_type, '[]'::jsonb),
    'by_month', COALESCE(v_by_month, '[]'::jsonb)
  );

  RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
