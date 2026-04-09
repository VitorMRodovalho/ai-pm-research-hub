-- Fix volunteer agreement workflow: allow chapter_board to counter-sign for their chapter
-- Previously only manager/superadmin could counter-sign and see pending certs.
-- Now chapter_board designation can:
--   1. Counter-sign certificates of members in their own chapter
--   2. See pending certs from their chapter
--   3. View volunteer agreement status scoped to their chapter
--   4. Receive notifications when members of their chapter sign

-- Fix 1: counter_sign_certificate — allow chapter_board for same chapter
DROP FUNCTION IF EXISTS counter_sign_certificate(uuid);
CREATE OR REPLACE FUNCTION counter_sign_certificate(p_certificate_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_member_chapter text;
  v_is_manager boolean;
  v_is_chapter_board boolean;
  v_cert record;
  v_cert_member_chapter text;
  v_hash text;
BEGIN
  SELECT m.id, m.chapter,
    (m.operational_role IN ('manager') OR m.is_superadmin = true),
    ('chapter_board' = ANY(m.designations))
  INTO v_member_id, v_member_chapter, v_is_manager, v_is_chapter_board
  FROM members m WHERE m.auth_id = auth.uid();

  IF NOT COALESCE(v_is_manager, false) AND NOT COALESCE(v_is_chapter_board, false) THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_cert FROM certificates WHERE id = p_certificate_id;
  IF v_cert IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF v_cert.counter_signed_by IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_counter_signed'); END IF;

  IF v_is_chapter_board AND NOT v_is_manager THEN
    SELECT m.chapter INTO v_cert_member_chapter FROM members m WHERE m.id = v_cert.member_id;
    IF v_cert_member_chapter IS DISTINCT FROM v_member_chapter THEN
      RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
    END IF;
  END IF;

  v_hash := encode(sha256(convert_to(
    COALESCE(v_cert.signature_hash,'') || v_member_id::text || now()::text || 'nucleo-ia-countersign-salt', 'UTF8'
  )), 'hex');

  UPDATE certificates SET counter_signed_by = v_member_id, counter_signed_at = now() WHERE id = p_certificate_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'certificate_counter_signed', 'certificate', p_certificate_id,
    jsonb_build_object('verification_code', v_cert.verification_code, 'type', v_cert.type));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
  VALUES (v_cert.member_id, 'certificate_ready',
    'Seu ' || v_cert.title || ' esta pronto!',
    'O documento foi contra-assinado e esta disponivel. Codigo: ' || v_cert.verification_code,
    '/certificates', 'certificate', p_certificate_id);

  RETURN jsonb_build_object('success', true, 'counter_signature_hash', v_hash, 'counter_signed_at', now());
END;
$$;

-- Fix 2: get_pending_countersign — scope by chapter for chapter_board
DROP FUNCTION IF EXISTS get_pending_countersign();
CREATE OR REPLACE FUNCTION get_pending_countersign()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_member_chapter text;
  v_is_manager boolean;
  v_is_chapter_board boolean;
  result jsonb;
BEGIN
  SELECT m.id, m.chapter,
    (m.operational_role IN ('manager') OR m.is_superadmin = true),
    ('chapter_board' = ANY(m.designations))
  INTO v_member_id, v_member_chapter, v_is_manager, v_is_chapter_board
  FROM members m WHERE m.auth_id = auth.uid();

  IF NOT COALESCE(v_is_manager, false) AND NOT COALESCE(v_is_chapter_board, false) THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id, 'type', c.type, 'title', c.title, 'member_name', m.name, 'member_email', m.email,
    'member_role', m.operational_role, 'member_chapter', m.chapter, 'tribe_name', t.name, 'cycle', c.cycle,
    'verification_code', c.verification_code, 'issued_at', c.issued_at,
    'signature_hash', c.signature_hash
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO result
  FROM certificates c
  JOIN members m ON m.id = c.member_id
  LEFT JOIN tribes t ON t.id = m.tribe_id
  WHERE c.counter_signed_by IS NULL
    AND COALESCE(c.status, 'issued') = 'issued'
    AND (COALESCE(v_is_manager, false) OR m.chapter = v_member_chapter);

  RETURN result;
END;
$$;

