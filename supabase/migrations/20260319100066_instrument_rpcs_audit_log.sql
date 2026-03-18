-- ============================================================
-- W-ADMIN Phase 2: Instrument member-modifying RPCs with audit logging
--
-- CREATE OR REPLACE for each RPC, preserving all existing logic
-- and adding INSERT INTO admin_audit_log after each mutation.
-- Also adds get_audit_log RPC for superadmin querying.
-- ============================================================

-- ═══════════════════════════════════════════════════════════════
-- 1. admin_inactivate_member — adds audit: member.inactivated
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_inactivate_member(
  p_member_id uuid,
  p_reason    text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_actor_id uuid;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();

  UPDATE public.members
     SET is_active = false,
         inactivation_reason = p_reason
   WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_actor_id,
    'member.inactivated',
    'member',
    p_member_id,
    jsonb_build_object(
      'is_active', false,
      'reason', p_reason
    )
  );

  RETURN json_build_object('success', true);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 2. admin_reactivate_member — adds audit: member.reactivated
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_reactivate_member(
  p_member_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_actor_id uuid;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();

  UPDATE public.members
     SET is_active = true,
         inactivation_reason = NULL
   WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_actor_id,
    'member.reactivated',
    'member',
    p_member_id,
    jsonb_build_object('is_active', true)
  );

  RETURN json_build_object('success', true);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 3. admin_move_member_tribe — adds audit: member.tribe_moved
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_move_member_tribe(
  p_member_id uuid,
  p_new_tribe_id integer,
  p_reason text DEFAULT 'Administrative transfer'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller record;
  v_member record;
  v_old_tribe_name text;
  v_new_tribe_name text;
  v_cycle record;
BEGIN
  SELECT * INTO v_caller FROM public.get_my_member_record();
  IF v_caller IS NULL OR v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Superadmin access required';
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
    'TRANSFER: ' || COALESCE(v_old_tribe_name, 'N/A') || ' -> ' || v_new_tribe_name || '. Reason: ' || p_reason || '. By: ' || v_caller.name
  );

  UPDATE public.members
  SET tribe_id = p_new_tribe_id
  WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_caller.id,
    'member.tribe_moved',
    'member',
    p_member_id,
    jsonb_build_object(
      'old_tribe_id', v_member.tribe_id,
      'new_tribe_id', p_new_tribe_id,
      'old_tribe_name', COALESCE(v_old_tribe_name, 'N/A'),
      'new_tribe_name', v_new_tribe_name,
      'reason', p_reason
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'member_name', v_member.name,
    'from_tribe', COALESCE(v_old_tribe_name, 'N/A'),
    'to_tribe', v_new_tribe_name,
    'reason', p_reason
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 4. admin_deactivate_member — adds audit: member.deactivated
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_deactivate_member(
  p_member_id uuid,
  p_reason text DEFAULT 'Administrative deactivation'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller record;
  v_member record;
  v_tribe_name text;
  v_cycle record;
BEGIN
  SELECT * INTO v_caller FROM public.get_my_member_record();
  IF v_caller IS NULL OR v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Superadmin access required';
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
    'DEACTIVATED: ' || p_reason || '. By: ' || v_caller.name
  );

  UPDATE public.members
  SET current_cycle_active = false,
      inactivated_at = now()
  WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_caller.id,
    'member.deactivated',
    'member',
    p_member_id,
    jsonb_build_object(
      'current_cycle_active', false,
      'reason', p_reason
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'member_name', v_member.name,
    'tribe', COALESCE(v_tribe_name, 'N/A'),
    'reason', p_reason,
    'draft_email_subject', 'Comunicado: Afastamento de ' || v_member.name,
    'draft_email_body', 'Prezados,\n\nInformamos que o(a) pesquisador(a) ' || v_member.name || ' foi desligado(a) do Nucleo IA & GP.\nMotivo: ' || p_reason || '\n\nAtenciosamente,\nGerencia do Projeto'
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 5. admin_change_tribe_leader — adds audit for old leader
--    (role.demoted) and new leader (role.promoted + tribe assigned)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_change_tribe_leader(
  p_tribe_id integer,
  p_new_leader_id uuid,
  p_reason text DEFAULT 'Leadership transition'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller record;
  v_tribe record;
  v_old_leader record;
  v_new_leader record;
  v_cycle record;
BEGIN
  SELECT * INTO v_caller FROM public.get_my_member_record();
  IF v_caller IS NULL OR v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Superadmin access required';
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN
    RAISE EXCEPTION 'Tribe not found: %', p_tribe_id;
  END IF;

  SELECT * INTO v_new_leader FROM public.members WHERE id = p_new_leader_id;
  IF v_new_leader IS NULL THEN
    RAISE EXCEPTION 'New leader member not found: %', p_new_leader_id;
  END IF;

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
        COALESCE(v_cycle.cycle_code, 'cycle_3'),
        COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
        COALESCE(v_cycle.cycle_start, now()::text),
        now()::text,
        v_old_leader.operational_role,
        v_old_leader.designations,
        v_old_leader.tribe_id,
        v_tribe.name,
        v_old_leader.chapter,
        true,
        v_old_leader.name,
        'LEADER_REMOVED: Replaced by ' || v_new_leader.name || '. Reason: ' || p_reason || '. By: ' || v_caller.name
      );

      UPDATE public.members
      SET operational_role = 'researcher'
      WHERE id = v_old_leader.id
        AND operational_role = 'tribe_leader';

      -- Audit: old leader demoted
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (
        v_caller.id,
        'role.demoted',
        'member',
        v_old_leader.id,
        jsonb_build_object(
          'old_role', 'tribe_leader',
          'new_role', 'researcher',
          'tribe_id', p_tribe_id,
          'tribe_name', v_tribe.name,
          'reason', p_reason
        )
      );
    END IF;
  END IF;

  UPDATE public.members
  SET operational_role = 'tribe_leader',
      tribe_id = p_tribe_id
  WHERE id = p_new_leader_id;

  UPDATE public.tribes
  SET leader_member_id = p_new_leader_id
  WHERE id = p_tribe_id;

  INSERT INTO public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) VALUES (
    p_new_leader_id,
    COALESCE(v_cycle.cycle_code, 'cycle_3'),
    COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
    COALESCE(v_cycle.cycle_start, now()::text),
    NULL,
    'tribe_leader',
    v_new_leader.designations,
    p_tribe_id,
    v_tribe.name,
    v_new_leader.chapter,
    true,
    v_new_leader.name,
    'LEADER_ASSIGNED: Promoted to leader of ' || v_tribe.name || '. Reason: ' || p_reason || '. By: ' || v_caller.name
  );

  -- Audit: new leader promoted
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_caller.id,
    'role.promoted',
    'member',
    p_new_leader_id,
    jsonb_build_object(
      'old_role', v_new_leader.operational_role,
      'new_role', 'tribe_leader',
      'tribe_id', p_tribe_id,
      'tribe_name', v_tribe.name,
      'reason', p_reason
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'tribe', v_tribe.name,
    'old_leader', COALESCE(v_old_leader.name, 'N/A'),
    'new_leader', v_new_leader.name,
    'reason', p_reason
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 6. get_audit_log — superadmin query RPC with filtering
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_audit_log(
  p_actor_id uuid DEFAULT NULL,
  p_target_id uuid DEFAULT NULL,
  p_action text DEFAULT NULL,
  p_date_from timestamptz DEFAULT NULL,
  p_date_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid() AND is_superadmin = true
  ) THEN RAISE EXCEPTION 'Superadmin only'; END IF;

  RETURN jsonb_build_object(
    'total', (
      SELECT count(*) FROM admin_audit_log al
      WHERE (p_actor_id IS NULL OR al.actor_id = p_actor_id)
        AND (p_target_id IS NULL OR al.target_id = p_target_id)
        AND (p_action IS NULL OR al.action ILIKE '%' || p_action || '%')
        AND (p_date_from IS NULL OR al.created_at >= p_date_from)
        AND (p_date_to IS NULL OR al.created_at <= p_date_to)
    ),
    'entries', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', al.id,
        'actor_name', actor.full_name,
        'actor_id', al.actor_id,
        'action', al.action,
        'target_name', target.full_name,
        'target_id', al.target_id,
        'changes', al.changes,
        'created_at', al.created_at
      ) ORDER BY al.created_at DESC), '[]'::jsonb)
      FROM admin_audit_log al
      LEFT JOIN members actor ON actor.id = al.actor_id
      LEFT JOIN members target ON target.id = al.target_id
      WHERE (p_actor_id IS NULL OR al.actor_id = p_actor_id)
        AND (p_target_id IS NULL OR al.target_id = p_target_id)
        AND (p_action IS NULL OR al.action ILIKE '%' || p_action || '%')
        AND (p_date_from IS NULL OR al.created_at >= p_date_from)
        AND (p_date_to IS NULL OR al.created_at <= p_date_to)
      LIMIT p_limit OFFSET p_offset
    ),
    'actors', (
      SELECT COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
        'id', m.id, 'name', m.full_name
      )), '[]'::jsonb)
      FROM admin_audit_log al
      JOIN members m ON m.id = al.actor_id
    )
  );
END;
$$;
