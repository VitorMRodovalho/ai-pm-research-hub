-- ============================================================
-- drop_event_instance & update_event_instance RPCs
-- Allows tribe leaders and admins to cancel or reschedule
-- individual event instances from recurring series.
-- ============================================================

-- ---- drop_event_instance ----
CREATE OR REPLACE FUNCTION public.drop_event_instance(p_event_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_is_admin boolean;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_date date;
  v_event_title text;
  v_att_count int;
  v_blocker text;
BEGIN
  -- Auth guard
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- Get event info
  SELECT tribe_id, date, title
  INTO v_event_tribe, v_event_date, v_event_title
  FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;

  -- Permission check
  IF NOT (
    v_is_admin = true
    OR v_caller_role IN ('manager', 'deputy_manager')
    OR (v_caller_role = 'tribe_leader' AND v_caller_tribe = v_event_tribe)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires admin, manager, or tribe leader of this tribe';
  END IF;

  -- Safety: reject if attendance exists
  SELECT count(*) INTO v_att_count FROM public.attendance WHERE event_id = p_event_id;
  IF v_att_count > 0 THEN
    RAISE EXCEPTION 'Evento possui % presenca(s) registrada(s). Remova as presencas primeiro.', v_att_count;
  END IF;

  -- Safety: reject if non-CASCADE dependencies exist
  v_blocker := '';
  IF EXISTS (SELECT 1 FROM public.meeting_artifacts WHERE event_id = p_event_id) THEN
    v_blocker := v_blocker || 'meeting_artifacts, ';
  END IF;
  IF EXISTS (SELECT 1 FROM public.cost_entries WHERE event_id = p_event_id) THEN
    v_blocker := v_blocker || 'cost_entries, ';
  END IF;
  IF EXISTS (SELECT 1 FROM public.cpmai_sessions WHERE event_id = p_event_id) THEN
    v_blocker := v_blocker || 'cpmai_sessions, ';
  END IF;
  IF EXISTS (SELECT 1 FROM public.webinars WHERE event_id = p_event_id) THEN
    v_blocker := v_blocker || 'webinars, ';
  END IF;
  IF EXISTS (SELECT 1 FROM public.event_showcases WHERE event_id = p_event_id) THEN
    v_blocker := v_blocker || 'event_showcases, ';
  END IF;
  IF EXISTS (SELECT 1 FROM public.meeting_action_items WHERE carried_to_event_id = p_event_id) THEN
    v_blocker := v_blocker || 'meeting_action_items (carried_to), ';
  END IF;

  IF v_blocker <> '' THEN
    v_blocker := rtrim(v_blocker, ', ');
    RAISE EXCEPTION 'Evento possui dependencias que impedem a exclusao: %', v_blocker;
  END IF;

  -- Delete (CASCADE handles: attendance, event_tag_assignments, event_audience_rules, event_invited_members, meeting_action_items)
  DELETE FROM public.events WHERE id = p_event_id;

  RETURN json_build_object(
    'success', true,
    'deleted_event_id', p_event_id,
    'deleted_date', v_event_date,
    'deleted_title', v_event_title
  );
END;
$$;

-- ---- update_event_instance ----
CREATE OR REPLACE FUNCTION public.update_event_instance(
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
  v_is_admin boolean;
  v_caller_tribe int;
  v_event_tribe int;
  v_updated text[] := '{}';
BEGIN
  -- Auth guard
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- Get event tribe
  SELECT tribe_id INTO v_event_tribe FROM public.events WHERE id = p_event_id;
  IF v_event_tribe IS NULL AND NOT EXISTS (SELECT 1 FROM public.events WHERE id = p_event_id) THEN
    RAISE EXCEPTION 'Event not found';
  END IF;

  -- Permission check
  IF NOT (
    v_is_admin = true
    OR v_caller_role IN ('manager', 'deputy_manager')
    OR (v_caller_role = 'tribe_leader' AND v_caller_tribe = v_event_tribe)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires admin, manager, or tribe leader of this tribe';
  END IF;

  -- Update fields if provided
  IF p_new_date IS NOT NULL THEN
    -- Check for conflict: same tribe, same date, different event
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

-- Grant access
GRANT EXECUTE ON FUNCTION public.drop_event_instance(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_event_instance(uuid, date, time, int, text, text, text) TO authenticated;