-- Fix 3: sign_volunteer_agreement — notify chapter_board + set issued_by to chapter focal
DROP FUNCTION IF EXISTS sign_volunteer_agreement(text);
CREATE OR REPLACE FUNCTION sign_volunteer_agreement(p_language text DEFAULT 'pt-BR')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member record; v_template record; v_cert_id uuid; v_code text; v_hash text;
  v_content jsonb; v_cycle int; v_existing uuid; v_issuer_id uuid;
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.tribe_id, m.pmi_id, m.chapter, t.name as tribe_name
  INTO v_member FROM members m LEFT JOIN tribes t ON t.id = m.tribe_id WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  v_cycle := EXTRACT(YEAR FROM now())::int;
  SELECT id INTO v_existing FROM certificates WHERE member_id = v_member.id AND type = 'volunteer_agreement' AND cycle = v_cycle AND status = 'issued';
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_signed', 'certificate_id', v_existing); END IF;

  SELECT * INTO v_template FROM governance_documents WHERE doc_type = 'volunteer_term_template' AND status = 'active' ORDER BY created_at DESC LIMIT 1;
  IF v_template.id IS NULL THEN RETURN jsonb_build_object('error', 'template_not_found'); END IF;

  -- Find issuer: chapter_board of member's chapter, fallback to manager
  SELECT id INTO v_issuer_id FROM members
  WHERE chapter = v_member.chapter AND 'chapter_board' = ANY(designations) AND is_active = true
  ORDER BY operational_role = 'sponsor' DESC LIMIT 1;
  IF v_issuer_id IS NULL THEN
    SELECT id INTO v_issuer_id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1;
  END IF;

  v_content := jsonb_build_object(
    'template_id', v_template.id, 'template_version', v_template.version, 'template_title', v_template.title,
    'member_name', v_member.name, 'member_email', v_member.email, 'member_role', v_member.operational_role,
    'member_tribe', v_member.tribe_name, 'member_pmi_id', v_member.pmi_id, 'member_chapter', v_member.chapter,
    'language', p_language, 'signed_at', now(),
    'chapter_cnpj', '06.065.645/0001-99', 'chapter_name', 'PMI Goias',
    'clauses', jsonb_build_array(
      '1. Ciencia Lei 9.608/1998 — sem vinculo trabalhista, previdenciario, fiscal',
      '1a. PMI Goias sem vinculo com VOLUNTARIO',
      '1b. Parceiros sem vinculo com VOLUNTARIO',
      '1c. PMI Goias sem obrigacao de equipamentos',
      '2. Cessao de direitos sobre produtos e servicos ao PMI Goias',
      '3. Direito a reconhecimento oficial do trabalho',
      '4. Nao usar nome/documentos do PMI sem autorizacao',
      '5. Conformidade com politicas e etica do PMI',
      '6. Rescisao a qualquer tempo, sem onus',
      '7. Ressarcimento de despesas previamente autorizadas',
      '7a. Despesas devem ser expressamente autorizadas',
      '8. Validade indeterminada ou ate rescisao (art. 6)',
      '9. LGPD Lei 13.709/2018 — confidencialidade e protecao de dados',
      '9a. Tratar dados conforme principios LGPD',
      '9b. Manter sigilo de dados e informacoes',
      '9c. Nao revelar/reproduzir dados a terceiros',
      '9d. Nao obter propriedade intelectual de informacoes sigilosas',
      '9e. Usar informacoes confidenciais apenas para fins do programa',
      '9f. Manter procedimentos de prevencao de extravios',
      '10. Substitui NDA para fins de voluntariado',
      '11. Autorizacao de uso de fotos/imagens em eventos',
      '12. Nao estabelece sociedade/mandato/representacao'
    ),
    'legal_basis', jsonb_build_array(
      'Lei 9.608/1998 — Servico Voluntario',
      'Lei 13.709/2018 — LGPD',
      'Lei 14.063/2020 Art. 4§I — Assinatura eletronica simples'
    )
  );

  v_code := 'TERM-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));
  v_hash := encode(sha256(convert_to(v_content::text || v_member.id::text || now()::text || 'nucleo-ia-volunteer-salt', 'UTF8')), 'hex');

  INSERT INTO certificates (member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
    period_start, period_end, function_role, language, status, signature_hash, content_snapshot, template_id)
  VALUES (v_member.id, 'volunteer_agreement',
    CASE p_language WHEN 'en-US' THEN 'Volunteer Agreement — Cycle ' || v_cycle WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado — Ciclo ' || v_cycle
    ELSE 'Termo de Voluntariado — Ciclo ' || v_cycle END,
    v_template.description, v_cycle, now(), v_issuer_id,
    v_code, EXTRACT(YEAR FROM now())::text || '-01-01', EXTRACT(YEAR FROM now())::text || '-06-30',
    v_member.operational_role, p_language, 'issued', v_hash, v_content, v_template.id::text
  ) RETURNING id INTO v_cert_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'volunteer_agreement_signed', 'certificate', v_cert_id,
    jsonb_build_object('verification_code', v_code, 'cycle', v_cycle, 'chapter', v_member.chapter));

  -- Notify manager/superadmin AND chapter_board of the member's chapter
  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
  SELECT m.id, 'volunteer_agreement_signed', v_member.name || ' assinou o Termo de Voluntariado',
    'Capitulo: ' || COALESCE(v_member.chapter, '—') || '. Ciclo ' || v_cycle || '. Codigo: ' || v_code || '. Pendente contra-assinatura.',
    '/admin/certificates', 'certificate', v_cert_id
  FROM members m
  WHERE m.is_active = true
    AND m.id != v_member.id
    AND (
      m.operational_role = 'manager'
      OR m.is_superadmin = true
      OR ('chapter_board' = ANY(m.designations) AND m.chapter = v_member.chapter)
    );

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code, 'signature_hash', v_hash, 'signed_at', now());
END;
$$;

