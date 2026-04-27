-- ADR-0033 Phase 1 (Accepted, p66): partner subsystem V4 conversion (4 of 8 fns)
-- See docs/adr/ADR-0033-partner-subsystem-v4-conversion.md
--
-- PM ratified Q1-Q4 (2026-04-26 p66): Phase 1 only / manage_platform / defer signals / p66
--
-- Privilege expansion safety check (verified pre-apply):
--   legacy_count = 11
--   v4_count = 10
--   would_gain = []
--   would_lose = [João Uzejka Dos Santos] — chapter_liaison designation
--                sem V4 engagement chapter_board × liaison (mesma drift pattern
--                ADR-0030)

-- ============================================================
-- 1. admin_manage_partner_entity → reuse manage_partner
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_manage_partner_entity(
  p_action text,
  p_id uuid DEFAULT NULL::uuid,
  p_name text DEFAULT NULL::text,
  p_entity_type text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text,
  p_partnership_date date DEFAULT NULL::date,
  p_cycle_code text DEFAULT 'cycle3-2026'::text,
  p_contact_name text DEFAULT NULL::text,
  p_contact_email text DEFAULT NULL::text,
  p_status text DEFAULT 'active'::text,
  p_notes text DEFAULT NULL::text,
  p_chapter text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_new_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'authentication_required');
  END IF;

  -- V4 gate (Opção B reuse manage_partner — same precedent as ADR-0031/0032)
  IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
    RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
  END IF;

  IF p_action IN ('create', 'update') AND p_entity_type IS NOT NULL THEN
    IF p_entity_type NOT IN ('academia', 'academic', 'governo', 'empresa', 'pmi_chapter', 'outro', 'community', 'research', 'association') THEN
      RETURN jsonb_build_object('success', false, 'error', 'invalid_entity_type');
    END IF;
  END IF;
  IF p_action IN ('create', 'update') AND p_status IS NOT NULL THEN
    IF p_status NOT IN ('active', 'prospect', 'inactive', 'contact', 'negotiation', 'churned') THEN
      RETURN jsonb_build_object('success', false, 'error', 'invalid_status');
    END IF;
  END IF;

  CASE p_action
    WHEN 'create' THEN
      IF p_name IS NULL OR p_entity_type IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'missing_required_fields');
      END IF;
      INSERT INTO public.partner_entities (name, entity_type, description, partnership_date, cycle_code, contact_name, contact_email, status, notes, chapter, updated_at)
      VALUES (p_name, p_entity_type, p_description, COALESCE(p_partnership_date, CURRENT_DATE), p_cycle_code, p_contact_name, p_contact_email, p_status, p_notes, p_chapter, now())
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
        status = COALESCE(p_status, status),
        notes = COALESCE(p_notes, notes),
        chapter = COALESCE(p_chapter, chapter),
        updated_at = now()
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
COMMENT ON FUNCTION public.admin_manage_partner_entity(text, uuid, text, text, text, date, text, text, text, text, text, text) IS
  'Phase B'' V4 conversion (ADR-0033 Phase 1, p66): Opção B reuse manage_partner via can_by_member. Was V3 (SA OR manager/deputy OR designations sponsor/chapter_liaison).';

