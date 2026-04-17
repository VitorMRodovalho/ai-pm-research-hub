-- ============================================================
-- A4.2 — Member admin RPCs: V4 auth via can_by_member (ADR-0011)
--
-- RPCs refactored:
--   admin_offboard_member        → manage_member
--   admin_reactivate_member(3)   → manage_member   (+ DROP legacy overload(1))
--   admin_update_member          → manage_member
--   admin_update_member_audited  → manage_member
--   promote_to_leader_track      → promote
--   manage_selection_committee   → promote
--
-- Pattern: can_by_member is single source of truth. Hardcoded role list
-- dropped; legacy operational_role cache still read for other purposes.
-- ============================================================

-- ── DROP legacy overload (no auth gate, superseded by (uuid,int,text)) ──
DROP FUNCTION IF EXISTS public.admin_reactivate_member(uuid);

-- ── admin_offboard_member ──
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
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  IF p_new_status NOT IN ('observer','alumni','inactive') THEN
    RETURN jsonb_build_object('error','Invalid target status (observer|alumni|inactive)');
  END IF;

  IF v_member.member_status = p_new_status THEN
    RETURN jsonb_build_object('error','Member is already ' || p_new_status);
  END IF;

  v_new_role := CASE p_new_status
    WHEN 'alumni'   THEN 'alumni'
    WHEN 'observer' THEN 'observer'
    WHEN 'inactive' THEN 'none'
  END;

  INSERT INTO public.member_status_transitions (
    member_id, previous_status, new_status, previous_tribe_id,
    reason_category, reason_detail, items_reassigned_to, actor_member_id
  ) VALUES (
    p_member_id, COALESCE(v_member.member_status,'active'), p_new_status, v_member.tribe_id,
    p_reason_category, p_reason_detail, p_reassign_to, v_caller.id
  ) RETURNING id INTO v_transition_id;

  IF v_member.operational_role IS DISTINCT FROM v_new_role THEN
    INSERT INTO public.member_role_changes (
      member_id, change_type, field_name, old_value, new_value,
      effective_date, reason, authorized_by, executed_by
    ) VALUES (
      p_member_id, 'role_changed', 'operational_role',
      to_jsonb(v_member.operational_role), to_jsonb(v_new_role),
      CURRENT_DATE, p_reason_detail, v_caller.id, v_caller.id
    );
  END IF;

  UPDATE public.members SET
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

  IF v_member.person_id IS NOT NULL THEN
    UPDATE public.engagements SET
      status = 'offboarded', end_date = CURRENT_DATE,
      revoked_at = now(), revoked_by = v_caller.person_id,
      revoke_reason = COALESCE(p_reason_detail, p_reason_category),
      updated_at = now()
    WHERE person_id = v_member.person_id AND status = 'active';
    GET DIAGNOSTICS v_engagements_closed = ROW_COUNT;
  END IF;

  IF p_reassign_to IS NOT NULL THEN
    UPDATE public.board_items SET assignee_id = p_reassign_to
    WHERE assignee_id = p_member_id AND status != 'archived';
    GET DIAGNOSTICS v_items_reassigned = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'transition_id', v_transition_id,
    'member_name', v_member.name,
    'previous_status', COALESCE(v_member.member_status,'active'),
    'new_status', p_new_status, 'new_role', v_new_role,
    'items_reassigned', v_items_reassigned,
    'engagements_closed', v_engagements_closed,
    'designations_cleared', COALESCE(array_length(v_member.designations,1),0)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_offboard_member(uuid, text, text, text, uuid) TO authenticated;

-- ── admin_reactivate_member(uuid, int, text) ──
DROP FUNCTION IF EXISTS public.admin_reactivate_member(uuid, integer, text);

