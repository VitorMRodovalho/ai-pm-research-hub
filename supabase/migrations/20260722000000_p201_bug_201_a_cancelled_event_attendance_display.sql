-- ============================================================================
-- p201 BUG-201.A — cancelled events show all participants as 'absent'
--
-- PM-reported 2026-05-19: "Talentos & Upskilling — Reunião Semanal 04 May 2026
-- · CANCELADA esta cancelada mas todos os participantes estao constando falta
-- ao invés de mostrar como cancelada".
--
-- Context:
-- p199-c (commit 5b723dd3) added trigger trg_cleanup_attendance_on_event_cancel
-- that DELETEs attendance rows when event.status transitions to 'cancelled'.
-- This trigger ran for the Talentos & Upskilling event (id 5e42678e-2dfd-
-- 4f99-a183-a467c207a011, cancelled 2026-05-19 16:09:31). However, 2 attendance
-- RPCs (`get_attendance_grid` admin global grid; `get_initiative_attendance_
-- grid` no-legacy-tribe fallback path) and `get_tribe_event_roster` (roster
-- modal) do NOT handle cancelled events:
--   - Grid `cell_status` CASE has no 'cancelled' branch → falls through to
--     'absent' default (since attendance rows were just deleted).
--   - Roster row `present` defaults to false via COALESCE when no row exists.
-- Reference correct pattern: `get_tribe_attendance_grid` already short-
-- circuits with `WHEN ge.status = 'cancelled' THEN 'na'` as first branch.
--
-- This migration:
-- 1. `get_attendance_grid` — adds e.status to grid_events; adds cancelled→'na'
--    first branch in cell_status; emits is_cancelled in events output.
-- 2. `get_initiative_attendance_grid` — same fix in the `v_tribe_id IS NULL`
--    fallback path (delegates path via get_tribe_attendance_grid already OK).
-- 3. `get_tribe_event_roster` — adds `event_cancelled` per-row so UI can
--    render cancelled rosters without misleading 'absent' state.
--
-- Companion FE patch: src/pages/attendance.astro openRoster() detects
-- event_cancelled and renders 🚫 instead of toggle/❌; counter shows
-- "Cancelada — sem registro de presença" instead of "0/N presentes";
-- bulk-mark buttons hidden. New i18n key: attendance.roster.cancelled.
--
-- Sanity post-apply:
--   Talentos & Upskilling event id=5e42678e-2dfd-4f99-a183-a467c207a011
--   appears in grid with all cells 'na'; roster returns each row with
--   event_cancelled=true.
--
-- ROLLBACK: restore each function body to its prior state. Pre-apply bodies
-- were captured via pg_get_functiondef in the p201 session.
-- ============================================================================

-- ──────────────────────────────────────────────────────────────────────────
-- 1) get_attendance_grid — admin global grid (used by /attendance AttendanceGridTab)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_attendance_grid(p_tribe_id integer DEFAULT NULL::integer, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  v_caller_tribe_id := public.get_member_tribe(v_member_id);

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_member_id, 'manage_partner');

  IF NOT v_is_admin AND NOT v_is_stakeholder THEN
    IF v_caller_tribe_id IS NOT NULL THEN
      p_tribe_id := v_caller_tribe_id;
    ELSE
      RETURN jsonb_build_object('error', 'No tribe assigned');
    END IF;
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type, e.nature, e.status,
           i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date) AS week_number
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms', 'evento_externo')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.initiative_id IS NULL OR e.type = 'tribo')
    ORDER BY e.date
  ),
  active_members AS MATERIALIZED (
    SELECT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations
    FROM public.members m
    WHERE m.is_active = true
      AND m.operational_role NOT IN ('guest', 'none')
  ),
  active_members_scoped AS (
    SELECT * FROM active_members
    WHERE p_tribe_id IS NULL OR tribe_id = p_tribe_id
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
    FROM active_members_scoped m CROSS JOIN grid_events ge
  ),
  cell_status AS (
    SELECT el.member_id, el.event_id, el.is_eligible,
      CASE
        WHEN ge.status = 'cancelled' THEN 'na'
        WHEN NOT el.is_eligible THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN 'scheduled'
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL THEN 'present'
        ELSE 'absent'
      END AS status
    FROM eligibility el JOIN grid_events ge ON ge.id = el.event_id
    LEFT JOIN public.attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
  ),
  member_stats AS (
    SELECT cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2) AS rate,
      ROUND(SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1) AS hours
    FROM cell_status cs JOIN grid_events ge ON ge.id = cs.event_id
    GROUP BY cs.member_id
  ),
  detractor_calc AS (
    SELECT cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2 JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.status = 'absent' AND sub.rn <= (
        SELECT MIN(rn2) FROM (
          SELECT status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3 JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.status = 'present'
      )) AS consecutive_absences
    FROM cell_status cs GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM active_members_scoped),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms), 0),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc WHERE consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc WHERE consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type, 'nature', ge.nature,
      'status', ge.status,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled')
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'tribes', (SELECT COALESCE(jsonb_agg(tribe_row ORDER BY tribe_row->>'tribe_name'), '[]'::jsonb) FROM (
      SELECT jsonb_build_object(
        'tribe_id', t.id, 'tribe_name', t.name,
        'leader_name', COALESCE((
          SELECT m2.name FROM public.members m2
          WHERE m2.operational_role = 'tribe_leader'
            AND public.get_member_tribe(m2.id) = t.id
          LIMIT 1
        ), '—'),
        'avg_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN active_members_scoped am ON am.id = ms.member_id WHERE am.tribe_id = t.id), 0),
        'member_count', (SELECT COUNT(*) FROM active_members_scoped am WHERE am.tribe_id = t.id),
        'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', am.id, 'name', am.name, 'chapter', am.chapter,
          'rate', COALESCE(ms.rate, 0), 'hours', COALESCE(ms.hours, 0),
          'eligible_count', COALESCE(ms.eligible_count, 0), 'present_count', COALESCE(ms.present_count, 0),
          'detractor_status', CASE
            WHEN COALESCE(dc.consecutive_absences, 0) >= 3 THEN 'detractor'
            WHEN COALESCE(dc.consecutive_absences, 0) = 2 THEN 'at_risk'
            ELSE 'regular' END,
          'consecutive_absences', COALESCE(dc.consecutive_absences, 0),
          'attendance', (SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
            FROM cell_status cs WHERE cs.member_id = am.id)
        ) ORDER BY COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
          FROM active_members_scoped am
          LEFT JOIN member_stats ms ON ms.member_id = am.id
          LEFT JOIN detractor_calc dc ON dc.member_id = am.id
          WHERE am.tribe_id = t.id)
      ) AS tribe_row
      FROM public.tribes t WHERE t.is_active = true AND (p_tribe_id IS NULL OR t.id = p_tribe_id)
    ) sub)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- ──────────────────────────────────────────────────────────────────────────
