-- #576 — gamification cockpit RPC performance (follow-up to #425 / PR #575).
-- PERF, NOT CORRECTNESS: output of both functions is preserved byte-for-byte
-- (verified live via per-tribe + per-initiative md5 fingerprints, antes==depois,
--  and a per-member attendance-map equivalence probe: 37/37 members, 0 mismatches).
--
-- Changes to get_tribe_gamification(integer) + get_initiative_gamification(uuid):
--   1. attendance_rate: was public.get_attendance_rate(member, cycle) called ONCE PER
--      MEMBER inside jsonb_agg (an N+1; a SQL function gets no inline benefit in a
--      plpgsql caller). Now computed in ONE grouped scan into a jsonb map keyed by
--      member_id, then read with (v_attendance -> member::text). The grouped query
--      mirrors get_attendance_rate's body exactly (same numerator/denominator,
--      same event-type/cancel/date window) so per-member values are identical,
--      including NULL (absent map key -> SQL NULL -> JSON null; present-with-NULL
--      -> jsonb null -> JSON null). get_attendance_rate is UNCHANGED and still the
--      SSOT for every other caller.
--   2. last_activity: was a per-member correlated subquery MAX(gamification_points.
--      created_at). Folded into the existing points_per_member aggregate as
--      MAX(gp.created_at) — same value, reuses the one gp scan, zero extra subquery.
--   3. Roster hoist (tribe fn): the five initiative-FILTERED v_initiative_roster
--      sub-scans (members WHERE, trail_completion, cert_coverage, monthly_trend,
--      and the already-collected member-id list) now reuse the v_member_ids array
--      collected once. x IN (SELECT member_id FROM v_initiative_roster WHERE
--      initiative_id = X) is provably equivalent to x = ANY(v_member_ids) because
--      v_member_ids := array_agg(member_id) over the SAME source+filter. The two
--      GLOBAL cross-tribe roster scans (tribe_rank / tribe_ranking) are unchanged.
--      points_per_member also gains WHERE member_id = ANY(v_member_ids) (was an
--      unfiltered full aggregate whose non-roster rows were discarded by the join).
--   4. Roster hoist (initiative fn): init_members + member_data CTEs marked
--      MATERIALIZED (referenced 4-5x each) so the roster is scanned once.
--   5. Delegation double-fetch (item 5): get_initiative_gamification now resolves
--      routing (resolve_tribe_id) BEFORE the members-by-auth_id fetch. Tribe-backed
--      initiatives delegate straight to get_tribe_gamification (which runs its own
--      auth gate), avoiding a second members lookup on the common path. The
--      standalone path authenticates inline. Output is identical: a non-member
--      still receives 'Unauthorized' (from the delegate, or the standalone gate).
--
-- Indexes:
--   * idx_gp_member_created (member_id, created_at DESC) — serves the folded
--     last_activity MAX, the cycle_points created_at FILTER, and the streak-walk
--     scan in get_member_gamification_stats. Supersedes the bare (member_id) index,
--     which is then DROPped as redundant (composite leading column covers it).
--   * idx_cp_member_status (member_id, status) — status-filtered course_progress
--     reads (trail_progress count + trail_completion AVG). The trail_courses
--     both-equality join is already served by the existing UNIQUE
--     course_progress_member_id_course_id_key (member_id, course_id), so the issue's
--     proposed (course_id, member_id) is intentionally NOT added (redundant).
--
-- No signature change -> CREATE OR REPLACE (preserves ACL: authenticated +
-- service_role, no anon/public; defensive REVOKE re-applied below). SECURITY
-- DEFINER + every authority gate unchanged.
--
-- ROLLBACK: re-apply both bodies from migration
-- 20260805000128_p278_425_gamification_coaching_cockpit.sql (the prior canonical
-- capture; whose own rollback chains back to ...089). Then, to restore the index
-- topology this migration changes:
--   DROP INDEX IF EXISTS public.idx_gp_member_created;
--   DROP INDEX IF EXISTS public.idx_cp_member_status;
--   CREATE INDEX idx_gamification_member ON public.gamification_points(member_id);
-- (idx_gamification_member was proactively dropped here as redundant, NOT lost.)

-- ── Indexes ─────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_gp_member_created
  ON public.gamification_points (member_id, created_at DESC);

DROP INDEX IF EXISTS public.idx_gamification_member;

COMMENT ON INDEX public.idx_gp_member_created IS
  '#576: (member_id, created_at DESC). Supersedes idx_gamification_member (member_id) — '
  'the composite leading column covers every member_id lookup the bare index served, plus '
  'the folded last_activity MAX(created_at), the cycle_points created_at FILTER, and the '
  'get_member_gamification_stats streak-walk. idx_gamification_member dropped in this migration.';

CREATE INDEX IF NOT EXISTS idx_cp_member_status
  ON public.course_progress (member_id, status);

