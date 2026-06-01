-- p277 / #419 metric 4 (M4 final piece) — converge gamification member cohorts onto the canonical roster
--
-- Problem: get_tribe_gamification and get_initiative_gamification (native branch) were the last #419 surfaces
-- still computing their member cohort off a non-canonical path, so they disagreed with every other surface
-- after the participants-only revision (mig 088):
--   - get_tribe_gamification:  members.tribe_id = p_tribe_id AND is_active  → tribe-8 = 6 (keeps curator Roberto
--     Macêdo, role=curator/kind=observer/active) while get_tribe_stats / exec_tribe_dashboard / the roster all = 5.
--   - get_initiative_gamification (native, non-tribe branch): engagements WHERE status='active' (no role/kind
--     filter) → keeps observers, so Mesa Redonda = 7 / LATAM = 5 / Grupo de Estudos = 4 while the converged
--     get_initiative_stats / exec_cross_initiative_comparison / the roster = 4 / 3 / 3.
--
-- Fix: point the MEMBER COHORT (member_count, the members list, cert_coverage denom, total_xp, monthly_trend,
-- and the cross-tribe XP-ranking sums) at the canonical primitive `v_initiative_roster`
-- (status='active' AND role<>'observer' AND kind<>'observer' — participants only). The XP-RANKING expressions
-- (ORDER BY total_points DESC, RANK() OVER (ORDER BY txp DESC)) are LEFT UNTOUCHED — those are M5/PR5-E
-- (cycle-mode ordering + member_id tiebreak + opt-out pool), kept separable per the M4-C discipline
-- (change WHO is in the cohort, not HOW XP ranks).
--
-- Live antes→depois (cycle_3, 2026-06-01):
--   get_tribe_gamification tribe-8:  member_count 6→5, total_xp 2815→2535, avg_xp 469→507, cert_coverage
--     0.17→0.20, tribe_rank 2→2 (cross-tribe RANK order unchanged — only tribe-8's listed total_xp 2815→2535);
--     tribes 1/2/4/5/6/7 unchanged.
--   get_initiative_gamification native:  Mesa Redonda 7→4 (xp 4880→2375), LATAM 5→3 (2660→1395),
--     Grupo de Estudos 4→3 (2765→1845); 5 other native unchanged; tribe initiatives delegate → inherit the
--     get_tribe_gamification fix.
--
-- Verified safe: person→member is 1:1 (0 multi); tribe→initiative is 1:1 (0 multi); every active-tribe roster
-- has persons==members and 0 NULL member_id (so get_initiative_roster_count == the member-keyed list length);
-- 0 members belong to >1 tribe via the roster (cross-tribe sums stay one-member-one-tribe).
--
-- Same signatures (CREATE OR REPLACE). Rollback: re-apply the prior definitions from mig before this one
-- (members.tribe_id ∧ is_active cohort for get_tribe_gamification; engagements status='active' init_members
-- for get_initiative_gamification).

CREATE OR REPLACE FUNCTION public.get_tribe_gamification(p_tribe_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_result jsonb;
  v_summary jsonb;
  v_members jsonb;
  v_ranking jsonb;
  v_trend jsonb;
  v_total_xp bigint;
  v_member_count int;
  v_cycle_start date;
  v_initiative_id uuid;
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
    'trail_progress', (SELECT count(*) FROM gamification_points gp WHERE gp.member_id = m.id AND gp.category = 'trail')
  ) ORDER BY COALESCE(p.total_points, 0) DESC), '[]'::jsonb)
  INTO v_members
  FROM members m
  LEFT JOIN points_per_member p ON p.member_id = m.id
  WHERE m.id IN (SELECT member_id FROM v_initiative_roster WHERE initiative_id = v_initiative_id);

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
    'trail_completion', 0
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
 SET search_path TO 'public'
AS $function$
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
      'producao_points', md.producao_points, 'curadoria_points', md.curadoria_points,
      'champions_points', md.champions_points,
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
$function$;

NOTIFY pgrst, 'reload schema';
