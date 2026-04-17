-- ============================================================
-- A4.1 — Event RPCs: V4 auth via can_by_member (ADR-0011)
--
-- Pattern:
--   1. Primary gate: can_by_member(caller, 'manage_event') — engagement-derived
--   2. Scope refinement: tribe_leader constrained to own tribe
--   3. Legacy role list REMOVED — can() is the single source of truth
--
-- RPCs refactored:
--   - drop_event_instance(uuid, boolean)
--   - update_event_instance(uuid, date, time, int, text, text, text)
--   - update_future_events_in_group(uuid, time, int, text, text, text, text, text)
--
-- Rollback: migrations 20260409010000 + 20260423010000 + 20260424010000 + 20260423020000
-- ============================================================

-- ── drop_event_instance ──
DROP FUNCTION IF EXISTS public.drop_event_instance(uuid, boolean);

CREATE FUNCTION public.drop_event_instance(
  p_event_id uuid,
  p_force_delete_attendance boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_date date;
  v_event_title text;
  v_att_count int;
  v_blocker text;
BEGIN
  SELECT id, operational_role, tribe_id
  INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT tribe_id, date, title
  INTO v_event_tribe, v_event_date, v_event_title
  FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;

  -- V4 primary gate
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  -- Scope refinement: tribe_leader only for own tribe events
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  SELECT count(*) INTO v_att_count FROM public.attendance WHERE event_id = p_event_id;
  IF v_att_count > 0 AND NOT p_force_delete_attendance THEN
    RAISE EXCEPTION 'attendance_exists:%', v_att_count
      USING HINT = 'Evento possui ' || v_att_count || ' presença(s) registrada(s). Re-chame com p_force_delete_attendance=true para remover.';
  END IF;

  v_blocker := '';
  IF EXISTS (SELECT 1 FROM public.meeting_artifacts WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'meeting_artifacts, '; END IF;
  IF EXISTS (SELECT 1 FROM public.cost_entries WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'cost_entries, '; END IF;
  IF EXISTS (SELECT 1 FROM public.cpmai_sessions WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'cpmai_sessions, '; END IF;
  IF EXISTS (SELECT 1 FROM public.webinars WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'webinars, '; END IF;
  IF EXISTS (SELECT 1 FROM public.event_showcases WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'event_showcases, '; END IF;
  IF EXISTS (SELECT 1 FROM public.meeting_action_items WHERE carried_to_event_id = p_event_id) THEN v_blocker := v_blocker || 'meeting_action_items (carried_to), '; END IF;

  IF v_blocker <> '' THEN
    v_blocker := rtrim(v_blocker, ', ');
    RAISE EXCEPTION 'Evento possui dependencias que impedem a exclusao: %', v_blocker;
  END IF;

  IF v_att_count > 0 AND p_force_delete_attendance THEN
    DELETE FROM public.attendance WHERE event_id = p_event_id;
  END IF;

  DELETE FROM public.events WHERE id = p_event_id;

  RETURN json_build_object(
    'success', true,
    'deleted_event_id', p_event_id,
    'deleted_date', v_event_date,
    'deleted_title', v_event_title,
    'deleted_attendance_count', COALESCE(v_att_count, 0),
    'force_used', p_force_delete_attendance
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.drop_event_instance(uuid, boolean) TO authenticated;

-- ── update_event_instance ──
DROP FUNCTION IF EXISTS public.update_event_instance(uuid, date, time, int, text, text, text);

CREATE FUNCTION public.update_event_instance(
  p_event_id uuid,
  p_new_date date DEFAULT NULL,
  p_new_time_start time DEFAULT NULL,
  p_new_duration_minutes int DEFAULT NULL,
  p_meeting_link text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_agenda_text text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_updated text[] := '{}';
BEGIN
  SELECT id, operational_role, tribe_id
  INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT tribe_id INTO v_event_tribe FROM public.events WHERE id = p_event_id;
  IF v_event_tribe IS NULL AND NOT EXISTS (SELECT 1 FROM public.events WHERE id = p_event_id) THEN
    RAISE EXCEPTION 'Event not found';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  IF p_new_date IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.events
      WHERE tribe_id = v_event_tribe AND date = p_new_date AND id <> p_event_id
    ) THEN
      RAISE EXCEPTION 'Ja existe um evento desta tribo na data %', p_new_date;
    END IF;
    UPDATE public.events SET date = p_new_date, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'date');
  END IF;

  IF p_new_time_start IS NOT NULL THEN
    UPDATE public.events SET time_start = p_new_time_start, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'time_start');
  END IF;

  IF p_new_duration_minutes IS NOT NULL THEN
    UPDATE public.events SET duration_minutes = p_new_duration_minutes, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'duration_minutes');
  END IF;

  IF p_meeting_link IS NOT NULL THEN
    UPDATE public.events SET meeting_link = p_meeting_link, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'meeting_link');
  END IF;

  IF p_notes IS NOT NULL THEN
    UPDATE public.events SET notes = p_notes, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'notes');
  END IF;

  IF p_agenda_text IS NOT NULL THEN
    UPDATE public.events SET agenda_text = p_agenda_text, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'agenda_text');
  END IF;

  RETURN json_build_object(
    'success', true,
    'event_id', p_event_id,
    'updated_fields', to_json(v_updated)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_event_instance(uuid, date, time, int, text, text, text) TO authenticated;

-- ── update_future_events_in_group ──
DROP FUNCTION IF EXISTS public.update_future_events_in_group(uuid, time, int, text, text, text, text, text);

CREATE FUNCTION public.update_future_events_in_group(
  p_event_id uuid,
  p_new_time_start time DEFAULT NULL,
  p_duration_minutes int DEFAULT NULL,
  p_meeting_link text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_visibility text DEFAULT NULL,
  p_type text DEFAULT NULL,
  p_nature text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id     uuid;
  v_caller_role   text;
  v_caller_tribe  int;
  v_event_tribe   int;
  v_event_date    date;
  v_rec_group     uuid;
  v_updated_count int;
BEGIN
  SELECT id, operational_role, tribe_id
  INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT tribe_id, date, recurrence_group
  INTO v_event_tribe, v_event_date, v_rec_group
  FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;
  IF v_rec_group IS NULL THEN RAISE EXCEPTION 'Event is not part of a recurring series'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  IF p_type IS NOT NULL AND p_type NOT IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN
    RAISE EXCEPTION 'Invalid event type: %', p_type;
  END IF;
  IF p_nature IS NOT NULL AND p_nature NOT IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN
    RAISE EXCEPTION 'Invalid event nature: %', p_nature;
  END IF;

  WITH updated AS (
    UPDATE public.events SET
      time_start       = COALESCE(p_new_time_start, time_start),
      duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
      meeting_link     = COALESCE(p_meeting_link, meeting_link),
      notes            = COALESCE(p_notes, notes),
      visibility       = COALESCE(p_visibility, visibility),
      type             = COALESCE(p_type, type),
      nature           = COALESCE(p_nature, nature),
      updated_at       = now()
    WHERE recurrence_group = v_rec_group AND date >= v_event_date
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