-- ── get_tribe_gamification ──────────────────────────────────────────────────────
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
  v_attendance jsonb := '{}'::jsonb;
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

    -- #576: batch attendance_rate for the whole roster in ONE grouped scan
    -- (was public.get_attendance_rate(member, cycle) per member = N+1). Mirrors
    -- get_attendance_rate's numerator/denominator/event-window; v_cycle_start is
    -- already resolved above (so the fn's COALESCE-to-current-cycle fallback is
    -- unneeded here). Per-member values (incl. the NULL case) are identical.
    SELECT COALESCE(jsonb_object_agg(ar.member_id::text, ar.rate), '{}'::jsonb)
    INTO v_attendance
    FROM (
      SELECT a.member_id,
        ROUND(
          count(*) FILTER (WHERE a.present = true)::numeric
          / NULLIF(count(*) FILTER (WHERE a.excused IS NOT TRUE), 0), 2) AS rate
      FROM attendance a
      JOIN events e ON e.id = a.event_id
      WHERE a.member_id = ANY(v_member_ids)
        AND e.date >= v_cycle_start
        AND e.date <= CURRENT_DATE
        AND e.status IS DISTINCT FROM 'cancelled'
        AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
      GROUP BY a.member_id
    ) ar;
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
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points,
      MAX(gp.created_at) AS last_activity_ts
    FROM gamification_points gp
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
    WHERE gp.member_id = ANY(v_member_ids)
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
    -- #576: attendance_rate served from the pre-batched map (value identical to
    -- the prior per-member public.get_attendance_rate(m.id, v_cycle_start) call).
    'attendance_rate', (v_attendance -> m.id::text),
    'current_streak', COALESCE((v_stats -> m.id::text ->> 'current_streak')::int, 0),
    'longest_streak', COALESCE((v_stats -> m.id::text ->> 'longest_streak')::int, 0),
    'active_cycles', COALESCE((v_stats -> m.id::text ->> 'active_cycles')::int, 0),
    -- #576: last_activity folded into points_per_member's MAX(created_at) — same
    -- value as the prior per-member correlated MAX subquery. last VOLUNTARY
    -- gamification activity (NOT members.last_seen_at — login presence to peers
    -- would be an LGPD Art. 9 minimisation issue).
    'last_activity', to_char(p.last_activity_ts, 'YYYY-MM-DD'),
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
  WHERE m.id = ANY(v_member_ids);

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
    FROM (SELECT DISTINCT u AS member_id FROM unnest(v_member_ids) u) rm
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
        WHERE id = ANY(v_member_ids)
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
    WHERE gp.member_id = ANY(v_member_ids)
      AND gp.created_at >= v_cycle_start
    GROUP BY date_trunc('month', gp.created_at)
  ) sub;

  RETURN jsonb_build_object('summary', v_summary, 'members', v_members, 'tribe_ranking', v_ranking, 'monthly_trend', v_trend);
END;
$function$;

-- ── get_initiative_gamification ─────────────────────────────────────────────────
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
  v_attendance jsonb := '{}'::jsonb;
  v_trail_total int;
BEGIN
  -- #576 (item 5): resolve routing FIRST so tribe-backed initiatives delegate to
  -- get_tribe_gamification (which runs its own auth gate) without a redundant
  -- members-by-auth_id fetch here. The standalone path authenticates below.
  -- Output is identical: a non-member still gets 'Unauthorized' either way.
  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_gamification(v_tribe_id);
  END IF;

  -- standalone (non-tribe) initiative path: authenticate the caller.
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

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

    -- #576: batch attendance_rate (was get_attendance_rate per member = N+1).
    SELECT COALESCE(jsonb_object_agg(ar.member_id::text, ar.rate), '{}'::jsonb)
    INTO v_attendance
    FROM (
      SELECT a.member_id,
        ROUND(
          count(*) FILTER (WHERE a.present = true)::numeric
          / NULLIF(count(*) FILTER (WHERE a.excused IS NOT TRUE), 0), 2) AS rate
      FROM attendance a
      JOIN events e ON e.id = a.event_id
      WHERE a.member_id = ANY(v_member_ids)
        AND e.date >= v_cycle_start
        AND e.date <= CURRENT_DATE
        AND e.status IS DISTINCT FROM 'cancelled'
        AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
      GROUP BY a.member_id
    ) ar;
  END IF;

  v_trail_total := (SELECT count(*) FROM courses WHERE is_trail = true);

  WITH init_members AS MATERIALIZED (
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
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points,
      MAX(gp.created_at) AS last_activity_ts
    FROM gamification_points gp
    JOIN init_members im ON im.id = gp.member_id
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
    GROUP BY gp.member_id
  ),
  member_data AS MATERIALIZED (
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
           p.last_activity_ts AS last_activity_ts,
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
      -- #576: attendance_rate from the pre-batched map (value identical to the
      -- prior per-member public.get_attendance_rate(md.id, v_cycle_start) call).
      'attendance_rate', (v_attendance -> md.id::text),
      'current_streak', COALESCE((v_stats -> md.id::text ->> 'current_streak')::int, 0),
      'longest_streak', COALESCE((v_stats -> md.id::text ->> 'longest_streak')::int, 0),
      'active_cycles', COALESCE((v_stats -> md.id::text ->> 'active_cycles')::int, 0),
      -- #576: last_activity folded into points_per_member's MAX(created_at).
      'last_activity', to_char(md.last_activity_ts, 'YYYY-MM-DD'),
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

-- Defense-in-depth (security council): explicit idempotent REVOKE so this
-- CREATE OR REPLACE can never silently re-grant Supabase's PUBLIC/anon default.
REVOKE ALL ON FUNCTION public.get_tribe_gamification(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_initiative_gamification(uuid) FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';
