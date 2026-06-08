-- #425 — Tribe gamification tab -> per-member coaching cockpit (RPC layer)
-- Extends get_tribe_gamification(integer) and get_initiative_gamification(uuid):
--   * trail_completion: was hardcoded 0; now real AVG over the roster cohort of
--     (completed trail courses / total is_trail courses) as a FRACTION 0..1, to
--     match the frontend's ×100 render and the cert_coverage convention. Mirrors
--     calc_trail_completion_pct()'s partial-credit AVG-of-member-rates, scoped to
--     this tribe/initiative roster (the org headline stays in calc_trail_completion_pct).
--   * trail_progress (per member): recanonised to count COMPLETED trail COURSES from
--     course_progress (single source of truth, aligns with get_public_trail_ranking),
--     replacing the prior count of gamification_points rows with category='trail'.
--     (0 members diverge on live data 2026-06-07, so no value change today.)
--   * NEW per-member coaching primitives:
--       attendance_rate  -> public.get_attendance_rate(member, cycle) (SSOT)
--       current_streak / longest_streak / active_cycles
--                        -> public.get_member_gamification_stats(uuid[]) (SSOT),
--                           called once per request, guarded by EXCEPTION so a
--                           non-active viewer still gets the table (zeroed streaks).
--       last_activity    -> MAX(gamification_points.created_at) (voluntary activity only;
--                           NOT members.last_seen_at — login presence to peers = LGPD Art. 9)
--       trail_courses[]  -> per-course {course_id,code,name,tier,status} where
--                           status = completed | in_progress | missing (no row).
-- No signature change -> CREATE OR REPLACE (preserves ACL: authenticated+service_role,
-- no anon/public; re-verified post-apply). SECURITY DEFINER + authority gates unchanged.
--
-- ROLLBACK: re-apply the bodies from migration 20260805000089
-- (p277_419_m4_gamification_cohort_roster) — that is the prior canonical capture of
-- both functions (with trail_completion hardcoded 0 and the points-based trail_progress).

