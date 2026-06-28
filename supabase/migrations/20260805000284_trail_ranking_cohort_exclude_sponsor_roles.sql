-- Wave 1 follow-through (Ivan): align get_public_trail_ranking's cohort to calc_trail_completion_pct.
--
-- M6 (ADR-0100) contract: the public trail ranking and the home calc_trail_completion_pct must share
-- ONE cohort (tested by p277-419-m6 "home == ranking"). calc excludes operational_role IN
-- ('sponsor','chapter_liaison','observer','candidate','visitor','guest'); the ranking did NOT — it
-- admitted anyone with a tribe OR an active leader/coordinator/manager/participant engagement. Those
-- two definitions coincided until Ivan Lourenço became a sponsor (mig …282): he is also the governance-
-- committee LEADER, so calc now drops him (sponsor) while the ranking still admitted him (engagement
-- role='leader') → the home==ranking invariant diverged.
--
-- Fix: apply the SAME operational_role exclusion in the ranking. A sponsor / chapter focal point /
-- observer is not a CPMAI-trail participant, so this is the correct cohort for a trail ranking — and it
-- restores the single-cohort M6 contract. Behaviour: removes Ivan (and any future sponsor/liaison with a
-- qualifying engagement) from the public trail ranking; researchers/leaders/managers are unaffected.

CREATE OR REPLACE FUNCTION public.get_public_trail_ranking()
 RETURNS TABLE(member_name text, photo_url text, completed integer, in_progress integer, pct integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
      AND m.gamification_opt_out = false
      AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
      -- M6 single-cohort parity with calc_trail_completion_pct (#419 / ADR-0100): exclude the same
      -- non-trail operational roles (sponsor/chapter_liaison/observer/candidate/visitor/guest).
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor', 'guest')
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
$function$;
