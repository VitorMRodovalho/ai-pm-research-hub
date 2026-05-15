-- p160 (2026-05-14): add events.status to get_events_with_attendance return
-- so frontend can render cancelled badge / strikethrough.
-- DROP+CREATE because signature changes (new column in RETURNS TABLE).

DROP FUNCTION IF EXISTS public.get_events_with_attendance(integer, integer);

CREATE OR REPLACE FUNCTION public.get_events_with_attendance(p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
RETURNS TABLE(
  id uuid, title text, date date, type text, nature text,
  duration_minutes integer, time_start time without time zone,
  meeting_link text, youtube_url text, is_recorded boolean, audience_level text,
  tribe_id integer, attendee_count bigint,
  agenda_text text, agenda_url text, minutes_text text, minutes_url text,
  recording_url text, recording_type text, notes text, visibility text,
  external_attendees text[], recurrence_group uuid, initiative_id uuid, initiative_name text,
  status text, cancelled_at timestamptz, cancellation_reason text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    e.id, e.title, e.date, e.type, e.nature,
    e.duration_minutes, e.time_start, e.meeting_link,
    e.youtube_url, e.is_recorded, e.audience_level,
    i.legacy_tribe_id AS tribe_id,
    (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id) AS attendee_count,
    e.agenda_text, e.agenda_url,
    e.minutes_text, e.minutes_url,
    e.recording_url, e.recording_type,
    e.notes, e.visibility,
    e.external_attendees, e.recurrence_group,
    e.initiative_id,
    i.title AS initiative_name,
    e.status, e.cancelled_at, e.cancellation_reason
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
$$;

GRANT EXECUTE ON FUNCTION public.get_events_with_attendance(integer, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
