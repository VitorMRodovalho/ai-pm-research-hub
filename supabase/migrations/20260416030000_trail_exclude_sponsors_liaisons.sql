-- ═══════════════════════════════════════════════════════════════
-- Fix: Trail ranking includes only active participants
-- Inverted logic: include if has tribe OR functional engagement
-- (leader, coordinator, manager, participant).
-- Excludes governance-only roles (sponsor, board_member, liaison,
-- observer) who have no obligation to complete the trail.
-- Also: dynamic trail count (no hardcoded /6)
-- Rollback: DROP FUNCTION get_public_trail_ranking();
-- ═══════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS get_public_trail_ranking();

CREATE OR REPLACE FUNCTION get_public_trail_ranking()
RETURNS TABLE(member_name text, photo_url text, completed int, in_progress int, pct int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
  WITH trail_courses AS (
    SELECT id FROM courses WHERE is_trail = true
  ),
  trail_total AS (
    SELECT count(*)::int AS cnt FROM trail_courses
  ),
  eligible_members AS (
    SELECT DISTINCT m.id, m.name, m.photo_url
    FROM members m
    WHERE m.is_active AND m.current_cycle_active
      AND (
        m.tribe_id IS NOT NULL
        OR EXISTS(
          SELECT 1 FROM engagements e
          WHERE e.person_id = m.person_id AND e.status = 'active'
            AND e.role IN ('leader', 'coordinator', 'manager', 'participant')
        )
      )
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
    em.name,
    em.photo_url,
    COALESCE(ms.completed, 0)::int,
    COALESCE(ms.in_progress, 0)::int,
    CASE WHEN tt.cnt > 0 THEN ROUND(COALESCE(ms.completed, 0)::numeric / tt.cnt * 100)::int ELSE 0 END
  FROM eligible_members em
  CROSS JOIN trail_total tt
  LEFT JOIN member_stats ms ON ms.member_id = em.id
  ORDER BY COALESCE(ms.completed, 0) DESC, COALESCE(ms.in_progress, 0) DESC, em.name;
$$;

GRANT EXECUTE ON FUNCTION get_public_trail_ranking TO anon;
GRANT EXECUTE ON FUNCTION get_public_trail_ranking TO authenticated;
