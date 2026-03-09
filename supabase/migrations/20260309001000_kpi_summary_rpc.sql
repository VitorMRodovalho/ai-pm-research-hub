-- KPI summary RPC — aggregates live data for the KPI section on index page
-- Replaces hardcoded data/kpis.ts with real numbers from DB

CREATE OR REPLACE FUNCTION public.kpi_summary()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE current_cycle_active = true AND chapter IS NOT NULL),
    'active_members', (SELECT COUNT(*) FROM members WHERE current_cycle_active = true),
    'tribes', (SELECT COUNT(*) FROM tribes),
    'published_artifacts', (SELECT COUNT(*) FROM artifacts WHERE status = 'published'),
    'total_events', (SELECT COUNT(*) FROM events),
    'impact_hours', COALESCE((SELECT total_impact_hours FROM impact_hours_total LIMIT 1), 0),
    'impact_target', COALESCE((SELECT annual_target_hours FROM impact_hours_total LIMIT 1), 1800),
    'impact_pct', COALESCE((SELECT percent_of_target FROM impact_hours_total LIMIT 1), 0),
    'cert_pct', ROUND(COALESCE(
      (SELECT COUNT(*)::numeric * 100 / NULLIF(COUNT(*) FILTER (WHERE current_cycle_active), 0)
       FROM members WHERE cpmai_certified = true AND current_cycle_active = true), 0
    ))
  );
$$;

GRANT EXECUTE ON FUNCTION public.kpi_summary() TO anon, authenticated;
