-- ============================================================================
-- GC-139: Volunteer Agreement + Certificates — Sprint 3 "Emancipação"
-- Constraint expansion + template seed + 5 RPCs
-- ============================================================================

-- PART 1: Expand type constraints
ALTER TABLE certificates DROP CONSTRAINT IF EXISTS certificates_type_check;
ALTER TABLE certificates ADD CONSTRAINT certificates_type_check
  CHECK (type IN ('participation', 'completion', 'contribution', 'excellence', 'volunteer_agreement'));

ALTER TABLE governance_documents DROP CONSTRAINT IF EXISTS governance_documents_doc_type_check;
ALTER TABLE governance_documents ADD CONSTRAINT governance_documents_doc_type_check
  CHECK (doc_type IN ('manual', 'cooperation_agreement', 'framework_reference', 'addendum', 'policy', 'volunteer_term_template'));

-- PART 2: Seed volunteer term template
INSERT INTO governance_documents (title, doc_type, description, version, status, valid_from)
SELECT 'Termo de Voluntariado — Template Ciclo 3', 'volunteer_term_template',
  'Template base para o Termo de Voluntariado do Nucleo de Estudos e Pesquisa em IA & GP.',
  'R3-C3', 'active', '2026-01-01'
WHERE NOT EXISTS (SELECT 1 FROM governance_documents WHERE doc_type = 'volunteer_term_template');

-- PART 3: sign_volunteer_agreement RPC
DROP FUNCTION IF EXISTS sign_volunteer_agreement(text);
CREATE OR REPLACE FUNCTION sign_volunteer_agreement(p_language text DEFAULT 'pt-BR')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_member record; v_template record; v_cert_id uuid; v_code text; v_hash text; v_content jsonb; v_cycle int; v_existing uuid;
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.tribe_id, t.name as tribe_name
  INTO v_member FROM members m LEFT JOIN tribes t ON t.id = m.tribe_id WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  v_cycle := EXTRACT(YEAR FROM now())::int;
  SELECT id INTO v_existing FROM certificates WHERE member_id = v_member.id AND type = 'volunteer_agreement' AND cycle = v_cycle AND status = 'issued';
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_signed', 'certificate_id', v_existing); END IF;

  SELECT * INTO v_template FROM governance_documents WHERE doc_type = 'volunteer_term_template' AND status = 'active' ORDER BY created_at DESC LIMIT 1;
  IF v_template.id IS NULL THEN RETURN jsonb_build_object('error', 'template_not_found'); END IF;

  v_content := jsonb_build_object('template_id', v_template.id, 'template_version', v_template.version,
    'member_name', v_member.name, 'member_email', v_member.email, 'member_role', v_member.operational_role,
    'member_tribe', v_member.tribe_name, 'language', p_language, 'signed_at', now(),
    'terms', jsonb_build_array('Participacao voluntaria sem remuneracao','Compromisso com reunioes e entregas',
      'Respeito ao codigo de conduta do PMI','Autorizacao para uso do nome','Ciencia da Politica de Privacidade'));

  v_code := 'TERM-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));
  v_hash := encode(sha256(convert_to(v_content::text || v_member.id::text || now()::text || 'nucleo-ia-volunteer-salt', 'UTF8')), 'hex');

  INSERT INTO certificates (member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
    period_start, period_end, function_role, language, status, signature_hash, content_snapshot, template_id)
  VALUES (v_member.id, 'volunteer_agreement',
    CASE p_language WHEN 'en-US' THEN 'Volunteer Agreement — Cycle ' || v_cycle WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado — Ciclo ' || v_cycle
    ELSE 'Termo de Voluntariado — Ciclo ' || v_cycle END,
    v_template.description, v_cycle, now(),
    (SELECT id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1),
    v_code, EXTRACT(YEAR FROM now())::text || '-01-01', EXTRACT(YEAR FROM now())::text || '-06-30',
    v_member.operational_role, p_language, 'issued', v_hash, v_content, v_template.id::text
  ) RETURNING id INTO v_cert_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'volunteer_agreement_signed', 'certificate', v_cert_id,
    jsonb_build_object('verification_code', v_code, 'cycle', v_cycle));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
  SELECT m.id, 'volunteer_agreement_signed', v_member.name || ' assinou o Termo de Voluntariado',
    'Ciclo ' || v_cycle || '. Codigo: ' || v_code, '/admin/certificates', 'certificate', v_cert_id
  FROM members m WHERE m.operational_role = 'manager' OR (m.is_superadmin = true AND m.is_active = true);

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code, 'signature_hash', v_hash, 'signed_at', now());
END;
$$;
GRANT EXECUTE ON FUNCTION sign_volunteer_agreement(text) TO authenticated;

