-- WS-A1: gated accessor for a tribe's WhatsApp GROUP link.
-- Replaces the anon-key direct read of tribes.whatsapp_url (WS-A0 removed the
-- frontend reads). The link is served ONLY to an active, term-signed member of
-- that tribe (or a manage_platform admin). Pre-onboarding members are blocked.
-- Rollback: DROP FUNCTION IF EXISTS public.get_tribe_group_link(integer);
DROP FUNCTION IF EXISTS public.get_tribe_group_link(integer);

CREATE FUNCTION public.get_tribe_group_link(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid           uuid := auth.uid();
  v_member_id     uuid;
  v_is_active     boolean;
  v_member_status text;
  v_person_id     uuid;
  v_link          text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  SELECT id, is_active, member_status
    INTO v_member_id, v_is_active, v_member_status
    FROM public.members
   WHERE auth_id = v_uid
   LIMIT 1;

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  IF v_is_active IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'reason', 'inactive');
  END IF;

  -- V4 authority resolves on person_id (= persons.id), not auth.uid().
  SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;

  -- Fail closed if the member has no person row (member_is_pre_onboarding(NULL,...)
  -- would otherwise evaluate to false and silently skip the term gate).
  IF v_person_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  -- Governance invariant: tribe group link only after the volunteer term is signed.
  IF public.member_is_pre_onboarding(v_person_id, v_member_status) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'pre_onboarding');
  END IF;

  -- Must belong to the tribe (mirrors exec_tribe_dashboard) or be a platform admin.
  IF public.get_member_tribe(v_member_id) IS DISTINCT FROM p_tribe_id
     AND NOT public.can_by_member(v_member_id, 'manage_platform') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_in_tribe');
  END IF;

  SELECT whatsapp_url INTO v_link FROM public.tribes WHERE id = p_tribe_id;

  IF v_link IS NULL OR btrim(v_link) = '' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'no_link');
  END IF;

  RETURN jsonb_build_object('success', true, 'whatsapp_url', v_link);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_tribe_group_link(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_tribe_group_link(integer) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
