-- ═══════════════════════════════════════════════════════════════════════════
-- Wave 8: Drop legacy role/roles columns from members
-- Frontend is fully migrated to operational_role + designations.
-- The sync trigger was a transitional shim and is no longer needed.
-- Must recreate gamification_leaderboard VIEW which depends on m.role.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Step 1: Drop the sync trigger
DROP TRIGGER IF EXISTS trg_sync_legacy_role ON public.members;
DROP FUNCTION IF EXISTS public.sync_legacy_role_columns();

-- Step 2: Recreate gamification_leaderboard WITHOUT role column
DROP VIEW IF EXISTS public.gamification_leaderboard CASCADE;

CREATE OR REPLACE VIEW public.gamification_leaderboard AS
WITH current_cycle AS (
  SELECT cycle_start FROM public.cycles WHERE is_current = TRUE LIMIT 1
)
SELECT
  m.id AS member_id,
  m.name,
  m.chapter,
  m.photo_url,
  m.operational_role,
  m.designations,
  COALESCE(SUM(gp.points), 0)::INT AS total_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'attendance'), 0)::INT AS attendance_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'course'), 0)::INT AS course_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'artifact'), 0)::INT AS artifact_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category NOT IN ('attendance','course','artifact')), 0)::INT AS bonus_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::INT AS cycle_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'attendance' AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::INT AS cycle_attendance_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'course' AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::INT AS cycle_course_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'artifact' AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::INT AS cycle_artifact_points,
  COALESCE(SUM(gp.points) FILTER (
    WHERE gp.category NOT IN ('attendance','course','artifact')
      AND gp.created_at >= (SELECT cycle_start FROM current_cycle)
  ), 0)::INT AS cycle_bonus_points
FROM public.members m
LEFT JOIN public.gamification_points gp ON gp.member_id = m.id
WHERE m.current_cycle_active = TRUE
GROUP BY m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations;

GRANT SELECT ON public.gamification_leaderboard TO authenticated;
GRANT SELECT ON public.gamification_leaderboard TO anon;

-- Step 3: Drop legacy columns
ALTER TABLE public.members DROP COLUMN IF EXISTS role;
ALTER TABLE public.members DROP COLUMN IF EXISTS roles;

COMMIT;
