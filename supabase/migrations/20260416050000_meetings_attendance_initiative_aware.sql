-- ═══════════════════════════════════════════════════════════════
-- Fix: Meetings + Attendance pages show initiative context
-- Before: initiative events lumped into "Geral (sem tribo)"
-- After: grouped by initiative name, badge on event cards
-- Rollback: restore original list_meetings_with_notes,
--           get_meeting_notes_compliance, get_events_with_attendance
-- ═══════════════════════════════════════════════════════════════

-- 1. list_meetings_with_notes — add initiative_id + initiative_name
DROP FUNCTION IF EXISTS list_meetings_with_notes(integer, text, text, boolean, integer, integer);

CREATE OR REPLACE FUNCTION public.list_meetings_with_notes(
  p_tribe_id integer DEFAULT NULL,
  p_type text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_include_empty boolean DEFAULT false,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_total int;
  v_rows jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT count(*) INTO v_total
  FROM events e
  WHERE (p_tribe_id IS NULL OR e.tribe_id = p_tribe_id)
    AND (p_type IS NULL OR e.type = p_type)
    AND (p_include_empty OR (e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20))
    AND (
      p_search IS NULL OR p_search = ''
      OR to_tsvector('portuguese',
           coalesce(e.title, '') || ' ' ||
           coalesce(e.minutes_text, '') || ' ' ||
           coalesce(e.agenda_text, '')
         ) @@ plainto_tsquery('portuguese', p_search)
    );

  SELECT coalesce(jsonb_agg(row_to_json(sub) ORDER BY sub.date DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      e.id, e.title, e.date, e.type, e.tribe_id,
      t.name as tribe_name,
      e.initiative_id,
      i.title as initiative_name,
      e.youtube_url, e.recording_url,
      e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20 as has_minutes,
      length(coalesce(e.minutes_text, '')) as minutes_length,
      e.agenda_text IS NOT NULL as has_agenda,
      (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true) as attendee_count
    FROM events e
    LEFT JOIN tribes t ON t.id = e.tribe_id
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE (p_tribe_id IS NULL OR e.tribe_id = p_tribe_id)
      AND (p_type IS NULL OR e.type = p_type)
      AND (p_include_empty OR (e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20))
      AND (
        p_search IS NULL OR p_search = ''
        OR to_tsvector('portuguese',
             coalesce(e.title, '') || ' ' ||
             coalesce(e.minutes_text, '') || ' ' ||
             coalesce(e.agenda_text, '')
           ) @@ plainto_tsquery('portuguese', p_search)
      )
    ORDER BY e.date DESC
    LIMIT p_limit
    OFFSET p_offset
  ) sub;

  RETURN jsonb_build_object(
    'meetings', v_rows,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_meetings_with_notes(integer, text, text, boolean, integer, integer) TO authenticated;


-- 2. get_meeting_notes_compliance — group by tribe OR initiative
DROP FUNCTION IF EXISTS get_meeting_notes_compliance();

CREATE OR REPLACE FUNCTION public.get_meeting_notes_compliance()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  WITH stats AS (
    SELECT
      e.tribe_id AS t_id,
      COALESCE(t.name, i.title, 'Gerais/sem tribo') as group_name,
      count(*) FILTER (WHERE e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL) as recorded,
      count(*) FILTER (
        WHERE (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL)
          AND e.minutes_text IS NOT NULL
          AND length(trim(e.minutes_text)) >= 20
          AND lower(trim(e.minutes_text)) NOT IN ('teste', 'teste teste', 'test', 'placeholder', '-')
      ) as with_minutes
    FROM events e
    LEFT JOIN tribes t ON t.id = e.tribe_id
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date <= current_date
    GROUP BY e.tribe_id, COALESCE(t.name, i.title, 'Gerais/sem tribo')
  )
  SELECT jsonb_build_object(
    'by_tribe', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'tribe_id', s.t_id,
          'tribe_name', s.group_name,
          'recorded', s.recorded,
          'with_minutes', s.with_minutes,
          'pct', CASE WHEN s.recorded > 0 THEN round(100.0 * s.with_minutes / s.recorded) ELSE 100 END
        ) ORDER BY CASE WHEN s.recorded > 0 THEN round(100.0 * s.with_minutes / s.recorded) ELSE 100 END ASC
      ) FROM stats s WHERE s.recorded > 0
    ), '[]'::jsonb),
    'total_recorded', (SELECT sum(recorded) FROM stats),
    'total_with_minutes', (SELECT sum(with_minutes) FROM stats),
    'overall_pct', CASE
      WHEN (SELECT sum(recorded) FROM stats) > 0
      THEN round(100.0 * (SELECT sum(with_minutes) FROM stats) / (SELECT sum(recorded) FROM stats))
      ELSE 100
    END
  ) INTO v_result;
  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_meeting_notes_compliance() TO authenticated;


-- 3. get_events_with_attendance — add initiative_id + initiative_name
DROP FUNCTION IF EXISTS get_events_with_attendance(int, int);

CREATE OR REPLACE FUNCTION public.get_events_with_attendance(
  p_limit int DEFAULT 500,
  p_offset int DEFAULT 0
)
RETURNS TABLE(
  id uuid, title text, date date, type text, nature text,
  duration_minutes int, time_start time, meeting_link text,
  youtube_url text, is_recorded boolean, audience_level text,
  tribe_id int, attendee_count bigint,
  agenda_text text, agenda_url text,
  minutes_text text, minutes_url text,
  recording_url text, recording_type text,
  notes text, visibility text,
  external_attendees text[], recurrence_group uuid,
  initiative_id uuid, initiative_name text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    e.id, e.title, e.date, e.type, e.nature,
    e.duration_minutes, e.time_start, e.meeting_link,
    e.youtube_url, e.is_recorded, e.audience_level,
    e.tribe_id,
    (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id) AS attendee_count,
    e.agenda_text, e.agenda_url,
    e.minutes_text, e.minutes_url,
    e.recording_url, e.recording_type,
    e.notes, e.visibility,
    e.external_attendees, e.recurrence_group,
    e.initiative_id,
    i.title AS initiative_name
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
$$;

GRANT EXECUTE ON FUNCTION public.get_events_with_attendance(int, int) TO authenticated;
