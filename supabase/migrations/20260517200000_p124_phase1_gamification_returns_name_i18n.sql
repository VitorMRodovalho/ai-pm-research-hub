-- p124 phase 1 — get_tribe_gamification leaderboard now includes tribes.name_i18n.
-- Frontend (CrossTribeWidget / TribeGamificationTab) can pick localized name.
-- No signature change.
--
-- Discovery via HAR (2026-05-08 night): tribe-ranking response was returning
-- `tribe_name` from canonical PT column even when the page lang was en-US,
-- so the cross-tribe ranking chart showed "Radar Tecnológico" / "ROI &
-- Portfólio" etc. instead of localized labels.

CREATE OR REPLACE FUNCTION public.get_tribe_gamification(p_tribe_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record; v_result jsonb; v_summary jsonb; v_members jsonb; v_ranking jsonb; v_trend jsonb;
  v_total_xp bigint; v_member_count int;
  v_cycle_start date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
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

  -- p124 phase 1: include name_i18n so frontend can show localized tribe names
  -- in cross-tribe ranking chart instead of canonical PT names.
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'tribe_id', sub.tid,
      'tribe_name', sub.tname,
      'tribe_name_i18n', sub.tname_i18n,
      'total_xp', sub.txp
    )
    ORDER BY sub.txp DESC
  ), '[]'::jsonb)
  INTO v_ranking
  FROM (
    SELECT t.id AS tid, t.name AS tname, t.name_i18n AS tname_i18n, COALESCE(SUM(gp.points), 0) AS txp
    FROM tribes t
    LEFT JOIN members m4 ON m4.tribe_id = t.id AND m4.is_active = true
    LEFT JOIN gamification_points gp ON gp.member_id = m4.id
    WHERE t.is_active = true
    GROUP BY t.id, t.name, t.name_i18n
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
$function$;

NOTIFY pgrst, 'reload schema';
