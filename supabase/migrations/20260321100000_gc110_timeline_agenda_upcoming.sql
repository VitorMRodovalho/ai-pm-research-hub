-- GC-110: Add agenda_text to upcoming events in get_tribe_events_timeline
-- (already present in past events section)
-- Full function recreated to include 'agenda_text' in upcoming jsonb_build_object

DROP FUNCTION IF EXISTS get_tribe_events_timeline(integer, integer, integer);
CREATE FUNCTION get_tribe_events_timeline(
  p_tribe_id integer,
  p_upcoming_limit integer DEFAULT 3,
  p_past_limit integer DEFAULT 5
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record; v_upcoming jsonb; v_past jsonb; v_next_recurring jsonb;
  v_tribe_member_count int;
  v_now_brt timestamptz := NOW() AT TIME ZONE 'America/Sao_Paulo';
  v_today_brt date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  SELECT count(*) INTO v_tribe_member_count FROM members
  WHERE tribe_id = p_tribe_id AND is_active = true AND operational_role NOT IN ('sponsor','chapter_liaison');

  -- Upcoming (now includes agenda_text)
  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'date', row_data->>'title'), '[]'::jsonb)
  INTO v_upcoming FROM (
    SELECT jsonb_build_object(
      'id', e.id, 'title', e.title, 'date', e.date, 'type', e.type, 'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_minutes, 60), 'meeting_link', e.meeting_link,
      'audience_level', e.audience_level, 'tribe_id', e.tribe_id,
      'is_tribe_event', (e.tribe_id = p_tribe_id),
      'agenda_text', e.agenda_text,
      'eligible_count', CASE
        WHEN e.type IN ('geral','kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN e.tribe_id = p_tribe_id THEN v_tribe_member_count ELSE 0 END
    ) as row_data FROM events e
    WHERE (e.tribe_id = p_tribe_id OR e.type IN ('geral','kickoff','lideranca'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
      AND (e.date > v_today_brt OR (e.date = v_today_brt AND (
        e.date::timestamp + COALESCE((SELECT tms.time_start FROM tribe_meeting_slots tms WHERE tms.tribe_id = e.tribe_id AND tms.is_active LIMIT 1), '19:30'::time)
        + (COALESCE(e.duration_minutes, 60) || ' minutes')::interval)::timestamp > v_now_brt::timestamp))
    ORDER BY e.date ASC LIMIT p_upcoming_limit
  ) sub;

  -- Past (unchanged)
  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'date') DESC), '[]'::jsonb)
  INTO v_past FROM (
    SELECT jsonb_build_object(
      'id', e.id, 'title', e.title, 'date', e.date, 'type', e.type, 'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_actual, e.duration_minutes, 60), 'tribe_id', e.tribe_id,
      'is_tribe_event', (e.tribe_id = p_tribe_id),
      'youtube_url', e.youtube_url, 'recording_url', e.recording_url, 'recording_type', e.recording_type,
      'has_recording', (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL),
      'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true),
      'eligible_count', CASE
        WHEN e.type IN ('geral','kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN e.tribe_id = p_tribe_id THEN v_tribe_member_count ELSE 0 END,
      'agenda_text', e.agenda_text, 'minutes_text', e.minutes_text
    ) as row_data FROM events e
    WHERE e.date <= v_today_brt AND (e.tribe_id = p_tribe_id OR e.type IN ('geral','kickoff'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
    ORDER BY e.date DESC LIMIT p_past_limit
  ) sub;

  SELECT jsonb_build_object(
    'day_of_week', tms.day_of_week, 'time_start', tms.time_start, 'time_end', tms.time_end,
    'day_name_pt', CASE tms.day_of_week WHEN 0 THEN 'Domingo' WHEN 1 THEN 'Segunda' WHEN 2 THEN 'Terça' WHEN 3 THEN 'Quarta' WHEN 4 THEN 'Quinta' WHEN 5 THEN 'Sexta' WHEN 6 THEN 'Sábado' END,
    'day_name_en', CASE tms.day_of_week WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday' WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday' WHEN 6 THEN 'Saturday' END
  ) INTO v_next_recurring FROM tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true LIMIT 1;

  RETURN jsonb_build_object('upcoming', v_upcoming, 'past', v_past, 'next_recurring', COALESCE(v_next_recurring, 'null'::jsonb), 'tribe_member_count', v_tribe_member_count);
END;
$$;

NOTIFY pgrst, 'reload schema';
