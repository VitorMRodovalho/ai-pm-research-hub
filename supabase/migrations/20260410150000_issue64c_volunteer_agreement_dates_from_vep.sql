-- ============================================================
-- Issue #64 (follow-up): volunteer_agreement dates hardcoded as
-- YYYY-01-01 → YYYY-06-30. Should use actual VEP start/end dates
-- from vep_opportunities via selection_applications chain.
--
-- Chain: members.email → selection_applications.email → vep_opportunity_id
--        → vep_opportunities.opportunity_id → start_date, end_date
--
-- Fallbacks:
-- 1. Multiple applications (triagem case): pick one matching operational_role
-- 2. No application (founders like Vitor): use current-year VEP matching role
-- 3. No VEP at all: use full calendar year as last resort
-- ============================================================

DROP FUNCTION IF EXISTS sign_volunteer_agreement(text);
CREATE OR REPLACE FUNCTION sign_volunteer_agreement(p_language text DEFAULT 'pt-BR')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_member record;
  v_template record;
  v_cert_id uuid;
  v_code text;
  v_hash text;
  v_content jsonb;
  v_cycle int;
  v_existing uuid;
  v_issuer_id uuid;
  v_vep record;
  v_period_start text;
  v_period_end text;
  v_member_role_for_vep text;
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.tribe_id, m.pmi_id, m.chapter, t.name as tribe_name
  INTO v_member FROM members m LEFT JOIN tribes t ON t.id = m.tribe_id WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  v_cycle := EXTRACT(YEAR FROM now())::int;
  SELECT id INTO v_existing FROM certificates
  WHERE member_id = v_member.id AND type = 'volunteer_agreement' AND cycle = v_cycle AND status = 'issued';
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_signed', 'certificate_id', v_existing); END IF;

  SELECT * INTO v_template FROM governance_documents
  WHERE doc_type = 'volunteer_term_template' AND status = 'active'
  ORDER BY created_at DESC LIMIT 1;
  IF v_template.id IS NULL THEN RETURN jsonb_build_object('error', 'template_not_found'); END IF;

  -- Find issuer: chapter_board of member's chapter, fallback to manager
  SELECT id INTO v_issuer_id FROM members
  WHERE chapter = v_member.chapter AND 'chapter_board' = ANY(designations) AND is_active = true
  ORDER BY operational_role = 'sponsor' DESC LIMIT 1;
  IF v_issuer_id IS NULL THEN
    SELECT id INTO v_issuer_id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1;
  END IF;

  -- ============================================================
  -- VEP lookup (fix: use real opportunity dates instead of hardcoded)
  -- ============================================================

  -- Map operational_role to VEP role_default
  v_member_role_for_vep := CASE
    WHEN v_member.operational_role IN ('tribe_leader', 'deputy_manager', 'manager') THEN 'leader'
    ELSE 'researcher'
  END;

  -- Attempt 1: find VEP via the member's application that matches role
  SELECT vo.*
  INTO v_vep
  FROM selection_applications sa
  JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
  WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
    AND sa.vep_opportunity_id IS NOT NULL
    AND vo.role_default = v_member_role_for_vep
    AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
  ORDER BY sa.created_at DESC
  LIMIT 1;

  -- Attempt 2: any application of this member in current year (regardless of role match)
  IF v_vep.opportunity_id IS NULL THEN
    SELECT vo.*
    INTO v_vep
    FROM selection_applications sa
    JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
    WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
      AND sa.vep_opportunity_id IS NOT NULL
      AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
    ORDER BY sa.created_at DESC
    LIMIT 1;
  END IF;

  -- Attempt 3 (founder/legacy fallback): any active VEP of current year matching role
  IF v_vep.opportunity_id IS NULL THEN
    SELECT *
    INTO v_vep
    FROM vep_opportunities
    WHERE EXTRACT(YEAR FROM start_date) = v_cycle
      AND role_default = v_member_role_for_vep
      AND is_active = true
    ORDER BY start_date DESC
    LIMIT 1;
  END IF;

  -- Attempt 4 (last resort): any VEP of current year
  IF v_vep.opportunity_id IS NULL THEN
    SELECT *
    INTO v_vep
    FROM vep_opportunities
    WHERE EXTRACT(YEAR FROM start_date) = v_cycle
    ORDER BY start_date DESC
    LIMIT 1;
  END IF;

  -- Final fallback: full calendar year
  IF v_vep.start_date IS NOT NULL THEN
    v_period_start := v_vep.start_date::text;
    v_period_end := v_vep.end_date::text;
  ELSE
    v_period_start := v_cycle::text || '-01-01';
    v_period_end := v_cycle::text || '-12-31';
  END IF;

  v_content := jsonb_build_object(
    'template_id', v_template.id,
    'template_version', v_template.version,
    'template_title', v_template.title,
    'member_name', v_member.name,
    'member_email', v_member.email,
    'member_role', v_member.operational_role,
    'member_tribe', v_member.tribe_name,
    'member_pmi_id', v_member.pmi_id,
    'member_chapter', v_member.chapter,
    'language', p_language,
    'signed_at', now(),
    'chapter_cnpj', '06.065.645/0001-99',
    'chapter_name', 'PMI Goias',
    'vep_opportunity_id', v_vep.opportunity_id,
    'vep_title', v_vep.title,
    'period_start', v_period_start,
    'period_end', v_period_end,
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

  INSERT INTO certificates (
    member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
    period_start, period_end, function_role, language, status, signature_hash, content_snapshot, template_id
  ) VALUES (
    v_member.id, 'volunteer_agreement',
    CASE p_language
      WHEN 'en-US' THEN 'Volunteer Agreement — Cycle ' || v_cycle
      WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado — Ciclo ' || v_cycle
      ELSE 'Termo de Voluntariado — Ciclo ' || v_cycle
    END,
    v_template.description, v_cycle, now(), v_issuer_id,
    v_code,
    v_period_start,  -- from VEP
    v_period_end,    -- from VEP
    v_member.operational_role, p_language, 'issued', v_hash, v_content, v_template.id::text
  ) RETURNING id INTO v_cert_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'volunteer_agreement_signed', 'certificate', v_cert_id,
    jsonb_build_object(
      'verification_code', v_code,
      'cycle', v_cycle,
      'chapter', v_member.chapter,
      'vep_opportunity_id', v_vep.opportunity_id,
      'period_start', v_period_start,
      'period_end', v_period_end
    ));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
  SELECT m.id, 'volunteer_agreement_signed',
    v_member.name || ' assinou o Termo de Voluntariado',
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

  RETURN jsonb_build_object(
    'success', true,
    'certificate_id', v_cert_id,
    'verification_code', v_code,
    'signature_hash', v_hash,
    'signed_at', now(),
    'period_start', v_period_start,
    'period_end', v_period_end
  );
