-- p84 — extend get_homepage_stats + get_public_platform_stats with initiatives count
-- and active_leaders count, so Hero/PlatformStats can show:
--   - tribes (already had)
--   - initiatives (NEW — non-tribe cross-cutting initiatives)
--   - active_leaders (NEW — for "Dream Team — N Líderes" dynamic label)

CREATE OR REPLACE FUNCTION public.get_homepage_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN jsonb_build_object(
    'members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
    'observers', (SELECT count(*) FROM members WHERE member_status = 'observer'),
    'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni'),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
    ),
    'total_initiatives', (
      SELECT count(*) FROM initiatives WHERE status = 'active'
    ),
    'active_leaders', (
      SELECT count(DISTINCT person_id) FROM auth_engagements
      WHERE status = 'active' AND role IN ('leader', 'co_leader', 'co_gp')
    ),
    'chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE is_active = true AND chapter IS NOT NULL),
    'impact_hours', (
      SELECT COALESCE(round(sum(
        COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric
        * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)
      ) / 60), 0)
      FROM events e
      WHERE e.date >= '2026-01-01' AND e.date <= CURRENT_DATE
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_platform_stats()
RETURNS json
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT json_build_object(
    'active_members', (SELECT COUNT(*) FROM members WHERE is_active AND current_cycle_active),
    'total_tribes', (SELECT COUNT(*) FROM tribes WHERE is_active),
    'total_initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
    ),
    'total_chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE is_active AND chapter != 'Externo'),
    'total_events', (SELECT COUNT(*) FROM events WHERE date >= '2026-01-01'),
    'total_resources', (SELECT COUNT(*) FROM hub_resources WHERE is_active),
    'retention_rate', (
      SELECT ROUND(
        COUNT(*) FILTER (WHERE current_cycle_active)::numeric /
        NULLIF(COUNT(*) FILTER (WHERE is_active OR member_status = 'alumni'), 0) * 100, 1
      )
      FROM members WHERE member_status IN ('active','alumni','observer')
    )
  );
$function$;

NOTIFY pgrst, 'reload schema';
