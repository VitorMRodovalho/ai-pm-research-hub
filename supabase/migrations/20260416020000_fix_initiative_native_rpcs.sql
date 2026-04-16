-- ═══════════════════════════════════════════════════════════════
-- Fix: Initiative RPCs work natively for non-tribe initiatives
-- Bug: get_initiative_attendance_grid referenced tribes.tribe_id (doesn't exist)
-- Bug: get_initiative_stats delegated to get_tribe_stats(NULL) → all zeros
-- Fix: Use resolve_tribe_id() for clean tribe bridge; native path for non-tribe
-- Rollback: DROP FUNCTION get_initiative_attendance_grid(uuid,text);
--           DROP FUNCTION get_initiative_stats(uuid);
-- ═══════════════════════════════════════════════════════════════

-- ── 1. get_initiative_attendance_grid ────────────────────────────────────

DROP FUNCTION IF EXISTS get_initiative_attendance_grid(uuid, text);

CREATE OR REPLACE FUNCTION public.get_initiative_attendance_grid(
  p_initiative_id uuid,
  p_event_type text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  -- Try tribe bridge via resolve_tribe_id (backward compat for tribe-based initiatives)
  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_attendance_grid(v_tribe_id, p_event_type);
  END IF;

  -- Native initiative attendance grid (study_group, workgroup, committee, etc.)
  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number
    FROM events e
    WHERE e.initiative_id = p_initiative_id
      AND e.date >= v_cycle_start
      AND (p_event_type IS NULL OR e.type = p_event_type)
    ORDER BY e.date
  ),
  grid_members AS (
    SELECT DISTINCT m.id, m.name, m.chapter, m.operational_role, m.designations, m.member_status
    FROM engagements eng
    JOIN members m ON m.person_id = eng.person_id
    WHERE eng.initiative_id = p_initiative_id AND eng.status = 'active'
    UNION
    SELECT DISTINCT m.id, m.name, m.chapter, m.operational_role, m.designations, m.member_status
    FROM members m
    JOIN attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
  ),
  cell_status AS (
    SELECT
      gm.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.date > CURRENT_DATE THEN
          CASE WHEN gm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL THEN 'absent'
        ELSE 'absent'
      END AS status
    FROM grid_members gm
    CROSS JOIN grid_events ge
    LEFT JOIN attendance a ON a.member_id = gm.id AND a.event_id = ge.id
  ),
  member_stats AS (
    SELECT
      cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(
        COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2
      ) AS rate,
      ROUND(
        SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1
      ) AS hours
    FROM cell_status cs
    JOIN grid_events ge ON ge.id = cs.event_id
    GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM grid_members WHERE member_status = 'active'),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', false,
      'is_future', (ge.date > CURRENT_DATE)
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', gm.id, 'name', gm.name, 'chapter', gm.chapter,
        'member_status', gm.member_status,
        'rate', COALESCE(ms.rate, 0),
        'hours', COALESCE(ms.hours, 0),
        'eligible_count', COALESCE(ms.eligible_count, 0),
        'present_count', COALESCE(ms.present_count, 0),
        'detractor_status', 'regular',
        'consecutive_absences', 0,
        'attendance', (
          SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
          FROM cell_status cs WHERE cs.member_id = gm.id
        )
      ) ORDER BY COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
      FROM grid_members gm
      LEFT JOIN member_stats ms ON ms.member_id = gm.id
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_initiative_attendance_grid(uuid, text) TO authenticated;


-- ── 2. get_initiative_stats (native path for non-tribe initiatives) ──────

DROP FUNCTION IF EXISTS get_initiative_stats(uuid);