-- Fix 4: get_volunteer_agreement_status — scope by chapter + include focal points
DROP FUNCTION IF EXISTS get_volunteer_agreement_status();
CREATE OR REPLACE FUNCTION get_volunteer_agreement_status()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
  v_caller_chapter text;
  v_is_manager boolean;
  v_is_chapter_board boolean;
BEGIN
  SELECT
    m.chapter,
    (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager')),
    ('chapter_board' = ANY(m.designations))
  INTO v_caller_chapter, v_is_manager, v_is_chapter_board
  FROM members m WHERE m.auth_id = auth.uid();

  IF NOT COALESCE(v_is_manager, false) AND NOT COALESCE(v_is_chapter_board, false) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'caller_chapter', v_caller_chapter,
    'is_manager', COALESCE(v_is_manager, false),
    'summary', (
      SELECT jsonb_build_object(
        'total_eligible', count(*),
        'signed', count(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM certificates c
          WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
        )),
        'unsigned', count(*) FILTER (WHERE NOT EXISTS (
          SELECT 1 FROM certificates c
          WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
        )),
        'pct', ROUND(
          count(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM certificates c
            WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
            AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ))::numeric / NULLIF(count(*), 0) * 100, 1
        )
      )
      FROM members m
      WHERE m.is_active AND m.current_cycle_active
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
      AND (COALESCE(v_is_manager, false) OR m.chapter = v_caller_chapter)
    ),
    'by_chapter', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'chapter', sub.chapter,
        'total', sub.total,
        'signed', sub.signed,
        'unsigned', sub.total - sub.signed
      ) ORDER BY sub.chapter), '[]'::jsonb)
      FROM (
        SELECT m.chapter,
          count(*) as total,
          count(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM certificates c
            WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
            AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          )) as signed
        FROM members m
        WHERE m.is_active AND m.current_cycle_active
        AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
        AND (COALESCE(v_is_manager, false) OR m.chapter = v_caller_chapter)
        GROUP BY m.chapter
      ) sub
    ),
    'focal_points', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id,
        'name', m.name,
        'chapter', m.chapter,
        'role', m.operational_role
      ) ORDER BY m.chapter, m.name), '[]'::jsonb)
      FROM members m
      WHERE m.is_active AND 'chapter_board' = ANY(m.designations)
      AND (COALESCE(v_is_manager, false) OR m.chapter = v_caller_chapter)
    ),
    'members', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id,
        'name', m.name,
        'email', m.email,
        'chapter', m.chapter,
        'tribe_id', m.tribe_id,
        'role', m.operational_role,
        'signed', EXISTS (
          SELECT 1 FROM certificates c
          WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
        ),
        'signed_at', (
          SELECT c.issued_at FROM certificates c
          WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'verification_code', (
          SELECT c.verification_code FROM certificates c
          WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        )
      ) ORDER BY m.chapter, m.name), '[]'::jsonb)
      FROM members m
      WHERE m.is_active AND m.current_cycle_active
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
      AND (COALESCE(v_is_manager, false) OR m.chapter = v_caller_chapter)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;
