-- Fix: get_adoption_dashboard — nested aggregate error
-- Moved count/AVG aggregates into CTEs (tier_stats, tribe_stats, daily)
-- so jsonb_agg doesn't nest them.

CREATE OR REPLACE FUNCTION public.get_adoption_dashboard()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role = 'manager')
  ) THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  WITH tier_stats AS (
    SELECT operational_role,
      count(*)::integer as total,
      count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::integer as seen_7d,
      count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::integer as seen_30d,
      count(*) FILTER (WHERE last_seen_at IS NULL)::integer as never,
      ROUND(AVG(total_sessions)::numeric, 1) as avg_sessions
    FROM members WHERE is_active = true GROUP BY operational_role
  ),
  tribe_stats AS (
    SELECT t.id as tribe_id, t.name as tribe_name,
      count(m.id)::integer as total,
      count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '7 days')::integer as seen_7d,
      count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '30 days')::integer as seen_30d,
      count(m.id) FILTER (WHERE m.last_seen_at IS NULL)::integer as never,
      ROUND(AVG(m.total_sessions)::numeric, 1) as avg_sessions
    FROM tribes t LEFT JOIN members m ON m.tribe_id = t.id AND m.is_active = true
    GROUP BY t.id, t.name
  ),
  daily AS (
    SELECT session_date, count(DISTINCT member_id)::integer as cnt, sum(pages_visited)::integer as pvs
    FROM member_activity_sessions WHERE session_date > CURRENT_DATE - 30 GROUP BY session_date
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'summary', jsonb_build_object(
      'total_active', (SELECT count(*) FROM members WHERE is_active = true),
      'ever_logged_in', (SELECT count(*) FROM members WHERE is_active = true AND auth_id IS NOT NULL),
      'seen_last_7d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '7 days'),
      'seen_last_30d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '30 days'),
      'never_seen', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at IS NULL),
      'adoption_pct_7d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members),
      'adoption_pct_30d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::numeric / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members),
      'avg_sessions_per_member', (SELECT ROUND(AVG(total_sessions)::numeric, 1) FROM members WHERE is_active = true AND total_sessions > 0)
    ),
    'by_tier', (SELECT COALESCE(jsonb_agg(jsonb_build_object('tier', ts.operational_role, 'total', ts.total, 'seen_7d', ts.seen_7d, 'seen_30d', ts.seen_30d, 'never', ts.never, 'avg_sessions', ts.avg_sessions)), '[]'::jsonb) FROM tier_stats ts),
    'by_tribe', (SELECT COALESCE(jsonb_agg(jsonb_build_object('tribe_id', ts.tribe_id, 'tribe_name', ts.tribe_name, 'total', ts.total, 'seen_7d', ts.seen_7d, 'seen_30d', ts.seen_30d, 'never', ts.never, 'avg_sessions', ts.avg_sessions) ORDER BY ts.tribe_id), '[]'::jsonb) FROM tribe_stats ts),
    'daily_activity', (SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d.dt::text, 'unique_members', COALESCE(dy.cnt, 0), 'total_pageviews', COALESCE(dy.pvs, 0)) ORDER BY d.dt), '[]'::jsonb) FROM generate_series(CURRENT_DATE - 30, CURRENT_DATE, '1 day') d(dt) LEFT JOIN daily dy ON dy.session_date = d.dt),
    'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'tier', m.operational_role, 'tribe_id', m.tribe_id, 'tribe_name', t.name, 'has_auth', m.auth_id IS NOT NULL, 'last_seen', m.last_seen_at, 'total_sessions', m.total_sessions, 'last_pages', m.last_active_pages, 'status', CASE WHEN m.last_seen_at IS NULL THEN 'never' WHEN m.last_seen_at > now() - interval '7 days' THEN 'active' WHEN m.last_seen_at > now() - interval '30 days' THEN 'inactive' ELSE 'dormant' END) ORDER BY m.last_seen_at DESC NULLS LAST), '[]'::jsonb) FROM members m LEFT JOIN tribes t ON t.id = m.tribe_id WHERE m.is_active = true)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
