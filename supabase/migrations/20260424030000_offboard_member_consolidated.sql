-- ============================================================
-- Consolidated offboard pipeline (Bug 3)
-- Wellington (16/Abr) exposed gap: the UI calls admin_offboard_member
-- which sets is_active=false + member_status + offboarded_at, but
-- DOES NOT update operational_role, DOES NOT clear designations,
-- and DOES NOT end active engagements. Result: ghost data (appears
-- in tribe pages, counted in rosters, engagement still "active").
--
-- Fix: replace admin_offboard_member with a single pipeline that
-- covers all sync'd fields + ends engagements + reassigns cards +
-- preserves audit trail. Keep legacy offboard_member as shim.
--
-- V4 NOTE: permission check still reads operational_role; full V4
-- migration to can_by_member(... 'manage_member') tracked under Eixo A.
--
-- Rollback: DROP new signature + restore prior CREATE OR REPLACE blob
-- (original migration 20260410100000_issue64).
-- ============================================================

DROP FUNCTION IF EXISTS public.admin_offboard_member(uuid, text, text, text, uuid);

CREATE FUNCTION public.admin_offboard_member(
  p_member_id       uuid,
  p_new_status      text,
  p_reason_category text,
  p_reason_detail   text DEFAULT NULL,
  p_reassign_to     uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller        record;
  v_member        record;
  v_transition_id uuid;
  v_items_reassigned int := 0;
  v_engagements_closed int := 0;
  v_new_role      text;
BEGIN
  -- Auth gate
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (
    v_caller.operational_role NOT IN ('manager','deputy_manager')
    AND v_caller.is_superadmin IS NOT TRUE
  ) THEN
    RETURN jsonb_build_object('error','Unauthorized');
  END IF;

  SELECT * INTO v_member FROM members WHERE id = p_member_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error','Member not found');
  END IF;

  IF p_new_status NOT IN ('observer','alumni','inactive') THEN
    RETURN jsonb_build_object('error','Invalid target status (observer|alumni|inactive)');
  END IF;

  IF v_member.member_status = p_new_status THEN
    RETURN jsonb_build_object('error','Member is already ' || p_new_status);
  END IF;

  -- Sync operational_role with new_status
  v_new_role := CASE p_new_status
    WHEN 'alumni'   THEN 'alumni'
    WHEN 'observer' THEN 'observer'
    WHEN 'inactive' THEN 'none'
  END;

  -- Transition log
  INSERT INTO member_status_transitions (
    member_id, previous_status, new_status, previous_tribe_id,
    reason_category, reason_detail, items_reassigned_to, actor_member_id
  ) VALUES (
    p_member_id, COALESCE(v_member.member_status,'active'), p_new_status, v_member.tribe_id,
    p_reason_category, p_reason_detail, p_reassign_to, v_caller.id
  ) RETURNING id INTO v_transition_id;

  -- Role-change log (dual audit)
  IF v_member.operational_role IS DISTINCT FROM v_new_role THEN
    INSERT INTO member_role_changes (
      member_id, change_type, field_name,
      old_value, new_value, effective_date, reason, authorized_by, executed_by
    ) VALUES (
      p_member_id, 'role_changed', 'operational_role',
      to_jsonb(v_member.operational_role), to_jsonb(v_new_role),
      CURRENT_DATE, p_reason_detail, v_caller.id, v_caller.id
    );
  END IF;

  -- Full member sync: status + role + is_active + designations + offboarded_{at,by} + reason
  UPDATE members SET
    member_status        = p_new_status,
    operational_role     = v_new_role,
    is_active            = false,
    designations         = '{}'::text[],
    offboarded_at        = now(),
    offboarded_by        = v_caller.id,
    status_changed_at    = now(),
    status_change_reason = COALESCE(p_reason_detail, p_reason_category),
    updated_at           = now()
  WHERE id = p_member_id;

  -- End active engagements for this person (V4: engagements keyed by person_id)
  IF v_member.person_id IS NOT NULL THEN
    UPDATE engagements SET
      status        = 'offboarded',
      end_date      = CURRENT_DATE,
      revoked_at    = now(),
      revoked_by    = v_caller.person_id,
      revoke_reason = COALESCE(p_reason_detail, p_reason_category),
      updated_at    = now()
    WHERE person_id = v_member.person_id
      AND status = 'active';
    GET DIAGNOSTICS v_engagements_closed = ROW_COUNT;
  END IF;

  -- Reassign board items if specified
  IF p_reassign_to IS NOT NULL THEN
    UPDATE board_items SET assignee_id = p_reassign_to
    WHERE assignee_id = p_member_id AND status != 'archived';
    GET DIAGNOSTICS v_items_reassigned = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'success',            true,
    'transition_id',      v_transition_id,
    'member_name',        v_member.name,
    'previous_status',    COALESCE(v_member.member_status,'active'),
    'new_status',         p_new_status,
    'new_role',           v_new_role,
    'items_reassigned',   v_items_reassigned,
    'engagements_closed', v_engagements_closed,
    'designations_cleared', COALESCE(array_length(v_member.designations,1),0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_offboard_member(uuid, text, text, text, uuid) TO authenticated;

-- Legacy shim: offboard_member delegates to the consolidated pipeline.
DROP FUNCTION IF EXISTS public.offboard_member(uuid, text, text, date);

CREATE FUNCTION public.offboard_member(
  p_member_id     uuid,
  p_new_status    text,
  p_reason        text,
  p_effective_date date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- effective_date argument is preserved for BC but not applied (consolidated pipeline uses now())
  RETURN public.admin_offboard_member(
    p_member_id       => p_member_id,
    p_new_status      => p_new_status,
    p_reason_category => 'administrative',
    p_reason_detail   => p_reason,
    p_reassign_to     => NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.offboard_member(uuid, text, text, date) TO authenticated;

NOTIFY pgrst, 'reload schema';
