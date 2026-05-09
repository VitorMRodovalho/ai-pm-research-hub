-- p124 phase 4 — three event-listing RPCs now include `title_i18n` in their
-- jsonb response so the frontend can render localized event titles in:
--   - tribe attendance grid header row
--   - tribe page upcoming/past meetings timeline
--   - initiative dashboard upcoming/past meetings timeline
--
-- list_initiative_deliverables already returns SETOF tribe_deliverables, which
-- now automatically includes title_i18n + description_i18n columns added in
-- phase 2 (no body change needed).
--
-- get_tribe_attendance_grid body preserves p124 phase A fixes (event_row_counts
-- CTE for 0-row → 'na' + a.present branches in cell_status). The only addition
-- here is `title_i18n` in the events jsonb_agg.

CREATE OR REPLACE FUNCTION public.get_tribe_attendance_grid(p_tribe_id integer, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  grid_events AS (
    SELECT e.id, e.date, e.title, e.title_i18n, e.type, i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number
    FROM public.events e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff') OR e.type = 'lideranca')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.initiative_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    ORDER BY e.date
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
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id
          AND e.kind = 'volunteer' AND e.status = 'active'
          AND e.initiative_id = v_tribe_initiative_id
      )
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    UNION
    SELECT DISTINCT m.id, m.name,
           public.get_member_tribe(m.id) AS tribe_id,
           m.chapter, m.operational_role, m.designations, m.member_status
    FROM public.members m JOIN public.attendance a ON a.member_id = m.id JOIN grid_events ge ON ge.id = a.event_id
    WHERE m.member_status IN ('observer', 'alumni', 'inactive')
      AND (
        EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.person_id = m.person_id
            AND e.kind = 'volunteer' AND e.status = 'active'
            AND e.initiative_id = v_tribe_initiative_id
        )
        OR EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.person_id = m.person_id
            AND e.kind = 'volunteer'
            AND e.initiative_id = v_tribe_initiative_id
            AND e.status = 'revoked'
        )
      )
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
  detractor_calc AS (
    SELECT cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2 JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.status = 'absent' AND sub.rn <= COALESCE((
        SELECT MIN(rn2) FROM (
          SELECT status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3 JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.status = 'present'), 999)) AS consecutive_absences
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
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'title_i18n', ge.title_i18n, 'type', ge.type,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', (ge.tribe_id = p_tribe_id), 'is_future', (ge.date > CURRENT_DATE)
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
$function$;

CREATE OR REPLACE FUNCTION public.get_tribe_events_timeline(p_tribe_id integer, p_upcoming_limit integer DEFAULT 3, p_past_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_upcoming jsonb;
  v_past jsonb;
  v_next_recurring jsonb;
  v_tribe_member_count int;
  v_tribe_initiative_id uuid;
  v_now_brt timestamptz := NOW() AT TIME ZONE 'America/Sao_Paulo';
  v_today_brt date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  SELECT count(*) INTO v_tribe_member_count
  FROM public.members m
  WHERE m.is_active = true
    AND m.operational_role NOT IN ('sponsor', 'chapter_liaison')
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    );

  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'date', row_data->>'title'), '[]'::jsonb)
  INTO v_upcoming
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'title_i18n', e.title_i18n,
      'date', e.date,
      'type', e.type,
      'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_minutes, 60),
      'meeting_link', e.meeting_link,
      'audience_level', e.audience_level,
      'tribe_id', i.legacy_tribe_id,
      'is_tribe_event', (i.legacy_tribe_id = p_tribe_id),
      'agenda_text', e.agenda_text,
      'eligible_count', CASE
        WHEN e.type IN ('geral', 'kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN i.legacy_tribe_id = p_tribe_id THEN v_tribe_member_count
        ELSE 0
      END
    ) as row_data
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff', 'lideranca'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
      AND (
        e.date > v_today_brt
        OR (
          e.date = v_today_brt
          AND (
            e.date::timestamp
            + COALESCE(
                (SELECT tms.time_start FROM tribe_meeting_slots tms
                 WHERE tms.tribe_id = i.legacy_tribe_id AND tms.is_active LIMIT 1),
                '19:30'::time
              )
            + (COALESCE(e.duration_minutes, 60) || ' minutes')::interval
          )::timestamp > v_now_brt::timestamp
        )
      )
    ORDER BY e.date ASC
    LIMIT p_upcoming_limit
  ) sub;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'date') DESC), '[]'::jsonb)
  INTO v_past
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'title_i18n', e.title_i18n,
      'date', e.date,
      'type', e.type,
      'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_actual, e.duration_minutes, 60),
      'tribe_id', i.legacy_tribe_id,
      'is_tribe_event', (i.legacy_tribe_id = p_tribe_id),
      'youtube_url', e.youtube_url,
      'recording_url', e.recording_url,
      'recording_type', e.recording_type,
      'has_recording', (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL),
      'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true),
      'eligible_count', CASE
        WHEN e.type IN ('geral', 'kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN i.legacy_tribe_id = p_tribe_id THEN v_tribe_member_count
        ELSE 0
      END,
      'agenda_text', e.agenda_text,
      'minutes_text', e.minutes_text
    ) as row_data
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date <= v_today_brt
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
    ORDER BY e.date DESC
    LIMIT p_past_limit
  ) sub;

  SELECT jsonb_build_object(
    'day_of_week', tms.day_of_week,
    'time_start', tms.time_start,
    'time_end', tms.time_end,
    'day_name_pt', CASE tms.day_of_week
      WHEN 0 THEN 'Domingo' WHEN 1 THEN 'Segunda' WHEN 2 THEN 'Terça'
      WHEN 3 THEN 'Quarta' WHEN 4 THEN 'Quinta' WHEN 5 THEN 'Sexta' WHEN 6 THEN 'Sábado'
    END,
    'day_name_en', CASE tms.day_of_week
      WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday'
      WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday' WHEN 6 THEN 'Saturday'
    END
  ) INTO v_next_recurring
  FROM tribe_meeting_slots tms
  WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true
  LIMIT 1;

  RETURN jsonb_build_object(
    'upcoming', v_upcoming,
    'past', v_past,
    'next_recurring', COALESCE(v_next_recurring, 'null'::jsonb),
    'tribe_member_count', v_tribe_member_count
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_initiative_events_timeline(p_initiative_id uuid, p_upcoming_limit integer DEFAULT 5, p_past_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_upcoming jsonb;
  v_past jsonb;
  v_today date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_eligible int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT count(*) INTO v_eligible
  FROM engagements
  WHERE initiative_id = p_initiative_id AND status = 'active';

  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'date'), '[]'::jsonb)
  INTO v_upcoming
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'title_i18n', e.title_i18n,
      'date', e.date,
      'time_start', e.time_start,
      'type', e.type,
      'duration_minutes', COALESCE(e.duration_minutes, 60),
      'meeting_link', e.meeting_link,
      'agenda_text', e.agenda_text
    ) as row_data
    FROM events e
    WHERE e.initiative_id = p_initiative_id
      AND e.date >= v_today
    ORDER BY e.date ASC
    LIMIT p_upcoming_limit
  ) sub;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'date') DESC), '[]'::jsonb)
  INTO v_past
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'title_i18n', e.title_i18n,
      'date', e.date,
      'time_start', e.time_start,
      'type', e.type,
      'duration_minutes', COALESCE(e.duration_actual, e.duration_minutes, 60),
      'recording_url', e.recording_url,
      'youtube_url', e.youtube_url,
      'has_recording', (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL),
      'minutes_text', e.minutes_text,
      'has_minutes', (e.minutes_text IS NOT NULL AND e.minutes_text != ''),
      'agenda_text', e.agenda_text,
      'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true),
      'eligible_count', v_eligible
    ) as row_data
    FROM events e
    WHERE e.initiative_id = p_initiative_id
      AND e.date < v_today
    ORDER BY e.date DESC
    LIMIT p_past_limit
  ) sub;

  RETURN jsonb_build_object(
    'upcoming', v_upcoming,
    'past', v_past
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
