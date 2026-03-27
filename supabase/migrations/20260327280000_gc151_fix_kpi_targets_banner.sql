-- GC-151: Fix KPI targets to use annual_kpi_targets table
-- Problem: CPMAI target was calculated as 70% of eligible members (=28)
-- Reality: annual_kpi_targets has cpmai_certified target = 5

CREATE OR REPLACE FUNCTION get_kpi_dashboard(
  p_cycle_start date DEFAULT '2026-01-01',
  p_cycle_end date DEFAULT '2026-06-30'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
DECLARE result jsonb; days_elapsed numeric; days_total numeric; linear_pct numeric;
BEGIN
  days_elapsed := GREATEST(current_date - p_cycle_start, 0);
  days_total := p_cycle_end - p_cycle_start;
  linear_pct := CASE WHEN days_total > 0 THEN round(days_elapsed / days_total * 100, 1) ELSE 0 END;
  SELECT jsonb_build_object('cycle_pct', linear_pct, 'kpis', jsonb_build_array(
    jsonb_build_object('name', 'Horas de Impacto', 'current', COALESCE((
      SELECT round(sum(COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric
        * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)) / 60)
      FROM events e WHERE e.date BETWEEN p_cycle_start AND p_cycle_end), 0),
      'target', 1800, 'unit', 'h', 'icon', 'clock'),
    jsonb_build_object('name', 'Certificação CPMAI', 'current',
      (SELECT count(*) FROM members WHERE is_active AND cpmai_certified = true),
      'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'cpmai_certified' AND year = 2026), 5),
      'unit', 'membros', 'icon', 'award'),
    jsonb_build_object('name', 'Pilotos de IA', 'current',
      COALESCE((SELECT (value)::int FROM site_config WHERE key = 'kpi_pilot_count_override'), 0),
      'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'pilots_completed' AND year = 2026), 3),
      'unit', '', 'icon', 'rocket'),
    jsonb_build_object('name', 'Artigos Publicados', 'current',
      (SELECT count(*) FROM board_items bi JOIN project_boards pb ON pb.id = bi.board_id
        WHERE pb.board_name ILIKE '%publica%' AND bi.status IN ('done','published')),
      'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'publications_submitted' AND year = 2026), 10),
      'unit', '', 'icon', 'file-text'),
    jsonb_build_object('name', 'Webinars Realizados', 'current',
      (SELECT count(*) FROM events WHERE type = 'webinar' AND date BETWEEN p_cycle_start AND p_cycle_end),
      'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'webinars_realized' AND year = 2026), 6),
      'unit', '', 'icon', 'video'),
    jsonb_build_object('name', 'Capítulos Integrados', 'current',
      (SELECT count(DISTINCT chapter) FROM members WHERE is_active AND chapter IS NOT NULL),
      'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND year = 2026), 8),
      'unit', '', 'icon', 'map-pin')
  )) INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION get_kpi_dashboard(date, date) TO authenticated;
NOTIFY pgrst, 'reload schema';