-- PART 4: counter_sign_certificate RPC
DROP FUNCTION IF EXISTS counter_sign_certificate(uuid);
CREATE OR REPLACE FUNCTION counter_sign_certificate(p_certificate_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_member_id uuid; v_is_authorized boolean; v_cert record; v_hash text;
BEGIN
  SELECT id, (operational_role IN ('manager') OR is_superadmin = true)
  INTO v_member_id, v_is_authorized FROM members WHERE auth_id = auth.uid();
  IF NOT COALESCE(v_is_authorized, false) THEN RETURN jsonb_build_object('error', 'not_authorized'); END IF;
  SELECT * INTO v_cert FROM certificates WHERE id = p_certificate_id;
  IF v_cert IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF v_cert.counter_signed_by IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_counter_signed'); END IF;

  v_hash := encode(sha256(convert_to(COALESCE(v_cert.signature_hash,'') || v_member_id::text || now()::text || 'nucleo-ia-countersign-salt', 'UTF8')), 'hex');
  UPDATE certificates SET counter_signed_by = v_member_id, counter_signed_at = now() WHERE id = p_certificate_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'certificate_counter_signed', 'certificate', p_certificate_id,
    jsonb_build_object('verification_code', v_cert.verification_code, 'type', v_cert.type));
  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
  VALUES (v_cert.member_id, 'certificate_ready', 'Seu ' || v_cert.title || ' esta pronto!',
    'Documento contra-assinado. Codigo: ' || v_cert.verification_code, '/certificates', 'certificate', p_certificate_id);

  RETURN jsonb_build_object('success', true, 'counter_signature_hash', v_hash, 'counter_signed_at', now());
END;
$$;
GRANT EXECUTE ON FUNCTION counter_sign_certificate(uuid) TO authenticated;

-- PART 5: get_my_certificates + get_pending_countersign RPCs
DROP FUNCTION IF EXISTS get_my_certificates();
CREATE OR REPLACE FUNCTION get_my_certificates()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_member_id uuid; result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id, 'type', c.type, 'title', c.title, 'cycle', c.cycle, 'status', c.status,
    'verification_code', c.verification_code, 'issued_at', c.issued_at,
    'issued_by_name', ib.name, 'counter_signed_by_name', cs.name,
    'counter_signed_at', c.counter_signed_at, 'period_start', c.period_start,
    'period_end', c.period_end, 'language', c.language,
    'has_counter_signature', c.counter_signed_by IS NOT NULL, 'signature_hash', c.signature_hash
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO result
  FROM certificates c LEFT JOIN members ib ON ib.id = c.issued_by LEFT JOIN members cs ON cs.id = c.counter_signed_by
  WHERE c.member_id = v_member_id AND COALESCE(c.status, 'issued') != 'revoked';
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION get_my_certificates() TO authenticated;

DROP FUNCTION IF EXISTS get_pending_countersign();
CREATE OR REPLACE FUNCTION get_pending_countersign()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_member_id uuid; v_is_authorized boolean; result jsonb;
BEGIN
  SELECT id, (operational_role IN ('manager') OR is_superadmin = true)
  INTO v_member_id, v_is_authorized FROM members WHERE auth_id = auth.uid();
  IF NOT COALESCE(v_is_authorized, false) THEN RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id, 'type', c.type, 'title', c.title, 'member_name', m.name, 'member_email', m.email,
    'member_role', m.operational_role, 'tribe_name', t.name, 'cycle', c.cycle,
    'verification_code', c.verification_code, 'issued_at', c.issued_at, 'signature_hash', c.signature_hash
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO result
  FROM certificates c JOIN members m ON m.id = c.member_id LEFT JOIN tribes t ON t.id = m.tribe_id
  WHERE c.counter_signed_by IS NULL AND COALESCE(c.status, 'issued') = 'issued';
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION get_pending_countersign() TO authenticated;

-- PART 6: link_attachment_to_governance RPC
DROP FUNCTION IF EXISTS link_attachment_to_governance(uuid, text, timestamptz, text[]);
CREATE OR REPLACE FUNCTION link_attachment_to_governance(
  p_attachment_id uuid, p_title text, p_signed_at timestamptz DEFAULT now(), p_parties text[] DEFAULT '{}'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_member_id uuid; v_is_admin boolean; v_attachment record; v_doc_id uuid;
BEGIN
  SELECT id, is_superadmin INTO v_member_id, v_is_admin FROM members WHERE auth_id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN RETURN jsonb_build_object('error', 'not_authorized'); END IF;
  SELECT * INTO v_attachment FROM partner_attachments WHERE id = p_attachment_id;
  IF v_attachment IS NULL THEN RETURN jsonb_build_object('error', 'attachment_not_found'); END IF;
  INSERT INTO governance_documents (title, doc_type, status, pdf_url, partner_entity_id, signed_at, parties, valid_from)
  VALUES (p_title, 'cooperation_agreement', 'active', v_attachment.file_url, v_attachment.partner_entity_id, p_signed_at, p_parties, p_signed_at)
  RETURNING id INTO v_doc_id;
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'attachment_linked_to_governance', 'governance_document', v_doc_id,
    jsonb_build_object('attachment_id', p_attachment_id, 'title', p_title));
  RETURN jsonb_build_object('success', true, 'governance_document_id', v_doc_id);
END;
$$;
GRANT EXECUTE ON FUNCTION link_attachment_to_governance(uuid, text, timestamptz, text[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
