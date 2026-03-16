-- Fix: chapters KPI target 5→8 (5 current, 3 in pipeline)
-- Also make get_homepage_stats use dynamic chapter count instead of hardcoded 5.

-- 1. Update KPI target
UPDATE annual_kpi_targets
SET target_value = 8,
    baseline_value = 5,
    notes = '5 capítulos integrados (GO, CE, DF, MG, RS). Meta 2026: 8 capítulos. 3 em prospecção.'
WHERE kpi_key = 'chapters_participating' AND cycle = 3;

-- 2. Update portfolio_kpi_targets if exists
UPDATE portfolio_kpi_targets
SET target_value = 8
WHERE metric_key = 'chapters_participating';

-- 3. Fix get_homepage_stats: hardcoded 5 → dynamic count
CREATE OR REPLACE FUNCTION get_homepage_stats()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN jsonb_build_object(
    'members', (SELECT count(*) FROM members WHERE is_active),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE is_active = true AND chapter IS NOT NULL),
    'impact_hours', (
      SELECT COALESCE(round(sum(
        COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric
        * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)
      ) / 60), 0)
      FROM events e WHERE e.date >= '2025-02-01'
    )
  );
END;
$$;
