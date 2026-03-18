-- ============================================================
-- W-ADMIN Phase 6: Bulk Operations RPCs
-- admin_bulk_allocate_tribe + admin_bulk_set_status
-- ============================================================

-- Bulk allocate tribe
CREATE OR REPLACE FUNCTION public.admin_bulk_allocate_tribe(
  p_member_ids uuid[],
  p_tribe_id integer
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_actor_id uuid;
  v_member_id uuid;
  v_old_tribe_id integer;
  v_count integer := 0;
BEGIN
  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'));
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'Admin only'; END IF;

  FOREACH v_member_id IN ARRAY p_member_ids LOOP
    SELECT tribe_id INTO v_old_tribe_id FROM members WHERE id = v_member_id;

    UPDATE members SET tribe_id = p_tribe_id WHERE id = v_member_id;

    INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (v_actor_id, 'member.tribe_allocated_bulk', 'member', v_member_id,
      jsonb_build_object('field', 'tribe_id', 'old', v_old_tribe_id, 'new', p_tribe_id));

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;

-- Bulk set status
CREATE OR REPLACE FUNCTION public.admin_bulk_set_status(
  p_member_ids uuid[],
  p_is_active boolean
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_actor_id uuid;
  v_member_id uuid;
  v_old_status boolean;
  v_count integer := 0;
BEGIN
  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'));
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'Admin only'; END IF;

  FOREACH v_member_id IN ARRAY p_member_ids LOOP
    SELECT is_active INTO v_old_status FROM members WHERE id = v_member_id;

    IF v_old_status IS DISTINCT FROM p_is_active THEN
      UPDATE members SET is_active = p_is_active WHERE id = v_member_id;

      INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (v_actor_id, 'member.status_changed_bulk', 'member', v_member_id,
        jsonb_build_object('field', 'is_active', 'old', v_old_status, 'new', p_is_active));

      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;
