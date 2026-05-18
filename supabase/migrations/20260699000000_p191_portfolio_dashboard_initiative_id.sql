-- OPP-190.I — Add initiative_id + initiative_kind to portfolio dashboard
--
-- V4 maturity: artifacts + by_tribe now include initiative.id + initiative.kind
-- so frontend can filter by initiative primitive (ADR-0005), not just
-- legacy_tribe_id (which is NULL for workgroups/committees/etc).
--
-- Today data shows 49/49 portfolio items são research_tribe kind. Filter
-- dropdown will surface the future-proof primitive even though it's
-- functionally equivalent to tribe filter for now.
--
-- Rollback: re-apply prior body without initiative_id/kind in artifacts +
-- by_tribe SELECT lists + GROUP BY.

CREATE OR REPLACE FUNCTION public.get_portfolio_dashboard(p_cycle integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_artifacts jsonb;
  v_summary jsonb;
  v_by_tribe jsonb;
  v_by_type jsonb;
  v_by_month jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(sub.*) ORDER BY sub.tribe_id, sub.baseline_date NULLS LAST)
  INTO v_artifacts
  FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.baseline_date, bi.forecast_date, bi.actual_completion_date,
      CASE
        WHEN bi.baseline_date IS NOT NULL AND bi.forecast_date IS NOT NULL
        THEN (bi.forecast_date - bi.baseline_date) ELSE NULL
      END AS variance_days,
      CASE
        WHEN bi.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN bi.baseline_date IS NULL OR bi.forecast_date IS NULL THEN 'no_baseline'
        WHEN CURRENT_DATE > bi.forecast_date THEN 'delayed'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END AS health,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      i.id AS initiative_id,
      i.kind AS initiative_kind,
      m.name AS leader_name,
      bi.tags AS legacy_tags,
      (SELECT jsonb_agg(jsonb_build_object('name', tg.name, 'label', tg.label_pt, 'color', tg.color))
       FROM board_item_tag_assignments bita JOIN tags tg ON tg.id = bita.tag_id
       WHERE bita.board_item_id = bi.id AND tg.name NOT IN ('entregavel_lider', 'ciclo_3')) AS unified_tags,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) AS checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) AS checklist_done,
      CASE WHEN bi.baseline_date IS NOT NULL THEN 'Q' || EXTRACT(QUARTER FROM bi.baseline_date)::text ELSE 'TBD' END AS quarter,
      CASE WHEN bi.baseline_date IS NOT NULL THEN to_char(bi.baseline_date, 'YYYY-MM') ELSE 'TBD' END AS baseline_month
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    LEFT JOIN members m ON m.id = bi.assignee_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle AND bi.is_portfolio_item = true
  ) sub;

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
        WHEN CURRENT_DATE > bi.forecast_date THEN 'delayed'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END AS health,
      (bi.forecast_date - bi.baseline_date) AS variance_days,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) AS checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) AS checklist_done
    FROM board_items bi
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle AND bi.is_portfolio_item = true
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'tribe_id', sub.tribe_id, 'tribe_name', sub.tribe_name,
    'initiative_id', sub.initiative_id, 'initiative_kind', sub.initiative_kind,
    'leader', sub.leader_name, 'total', sub.total,
    'completed', sub.completed, 'on_track', sub.on_track,
    'at_risk', sub.at_risk, 'delayed', sub.delayed,
    'no_baseline', sub.no_baseline, 'next_deadline', sub.next_deadline,
    'checklist_pct', sub.checklist_pct
  ) ORDER BY sub.tribe_id NULLS LAST, sub.tribe_name)
  INTO v_by_tribe
  FROM (
    SELECT
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      i.id AS initiative_id,
      i.kind AS initiative_kind,
      m.name AS leader_name,
      count(*) AS total,
      count(*) FILTER (WHERE bi.actual_completion_date IS NOT NULL) AS completed,
      count(*) FILTER (
        WHERE bi.actual_completion_date IS NULL
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND bi.forecast_date <= bi.baseline_date
          AND CURRENT_DATE <= bi.forecast_date
      ) AS on_track,
      count(*) FILTER (
        WHERE bi.actual_completion_date IS NULL
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND (bi.forecast_date - bi.baseline_date) BETWEEN 1 AND 7
          AND CURRENT_DATE <= bi.forecast_date
      ) AS at_risk,
      count(*) FILTER (
        WHERE bi.actual_completion_date IS NULL
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND ((bi.forecast_date - bi.baseline_date) > 7 OR CURRENT_DATE > bi.forecast_date)
      ) AS delayed,
      count(*) FILTER (WHERE bi.baseline_date IS NULL) AS no_baseline,
      MIN(bi.forecast_date) FILTER (WHERE bi.actual_completion_date IS NULL AND bi.forecast_date >= CURRENT_DATE) AS next_deadline,
      CASE WHEN SUM(chk.total) > 0 THEN ROUND(SUM(chk.done)::numeric / SUM(chk.total) * 100, 1) ELSE 0 END AS checklist_pct
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    LEFT JOIN members m ON m.id = bi.assignee_id
    LEFT JOIN LATERAL (
      SELECT count(*) AS total, count(*) FILTER (WHERE is_completed) AS done
      FROM board_item_checklists WHERE board_item_id = bi.id
    ) chk ON true
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle AND bi.is_portfolio_item = true
    GROUP BY i.legacy_tribe_id, i.title, i.id, i.kind, m.name
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'type', sub.tag_name, 'label', sub.tag_label, 'color', sub.tag_color, 'count', sub.cnt
  ) ORDER BY sub.cnt DESC)
  INTO v_by_type
  FROM (
    SELECT tg.name AS tag_name, tg.label_pt AS tag_label, tg.color AS tag_color, count(DISTINCT bi.id) AS cnt
    FROM board_items bi
    JOIN board_item_tag_assignments bita ON bita.board_item_id = bi.id
    JOIN tags tg ON tg.id = bita.tag_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND tg.name NOT IN ('entregavel_lider', 'ciclo_3')
      AND tg.tier = 'system' AND bi.is_portfolio_item = true
    GROUP BY tg.name, tg.label_pt, tg.color
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'month', sub.month, 'count', sub.cnt, 'tribes', sub.tribes
  ) ORDER BY sub.month)
  INTO v_by_month
  FROM (
    SELECT
      to_char(bi.baseline_date, 'YYYY-MM') AS month,
      count(*) AS cnt,
      jsonb_agg(DISTINCT i.legacy_tribe_id) AS tribes
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND bi.baseline_date IS NOT NULL AND bi.is_portfolio_item = true
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
$function$;

-- Self-contained GRANT (council review LOW-191.E migration auditability pattern):
-- Postgres preserves ACL on CREATE OR REPLACE but file should be auditable in isolation.
GRANT EXECUTE ON FUNCTION public.get_portfolio_dashboard(integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