-- ============================================================
-- 2. admin_update_partner_status → reuse manage_partner
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_update_partner_status(
  p_partner_id uuid,
  p_new_status text,
  p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_current_status text;
  v_current_notes text;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Auth required';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT status, notes INTO v_current_status, v_current_notes FROM public.partner_entities WHERE id = p_partner_id;
  IF v_current_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'partner_not_found');
  END IF;

  IF p_new_status NOT IN ('prospect','contact','negotiation','active','inactive','churned') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_status');
  END IF;

  UPDATE public.partner_entities SET
    status = p_new_status,
    notes = CASE
      WHEN p_notes IS NOT NULL THEN
        COALESCE(v_current_notes || E'\n', '') || to_char(now(), 'YYYY-MM-DD') || ': [' || v_current_status || ' -> ' || p_new_status || '] ' || p_notes
      ELSE
        COALESCE(v_current_notes || E'\n', '') || to_char(now(), 'YYYY-MM-DD') || ': Status alterado de ' || v_current_status || ' para ' || p_new_status
    END,
    updated_at = now(),
    partnership_date = CASE
      WHEN p_new_status = 'active' AND partnership_date IS NULL THEN CURRENT_DATE
      ELSE partnership_date
    END
  WHERE id = p_partner_id;

  INSERT INTO public.partner_interactions (partner_id, interaction_type, summary, actor_member_id)
  VALUES (p_partner_id, 'status_change', v_current_status || ' -> ' || p_new_status, v_caller_id);

  UPDATE public.partner_entities SET last_interaction_at = now() WHERE id = p_partner_id;

  RETURN jsonb_build_object('success', true, 'old_status', v_current_status, 'new_status', p_new_status);
END;
$$;
COMMENT ON FUNCTION public.admin_update_partner_status(uuid, text, text) IS
  'Phase B'' V4 conversion (ADR-0033 Phase 1, p66): Opção B reuse manage_partner via can_by_member. Was V3 (SA OR manager/deputy OR designations sponsor/chapter_liaison).';

-- ============================================================
-- 3. get_partner_pipeline → reuse manage_partner
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_partner_pipeline()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT jsonb_build_object(
    'pipeline', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pe.id,
        'name', pe.name,
        'entity_type', pe.entity_type,
        'status', pe.status,
        'contact_name', pe.contact_name,
        'contact_email', pe.contact_email,
        'chapter', pe.chapter,
        'partnership_date', pe.partnership_date,
        'notes', pe.notes,
        'next_action', pe.next_action,
        'follow_up_date', pe.follow_up_date,
        'last_interaction_at', pe.last_interaction_at,
        'days_in_stage', EXTRACT(DAY FROM now() - COALESCE(pe.updated_at, pe.created_at))::int,
        'updated_at', COALESCE(pe.updated_at, pe.created_at)
      ) ORDER BY CASE pe.status
        WHEN 'negotiation' THEN 1
        WHEN 'contact' THEN 2
        WHEN 'prospect' THEN 3
        WHEN 'active' THEN 4
        WHEN 'inactive' THEN 5
        WHEN 'churned' THEN 6
      END, pe.updated_at DESC)
      FROM public.partner_entities pe
    ), '[]'::jsonb),
    'by_status', COALESCE((
      SELECT jsonb_object_agg(status, cnt)
      FROM (SELECT status, COUNT(*)::int as cnt FROM public.partner_entities GROUP BY status) sub
    ), '{}'::jsonb),
    'by_type', COALESCE((
      SELECT jsonb_object_agg(entity_type, cnt)
      FROM (SELECT entity_type, COUNT(*)::int as cnt FROM public.partner_entities GROUP BY entity_type) sub
    ), '{}'::jsonb),
    'total', (SELECT COUNT(*)::int FROM public.partner_entities),
    'active', (SELECT COUNT(*)::int FROM public.partner_entities WHERE status = 'active'),
    'stale', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pe.id,
        'name', pe.name,
        'status', pe.status,
        'days_stale', EXTRACT(DAY FROM now() - COALESCE(pe.updated_at, pe.created_at))::int
      ))
      FROM public.partner_entities pe
      WHERE pe.status IN ('prospect','contact','negotiation')
        AND COALESCE(pe.updated_at, pe.created_at) < now() - interval '30 days'
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION public.get_partner_pipeline() IS
  'Phase B'' V4 conversion (ADR-0033 Phase 1, p66): Opção B reuse manage_partner via can_by_member. Was V3 (SA OR manager/deputy OR designations sponsor/chapter_liaison).';

