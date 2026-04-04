-- Public trail ranking RPC — SECURITY DEFINER so anon can see trail progress
-- Fixes homepage TrailSection showing 0/6 for all members when not logged in
-- (course_progress RLS blocks anon SELECT)

BEGIN;

CREATE OR REPLACE FUNCTION get_public_trail_ranking()
RETURNS TABLE(member_name text, photo_url text, completed int, in_progress int, pct int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
  WITH trail_courses AS (
    SELECT id FROM courses WHERE is_trail = true
  ),
  progress AS (
    SELECT cp.member_id, cp.status
    FROM course_progress cp
    JOIN trail_courses tc ON tc.id = cp.course_id
  ),
  member_stats AS (
    SELECT
      p.member_id,
      COUNT(*) FILTER (WHERE p.status = 'completed') AS completed,
      COUNT(*) FILTER (WHERE p.status = 'in_progress') AS in_progress
    FROM progress p
    GROUP BY p.member_id
  )
  SELECT
    m.name,
    m.photo_url,
    COALESCE(ms.completed, 0)::int,
    COALESCE(ms.in_progress, 0)::int,
    CASE WHEN 6 > 0 THEN ROUND(COALESCE(ms.completed, 0)::numeric / 6 * 100)::int ELSE 0 END
  FROM members m
  LEFT JOIN member_stats ms ON ms.member_id = m.id
  WHERE m.is_active AND m.current_cycle_active
  ORDER BY COALESCE(ms.completed, 0) DESC, COALESCE(ms.in_progress, 0) DESC, m.name;
$$;

GRANT EXECUTE ON FUNCTION get_public_trail_ranking TO anon;
GRANT EXECUTE ON FUNCTION get_public_trail_ranking TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
