-- ============================================================
-- drop_event_instance: opt-in force delete of attendance
-- Rationale: UX fix. Previous behavior raised "Remova presenças primeiro"
-- as a terminal error; caller had to remarcate (Fabrício 16/Abr).
-- Now a two-step flow: first call returns attendance_count error,
-- caller confirms, second call with p_force_delete_attendance=true
-- cleans attendance in transaction and drops the event.
--
-- V4 NOTE (drift): permission check still reads operational_role directly.
-- Refactor to can_by_member(p_member,'manage_event',...) tracked under
-- Eixo A (MCP × Tiers × V4) — not fixed here to keep this change small.
--
-- Rollback: DROP + recreate original single-arg version.
-- ============================================================

DROP FUNCTION IF EXISTS public.drop_event_instance(uuid);

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
  v_is_admin boolean;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_date date;
  v_event_title text;
  v_att_count int;
  v_blocker text;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT tribe_id, date, title
  INTO v_event_tribe, v_event_date, v_event_title
  FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF NOT (
    v_is_admin = true
    OR v_caller_role IN ('manager', 'deputy_manager')
    OR (v_caller_role = 'tribe_leader' AND v_caller_tribe = v_event_tribe)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires admin, manager, or tribe leader of this tribe';
  END IF;

  SELECT count(*) INTO v_att_count FROM public.attendance WHERE event_id = p_event_id;
  IF v_att_count > 0 AND NOT p_force_delete_attendance THEN
    RAISE EXCEPTION 'attendance_exists:%', v_att_count
      USING HINT = 'Evento possui ' || v_att_count || ' presença(s) registrada(s). Re-chame com p_force_delete_attendance=true para remover.';
  END IF;

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

NOTIFY pgrst, 'reload schema';
