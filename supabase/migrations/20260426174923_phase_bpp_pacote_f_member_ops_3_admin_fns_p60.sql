-- Phase B'' Pacote F (p60) — 3 admin member-ops fns V3→V4 manage_member
-- All currently SECDEF with V3 gate (members.is_superadmin ONLY — tighter
-- than Pacote E's broad gate). V4 manage_member grant set is identical
-- (2 members = Vitor + Fabricio via superadmin override).
--
-- Privilege expansion safety check (verified pre-apply):
--   V3 superadmin-only: 2 members
--   V4 manage_member: 2 (same)
--   would_gain: [] / would_lose: []
--   ZERO expansion — clean conversion.
--
-- Discovered post-Pacote-E by querying for admin_* fns still using
-- get_my_member_record() V3 gate. 7 surfaced; 4 deferred (board lifecycle
-- with tribe_leader scope clause + list ops with tribe_leader read access)
-- pending PM ratify on V4 scope='tribe' or new actions. 3 here are clean.

-- ============================================================
-- 1. admin_change_tribe_leader → manage_member
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_change_tribe_leader(integer, uuid, text);
CREATE OR REPLACE FUNCTION public.admin_change_tribe_leader(
  p_tribe_id integer,
  p_new_leader_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
  v_tribe record;
  v_old_leader record;
  v_new_leader record;
  v_cycle record;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'permission_denied: manage_member required';
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found: %', p_tribe_id; END IF;

  SELECT * INTO v_new_leader FROM public.members WHERE id = p_new_leader_id;
  IF v_new_leader IS NULL THEN RAISE EXCEPTION 'New leader member not found: %', p_new_leader_id; END IF;

  SELECT * INTO v_cycle FROM public.cycles WHERE is_current = true LIMIT 1;

  IF v_tribe.leader_member_id IS NOT NULL THEN
    SELECT * INTO v_old_leader FROM public.members WHERE id = v_tribe.leader_member_id;

    IF v_old_leader IS NOT NULL THEN
      INSERT INTO public.member_cycle_history (
        member_id, cycle_code, cycle_label, cycle_start, cycle_end,
        operational_role, designations, tribe_id, tribe_name,
        chapter, is_active, member_name_snapshot, notes
      ) VALUES (
        v_old_leader.id,
        COALESCE(v_cycle.cycle_code, 'cycle_3'), COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
        COALESCE(v_cycle.cycle_start, now()::text), now()::text,
        v_old_leader.operational_role, v_old_leader.designations,
        v_old_leader.tribe_id, v_tribe.name,
        v_old_leader.chapter, true, v_old_leader.name,
        'LEADER_REMOVED: Replaced by ' || v_new_leader.name || '. Reason: ' || p_reason || '. By: ' || v_caller_name
      );

      UPDATE public.members SET operational_role = 'researcher'
      WHERE id = v_old_leader.id AND operational_role = 'tribe_leader';

      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (v_caller_id, 'role.demoted', 'member', v_old_leader.id,
        jsonb_build_object('old_role', 'tribe_leader', 'new_role', 'researcher',
          'tribe_id', p_tribe_id, 'tribe_name', v_tribe.name, 'reason', p_reason));
    END IF;
  END IF;

  UPDATE public.members SET operational_role = 'tribe_leader', tribe_id = p_tribe_id
  WHERE id = p_new_leader_id;

  UPDATE public.tribes SET leader_member_id = p_new_leader_id WHERE id = p_tribe_id;

  INSERT INTO public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) VALUES (
    p_new_leader_id,
    COALESCE(v_cycle.cycle_code, 'cycle_3'), COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
    COALESCE(v_cycle.cycle_start, now()::text), NULL,
    'tribe_leader', v_new_leader.designations, p_tribe_id, v_tribe.name,
    v_new_leader.chapter, true, v_new_leader.name,
    'LEADER_ASSIGNED: Promoted to leader of ' || v_tribe.name || '. Reason: ' || p_reason || '. By: ' || v_caller_name
  );

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'role.promoted', 'member', p_new_leader_id,
    jsonb_build_object('old_role', v_new_leader.operational_role, 'new_role', 'tribe_leader',
      'tribe_id', p_tribe_id, 'tribe_name', v_tribe.name, 'reason', p_reason));

  RETURN jsonb_build_object(
    'success', true, 'tribe', v_tribe.name,
    'old_leader', COALESCE(v_old_leader.name, 'N/A'),
    'new_leader', v_new_leader.name, 'reason', p_reason
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_change_tribe_leader(integer, uuid, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_change_tribe_leader(integer, uuid, text) IS
  'Phase B'' V4 conversion (p60 Pacote F): manage_member gate via can_by_member. Was V3 (superadmin only). search_path hardened to ''''.';

-- ============================================================
-- 2. admin_deactivate_member → manage_member
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_deactivate_member(uuid, text);
CREATE OR REPLACE FUNCTION public.admin_deactivate_member(
  p_member_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
  v_member record;
  v_tribe_name text;
  v_cycle record;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'permission_denied: manage_member required';
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Member not found: %', p_member_id;
  END IF;

  SELECT name INTO v_tribe_name FROM public.tribes WHERE id = v_member.tribe_id;
  SELECT * INTO v_cycle FROM public.cycles WHERE is_current = true LIMIT 1;

  INSERT INTO public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) VALUES (
    p_member_id,
    COALESCE(v_cycle.cycle_code, 'cycle_3'),
    COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
    COALESCE(v_cycle.cycle_start, now()::text),
    now()::text,
    v_member.operational_role,
    v_member.designations,
    v_member.tribe_id,
    COALESCE(v_tribe_name, 'N/A'),
    v_member.chapter,
    false,
    v_member.name,
    'DEACTIVATED: ' || p_reason || '. By: ' || v_caller_name
  );

  UPDATE public.members
  SET current_cycle_active = false,
      inactivated_at = now()
  WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_caller_id, 'member.deactivated', 'member', p_member_id,
    jsonb_build_object('current_cycle_active', false, 'reason', p_reason)
  );

  RETURN jsonb_build_object(
    'success', true, 'member_name', v_member.name,
    'tribe', COALESCE(v_tribe_name, 'N/A'), 'reason', p_reason,
    'draft_email_subject', 'Comunicado: Afastamento de ' || v_member.name,
    'draft_email_body', 'Prezados,\n\nInformamos que o(a) pesquisador(a) ' || v_member.name || ' foi desligado(a) do Nucleo IA & GP.\nMotivo: ' || p_reason || '\n\nAtenciosamente,\nGerencia do Projeto'
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_deactivate_member(uuid, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_deactivate_member(uuid, text) IS
  'Phase B'' V4 conversion (p60 Pacote F): manage_member gate via can_by_member. Was V3 (superadmin only). search_path hardened to ''''.';

-- ============================================================
-- 3. admin_move_member_tribe → manage_member
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_move_member_tribe(uuid, integer, text);
CREATE OR REPLACE FUNCTION public.admin_move_member_tribe(
  p_member_id uuid,
  p_new_tribe_id integer,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
  v_member record;
  v_old_tribe_name text;
  v_new_tribe_name text;
  v_cycle record;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'permission_denied: manage_member required';
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Member not found: %', p_member_id;
  END IF;

  SELECT name INTO v_old_tribe_name FROM public.tribes WHERE id = v_member.tribe_id;
  SELECT name INTO v_new_tribe_name FROM public.tribes WHERE id = p_new_tribe_id;

  IF v_new_tribe_name IS NULL THEN
    RAISE EXCEPTION 'Target tribe not found: %', p_new_tribe_id;
  END IF;

  SELECT * INTO v_cycle FROM public.cycles WHERE is_current = true LIMIT 1;

  INSERT INTO public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) VALUES (
    p_member_id,
    COALESCE(v_cycle.cycle_code, 'cycle_3'),
    COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
    COALESCE(v_cycle.cycle_start, now()::text),
    now()::text,
    v_member.operational_role,
    v_member.designations,
    v_member.tribe_id,
    COALESCE(v_old_tribe_name, 'Sem tribo'),
    v_member.chapter,
    true,
    v_member.name,
    'TRANSFER: ' || COALESCE(v_old_tribe_name, 'N/A') || ' -> ' || v_new_tribe_name || '. Reason: ' || p_reason || '. By: ' || v_caller_name
  );

  UPDATE public.members
  SET tribe_id = p_new_tribe_id
  WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_caller_id, 'member.tribe_moved', 'member', p_member_id,
    jsonb_build_object(
      'old_tribe_id', v_member.tribe_id, 'new_tribe_id', p_new_tribe_id,
      'old_tribe_name', COALESCE(v_old_tribe_name, 'N/A'),
      'new_tribe_name', v_new_tribe_name, 'reason', p_reason
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'member_name', v_member.name,
    'from_tribe', COALESCE(v_old_tribe_name, 'N/A'),
    'to_tribe', v_new_tribe_name, 'reason', p_reason
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_move_member_tribe(uuid, integer, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_move_member_tribe(uuid, integer, text) IS
  'Phase B'' V4 conversion (p60 Pacote F): manage_member gate via can_by_member. Was V3 (superadmin only). search_path hardened to ''''.';

NOTIFY pgrst, 'reload schema';
