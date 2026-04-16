-- ═══════════════════════════════════════════════════════════════
-- Two fixes reported by Jefferson (T5 tribe leader) and Vitor (GP):
--
-- Bug #1 (Wellington offboard incomplete): earlier offboard only toggled
--   is_active=false + operational_role='none'. It forgot V4 fields
--   (member_status, designations, offboarded_at). Net effect: Wellington
--   vanished from both views — /attendance filters by is_active (so he's
--   out) and /tribe/5 grid_members filters by member_status='active' AND
--   operational_role not 'none' (so he's out here too). Intent was to
--   keep him as observer in T5.
--
-- Bug #2 (% faltas diverge between GP and tribe_leader): get_attendance_grid
--   doesn't branch on `ge.date > CURRENT_DATE`. Future events fall through
--   to 'absent', inflating the denominator and dropping rate. There are
--   46 future events vs 50 past in the current cycle → massive distortion.
--   get_tribe_attendance_grid already handles this with 'scheduled'.
--
-- Rollback:
--   UPDATE members SET member_status='active', designations='{}'::text[],
--     offboarded_at=NULL WHERE email='wbarbozaeng@gmail.com';
--   (and restore previous RPC body from 20260320100005 + earlier migrations)
-- ═══════════════════════════════════════════════════════════════

-- ── Fix #1: Wellington state ──
UPDATE public.members
SET member_status = 'observer',
    designations = ARRAY['observer']::text[],
    offboarded_at = '2026-04-16 16:00:00+00',
    updated_at = now()
WHERE email = 'wbarbozaeng@gmail.com';

-- ── Fix #2: get_attendance_grid — match get_tribe_attendance_grid ──
-- Treat future events as 'scheduled' so they don't inflate the denominator.
CREATE OR REPLACE FUNCTION public.get_attendance_grid(
  p_tribe_id integer DEFAULT NULL,
  p_event_type text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_caller record;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  IF v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
     AND NOT (v_caller.designations && ARRAY['sponsor', 'chapter_liaison', 'curator']) THEN
    IF v_caller.tribe_id IS NOT NULL THEN
      p_tribe_id := v_caller.tribe_id;
    ELSE
      RETURN jsonb_build_object('error', 'No tribe assigned');
    END IF;
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type, e.nature, e.tribe_id, t.name AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date) AS week_number
    FROM events e
    LEFT JOIN tribes t ON t.id = e.tribe_id
    WHERE e.date >= v_cycle_start
      AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms', 'evento_externo')
      AND (p_event_type IS NULL OR e.type = p_event_type)
    ORDER BY e.date
  ),
  active_members AS (
    SELECT m.id, m.name, m.tribe_id, m.chapter, m.operational_role, m.designations
    FROM members m
    WHERE m.is_active = true
      AND m.operational_role NOT IN ('guest', 'none')
      AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
  ),
  eligibility AS (
    SELECT m.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        WHEN ge.type = 'tribo' AND (m.tribe_id = ge.tribe_id OR m.operational_role IN ('manager', 'deputy_manager')) THEN true
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        WHEN ge.type = 'comms' AND m.designations && ARRAY['comms_team', 'comms_leader', 'comms_member'] THEN true
        ELSE false
      END AS is_eligible
    FROM active_members m
    CROSS JOIN grid_events ge
  ),
  cell_status AS (
    SELECT
      el.member_id, el.event_id, el.is_eligible,
      CASE
        WHEN NOT el.is_eligible THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN 'scheduled'
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL THEN 'present'
        ELSE 'absent'
      END AS status
    FROM eligibility el
    JOIN grid_events ge ON ge.id = el.event_id
    LEFT JOIN attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
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
  ),
  detractor_calc AS (
    SELECT
      cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2
        JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.status = 'absent' AND sub.rn <= (
        SELECT MIN(rn2) FROM (
          SELECT status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3
          JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.status = 'present'
      )) AS consecutive_absences
    FROM cell_status cs
    GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM active_members),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms), 0),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc WHERE consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc WHERE consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type, 'nature', ge.nature,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_future', (ge.date > CURRENT_DATE)
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'tribes', (
      SELECT COALESCE(jsonb_agg(tribe_row ORDER BY tribe_row->>'tribe_name'), '[]'::jsonb)
      FROM (
        SELECT jsonb_build_object(
          'tribe_id', t.id,
          'tribe_name', t.name,
          'leader_name', COALESCE((SELECT m2.name FROM members m2 WHERE m2.tribe_id = t.id AND m2.operational_role = 'tribe_leader' LIMIT 1), '—'),
          'avg_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN active_members am ON am.id = ms.member_id WHERE am.tribe_id = t.id), 0),
          'member_count', (SELECT COUNT(*) FROM active_members am WHERE am.tribe_id = t.id),
          'members', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
              'id', am.id, 'name', am.name, 'chapter', am.chapter,
              'rate', COALESCE(ms.rate, 0), 'hours', COALESCE(ms.hours, 0),
              'eligible_count', COALESCE(ms.eligible_count, 0),
              'present_count', COALESCE(ms.present_count, 0),
              'detractor_status', CASE
                WHEN COALESCE(dc.consecutive_absences, 0) >= 3 THEN 'detractor'
                WHEN COALESCE(dc.consecutive_absences, 0) = 2 THEN 'at_risk'
                ELSE 'regular'
              END,
              'consecutive_absences', COALESCE(dc.consecutive_absences, 0),
              'attendance', (
                SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
                FROM cell_status cs WHERE cs.member_id = am.id
              )
            ) ORDER BY COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
            FROM active_members am
            LEFT JOIN member_stats ms ON ms.member_id = am.id
            LEFT JOIN detractor_calc dc ON dc.member_id = am.id
            WHERE am.tribe_id = t.id
          )
        ) AS tribe_row
        FROM tribes t
        WHERE t.is_active = true AND (p_tribe_id IS NULL OR t.id = p_tribe_id)
      ) sub
    )
  ) INTO v_result;

  RETURN v_result;
END; $$;

NOTIFY pgrst, 'reload schema';
