-- Add agenda/minutes/recording columns to get_events_with_attendance RPC
-- so the attendance page can display artifact badges on event cards.

CREATE OR REPLACE FUNCTION public.get_events_with_attendance(
  p_limit  int DEFAULT 40,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id               uuid,
  title            text,
  date             date,
  type             text,
  duration_minutes int,
  meeting_link     text,
  youtube_url      text,
  is_recorded      boolean,
  audience_level   text,
  tribe_id         uuid,
  attendee_count   bigint,
  agenda_text      text,
  agenda_url       text,
  minutes_text     text,
  minutes_url      text,
  recording_url    text,
  recording_type   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    e.id,
    e.title,
    e.date,
    e.type,
    e.duration_minutes,
    e.meeting_link,
    e.youtube_url,
    e.is_recorded,
    e.audience_level,
    e.tribe_id,
    (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id) AS attendee_count,
    e.agenda_text,
    e.agenda_url,
    e.minutes_text,
    e.minutes_url,
    e.recording_url,
    e.recording_type
  FROM public.events e
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
$$;
