-- p118: fix get_tribe_gamification + get_initiative_gamification referencing dropped view
-- Same root cause as get_member_detail: ADR-0024 follow-up (mig 20260513050000) dropped
-- public.gamification_leaderboard. Both RPCs read columns that were view-only:
--   total_points, cycle_points, attendance_points, cert_points, badge_points, learning_points.
-- Replacement: aggregate from public.gamification_points directly via inline CTE.
-- Category mapping preserved from original view contract:
--   cycle_points: created_at >= current cycle_start
--   attendance_points: category='attendance'
--   cert_points: category LIKE 'cert_%'
--   badge_points: category='badge'
--   learning_points: category IN ('trail','knowledge_ai_pm','specialization','course')
-- Same jsonb shape preserved for component compatibility.

CREATE OR REPLACE FUNCTION public.get_tribe_gamification(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record; v_result jsonb; v_summary jsonb; v_members jsonb; v_ranking jsonb; v_trend jsonb;
  v_total_xp bigint; v_member_count int;
  v_cycle_start date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  -- V4 auth (ADR-0011): tribe members can view own tribe; admin/manager-tier can view any.
  -- view_internal_analytics is granted to manager/deputy_manager/sponsor/chapter_liaison via engagement_kind_permissions.
  IF NOT (
    v_caller.tribe_id = p_tribe_id
    OR public.can_by_member(v_caller.id, 'view_internal_analytics')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;

  SELECT count(*) INTO v_member_count FROM members WHERE tribe_id = p_tribe_id AND is_active = true;

  WITH points_per_member AS (
    SELECT
      member_id,
      SUM(points)::int AS total_points,
      COALESCE(SUM(points) FILTER (WHERE created_at >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(points) FILTER (WHERE category = 'attendance'), 0)::int AS attendance_points,
      COALESCE(SUM(points) FILTER (WHERE category LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(points) FILTER (WHERE category = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(points) FILTER (WHERE category IN ('trail','knowledge_ai_pm','specialization','course')), 0)::int AS learning_points
    FROM gamification_points
    GROUP BY member_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id, 'name', m.name,
    'total_points', COALESCE(p.total_points, 0),
    'cycle_points', COALESCE(p.cycle_points, 0),
    'attendance_points', COALESCE(p.attendance_points, 0),
    'cert_points', COALESCE(p.cert_points, 0),
    'badge_points', COALESCE(p.badge_points, 0),
    'learning_points', COALESCE(p.learning_points, 0),
    'credly_badge_count', COALESCE(jsonb_array_length(m.credly_badges), 0),
    'has_cpmai', COALESCE(m.cpmai_certified, false),
    'trail_progress', (SELECT count(*) FROM gamification_points gp WHERE gp.member_id = m.id AND gp.category = 'trail')
  ) ORDER BY COALESCE(p.total_points, 0) DESC), '[]'::jsonb)
  INTO v_members
  FROM members m
  LEFT JOIN points_per_member p ON p.member_id = m.id
  WHERE m.tribe_id = p_tribe_id AND m.is_active = true;

  SELECT COALESCE(SUM((elem->>'total_points')::bigint), 0)
  INTO v_total_xp
  FROM jsonb_array_elements(v_members) elem;

  v_summary := jsonb_build_object(
    'total_xp', v_total_xp,
    'avg_xp', CASE WHEN v_member_count > 0 THEN ROUND(v_total_xp::numeric / v_member_count) ELSE 0 END,
    'tribe_rank', (
      WITH tribe_totals AS (
        SELECT t.id AS tid, COALESCE(SUM(gp.points), 0) AS txp
        FROM tribes t
        LEFT JOIN members m2 ON m2.tribe_id = t.id AND m2.is_active = true
        LEFT JOIN gamification_points gp ON gp.member_id = m2.id
        WHERE t.is_active = true
        GROUP BY t.id
      ),
      ranked AS (
        SELECT tid, RANK() OVER (ORDER BY txp DESC) AS rk FROM tribe_totals
      )
      SELECT rk FROM ranked WHERE tid = p_tribe_id
    ),
    'cert_coverage', CASE WHEN v_member_count > 0 THEN ROUND(
      (SELECT count(*) FROM members
        WHERE tribe_id = p_tribe_id AND is_active = true
        AND (cpmai_certified = true OR jsonb_array_length(COALESCE(credly_badges, '[]'::jsonb)) > 0)
      )::numeric / v_member_count, 2
    ) ELSE 0 END,
    'trail_completion', 0
  );

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object('tribe_id', sub.tid, 'tribe_name', sub.tname, 'total_xp', sub.txp)
    ORDER BY sub.txp DESC
  ), '[]'::jsonb)
  INTO v_ranking
  FROM (
    SELECT t.id AS tid, t.name AS tname, COALESCE(SUM(gp.points), 0) AS txp
    FROM tribes t
    LEFT JOIN members m4 ON m4.tribe_id = t.id AND m4.is_active = true
    LEFT JOIN gamification_points gp ON gp.member_id = m4.id
    WHERE t.is_active = true
    GROUP BY t.id, t.name
  ) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'xp', month_xp) ORDER BY month), '[]'::jsonb)
  INTO v_trend
  FROM (
    SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
    FROM gamification_points gp
    JOIN members m5 ON m5.id = gp.member_id
    WHERE m5.tribe_id = p_tribe_id AND m5.is_active = true
      AND gp.created_at >= v_cycle_start
    GROUP BY date_trunc('month', gp.created_at)
  ) sub;

  RETURN jsonb_build_object('summary', v_summary, 'members', v_members, 'tribe_ranking', v_ranking, 'monthly_trend', v_trend);