CREATE OR REPLACE FUNCTION public.get_initiative_stats(
  p_initiative_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tribe_id int;
BEGIN
  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_stats(v_tribe_id);
  END IF;

  -- Native stats for non-tribe initiatives
  RETURN (
    WITH cycle AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1),
    init_members AS (
      SELECT DISTINCT m.id, m.name
      FROM engagements eng
      JOIN members m ON m.person_id = eng.person_id
      WHERE eng.initiative_id = p_initiative_id AND eng.status = 'active'
    ),
    init_events AS (
      SELECT e.id, COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes
      FROM events e, cycle c
      WHERE e.initiative_id = p_initiative_id AND e.date >= c.cycle_start AND e.date <= current_date
    ),
    att AS (
      SELECT a.event_id, a.member_id FROM attendance a
      JOIN init_events ie ON ie.id = a.event_id
      WHERE a.present = true AND a.excused IS NOT TRUE
    ),
    init_boards AS (
      SELECT bi.id, bi.status FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      WHERE pb.initiative_id = p_initiative_id
    )
    SELECT json_build_object(
      'member_count', (SELECT count(*) FROM init_members),
      'events_held', (SELECT count(*) FROM init_events),
      'attendance_rate', (SELECT round(
        count(a.*)::numeric / NULLIF((SELECT count(*) FROM init_members) * (SELECT count(*) FROM init_events), 0) * 100, 0
      ) FROM att a),
      'impact_hours', (SELECT coalesce(round(sum(ie.duration_minutes * sub.c)::numeric / 60, 1), 0)
        FROM init_events ie JOIN (SELECT event_id, count(*) c FROM att GROUP BY event_id) sub ON sub.event_id = ie.id),
      'cards_backlog', (SELECT count(*) FROM init_boards WHERE status = 'backlog'),
      'cards_in_progress', (SELECT count(*) FROM init_boards WHERE status = 'in_progress'),
      'cards_review', (SELECT count(*) FROM init_boards WHERE status = 'review'),
      'cards_done', (SELECT count(*) FROM init_boards WHERE status = 'done'),
      'top_contributors', (SELECT coalesce(json_agg(row_to_json(r) ORDER BY r.att_count DESC), '[]')
        FROM (
          SELECT im.name, count(a2.event_id) as att_count,
            round(count(a2.event_id)::numeric / NULLIF((SELECT count(*) FROM init_events), 0) * 100, 0) as rate
          FROM init_members im
          LEFT JOIN att a2 ON a2.member_id = im.id
          GROUP BY im.name
        ) r
      )
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_initiative_stats(uuid) TO authenticated;


-- ── 3. get_initiative_gamification (full GamificationData shape) ──

DROP FUNCTION IF EXISTS get_initiative_gamification(uuid);

CREATE OR REPLACE FUNCTION public.get_initiative_gamification(
  p_initiative_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_gamification(v_tribe_id);
  END IF;

  -- Native gamification for non-tribe initiatives
  -- Returns same shape as get_tribe_gamification for component compatibility
  WITH init_members AS (
    SELECT DISTINCT m.id, m.name, m.cpmai_certified, m.credly_badges
    FROM engagements eng
    JOIN members m ON m.person_id = eng.person_id
    WHERE eng.initiative_id = p_initiative_id AND eng.status = 'active'
  ),
  member_data AS (
    SELECT im.id, im.name,
           COALESCE(gl.total_points, 0) AS total_points,
           COALESCE(gl.cycle_points, 0) AS cycle_points,
           COALESCE(gl.attendance_points, 0) AS attendance_points,
           COALESCE(gl.cert_points, 0) AS cert_points,
           COALESCE(gl.badge_points, 0) AS badge_points,
           COALESCE(gl.learning_points, 0) AS learning_points,
           COALESCE(jsonb_array_length(im.credly_badges), 0) AS credly_badge_count,
           COALESCE(im.cpmai_certified, false) AS has_cpmai,
           (SELECT count(*) FROM gamification_points gp WHERE gp.member_id = im.id AND gp.category = 'trail') AS trail_progress
    FROM init_members im
    LEFT JOIN gamification_leaderboard gl ON gl.member_id = im.id
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
      AND gp.created_at >= (SELECT cycle_start FROM cycles WHERE is_current = true LIMIT 1)
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

GRANT EXECUTE ON FUNCTION public.get_initiative_gamification(uuid) TO authenticated;