CREATE FUNCTION public.admin_reactivate_member(
  p_member_id uuid,
  p_tribe_id  integer,
  p_role      text DEFAULT 'researcher'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller record;
  v_member record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  IF v_member.member_status = 'active' THEN
    RETURN jsonb_build_object('error','Member is already active');
  END IF;

  INSERT INTO public.member_status_transitions (
    member_id, previous_status, new_status, previous_tribe_id, new_tribe_id,
    reason_category, actor_member_id
  ) VALUES (
    p_member_id, v_member.member_status, 'active', v_member.tribe_id, p_tribe_id,
    'return', v_caller.id
  );

  UPDATE public.members SET
    member_status = 'active',
    is_active = true,
    tribe_id = p_tribe_id,
    operational_role = p_role,
    status_changed_at = now(),
    offboarded_at = NULL,
    offboarded_by = NULL
  WHERE id = p_member_id;

  RETURN jsonb_build_object('success', true, 'member_name', v_member.name, 'new_tribe', p_tribe_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_reactivate_member(uuid, integer, text) TO authenticated;

-- ── admin_update_member ──
DROP FUNCTION IF EXISTS public.admin_update_member(uuid, text, text, text, text[], text, integer, text, text, text, boolean);

CREATE FUNCTION public.admin_update_member(
  p_member_id uuid,
  p_name text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_operational_role text DEFAULT NULL,
  p_designations text[] DEFAULT NULL,
  p_chapter text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_pmi_id text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_linkedin_url text DEFAULT NULL,
  p_current_cycle_active boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_member record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Member not found');
  END IF;

  UPDATE public.members SET
    name = COALESCE(p_name, name),
    email = COALESCE(p_email, email),
    operational_role = COALESCE(p_operational_role, operational_role),
    designations = COALESCE(p_designations, designations),
    chapter = COALESCE(p_chapter, chapter),
    tribe_id = COALESCE(p_tribe_id, tribe_id),
    pmi_id = COALESCE(p_pmi_id, pmi_id),
    phone = COALESCE(p_phone, phone),
    linkedin_url = COALESCE(p_linkedin_url, linkedin_url),
    current_cycle_active = COALESCE(p_current_cycle_active, current_cycle_active),
    updated_at = now()
  WHERE id = p_member_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_update_member(uuid, text, text, text, text[], text, integer, text, text, text, boolean) TO authenticated;

-- ── admin_update_member_audited ──
DROP FUNCTION IF EXISTS public.admin_update_member_audited(uuid, jsonb);

CREATE FUNCTION public.admin_update_member_audited(
  p_member_id uuid,
  p_changes   jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_id uuid;
  v_old_record jsonb;
  v_field text;
  v_old_val text;
  v_new_val text;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_actor_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member permission';
  END IF;

  SELECT jsonb_build_object(
    'operational_role', m.operational_role,
    'designations', m.designations,
    'tribe_id', m.tribe_id,
    'chapter', m.chapter,
    'is_active', m.is_active,
    'is_superadmin', m.is_superadmin
  ) INTO v_old_record FROM public.members m WHERE m.id = p_member_id;

  UPDATE public.members SET
    operational_role = COALESCE((p_changes->>'operational_role'), operational_role),
    designations = CASE WHEN p_changes ? 'designations'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_changes->'designations'))
      ELSE designations END,
    tribe_id = CASE WHEN p_changes ? 'tribe_id'
      THEN (p_changes->>'tribe_id')::integer
      ELSE tribe_id END,
    chapter = COALESCE((p_changes->>'chapter'), chapter),
    is_active = CASE WHEN p_changes ? 'is_active'
      THEN (p_changes->>'is_active')::boolean
      ELSE is_active END,
    is_superadmin = CASE WHEN p_changes ? 'is_superadmin'
      THEN (p_changes->>'is_superadmin')::boolean
      ELSE is_superadmin END
  WHERE id = p_member_id;

  FOR v_field IN SELECT jsonb_object_keys(p_changes) LOOP
    v_old_val := v_old_record->>v_field;
    v_new_val := p_changes->>v_field;
    IF v_old_val IS DISTINCT FROM v_new_val THEN
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (
        v_actor_id, 'member.' || v_field || '_changed', 'member', p_member_id,
        jsonb_build_object('field', v_field, 'old', v_old_val, 'new', v_new_val)
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_update_member_audited(uuid, jsonb) TO authenticated;

-- ── promote_to_leader_track ──
DROP FUNCTION IF EXISTS public.promote_to_leader_track(uuid, boolean);

CREATE FUNCTION public.promote_to_leader_track(
  p_application_id uuid,
  p_create_leader_app boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_src record;
  v_new_leader_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'promote') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires promote permission');
  END IF;

  SELECT * INTO v_src FROM public.selection_applications WHERE id = p_application_id;
  IF v_src.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  IF v_src.role_applied = 'leader' THEN
    RETURN jsonb_build_object('error', 'already_leader_track');
  END IF;

  UPDATE public.selection_applications
  SET promotion_path = 'triaged_to_leader',
      track_decided_at = now(),
      track_decided_by = v_caller_id
  WHERE id = p_application_id;

  IF p_create_leader_app THEN
    INSERT INTO public.selection_applications (
      cycle_id, applicant_name, email, phone, chapter,
      role_applied, status, linkedin_url, motivation_letter,
      academic_background, areas_of_interest, availability_declared,
      non_pmi_experience, proposed_theme, leadership_experience,
      linked_application_id, promotion_path, track_decided_at, track_decided_by,
      created_at
    )
    SELECT cycle_id, applicant_name, email, phone, chapter,
      'leader', 'submitted', linkedin_url, motivation_letter,
      academic_background, areas_of_interest, availability_declared,
      non_pmi_experience, proposed_theme, leadership_experience,
      id, 'triaged_to_leader', now(), v_caller_id, now()
    FROM public.selection_applications WHERE id = p_application_id
    RETURNING id INTO v_new_leader_id;

    UPDATE public.selection_applications SET linked_application_id = v_new_leader_id WHERE id = p_application_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'promote_to_leader_track', 'selection_application', p_application_id,
    jsonb_build_object('created_leader_app', v_new_leader_id, 'original_role', v_src.role_applied));

  RETURN jsonb_build_object(
    'success', true,
    'researcher_application_id', p_application_id,
    'leader_application_id', v_new_leader_id,
    'promotion_path', 'triaged_to_leader'
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.promote_to_leader_track(uuid, boolean) TO authenticated;

-- ── manage_selection_committee ──
DROP FUNCTION IF EXISTS public.manage_selection_committee(uuid, text, uuid, text);

CREATE FUNCTION public.manage_selection_committee(
  p_cycle_id  uuid,
  p_action    text,
  p_member_id uuid,
  p_role      text DEFAULT 'evaluator'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'promote') THEN
    RETURN json_build_object('error','Unauthorized: requires promote permission');
  END IF;

  IF p_action = 'add' THEN
    INSERT INTO public.selection_committee (cycle_id, member_id, role, can_interview)
    VALUES (p_cycle_id, p_member_id, p_role, true)
    ON CONFLICT (cycle_id, member_id) DO UPDATE SET role = p_role;
    RETURN json_build_object('success', true, 'action', 'added', 'member_id', p_member_id);

  ELSIF p_action = 'remove' THEN
    DELETE FROM public.selection_committee WHERE cycle_id = p_cycle_id AND member_id = p_member_id;
    RETURN json_build_object('success', true, 'action', 'removed', 'member_id', p_member_id);

  ELSE
    RETURN json_build_object('error', 'Invalid action. Use add or remove.');
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.manage_selection_committee(uuid, text, uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