-- 2) get_initiative_attendance_grid — fallback path (no legacy_tribe_id)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_initiative_attendance_grid(p_initiative_id uuid, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_attendance_grid(v_tribe_id, p_event_type);
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type, e.status,
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
        WHEN ge.status = 'cancelled' THEN 'na'
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
      'cancelled_events', (SELECT COUNT(*) FROM grid_events WHERE status = 'cancelled'),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type,
      'status', ge.status,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', false,
      'is_future', (ge.date > CURRENT_DATE),
      'is_cancelled', (ge.status = 'cancelled')
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
$function$;

-- ──────────────────────────────────────────────────────────────────────────
-- 3) get_tribe_event_roster — adds event_cancelled per-row
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_tribe_event_roster(p_event_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller RECORD;
  v_event  RECORD;
  v_event_tribe_id int;
  v_result JSON;
  v_has_attendance boolean;
  v_event_cancelled boolean;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);
  v_event_cancelled := (v_event.status = 'cancelled');

  -- Access control: V4 baseline manage_event + residual tribe scope for tribe_leader
  IF NOT public.can_by_member(v_caller.id, 'manage_event') THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;
  IF v_caller.operational_role = 'tribe_leader'
     AND v_event_tribe_id IS NOT NULL
     AND v_event_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;

  SELECT EXISTS(SELECT 1 FROM attendance WHERE event_id = p_event_id) INTO v_has_attendance;

  SELECT json_agg(row_to_json(q) ORDER BY q.name) INTO v_result
  FROM (
    SELECT
      m.id, m.name, m.photo_url, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations) AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter,
      COALESCE(a.present, false) AS present,
      a.corrected_by IS NOT NULL AS was_corrected,
      v_event_cancelled AS event_cancelled
    FROM public.members m
    LEFT JOIN public.attendance a
      ON a.event_id = p_event_id AND a.member_id = m.id
    WHERE
      m.operational_role != 'guest'
      AND (
        CASE WHEN v_event.initiative_id IS NOT NULL AND v_event_tribe_id IS NULL THEN
          m.id IN (
            SELECT mm.id FROM members mm
            JOIN engagements eng ON eng.person_id = mm.person_id
            WHERE eng.initiative_id = v_event.initiative_id AND eng.status = 'active'
          )
          OR a.id IS NOT NULL

        WHEN v_event.type IN ('1on1', 'entrevista', 'parceria') AND v_has_attendance THEN
          a.id IS NOT NULL

        ELSE
          CASE COALESCE(v_event.audience_level, 'all')
            WHEN 'tribe' THEN
              m.current_cycle_active = true
              AND m.tribe_id = v_event_tribe_id
            WHEN 'leadership' THEN
              m.operational_role IN ('manager')
              OR 'sponsor'    = ANY(COALESCE(m.designations, '{}'))
              OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
              OR 'founder'    = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp'      = ANY(COALESCE(m.designations, '{}'))
            WHEN 'curators' THEN
              'curator' = ANY(COALESCE(m.designations, '{}'))
            ELSE
              m.current_cycle_active = true
              OR m.operational_role = 'manager'
              OR 'sponsor'    = ANY(COALESCE(m.designations, '{}'))
              OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
              OR 'curator'    = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp'      = ANY(COALESCE(m.designations, '{}'))
          END
        END
      )
  ) q;

  RETURN COALESCE(v_result, '[]'::json);
END;
$function$;

NOTIFY pgrst, 'reload schema';
