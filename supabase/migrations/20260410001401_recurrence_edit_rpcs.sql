-- ============================================================
-- Recurrence edit: upgrade get_events_with_attendance to return
-- recurrence_group + missing fields, and add update_future_events_in_group RPC
-- ============================================================

-- 1. Upgrade get_events_with_attendance — add recurrence_group, nature, time_start, notes, visibility, external_attendees
DROP FUNCTION IF EXISTS public.get_events_with_attendance(int, int);

CREATE OR REPLACE FUNCTION public.get_events_with_attendance(
  p_limit  int DEFAULT 40,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id               uuid,
  title            text,
  date             date,
  type             text,
  nature           text,
  duration_minutes int,
  time_start       time,
  meeting_link     text,
  youtube_url      text,
  is_recorded      boolean,
  audience_level   text,
  tribe_id         integer,
  attendee_count   bigint,
  agenda_text      text,
  agenda_url       text,
  minutes_text     text,
  minutes_url      text,
  recording_url    text,
  recording_type   text,
  notes            text,
  visibility       text,
  external_attendees text,
  recurrence_group text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    e.id,
    e.title,
    e.date,
    e.type,
    e.nature,
    e.duration_minutes,
    e.time_start,
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
    e.recording_type,
    e.notes,
    e.visibility,
    e.external_attendees,
    e.recurrence_group
  FROM public.events e
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
$$;

GRANT EXECUTE ON FUNCTION public.get_events_with_attendance(int, int) TO authenticated;

-- 2. New RPC: update_future_events_in_group
-- Updates fields on all events in the same recurrence_group where date >= the anchor event's date.
CREATE OR REPLACE FUNCTION public.update_future_events_in_group(
  p_event_id         uuid,
  p_new_time_start   time    DEFAULT NULL,
  p_duration_minutes int     DEFAULT NULL,
  p_meeting_link     text    DEFAULT NULL,
  p_notes            text    DEFAULT NULL,
  p_visibility       text    DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id    uuid;
  v_caller_role  text;
  v_is_admin     boolean;
  v_caller_tribe int;
  v_event_tribe  int;
  v_event_date   date;
  v_rec_group    text;
  v_updated_count int;
BEGIN
  -- Auth guard
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- Get anchor event info
  SELECT tribe_id, date, recurrence_group
  INTO v_event_tribe, v_event_date, v_rec_group
  FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;
  IF v_rec_group IS NULL THEN RAISE EXCEPTION 'Event is not part of a recurring series'; END IF;

  -- Permission check
  IF NOT (
    v_is_admin = true
    OR v_caller_role IN ('manager', 'deputy_manager')
    OR (v_caller_role = 'tribe_leader' AND v_caller_tribe = v_event_tribe)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires admin, manager, or tribe leader of this tribe';
  END IF;

  -- Update fields on all future events in the group (including the anchor event)
  WITH updated AS (
    UPDATE public.events
    SET
      time_start       = COALESCE(p_new_time_start, time_start),
      duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
      meeting_link     = COALESCE(p_meeting_link, meeting_link),
      notes            = COALESCE(p_notes, notes),
      visibility       = COALESCE(p_visibility, visibility),
      updated_at       = now()
    WHERE recurrence_group = v_rec_group
      AND date >= v_event_date
    RETURNING id
  )
  SELECT count(*) INTO v_updated_count FROM updated;

  RETURN json_build_object(
    'success', true,
    'recurrence_group', v_rec_group,
    'anchor_date', v_event_date,
    'updated_count', v_updated_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_future_events_in_group(uuid, time, int, text, text, text) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
