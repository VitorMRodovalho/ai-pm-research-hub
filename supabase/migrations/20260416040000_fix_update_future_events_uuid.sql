-- ═══════════════════════════════════════════════════════════════
-- Fix: update_future_events_in_group v_rec_group text → uuid
-- Bug: recurrence_group column is uuid but variable was text
-- → "operator does not exist: uuid = text" → PostgREST 404
-- Rollback: DROP FUNCTION update_future_events_in_group(uuid,time,int,text,text,text);
-- ═══════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS update_future_events_in_group(uuid, time, int, text, text, text);

CREATE OR REPLACE FUNCTION public.update_future_events_in_group(
  p_event_id uuid,
  p_new_time_start time DEFAULT NULL,
  p_duration_minutes int DEFAULT NULL,
  p_meeting_link text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_visibility text DEFAULT NULL
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
  v_rec_group    uuid;
  v_updated_count int;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT tribe_id, date, recurrence_group
  INTO v_event_tribe, v_event_date, v_rec_group
  FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;
  IF v_rec_group IS NULL THEN RAISE EXCEPTION 'Event is not part of a recurring series'; END IF;

  IF NOT (
    v_is_admin = true
    OR v_caller_role IN ('manager', 'deputy_manager')
    OR (v_caller_role = 'tribe_leader' AND v_caller_tribe = v_event_tribe)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires admin, manager, or tribe leader of this tribe';
  END IF;

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
