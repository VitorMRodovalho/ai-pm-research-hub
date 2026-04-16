-- ═══════════════════════════════════════════════════════════════
-- Add p_type + p_nature to update_future_events_in_group
-- Why: user reported that changing event type (geral→lideranca) on
-- recurring series only updated the anchor event. Type/nature are
-- shared across the series by governance rito.
-- Rollback: DROP FUNCTION update_future_events_in_group(uuid,time,int,text,text,text,text,text);
--           restore previous signature from 20260416040000_fix_update_future_events_uuid.sql
-- ═══════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.update_future_events_in_group(uuid, time, int, text, text, text);

CREATE OR REPLACE FUNCTION public.update_future_events_in_group(
  p_event_id         uuid,
  p_new_time_start   time    DEFAULT NULL,
  p_duration_minutes int     DEFAULT NULL,
  p_meeting_link     text    DEFAULT NULL,
  p_notes            text    DEFAULT NULL,
  p_visibility       text    DEFAULT NULL,
  p_type             text    DEFAULT NULL,
  p_nature           text    DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id     uuid;
  v_caller_role   text;
  v_is_admin      boolean;
  v_caller_tribe  int;
  v_event_tribe   int;
  v_event_date    date;
  v_rec_group     uuid;
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

  IF p_type IS NOT NULL AND p_type NOT IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms', 'parceria', 'entrevista', '1on1', 'evento_externo', 'webinar') THEN
    RAISE EXCEPTION 'Invalid event type: %', p_type;
  END IF;
  IF p_nature IS NOT NULL AND p_nature NOT IN ('kickoff', 'recorrente', 'avulsa', 'encerramento', 'workshop', 'entrevista_selecao') THEN
    RAISE EXCEPTION 'Invalid event nature: %', p_nature;
  END IF;

  WITH updated AS (
    UPDATE public.events
    SET
      time_start       = COALESCE(p_new_time_start, time_start),
      duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
      meeting_link     = COALESCE(p_meeting_link, meeting_link),
      notes            = COALESCE(p_notes, notes),
      visibility       = COALESCE(p_visibility, visibility),
      type             = COALESCE(p_type, type),
      nature           = COALESCE(p_nature, nature),
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

GRANT EXECUTE ON FUNCTION public.update_future_events_in_group(uuid, time, int, text, text, text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
