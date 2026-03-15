-- W142: GP Portfolio Dashboard RPC
-- Aggregates all entregavel_lider artifacts across tribes with health, variance, and dimensional breakdowns.

CREATE OR REPLACE FUNCTION public.get_portfolio_dashboard(
  p_cycle integer DEFAULT 3
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
  v_artifacts jsonb;
  v_summary jsonb;
  v_by_tribe jsonb;
  v_by_type jsonb;
  v_by_month jsonb;
BEGIN
  -- All artifacts tagged entregavel_lider for this cycle
  SELECT jsonb_agg(row_to_json(sub.*) ORDER BY sub.tribe_id, sub.baseline_date NULLS LAST)
  INTO v_artifacts
  FROM (
    SELECT
      bi.id,
      bi.title,
      bi.description,
      bi.status,
      bi.baseline_date,
      bi.forecast_date,
      bi.actual_completion_date,
      CASE
        WHEN bi.baseline_date IS NOT NULL AND bi.forecast_date IS NOT NULL
        THEN (bi.forecast_date - bi.baseline_date)
        ELSE NULL
      END as variance_days,
      CASE
        WHEN bi.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN bi.baseline_date IS NULL OR bi.forecast_date IS NULL THEN 'no_baseline'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END as health,
      pb.tribe_id,
      t.name as tribe_name,
      m.name as leader_name,
      bi.tags as legacy_tags,
      (SELECT jsonb_agg(jsonb_build_object('name', tg.name, 'label', tg.label_pt, 'color', tg.color))
       FROM board_item_tag_assignments bita
       JOIN tags tg ON tg.id = bita.tag_id
       WHERE bita.board_item_id = bi.id
       AND tg.name NOT IN ('entregavel_lider', 'ciclo_3')) as unified_tags,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) as checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) as checklist_done,
      CASE
        WHEN bi.baseline_date IS NOT NULL THEN 'Q' || EXTRACT(QUARTER FROM bi.baseline_date)::text
        ELSE 'TBD'
      END as quarter,
      CASE
        WHEN bi.baseline_date IS NOT NULL THEN to_char(bi.baseline_date, 'YYYY-MM')
        ELSE 'TBD'
      END as baseline_month
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN tribes t ON t.id = pb.tribe_id
    LEFT JOIN members m ON m.id = bi.assignee_id
    WHERE bi.status <> 'archived'
      AND bi.cycle = p_cycle
      AND EXISTS (
        SELECT 1 FROM board_item_tag_assignments bita
        JOIN tags tg ON tg.id = bita.tag_id
        WHERE bita.board_item_id = bi.id AND tg.name = 'entregavel_lider'
      )
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
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END as health,
      (bi.forecast_date - bi.baseline_date) as variance_days,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) as checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) as checklist_done
    FROM board_items bi
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND EXISTS (
        SELECT 1 FROM board_item_tag_assignments bita
        JOIN tags tg ON tg.id = bita.tag_id
        WHERE bita.board_item_id = bi.id AND tg.name = 'entregavel_lider'
      )
  ) sub;

  -- By tribe
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
      t.name as tribe_name,
      m.name as leader_name,
      count(*) as total,
      count(*) FILTER (WHERE bi.actual_completion_date IS NOT NULL) as completed,
      count(*) FILTER (WHERE bi.forecast_date IS NOT NULL AND bi.forecast_date <= bi.baseline_date AND bi.actual_completion_date IS NULL) as on_track,
      count(*) FILTER (WHERE bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL AND (bi.forecast_date - bi.baseline_date) BETWEEN 1 AND 7 AND bi.actual_completion_date IS NULL) as at_risk,
      count(*) FILTER (WHERE bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL AND (bi.forecast_date - bi.baseline_date) > 7 AND bi.actual_completion_date IS NULL) as delayed,
      count(*) FILTER (WHERE bi.baseline_date IS NULL) as no_baseline,
      MIN(bi.forecast_date) FILTER (WHERE bi.actual_completion_date IS NULL AND bi.forecast_date >= CURRENT_DATE) as next_deadline,
      CASE WHEN SUM(chk.total) > 0
        THEN ROUND(SUM(chk.done)::numeric / SUM(chk.total) * 100, 1)
        ELSE 0
      END as checklist_pct
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN tribes t ON t.id = pb.tribe_id
    LEFT JOIN members m ON m.id = bi.assignee_id
    LEFT JOIN LATERAL (
      SELECT count(*) as total, count(*) FILTER (WHERE is_completed) as done
      FROM board_item_checklists WHERE board_item_id = bi.id
    ) chk ON true
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND EXISTS (
        SELECT 1 FROM board_item_tag_assignments bita
        JOIN tags tg ON tg.id = bita.tag_id
        WHERE bita.board_item_id = bi.id AND tg.name = 'entregavel_lider'
      )
    GROUP BY pb.tribe_id, t.name, m.name
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
    SELECT tg.name as tag_name, tg.label_pt as tag_label, tg.color as tag_color, count(DISTINCT bi.id) as cnt
    FROM board_items bi
    JOIN board_item_tag_assignments bita ON bita.board_item_id = bi.id
    JOIN tags tg ON tg.id = bita.tag_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND tg.name NOT IN ('entregavel_lider', 'ciclo_3')
      AND tg.tier = 'system'
      AND EXISTS (
        SELECT 1 FROM board_item_tag_assignments bita2
        JOIN tags tg2 ON tg2.id = bita2.tag_id
        WHERE bita2.board_item_id = bi.id AND tg2.name = 'entregavel_lider'
      )
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
      to_char(bi.baseline_date, 'YYYY-MM') as month,
      count(*) as cnt,
      jsonb_agg(DISTINCT pb.tribe_id) as tribes
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND bi.baseline_date IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM board_item_tag_assignments bita
        JOIN tags tg ON tg.id = bita.tag_id
        WHERE bita.board_item_id = bi.id AND tg.name = 'entregavel_lider'
      )
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

GRANT EXECUTE ON FUNCTION public.get_portfolio_dashboard(integer) TO authenticated;

COMMENT ON FUNCTION public.get_portfolio_dashboard IS 'W142: GP Portfolio Dashboard — aggregates all entregavel_lider artifacts across tribes with health, variance, and dimensional breakdowns.';
