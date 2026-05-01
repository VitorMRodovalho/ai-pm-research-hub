-- ============================================================================
-- p87 Bug Ana Carla — bulk_mark_excused + override_existing param
-- ============================================================================
-- Trigger: tribe_leader Ana Carla report mobile bug — bulk excused silently
-- skipped events com attendance já marcada (filter NOT EXISTS excused=false).
-- Fix: opt-in override via p_override_existing param. Default false (preserves
-- current safe behavior).
--
-- Returns JSON now includes events_skipped count + override_used flag para
-- frontend warn user quando 0 events_marked + skipped > 0.
--
-- Drop+Create necessário (param novo arity).
-- ============================================================================

DROP FUNCTION IF EXISTS public.bulk_mark_excused(uuid, date, date, text);

CREATE OR REPLACE FUNCTION public.bulk_mark_excused(
  p_member_id uuid,
  p_date_from date,
  p_date_to date,
  p_reason text DEFAULT NULL,
  p_override_existing boolean DEFAULT false
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid; v_caller_role text; v_is_admin boolean; v_caller_tribe int;
  v_member_tribe int;
  v_count int := 0;
  v_skipped int := 0;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT tribe_id INTO v_member_tribe FROM public.members WHERE id = p_member_id;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_member_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage members of own tribe';
  END IF;

  IF NOT p_override_existing THEN
    SELECT COUNT(*) INTO v_skipped
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= p_date_from AND e.date <= p_date_to
      AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms')
      AND (
        e.type IN ('geral', 'kickoff')
        OR (e.type = 'tribo' AND i.legacy_tribe_id = v_member_tribe)
        OR (e.type = 'lideranca' AND EXISTS (SELECT 1 FROM members m WHERE m.id = p_member_id AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')))
      )
      AND EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.excused = false);
  END IF;

  INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason)
  SELECT e.id, p_member_id, false, true, p_reason
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.date >= p_date_from AND e.date <= p_date_to
    AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms')
    AND (
      e.type IN ('geral', 'kickoff')
      OR (e.type = 'tribo' AND i.legacy_tribe_id = v_member_tribe)
      OR (e.type = 'lideranca' AND EXISTS (SELECT 1 FROM members m WHERE m.id = p_member_id AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')))
    )
    AND (
      p_override_existing
      OR NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.excused = false)
    )
  ON CONFLICT (event_id, member_id) DO UPDATE SET
    present = false,
    excused = true,
    excuse_reason = p_reason,
    updated_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN json_build_object(
    'success', true,
    'events_marked', v_count,
    'events_skipped', v_skipped,
    'date_from', p_date_from,
    'date_to', p_date_to,
    'override_used', p_override_existing
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
