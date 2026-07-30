-- #1527 — the trail-ranking tribe filter on the home page was inert: the component builds its
-- dropdown from r.tribe_id / r.tribe_name, and get_public_trail_ranking() returned neither, so the
-- Map stayed empty and the <select> only ever had "all tribes". Closing it on the RPC side (option a)
-- rather than deleting the dropdown, because the panel is long and tribe is its only navigation.
--
-- Privacy read before widening an ANON surface: this adds nothing an anon client cannot already
-- derive. The `public_members` view is anon-SELECTable and already exposes (id, name, photo_url,
-- tribe_id), so the member->tribe association is already public; only the id->label was missing here,
-- and tribe names are published site content. The eligibility predicate is UNCHANGED, so the
-- gamification_opt_out / pre-onboarding / non-trail-role exclusions keep governing who appears.
--
-- Return type changes, so this is DROP + CREATE (CREATE OR REPLACE cannot change a return type).
-- The DROP resets the ACL to the default, which grants EXECUTE to PUBLIC, so the grants are restated
-- explicitly below: PUBLIC revoked, the three real callers granted (matches the live pre-DROP ACL
-- minus the redundant PUBLIC entry).

DROP FUNCTION IF EXISTS public.get_public_trail_ranking();

CREATE FUNCTION public.get_public_trail_ranking()
 RETURNS TABLE(member_name text, photo_url text, completed integer, in_progress integer, pct integer, tribe_id integer, tribe_name text)
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
    SELECT DISTINCT m.id, m.name, m.photo_url, m.tribe_id
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
    CASE WHEN tt.cnt > 0 THEN ROUND(COALESCE(ms.completed, 0)::numeric / tt.cnt * 100)::int ELSE 0 END,
    em.tribe_id,
    t.name
  FROM eligible_members em
  CROSS JOIN trail_total tt
  LEFT JOIN member_stats ms ON ms.member_id = em.id
  LEFT JOIN tribes t ON t.id = em.tribe_id
  ORDER BY COALESCE(ms.completed, 0) DESC, COALESCE(ms.in_progress, 0) DESC, em.name;
$function$;

REVOKE ALL ON FUNCTION public.get_public_trail_ranking() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_trail_ranking() TO anon;
GRANT EXECUTE ON FUNCTION public.get_public_trail_ranking() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_trail_ranking() TO service_role;

COMMENT ON FUNCTION public.get_public_trail_ranking() IS
  'Public (anon) trail-completion ranking. Returns tribe_id + tribe_name so the home-page tribe filter '
  'can populate (#1527); eligibility predicate unchanged (opt-out, pre-onboarding and non-trail roles '
  'still excluded). Members whose tribe comes from an engagement rather than members.tribe_id carry a '
  'NULL tribe and are reachable via the "all tribes" option.';
