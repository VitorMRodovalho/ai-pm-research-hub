-- ============================================================================
-- GC-140: Governance Automation — Sprint 4 "Automação"
-- Auto-CR generation, manual versioning, diff visual
-- ============================================================================

-- RPC 1: auto_generate_cr_for_partnership
DROP FUNCTION IF EXISTS auto_generate_cr_for_partnership(uuid);
CREATE OR REPLACE FUNCTION auto_generate_cr_for_partnership(p_partner_entity_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_partner record; v_gov_doc record; v_member_id uuid; v_cr_number text; v_cr_id uuid;
  v_existing_cr uuid; v_total_chapters int;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid() AND is_superadmin = true;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'not_authorized'); END IF;
  SELECT * INTO v_partner FROM partner_entities WHERE id = p_partner_entity_id;
  IF v_partner IS NULL THEN RETURN jsonb_build_object('error', 'partner_not_found'); END IF;
  IF v_partner.status != 'active' THEN RETURN jsonb_build_object('error', 'partner_not_active'); END IF;

  SELECT * INTO v_gov_doc FROM governance_documents
  WHERE partner_entity_id = p_partner_entity_id AND doc_type = 'cooperation_agreement' AND status = 'active'
  ORDER BY created_at DESC LIMIT 1;

  IF v_gov_doc.id IS NOT NULL THEN
    SELECT id INTO v_existing_cr FROM change_requests WHERE auto_generated = true AND source_document_id = v_gov_doc.id;
    IF v_existing_cr IS NOT NULL THEN RETURN jsonb_build_object('error', 'cr_already_exists', 'cr_id', v_existing_cr); END IF;
  END IF;

  SELECT count(*) INTO v_total_chapters FROM partner_entities WHERE entity_type = 'pmi_chapter' AND status = 'active';
  v_cr_number := 'CR-AUTO-' || EXTRACT(YEAR FROM now())::text || '-' ||
    LPAD((SELECT count(*) + 1 FROM change_requests WHERE auto_generated = true)::text, 3, '0');

  INSERT INTO change_requests (cr_number, title, status, category, priority, description, justification, proposed_changes,
    requested_by, requested_by_role, impact_level, impact_description, auto_generated, source_document_id)
  VALUES (v_cr_number, 'Expansao para ' || v_total_chapters || ' capitulos — inclusao ' || v_partner.name,
    'proposed', 'manual_update', 'high',
    'O ' || v_partner.name || ' assinou Acordo de Cooperacao. Actualizar §2.1.',
    'Acordo de Cooperacao assinado' || CASE WHEN v_gov_doc.id IS NOT NULL THEN ' (registado em governance_documents).' ELSE '.' END,
    'Adicionar a §2.1: ' || v_partner.name || ' | Adesao ' || EXTRACT(YEAR FROM now())::text,
    v_member_id, 'manager', 'medium', 'Actualiza a lista de capitulos no Manual.',
    true, v_gov_doc.id) RETURNING id INTO v_cr_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'cr_auto_generated', 'change_request', v_cr_id,
    jsonb_build_object('partner', v_partner.name, 'cr_number', v_cr_number));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
  SELECT m.id, 'governance_cr_new', 'Novo CR: ' || v_partner.name,
    v_cr_number || ' — Expansao para ' || v_total_chapters || ' capitulos.', '/governance', 'change_request', v_cr_id
  FROM members m WHERE m.operational_role = 'sponsor' AND m.is_active = true;

  RETURN jsonb_build_object('success', true, 'cr_id', v_cr_id, 'cr_number', v_cr_number, 'partner', v_partner.name, 'total_chapters', v_total_chapters);
END;
$$;
GRANT EXECUTE ON FUNCTION auto_generate_cr_for_partnership(uuid) TO authenticated;

-- RPC 2: generate_manual_version
DROP FUNCTION IF EXISTS generate_manual_version(text, text);
CREATE OR REPLACE FUNCTION generate_manual_version(p_version_label text, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid; v_is_admin boolean; v_approved_crs jsonb; v_doc_id uuid; v_previous_version text; v_count int;
BEGIN
  SELECT id, is_superadmin INTO v_member_id, v_is_admin FROM members WHERE auth_id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN RETURN jsonb_build_object('error', 'not_authorized'); END IF;
  SELECT count(*) INTO v_count FROM change_requests WHERE status = 'approved';
  IF v_count = 0 THEN RETURN jsonb_build_object('error', 'no_approved_crs'); END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('cr_number', cr_number, 'title', title, 'category', category,
    'approved_at', approved_at) ORDER BY cr_number), '[]'::jsonb) INTO v_approved_crs
  FROM change_requests WHERE status = 'approved';

  SELECT version INTO v_previous_version FROM governance_documents WHERE doc_type = 'manual' AND status = 'active' ORDER BY created_at DESC LIMIT 1;
  UPDATE governance_documents SET status = 'superseded' WHERE doc_type = 'manual' AND status = 'active';

  INSERT INTO governance_documents (title, doc_type, version, status, description, valid_from)
  VALUES ('Manual de Governanca e Operacoes — ' || p_version_label, 'manual', p_version_label, 'active',
    v_count::text || ' CRs incorporados. ' || COALESCE(p_notes, ''), now()) RETURNING id INTO v_doc_id;

  UPDATE change_requests SET status = 'implemented', implemented_at = now(), implemented_by = v_member_id,
    manual_version_from = COALESCE(v_previous_version, 'R2'), manual_version_to = p_version_label
  WHERE status = 'approved';

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'manual_version_generated', 'governance_document', v_doc_id,
    jsonb_build_object('version', p_version_label, 'previous', v_previous_version, 'crs_count', v_count));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
  SELECT m.id, 'governance_manual_published', 'Manual ' || p_version_label || ' publicado!',
    v_count::text || ' alteracoes incorporadas.', '/governance/preview', 'governance_document', v_doc_id
  FROM members m WHERE (m.operational_role IN ('sponsor', 'manager') OR m.is_superadmin = true) AND m.is_active = true;

  INSERT INTO announcements (title, message, type, is_active, created_by, starts_at)
  VALUES ('Manual ' || p_version_label || ' publicado', v_count::text || ' alteracoes aprovadas pelos presidentes.', 'governance', false, v_member_id, now());

  RETURN jsonb_build_object('success', true, 'version', p_version_label, 'document_id', v_doc_id,
    'crs_implemented', v_approved_crs, 'previous_version', v_previous_version);
END;
$$;
GRANT EXECUTE ON FUNCTION generate_manual_version(text, text) TO authenticated;

-- RPC 3: get_manual_diff
DROP FUNCTION IF EXISTS get_manual_diff();
CREATE OR REPLACE FUNCTION get_manual_diff()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_current_version text;
BEGIN
  SELECT version INTO v_current_version FROM governance_documents WHERE doc_type = 'manual' AND status = 'active' ORDER BY created_at DESC LIMIT 1;
  RETURN jsonb_build_object(
    'current_version', COALESCE(v_current_version, 'R2'),
    'total_implemented', (SELECT count(*) FROM change_requests WHERE status = 'implemented'),
    'total_pending', (SELECT count(*) FROM change_requests WHERE status IN ('submitted','proposed','under_review','approved','open','pending_review','in_review')),
    'total_approved_ready', (SELECT count(*) FROM change_requests WHERE status = 'approved'));
END;
$$;
GRANT EXECUTE ON FUNCTION get_manual_diff() TO authenticated;

NOTIFY pgrst, 'reload schema';
