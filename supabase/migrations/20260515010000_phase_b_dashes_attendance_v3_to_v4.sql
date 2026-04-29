-- Phase B'' batch 11 (p79): convert mark_member_present + mark_member_excused
-- from V3 hardcoded role list (manager/deputy_manager/tribe_leader/superadmin)
-- to V4 can_by_member('manage_event'). Surfaced by rpc-v4-auth contract test.
--
-- V3 → V4 mapping:
-- - is_superadmin=true → implicit via can()
-- - operational_role IN ('manager','deputy_manager') → can_by_member('manage_event') org-scope
-- - operational_role = 'tribe_leader' + tribe scope check → can_by_member('manage_event') init-scope
-- - members.tribe_id (V3 column) ELIMINATED — V4 derives via engagements
--
-- Self-mark (caller marking own attendance) preserved in mark_member_present.
-- Excused requires authority (no self-excuse permitted, V3 behavior preserved).

CREATE OR REPLACE FUNCTION public.mark_member_present(
  p_event_id uuid,
  p_member_id uuid,
  p_present boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN
    NULL;  -- self-mark always allowed
  ELSIF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: can only mark own presence or requires manage_event permission';
  END IF;

  IF p_present THEN
    INSERT INTO public.attendance (event_id, member_id, present, excused)
    VALUES (p_event_id, p_member_id, true, false)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = true, excused = false, updated_at = now();
  ELSE
    INSERT INTO public.attendance (event_id, member_id, present, excused)
    VALUES (p_event_id, p_member_id, false, false)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = false, updated_at = now();
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.mark_member_present(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_member_present(uuid, uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_member_excused(
  p_event_id uuid,
  p_member_id uuid,
  p_excused boolean DEFAULT true,
  p_reason text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;

  IF p_excused THEN
    INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason)
    VALUES (p_event_id, p_member_id, false, true, p_reason)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = false,
      excused = true,
      excuse_reason = p_reason,
      updated_at = now();
  ELSE
    UPDATE public.attendance SET excused = false, excuse_reason = NULL, updated_at = now()
    WHERE event_id = p_event_id AND member_id = p_member_id;
  END IF;

  RETURN json_build_object('success', true, 'excused', p_excused);
END;
$$;

REVOKE ALL ON FUNCTION public.mark_member_excused(uuid, uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_member_excused(uuid, uuid, boolean, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
