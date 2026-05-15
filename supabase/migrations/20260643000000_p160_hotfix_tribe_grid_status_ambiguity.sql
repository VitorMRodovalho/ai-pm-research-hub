-- p160 hotfix (2026-05-14): get_tribe_attendance_grid status column ambiguity
--
-- PM-reported PostgREST 400 right after migration 20260641000000 shipped.
-- Postgres log: "column reference \"status\" is ambiguous".
--
-- Root cause: 20260641 added events.status to grid_events CTE for the
-- ISO-week soft-cancel rule. The detractor_calc CTE has two nested subqueries
-- that joined cell_status × grid_events, both now exposing a `status` column
-- (cs.status = derived attendance status; ge.status = events.status). The
-- `SELECT status, ROW_NUMBER() ...` lines were unqualified → ambiguous.
--
-- Fix: alias as cs2.status AS cell_status / cs3.status AS cell_status and
-- propagate to outer WHERE sub.cell_status filters. Also aliased the
-- cancelled_events summary subquery (ge_c.status) for paranoia.

CREATE OR REPLACE FUNCTION public.get_tribe_attendance_grid(p_tribe_id integer, p_event_type text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_cycle_start date;
  v_tribe_initiative_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  v_caller_tribe_id := public.get_member_tribe(v_member_id);

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_member_id, 'manage_partner');

  IF NOT v_is_admin AND NOT v_is_stakeholder
     AND COALESCE(v_caller_tribe_id, -1) <> p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  WITH
  raw_events AS (
    SELECT e.id, e.date, e.title, e.title_i18n, e.type, e.status, i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number,
           EXTRACT(ISOYEAR FROM e.date)::int AS iso_year,
           EXTRACT(WEEK FROM e.date)::int AS iso_week
    FROM public.events e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff') OR e.type = 'lideranca')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.initiative_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
  ),
  cancelled_with_replan AS (
    SELECT re_cancelled.id AS cancelled_event_id
    FROM raw_events re_cancelled
    WHERE re_cancelled.status = 'cancelled'
      AND re_cancelled.tribe_id = p_tribe_id
      AND EXISTS (
        SELECT 1 FROM raw_events re_sibling
        WHERE re_sibling.id <> re_cancelled.id
          AND re_sibling.tribe_id = p_tribe_id
          AND re_sibling.status = 'scheduled'
          AND re_sibling.iso_year = re_cancelled.iso_year
          AND re_sibling.iso_week = re_cancelled.iso_week
      )
  ),
  grid_events AS (
    SELECT re.id, re.date, re.title, re.title_i18n, re.type, re.status, re.tribe_id,
           re.tribe_name, re.duration_minutes, re.week_number
    FROM raw_events re
    LEFT JOIN cancelled_with_replan cr ON cr.cancelled_event_id = re.id
    WHERE cr.cancelled_event_id IS NULL
    ORDER BY re.date
  ),
  event_row_counts AS (
    SELECT a.event_id, COUNT(*) AS row_count
    FROM public.attendance a
    WHERE a.event_id IN (SELECT id FROM grid_events)
    GROUP BY a.event_id
  ),
  grid_members AS (
    SELECT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations, m.member_status
    FROM public.members m
    WHERE m.member_status = 'active'
      AND (
        EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.person_id = m.person_id
            AND e.kind = 'volunteer' AND e.status = 'active'
            AND e.initiative_id = v_tribe_initiative_id
        )
        OR m.initiative_id = v_tribe_initiative_id
      )
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    UNION
    SELECT DISTINCT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations, m.member_status
    FROM public.members m
    JOIN public.attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
    WHERE m.member_status IN ('observer', 'alumni', 'inactive')
      AND ge.tribe_id = p_tribe_id
  ),
  eligibility AS (
    SELECT m.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        WHEN ge.type = 'tribo' AND ge.tribe_id = p_tribe_id THEN true
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        ELSE false
      END AS is_eligible
    FROM grid_members m CROSS JOIN grid_events ge
  ),
  cell_status AS (
    SELECT el.member_id, el.event_id, el.is_eligible,
      CASE
        WHEN ge.status = 'cancelled' THEN 'na'
        WHEN NOT el.is_eligible THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN CASE WHEN gm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL AND a.present = false THEN 'absent'
        WHEN COALESCE(erc.row_count, 0) = 0 THEN 'na'
        ELSE CASE
          WHEN gm.member_status != 'active' AND (gm.offboarded_at IS NULL OR gm.offboarded_at::date > ge.date) THEN 'absent'
          WHEN gm.member_status != 'active' AND gm.offboarded_at IS NOT NULL AND gm.offboarded_at::date <= ge.date THEN 'na'
          ELSE 'absent' END
      END AS status
    FROM eligibility el JOIN grid_events ge ON ge.id = el.event_id
    JOIN (SELECT id, member_status, offboarded_at FROM public.members) gm ON gm.id = el.member_id
    LEFT JOIN public.attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
    LEFT JOIN event_row_counts erc ON erc.event_id = ge.id
  ),
  member_stats AS (
    SELECT cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2) AS rate,
      ROUND(SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1) AS hours
    FROM cell_status cs JOIN grid_events ge ON ge.id = cs.event_id GROUP BY cs.member_id
  ),
  -- p160 hotfix: alias cell_status.status as cell_status to disambiguate from grid_events.status
  detractor_calc AS (
    SELECT cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT cs2.status AS cell_status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2 JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.cell_status = 'absent' AND sub.rn <= COALESCE((
        SELECT MIN(rn2) FROM (
          SELECT cs3.status AS cell_status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3 JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.cell_status = 'present'), 999)) AS consecutive_absences
    FROM cell_status cs GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM grid_members WHERE member_status = 'active'),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'perfect_attendance', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate >= 1.0),
      'below_50', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate < 0.5 AND ms.rate > 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'cancelled_events', (SELECT COUNT(*) FROM grid_events ge_c WHERE ge_c.status = 'cancelled'),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'title_i18n', ge.title_i18n, 'type', ge.type,
      'status', ge.status,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', (ge.tribe_id = p_tribe_id), 'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled')
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', am.id, 'name', am.name, 'chapter', am.chapter, 'member_status', am.member_status,
      'rate', COALESCE(ms.rate, 0), 'hours', COALESCE(ms.hours, 0),
      'eligible_count', COALESCE(ms.eligible_count, 0), 'present_count', COALESCE(ms.present_count, 0),
      'detractor_status', CASE
        WHEN am.member_status != 'active' THEN 'inactive'
        WHEN COALESCE(dc.consecutive_absences, 0) >= 3 THEN 'detractor'
        WHEN COALESCE(dc.consecutive_absences, 0) = 2 THEN 'at_risk'
        ELSE 'regular' END,
      'consecutive_absences', COALESCE(dc.consecutive_absences, 0),
      'attendance', (SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
        FROM cell_status cs WHERE cs.member_id = am.id)
    ) ORDER BY CASE WHEN am.member_status = 'active' THEN 0 ELSE 1 END, COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
      FROM grid_members am
      LEFT JOIN member_stats ms ON ms.member_id = am.id
      LEFT JOIN detractor_calc dc ON dc.member_id = am.id)
  ) INTO v_result;
  RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload schema';
