-- ═══════════════════════════════════════════════════════════════
-- W113: Partnership management RPC
-- CRUD for partner_entities via admin_manage_partner_entity
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_manage_partner_entity(
  p_action text,          -- 'create', 'update', 'delete'
  p_id uuid DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_entity_type text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_partnership_date date DEFAULT NULL,
  p_cycle_code text DEFAULT 'cycle3-2026',
  p_contact_name text DEFAULT NULL,
  p_contact_email text DEFAULT NULL,
  p_status text DEFAULT 'active'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_is_admin boolean;
  v_designations text[];
  v_new_id uuid;
BEGIN
  SELECT operational_role, is_superadmin, designations
  INTO v_role, v_is_admin, v_designations
  FROM public.members WHERE auth_id = auth.uid();

  -- ACL: superadmin, manager, deputy_manager, or sponsor/chapter_liaison designation
  IF NOT (
    v_is_admin
    OR v_role IN ('manager', 'deputy_manager')
    OR v_designations && ARRAY['sponsor', 'chapter_liaison']
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
  END IF;

  -- Validate entity_type
  IF p_action IN ('create', 'update') AND p_entity_type IS NOT NULL THEN
    IF p_entity_type NOT IN ('academia', 'governo', 'empresa', 'pmi_chapter', 'outro') THEN
      RETURN jsonb_build_object('success', false, 'error', 'invalid_entity_type');
    END IF;
  END IF;

  -- Validate status
  IF p_action IN ('create', 'update') AND p_status IS NOT NULL THEN
    IF p_status NOT IN ('active', 'prospect', 'inactive') THEN
      RETURN jsonb_build_object('success', false, 'error', 'invalid_status');
    END IF;
  END IF;

  CASE p_action
    WHEN 'create' THEN
      IF p_name IS NULL OR p_entity_type IS NULL OR p_partnership_date IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'missing_required_fields');
      END IF;
      INSERT INTO public.partner_entities (name, entity_type, description, partnership_date, cycle_code, contact_name, contact_email, status)
      VALUES (p_name, p_entity_type, p_description, p_partnership_date, p_cycle_code, p_contact_name, p_contact_email, p_status)
      RETURNING id INTO v_new_id;
      RETURN jsonb_build_object('success', true, 'id', v_new_id);

    WHEN 'update' THEN
      IF p_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'missing_id');
      END IF;
      UPDATE public.partner_entities SET
        name = COALESCE(p_name, name),
        entity_type = COALESCE(p_entity_type, entity_type),
        description = COALESCE(p_description, description),
        partnership_date = COALESCE(p_partnership_date, partnership_date),
        cycle_code = COALESCE(p_cycle_code, cycle_code),
        contact_name = COALESCE(p_contact_name, contact_name),
        contact_email = COALESCE(p_contact_email, contact_email),
        status = COALESCE(p_status, status)
      WHERE id = p_id;
      RETURN jsonb_build_object('success', true);

    WHEN 'delete' THEN
      IF p_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'missing_id');
      END IF;
      DELETE FROM public.partner_entities WHERE id = p_id;
      RETURN jsonb_build_object('success', true);

    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'invalid_action');
  END CASE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_manage_partner_entity(text, uuid, text, text, text, date, text, text, text, text) TO authenticated;
