-- p160 (2026-05-14): cancel_event_occurrence RPC — soft-cancel for one event
--
-- Companion to events.status column (migration 20260639000000). Differs from
-- drop_event_instance:
--  • drop_event_instance: hard-deletes events row + attendance. For admins
--    removing genuinely-wrong-data (duplicates, test rows). Loses history.
--  • cancel_event_occurrence: sets status='cancelled' + audit trail. Keeps
--    row + attendance. Visible in grid per ISO-week rule.
--
-- Frontend default for tribe leaders: cancel_event_occurrence.
-- Admin override (is_superadmin or manager): can still call drop_event_instance.

CREATE OR REPLACE FUNCTION public.cancel_event_occurrence(
  p_event_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event record;
  v_event_tribe int;
BEGIN
  SELECT id, operational_role, tribe_id
    INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT e.id, e.title, e.date, e.status, e.initiative_id, i.legacy_tribe_id
    INTO v_event
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;

  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Event not found');
  END IF;

  v_event_tribe := v_event.legacy_tribe_id;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;

  -- Tribe-leader scope: own tribe only
  IF v_caller_role = 'tribe_leader'
     AND v_event_tribe IS NOT NULL
     AND v_event_tribe IS DISTINCT FROM v_caller_tribe THEN
    RETURN jsonb_build_object('success', false, 'error', 'tribe_leader can only cancel own-tribe events');
  END IF;

  -- Idempotent: already cancelled
  IF v_event.status = 'cancelled' THEN
    RETURN jsonb_build_object('success', true, 'event_id', v_event.id, 'already_cancelled', true);
  END IF;

  UPDATE public.events SET
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = v_caller_id,
    cancellation_reason = p_reason,
    updated_at = now()
  WHERE id = p_event_id;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', v_event.id,
    'title', v_event.title,
    'date', v_event.date,
    'cancelled_by', v_caller_id,
    'reason', p_reason
  );
END;
$$;

-- Companion: uncancel (in case PM/leader makes a mistake)
CREATE OR REPLACE FUNCTION public.uncancel_event_occurrence(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT i.legacy_tribe_id INTO v_event_tribe
  FROM public.events e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_event_tribe IS NOT NULL
     AND v_event_tribe IS DISTINCT FROM v_caller_tribe THEN
    RETURN jsonb_build_object('success', false, 'error', 'tribe_leader scope');
  END IF;

  UPDATE public.events SET
    status = 'scheduled',
    cancelled_at = NULL, cancelled_by = NULL, cancellation_reason = NULL,
    updated_at = now()
  WHERE id = p_event_id AND status = 'cancelled';

  RETURN jsonb_build_object('success', true, 'event_id', p_event_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_event_occurrence(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.uncancel_event_occurrence(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
