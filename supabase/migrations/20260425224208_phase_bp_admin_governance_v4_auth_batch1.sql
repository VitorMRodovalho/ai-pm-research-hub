-- Track Q Phase B' — V4 auth migration of captured orphans (batch 1)
--
-- Migrates 2 functions from the p52 Q-A admin_governance batch
-- (`20260425143634`) from legacy V3 authority gates to V4 `can_by_member()`.
--
-- Source legacy gate (both functions):
--   (caller.is_superadmin = true OR caller.operational_role IN ('manager','deputy_manager'))
--
-- Target V4 action: `manage_platform`
--   Ladder: volunteer/manager + volunteer/deputy_manager + volunteer/co_gp
--           + (is_superadmin fast-path always honored by can_by_member)
--
-- Privilege expansion analysis (verified live data 2026-04-25):
--   - Currently only 2 active members satisfy old gate (Vitor manager+SA,
--     Fabricio SA via tribe_leader). Both also satisfy V4 manage_platform.
--   - 0 active deputy_manager engagements. 0 active co_gp engagements.
--   - Net authorization change in production today: ZERO.
--   - Co_gp expansion takes effect only when a co_gp engagement is created.
--     Co_gp = co-General Project leader, peer to manager. Admin authority
--     for board management + volunteer term generation is consistent with
--     this role.
--
-- Functions migrated:
--   1. admin_generate_volunteer_term — generates volunteer-term content for
--      a member. Self-read OR admin (legacy: manager/deputy/SA). V4: keep
--      self-read OR can_by_member('manage_platform').
--   2. admin_manage_board_member — adds/removes/updates board membership.
--      Admin only (legacy: manager/deputy/SA). V4:
--      can_by_member('manage_platform') only.
--
-- Bodies otherwise verbatim from `20260425143634_qa_orphan_recovery_admin_governance.sql`.

CREATE OR REPLACE FUNCTION public.admin_generate_volunteer_term(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_member record;
BEGIN
  -- Self-read OR platform admin
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT m.* INTO v_member FROM members m
  WHERE m.id = p_member_id
    AND (m.auth_id = auth.uid() OR public.can_by_member(v_caller_id, 'manage_platform'));

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Not found or unauthorized');
  END IF;

  RETURN jsonb_build_object(
    'member_id', v_member.id,
    'name', v_member.name,
    'email', v_member.email,
    'pmi_id', v_member.pmi_id,
    'phone', v_member.phone,
    'state', v_member.state,
    'country', v_member.country,
    'chapter', v_member.chapter,
    'generated_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_manage_board_member(p_board_id uuid, p_member_id uuid, p_board_role text DEFAULT 'editor'::text, p_action text DEFAULT 'add'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;

  IF p_action = 'add' THEN
    INSERT INTO board_members (board_id, member_id, board_role, granted_by)
    VALUES (p_board_id, p_member_id, p_board_role, v_caller.id)
    ON CONFLICT (board_id, member_id) DO UPDATE SET board_role = p_board_role;
  ELSIF p_action = 'remove' THEN
    DELETE FROM board_members WHERE board_id = p_board_id AND member_id = p_member_id;
  ELSIF p_action = 'update' THEN
    UPDATE board_members SET board_role = p_board_role WHERE board_id = p_board_id AND member_id = p_member_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'action', p_action, 'member_id', p_member_id, 'board_role', p_board_role);
END;
$function$;

NOTIFY pgrst, 'reload schema';