END;
$$;

GRANT EXECUTE ON FUNCTION sign_volunteer_agreement(text) TO authenticated;

-- ============================================================
-- BACKFILL: fix period_start / period_end of existing volunteer_agreement certs
-- ============================================================
UPDATE certificates c
SET
  period_start = coalesce(vep_data.start_date, c.period_start),
  period_end = coalesce(vep_data.end_date, c.period_end),
  content_snapshot = c.content_snapshot || jsonb_build_object(
    'period_start', coalesce(vep_data.start_date, c.period_start),
    'period_end', coalesce(vep_data.end_date, c.period_end),
    'vep_opportunity_id', vep_data.opportunity_id,
    'vep_title', vep_data.title,
    'backfilled_at', now()
  )
FROM (
  SELECT DISTINCT ON (c2.id)
    c2.id as cert_id,
    vo.opportunity_id,
    vo.title,
    vo.start_date::text as start_date,
    vo.end_date::text as end_date
  FROM certificates c2
  JOIN members m ON m.id = c2.member_id
  LEFT JOIN selection_applications sa ON lower(trim(sa.email)) = lower(trim(m.email))
  LEFT JOIN vep_opportunities vo
    ON vo.opportunity_id = sa.vep_opportunity_id
    AND EXTRACT(YEAR FROM vo.start_date) = c2.cycle
    AND vo.role_default = CASE
      WHEN m.operational_role IN ('tribe_leader','deputy_manager','manager') THEN 'leader'
      ELSE 'researcher'
    END
  WHERE c2.type = 'volunteer_agreement'
    AND c2.status = 'issued'
  ORDER BY c2.id, sa.created_at DESC NULLS LAST
) vep_data
WHERE c.id = vep_data.cert_id
  AND vep_data.start_date IS NOT NULL;

-- Secondary backfill: founders/members without application → fallback to current-year VEP by role
UPDATE certificates c
SET
  period_start = coalesce(fallback.start_date, c.period_start),
  period_end = coalesce(fallback.end_date, c.period_end),
  content_snapshot = c.content_snapshot || jsonb_build_object(
    'period_start', coalesce(fallback.start_date, c.period_start),
    'period_end', coalesce(fallback.end_date, c.period_end),
    'vep_opportunity_id', fallback.opportunity_id,
    'vep_title', fallback.title,
    'backfilled_fallback', true,
    'backfilled_at', now()
  )
FROM (
  SELECT DISTINCT ON (c2.id)
    c2.id as cert_id,
    vo.opportunity_id,
    vo.title,
    vo.start_date::text as start_date,
    vo.end_date::text as end_date
  FROM certificates c2
  JOIN members m ON m.id = c2.member_id
  JOIN vep_opportunities vo
    ON EXTRACT(YEAR FROM vo.start_date) = c2.cycle
    AND vo.role_default = CASE
      WHEN m.operational_role IN ('tribe_leader','deputy_manager','manager') THEN 'leader'
      ELSE 'researcher'
    END
  WHERE c2.type = 'volunteer_agreement'
    AND c2.status = 'issued'
    AND (c2.period_end = (c2.cycle::text || '-06-30') OR c2.period_start = (c2.cycle::text || '-01-01'))
  ORDER BY c2.id, vo.start_date DESC
) fallback
WHERE c.id = fallback.cert_id;

NOTIFY pgrst, 'reload schema';