END;
$$;

COMMENT ON FUNCTION public.get_tribe_gamification(integer) IS
  'p118 fix: rewritten to aggregate from gamification_points directly (was referencing dropped view public.gamification_leaderboard). Same jsonb shape preserved. Category mapping: cert_points = cert_*, badge_points = badge, learning_points = trail/knowledge_ai_pm/specialization/course.';

REVOKE EXECUTE ON FUNCTION public.get_tribe_gamification(integer) FROM PUBLIC, anon;

-- ============================================================
-- get_initiative_gamification: native path also referenced dropped view
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_initiative_gamification(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_result jsonb;
  v_cycle_start date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_gamification(v_tribe_id);
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;

  WITH init_members AS (
    SELECT DISTINCT m.id, m.name, m.cpmai_certified, m.credly_badges
    FROM engagements eng
    JOIN members m ON m.person_id = eng.person_id
    WHERE eng.initiative_id = p_initiative_id AND eng.status = 'active'
  ),
  points_per_member AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::int AS total_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gp.created_at >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'attendance'), 0)::int AS attendance_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gp.category LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gp.category IN ('trail','knowledge_ai_pm','specialization','course')), 0)::int AS learning_points
    FROM gamification_points gp
    JOIN init_members im ON im.id = gp.member_id
    GROUP BY gp.member_id
  ),
  member_data AS (
    SELECT im.id, im.name,
           COALESCE(p.total_points, 0) AS total_points,
           COALESCE(p.cycle_points, 0) AS cycle_points,
           COALESCE(p.attendance_points, 0) AS attendance_points,
           COALESCE(p.cert_points, 0) AS cert_points,
           COALESCE(p.badge_points, 0) AS badge_points,
           COALESCE(p.learning_points, 0) AS learning_points,
           COALESCE(jsonb_array_length(im.credly_badges), 0) AS credly_badge_count,
           COALESCE(im.cpmai_certified, false) AS has_cpmai,
           (SELECT count(*) FROM gamification_points gp2 WHERE gp2.member_id = im.id AND gp2.category = 'trail') AS trail_progress
    FROM init_members im
    LEFT JOIN points_per_member p ON p.member_id = im.id
  ),
  v_members AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', md.id, 'name', md.name,
      'total_points', md.total_points, 'cycle_points', md.cycle_points,
      'attendance_points', md.attendance_points, 'cert_points', md.cert_points,
      'badge_points', md.badge_points, 'learning_points', md.learning_points,
      'credly_badge_count', md.credly_badge_count,
      'has_cpmai', md.has_cpmai,
      'trail_progress', md.trail_progress
    ) ORDER BY md.total_points DESC), '[]'::jsonb) AS members_json
    FROM member_data md
  ),
  v_trend AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'xp', month_xp) ORDER BY month), '[]'::jsonb) AS trend_json
    FROM (
      SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
      FROM gamification_points gp
      JOIN init_members im ON im.id = gp.member_id
      WHERE gp.created_at >= v_cycle_start
      GROUP BY date_trunc('month', gp.created_at)
    ) sub
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_xp', COALESCE((SELECT SUM(total_points) FROM member_data), 0),
      'avg_xp', CASE WHEN (SELECT count(*) FROM member_data) > 0
                THEN ROUND((SELECT SUM(total_points) FROM member_data)::numeric / (SELECT count(*) FROM member_data))
                ELSE 0 END,
      'tribe_rank', NULL,
      'cert_coverage', CASE WHEN (SELECT count(*) FROM member_data) > 0
                       THEN ROUND((SELECT count(*) FROM member_data WHERE has_cpmai OR credly_badge_count > 0)::numeric / (SELECT count(*) FROM member_data), 2)
                       ELSE 0 END,
      'trail_completion', 0
    ),
    'members', (SELECT members_json FROM v_members),
    'tribe_ranking', '[]'::jsonb,
    'monthly_trend', (SELECT trend_json FROM v_trend)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_initiative_gamification(uuid) IS
  'p118 fix: native path rewritten to aggregate from gamification_points directly (was referencing dropped view). Tribe-bound initiatives still delegate to get_tribe_gamification.';

REVOKE EXECUTE ON FUNCTION public.get_initiative_gamification(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_initiative_gamification(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