CREATE OR REPLACE FUNCTION public.get_tribe_gamification(p_tribe_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_summary jsonb;
  v_members jsonb;
  v_ranking jsonb;
  v_trend jsonb;
  v_total_xp bigint;
  v_member_count int;
  v_cycle_start date;
  v_initiative_id uuid;
  v_member_ids uuid[];
  v_stats jsonb := '{}'::jsonb;
  v_trail_total int;
  v_trail_completion numeric;
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

  -- M4: canonical member cohort (participants-only roster), single source of truth.
  v_initiative_id := public.resolve_initiative_id(p_tribe_id);
  v_member_count := public.get_initiative_roster_count(v_initiative_id);

  -- #425: roster member ids for the batched coaching-stats call.
  SELECT array_agg(member_id) INTO v_member_ids
  FROM v_initiative_roster WHERE initiative_id = v_initiative_id;

  -- #425: streak / active-cycle coaching signals from the canonical RPC (SSOT).
  -- get_member_gamification_stats RAISEs if the caller is not an active member;
  -- a non-active viewer should still get the table, just with zeroed streaks.
  IF v_member_ids IS NOT NULL THEN
    BEGIN
      SELECT COALESCE(jsonb_object_agg(s.member_id::text, jsonb_build_object(
               'current_streak', s.current_streak_count,
               'longest_streak', s.longest_streak_count,
               'active_cycles', s.active_cycles_count
             )), '{}'::jsonb)
      INTO v_stats
      FROM public.get_member_gamification_stats(v_member_ids) s;
    EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN
      -- non-active viewer (insufficient_privilege) or >200-member cap
      -- (invalid_parameter_value): degrade gracefully to zeroed streaks. Any
      -- OTHER error propagates (schema drift / programming bugs must surface).
      v_stats := '{}'::jsonb;
    END;
  END IF;

  -- #425: dynamic trail denominator (no hardcoded 6).
  v_trail_total := (SELECT count(*) FROM courses WHERE is_trail = true);

  WITH points_per_member AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::int AS total_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gp.created_at >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0)::int AS attendance_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.slug = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0)::int AS learning_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'producao'), 0)::int AS producao_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0)::int AS curadoria_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points
    FROM gamification_points gp
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
    GROUP BY gp.member_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id, 'name', m.name,
    'total_points', COALESCE(p.total_points, 0),
    'cycle_points', COALESCE(p.cycle_points, 0),
    'attendance_points', COALESCE(p.attendance_points, 0),
    'cert_points', COALESCE(p.cert_points, 0),
    'badge_points', COALESCE(p.badge_points, 0),
    'learning_points', COALESCE(p.learning_points, 0),
    'producao_points', COALESCE(p.producao_points, 0),
    'curadoria_points', COALESCE(p.curadoria_points, 0),
    'champions_points', COALESCE(p.champions_points, 0),
    'credly_badge_count', COALESCE(jsonb_array_length(m.credly_badges), 0),
    'has_cpmai', COALESCE(m.cpmai_certified, false),
    -- #425: trail_progress = completed trail COURSES (course_progress, canonical).
    'trail_progress', (
      SELECT count(*) FROM course_progress cp
      WHERE cp.member_id = m.id AND cp.status = 'completed'
        AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
    ),
    -- #425: per-member coaching primitives.
    'attendance_rate', public.get_attendance_rate(m.id, v_cycle_start),
    'current_streak', COALESCE((v_stats -> m.id::text ->> 'current_streak')::int, 0),
    'longest_streak', COALESCE((v_stats -> m.id::text ->> 'longest_streak')::int, 0),
    'active_cycles', COALESCE((v_stats -> m.id::text ->> 'active_cycles')::int, 0),
    -- #425: last_activity = last VOLUNTARY gamification activity (already public on
    -- the leaderboard). Deliberately NOT members.last_seen_at — exposing a login-
    -- derived presence timestamp to tribe peers is an LGPD Art. 9 minimisation issue.
    'last_activity', to_char(
      (SELECT MAX(gp2.created_at) FROM gamification_points gp2 WHERE gp2.member_id = m.id),
      'YYYY-MM-DD'),
    'trail_courses', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'course_id', c.id, 'code', c.code, 'name', c.name, 'tier', c.tier,
        'status', COALESCE(cp.status, 'missing')
      ) ORDER BY c.sort_order), '[]'::jsonb)
      FROM courses c
      LEFT JOIN course_progress cp ON cp.course_id = c.id AND cp.member_id = m.id
      WHERE c.is_trail = true
    )
  ) ORDER BY COALESCE(p.total_points, 0) DESC), '[]'::jsonb)
  INTO v_members
  FROM members m
  LEFT JOIN points_per_member p ON p.member_id = m.id
  WHERE m.id IN (SELECT member_id FROM v_initiative_roster WHERE initiative_id = v_initiative_id);

  SELECT COALESCE(SUM((elem->>'total_points')::bigint), 0)
  INTO v_total_xp
  FROM jsonb_array_elements(v_members) elem;

  -- #425: real trail completion = AVG over roster of (completed/total), fraction 0..1.
  SELECT ROUND(AVG(member_pct), 2) INTO v_trail_completion
  FROM (
    SELECT (
      SELECT count(*) FROM course_progress cp
      WHERE cp.member_id = rm.member_id AND cp.status = 'completed'
        AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
    )::numeric / NULLIF(v_trail_total, 0) AS member_pct
    FROM (SELECT DISTINCT member_id FROM v_initiative_roster WHERE initiative_id = v_initiative_id) rm
  ) sub;

  v_summary := jsonb_build_object(
    'total_xp', v_total_xp,
    'avg_xp', CASE WHEN v_member_count > 0 THEN ROUND(v_total_xp::numeric / v_member_count) ELSE 0 END,
    'tribe_rank', (
      WITH tribe_totals AS (
        SELECT t.id AS tid, COALESCE(SUM(gp.points), 0) AS txp
        FROM tribes t
        LEFT JOIN (SELECT DISTINCT legacy_tribe_id, member_id FROM v_initiative_roster) m2 ON m2.legacy_tribe_id = t.id
        LEFT JOIN gamification_points gp ON gp.member_id = m2.member_id
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
        WHERE id IN (SELECT member_id FROM v_initiative_roster WHERE initiative_id = v_initiative_id)
        AND (cpmai_certified = true OR jsonb_array_length(COALESCE(credly_badges, '[]'::jsonb)) > 0)
      )::numeric / v_member_count, 2
    ) ELSE 0 END,
    'trail_completion', COALESCE(v_trail_completion, 0)
  );

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
    LEFT JOIN (SELECT DISTINCT legacy_tribe_id, member_id FROM v_initiative_roster) m4 ON m4.legacy_tribe_id = t.id
    LEFT JOIN gamification_points gp ON gp.member_id = m4.member_id
    WHERE t.is_active = true
    GROUP BY t.id, t.name, t.name_i18n
  ) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'xp', month_xp) ORDER BY month), '[]'::jsonb)
  INTO v_trend
  FROM (
    SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
    FROM gamification_points gp
    JOIN members m5 ON m5.id = gp.member_id
    WHERE m5.id IN (SELECT member_id FROM v_initiative_roster WHERE initiative_id = v_initiative_id)
      AND gp.created_at >= v_cycle_start
    GROUP BY date_trunc('month', gp.created_at)
  ) sub;

  RETURN jsonb_build_object('summary', v_summary, 'members', v_members, 'tribe_ranking', v_ranking, 'monthly_trend', v_trend);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_initiative_gamification(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_result jsonb;
  v_cycle_start date;
  v_member_ids uuid[];
  v_stats jsonb := '{}'::jsonb;
  v_trail_total int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_gamification(v_tribe_id);
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;

  SELECT array_agg(DISTINCT m.id) INTO v_member_ids
  FROM v_initiative_roster vir JOIN members m ON m.id = vir.member_id
  WHERE vir.initiative_id = p_initiative_id;

  -- #425: streak / active-cycle coaching signals (SSOT), guarded for non-active viewers.
  IF v_member_ids IS NOT NULL THEN
    BEGIN
      SELECT COALESCE(jsonb_object_agg(s.member_id::text, jsonb_build_object(
               'current_streak', s.current_streak_count,
               'longest_streak', s.longest_streak_count,
               'active_cycles', s.active_cycles_count
             )), '{}'::jsonb)
      INTO v_stats
      FROM public.get_member_gamification_stats(v_member_ids) s;
    EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN
      -- non-active viewer (insufficient_privilege) or >200-member cap
      -- (invalid_parameter_value): degrade gracefully to zeroed streaks. Any
      -- OTHER error propagates (schema drift / programming bugs must surface).
      v_stats := '{}'::jsonb;
    END;
  END IF;

  v_trail_total := (SELECT count(*) FROM courses WHERE is_trail = true);

  WITH init_members AS (
    SELECT DISTINCT m.id, m.name, m.cpmai_certified, m.credly_badges
    FROM v_initiative_roster vir
    JOIN members m ON m.id = vir.member_id
    WHERE vir.initiative_id = p_initiative_id
  ),
  points_per_member AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::int AS total_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gp.created_at >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0)::int AS attendance_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.slug = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0)::int AS learning_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'producao'), 0)::int AS producao_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0)::int AS curadoria_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points
    FROM gamification_points gp
    JOIN init_members im ON im.id = gp.member_id
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
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
           COALESCE(p.producao_points, 0) AS producao_points,
           COALESCE(p.curadoria_points, 0) AS curadoria_points,
           COALESCE(p.champions_points, 0) AS champions_points,
           COALESCE(jsonb_array_length(im.credly_badges), 0) AS credly_badge_count,
           COALESCE(im.cpmai_certified, false) AS has_cpmai,
           (SELECT count(*) FROM course_progress cp
             WHERE cp.member_id = im.id AND cp.status = 'completed'
               AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)) AS trail_progress
    FROM init_members im
    LEFT JOIN points_per_member p ON p.member_id = im.id
  ),
  v_members AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', md.id, 'name', md.name,
      'total_points', md.total_points, 'cycle_points', md.cycle_points,
      'attendance_points', md.attendance_points, 'cert_points', md.cert_points,
      'badge_points', md.badge_points, 'learning_points', md.learning_points,
      'producao_points', md.producao_points, 'curadoria_points', md.curadoria_points,
      'champions_points', md.champions_points,
      'credly_badge_count', md.credly_badge_count,
      'has_cpmai', md.has_cpmai,
      'trail_progress', md.trail_progress,
      'attendance_rate', public.get_attendance_rate(md.id, v_cycle_start),
      'current_streak', COALESCE((v_stats -> md.id::text ->> 'current_streak')::int, 0),
      'longest_streak', COALESCE((v_stats -> md.id::text ->> 'longest_streak')::int, 0),
      'active_cycles', COALESCE((v_stats -> md.id::text ->> 'active_cycles')::int, 0),
      'last_activity', to_char(
        (SELECT MAX(gp2.created_at) FROM gamification_points gp2 WHERE gp2.member_id = md.id),
        'YYYY-MM-DD'),
      'trail_courses', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'course_id', c.id, 'code', c.code, 'name', c.name, 'tier', c.tier,
          'status', COALESCE(cp.status, 'missing')
        ) ORDER BY c.sort_order), '[]'::jsonb)
        FROM courses c
        LEFT JOIN course_progress cp ON cp.course_id = c.id AND cp.member_id = md.id
        WHERE c.is_trail = true
      )
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
  ),
  v_trail AS (
    SELECT ROUND(AVG(member_pct), 2) AS pct FROM (
      SELECT (
        SELECT count(*) FROM course_progress cp
        WHERE cp.member_id = im.id AND cp.status = 'completed'
          AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
      )::numeric / NULLIF(v_trail_total, 0) AS member_pct
      FROM init_members im
    ) s
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
      'trail_completion', COALESCE((SELECT pct FROM v_trail), 0)
    ),
    'members', (SELECT members_json FROM v_members),
    'tribe_ranking', '[]'::jsonb,
    'monthly_trend', (SELECT trend_json FROM v_trend)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- #425 defense-in-depth (security council): explicit idempotent REVOKE so a future
-- DROP+CREATE on either function can never silently re-grant Supabase's PUBLIC/anon
-- default. CREATE OR REPLACE above preserves ACL; these make the intent self-enforcing.
REVOKE ALL ON FUNCTION public.get_tribe_gamification(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_initiative_gamification(uuid) FROM PUBLIC, anon;