-- ============================================================
-- 4. auto_generate_cr_for_partnership → reuse manage_platform
-- ============================================================
CREATE OR REPLACE FUNCTION public.auto_generate_cr_for_partnership(p_partner_entity_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_partner record;
  v_gov_doc record;
  v_member_id uuid;
  v_cr_number text;
  v_cr_id uuid;
  v_existing_cr uuid;
  v_total_chapters int;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'auth_required');
  END IF;

  -- V4 gate: manage_platform (replaces V3 is_superadmin = true)
  IF NOT public.can_by_member(v_member_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_partner FROM public.partner_entities WHERE id = p_partner_entity_id;
  IF v_partner IS NULL THEN
    RETURN jsonb_build_object('error', 'partner_not_found');
  END IF;

  IF v_partner.status != 'active' THEN
    RETURN jsonb_build_object('error', 'partner_not_active');
  END IF;

  SELECT * INTO v_gov_doc FROM public.governance_documents
  WHERE partner_entity_id = p_partner_entity_id
    AND doc_type = 'cooperation_agreement'
    AND status = 'active'
  ORDER BY created_at DESC LIMIT 1;

  IF v_gov_doc.id IS NOT NULL THEN
    SELECT id INTO v_existing_cr FROM public.change_requests
    WHERE auto_generated = true AND source_document_id = v_gov_doc.id;
    IF v_existing_cr IS NOT NULL THEN
      RETURN jsonb_build_object('error', 'cr_already_exists', 'cr_id', v_existing_cr);
    END IF;
  END IF;

  SELECT count(*) INTO v_total_chapters FROM public.partner_entities
  WHERE entity_type = 'pmi_chapter' AND status = 'active';

  v_cr_number := 'CR-AUTO-' || EXTRACT(YEAR FROM now())::text || '-' ||
                 LPAD((SELECT count(*) + 1 FROM public.change_requests WHERE auto_generated = true)::text, 3, '0');

  INSERT INTO public.change_requests (
    cr_number, title, status, category, priority, description, justification,
    proposed_changes, requested_by, requested_by_role, impact_level, impact_description,
    auto_generated, source_document_id
  ) VALUES (
    v_cr_number,
    'Expansao para ' || v_total_chapters || ' capitulos — inclusao ' || v_partner.name,
    'proposed', 'manual_update', 'high',
    'O ' || v_partner.name || ' assinou Acordo de Cooperacao e passou a integrar o Nucleo. Actualizar §2.1 (Capitulos Integrados).',
    'Acordo de Cooperacao assinado' || CASE WHEN v_gov_doc.id IS NOT NULL THEN ' (registado em governance_documents).' ELSE '.' END,
    'Adicionar a tabela §2.1: ' || v_partner.name || ' | Adesao ' || EXTRACT(YEAR FROM now())::text,
    v_member_id, 'manager', 'medium',
    'Actualiza a lista oficial de capitulos no Manual.',
    true, v_gov_doc.id
  ) RETURNING id INTO v_cr_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'cr_auto_generated', 'change_request', v_cr_id,
          jsonb_build_object('partner', v_partner.name, 'cr_number', v_cr_number));

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id)
  SELECT m.id, 'governance_cr_new',
    'Novo CR automatico: ' || v_partner.name,
    v_cr_number || ' — Expansao para ' || v_total_chapters || ' capitulos.',
    '/governance', 'change_request', v_cr_id
  FROM public.members m
  WHERE m.operational_role = 'sponsor' AND m.is_active = true;

  RETURN jsonb_build_object(
    'success', true,
    'cr_id', v_cr_id,
    'cr_number', v_cr_number,
    'partner', v_partner.name,
    'total_chapters', v_total_chapters
  );
END;
$$;
COMMENT ON FUNCTION public.auto_generate_cr_for_partnership(uuid) IS
  'Phase B'' V4 conversion (ADR-0033 Phase 1, p66): manage_platform via can_by_member. Was V3 (is_superadmin only). p66 expansion: manager/deputy_manager/co_gp gain access (intentional per ADR-0033 Q2 ratify, narrower than manage_partner).';

NOTIFY pgrst, 'reload schema';
