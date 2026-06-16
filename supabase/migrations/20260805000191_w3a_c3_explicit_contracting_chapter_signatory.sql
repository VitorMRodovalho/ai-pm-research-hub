-- Wave 3a-ii (C3) #740 — make the volunteer-agreement contracting party + signatory EXPLICIT
--
-- WHAT: public.sign_volunteer_agreement no longer derives the contracting party from a
--   brittle, format-dependent join on the member's affiliation chapter. It now:
--   (R1) ALWAYS selects the contracting chapter (chapter_registry.is_contracting_chapter
--        = true → PMI-GO) as the contracting party (chapter_cnpj / chapter_name).
--   (R2) sets the issuer (issued_by) to a board member of the CONTRACTING chapter
--        (PMI-GO), not the volunteer's affiliation chapter — so the entity that contracts
--        and the entity whose representative signs are the same (CC/2002 arts. 115-120).
--        Falls back to a manager when no PMI-GO board member exists. Writes
--        `contracting_chapter` (= PMI-GO), `issuer_chapter`, `issuer_authority_basis`
--        to content_snapshot. The volunteer's own chapter stays as `member_chapter`
--        (informational indicator only).
--   (R3) records `chapter_cnpj_source` in admin_audit_log so the emergency hardcoded
--        fallback is observable if ever hit.
--
-- WHY: legal-counsel parecer (2026-06-16, #740 C3). Today the contracting party already
--   resolves to PMI-GO, but BY ACCIDENT: the first lookup joins chapter_registry.chapter_code
--   ('GO') to members.chapter ('PMI-GO') which never matches, so it falls through to the
--   is_contracting_chapter branch. That accident becomes a bug-as-governance time bomb the
--   moment members.chapter format is normalized (Wave 3 risk). The Núcleo program operates
--   under PMI-GO's legal entity; other chapters are informational affiliation. Making this
--   explicit carries zero added risk and removes the dependency on the format accident.
--   The issuer≠contractant inconsistency (a non-GO board member counter-signing a contract
--   with PMI-GO) is a representation defect (no delegation instrument exists) — Opção A
--   (issuer = contracting-chapter board) is adopted per the parecer.
--
-- COUNTER-SIGN: counter_sign_certificate already gates a chapter_board counter-signer by
--   content_snapshot->>'contracting_chapter' (falling back to the member's chapter). By now
--   WRITING contracting_chapter=PMI-GO at signing, that gate correctly requires a PMI-GO
--   board member (or any manage_member holder) — no change to counter_sign_certificate.
--
-- IMMUTABILITY (LGPD / #648): only FUTURE certificates are affected. Existing certs keep
--   their immutable content_snapshot + signature_hash; we never retroactively rewrite a
--   signed term (would be document tampering, CP art. 297 / Lei 14.063/2020 art. 4º).
--
-- DROP+CREATE (not CREATE OR REPLACE) per this function's drift history (parecer R5);
--   signature unchanged.
--
-- ROLLBACK: re-apply the pre-C3 body (20260805000150 / #648).

DROP FUNCTION IF EXISTS public.sign_volunteer_agreement(text, text, text);

CREATE FUNCTION public.sign_volunteer_agreement(p_language text DEFAULT 'pt-BR'::text, p_signed_ip text DEFAULT NULL::text, p_signed_user_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_template record; v_cert_id uuid; v_code text; v_hash text;
  v_content jsonb; v_cycle int; v_existing uuid; v_issuer_id uuid; v_vep record;
  v_period_start date; v_period_end date;
  v_member_role_for_vep text; v_history record; v_source text;
  v_missing_fields text[] := '{}';
  v_engagement_updated boolean := false;
  v_chapter_cnpj text; v_chapter_legal_name text;
  v_contracting_code text;                         -- C3: registry code of the contracting chapter (GO)
  v_chapter_cnpj_source text := 'chapter_registry'; -- C3 R3: audit observability of the fallback
  v_issuer_basis text := 'contracting_chapter_board'; -- C3 R2: representation basis for issued_by
  v_ip inet := NULL;
BEGIN
  -- Server-side cap on UA length to prevent storage abuse via direct PostgREST
  -- or MCP callers that bypass the frontend's 500-char trim.
  p_signed_user_agent := left(p_signed_user_agent, 500);

  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
    m.phone, m.address, m.city, m.state, m.country, m.birth_date,
    m.pmi_id_verified,  -- #625: estado do farol de filiação no momento da assinatura
    t.name as tribe_name
  INTO v_member
  FROM members m LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
  WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  IF v_member.pmi_id IS NULL OR length(trim(v_member.pmi_id)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'pmi_id');
  END IF;
  IF v_member.phone IS NULL OR length(trim(v_member.phone)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'phone');
  END IF;
  IF v_member.address IS NULL OR length(trim(v_member.address)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'address');
  END IF;
  IF v_member.city IS NULL OR length(trim(v_member.city)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'city');
  END IF;
  IF v_member.state IS NULL OR length(trim(v_member.state)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'state');
  END IF;
  IF v_member.country IS NULL OR length(trim(v_member.country)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'country');
  END IF;
  IF v_member.birth_date IS NULL THEN
    v_missing_fields := array_append(v_missing_fields, 'birth_date');
  END IF;

  IF array_length(v_missing_fields, 1) > 0 THEN
    RETURN jsonb_build_object(
      'error', 'profile_incomplete',
      'message', 'Você precisa completar seu perfil antes de assinar o Termo de Voluntariado.',
      'missing_fields', to_jsonb(v_missing_fields),
      'profile_url', '/profile'
    );
  END IF;

  -- C3 R1: the contracting party is ALWAYS the contracting chapter (PMI-GO), regardless of
  -- the volunteer's affiliation chapter. The member's chapter is informational only.
  SELECT cr.cnpj, cr.legal_name, cr.chapter_code
    INTO v_chapter_cnpj, v_chapter_legal_name, v_contracting_code
  FROM chapter_registry cr
  WHERE cr.is_contracting_chapter = true AND cr.is_active = true
  LIMIT 1;

  IF v_chapter_cnpj IS NULL THEN
    -- Emergency fallback (flagged in audit). Should never fire while chapter_registry is sane.
    v_chapter_cnpj := '06.065.645/0001-99';
    v_chapter_legal_name := 'PMI Goias';
    v_contracting_code := 'GO';
    v_chapter_cnpj_source := 'hardcoded_emergency_fallback';
  END IF;

  v_cycle := EXTRACT(YEAR FROM now())::int;
  SELECT id INTO v_existing FROM certificates
  WHERE member_id = v_member.id AND type = 'volunteer_agreement' AND cycle = v_cycle AND status = 'issued';
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_signed', 'certificate_id', v_existing); END IF;

  SELECT * INTO v_template FROM governance_documents
  WHERE doc_type = 'volunteer_term_template' AND status = 'active'
  ORDER BY created_at DESC LIMIT 1;
  IF v_template.id IS NULL THEN RETURN jsonb_build_object('error', 'template_not_found'); END IF;

  -- C3 R2: the issuer (issued_by) represents the CONTRACTING chapter (PMI-GO), so the
  -- entity that contracts and the representative who signs are the same. members.chapter is
  -- stored prefixed ('PMI-' || code); chapter_registry.chapter_code is unprefixed.
  SELECT id INTO v_issuer_id FROM members
  WHERE chapter = 'PMI-' || v_contracting_code AND 'chapter_board' = ANY(designations) AND is_active = true
  ORDER BY operational_role = 'sponsor' DESC LIMIT 1;
  IF v_issuer_id IS NULL THEN
    SELECT id INTO v_issuer_id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1;
    v_issuer_basis := 'manager_fallback';
  END IF;

  v_member_role_for_vep := CASE
    WHEN v_member.operational_role IN ('manager', 'deputy_manager') THEN 'manager'
    WHEN v_member.operational_role = 'tribe_leader' THEN 'leader'
    ELSE 'researcher'
  END;

  SELECT vo.* INTO v_vep FROM selection_applications sa
  JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
  WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
    AND vo.role_default = v_member_role_for_vep
    AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
  ORDER BY sa.created_at DESC LIMIT 1;

  IF v_vep.opportunity_id IS NOT NULL THEN
    v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'application_match';
  ELSE
    SELECT vo.* INTO v_vep FROM selection_applications sa
    JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
    WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
      AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
    ORDER BY sa.created_at DESC LIMIT 1;
    IF v_vep.opportunity_id IS NOT NULL THEN
      v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'application_year_match';
    ELSE
      SELECT cycle_code, cycle_start, cycle_end INTO v_history
      FROM member_cycle_history WHERE member_id = v_member.id
      ORDER BY cycle_start DESC LIMIT 1;
      IF v_history.cycle_code IS NOT NULL THEN
        v_period_start := v_history.cycle_start;
        v_period_end := (v_history.cycle_start + interval '12 months' - interval '1 day')::date;
        v_source := 'cycle_history:' || v_history.cycle_code;
      ELSE
        SELECT * INTO v_vep FROM vep_opportunities
        WHERE EXTRACT(YEAR FROM start_date) = v_cycle
          AND role_default = v_member_role_for_vep AND is_active = true
        ORDER BY start_date DESC LIMIT 1;
        IF v_vep.opportunity_id IS NOT NULL THEN
          v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'founder_role_vep';
        ELSE
          RETURN jsonb_build_object('error', 'cannot_derive_period',
            'message', 'No application, cycle history, or matching VEP found. Admin must set period manually.',
            'member_id', v_member.id, 'member_name', v_member.name);
        END IF;
      END IF;
    END IF;
  END IF;

  v_content := jsonb_build_object(
    'template_id', v_template.id, 'template_version', v_template.version, 'template_title', v_template.title,
    -- #648: snapshot do corpo COMPLETO das cláusulas na assinatura (imutabilidade).
    -- O render passa a usar este snapshot, nunca o template 'active' live; e o
    -- signature_hash (computado sobre v_content) passa a cobrir o texto aceito.
    'clauses', v_template.content,
    'member_name', v_member.name, 'member_email', v_member.email, 'member_role', v_member.operational_role,
    'member_tribe', v_member.tribe_name, 'member_pmi_id', v_member.pmi_id, 'member_chapter', v_member.chapter,
    'member_phone', v_member.phone, 'member_address', v_member.address,
    'member_city', v_member.city, 'member_state', v_member.state,
    'member_country', v_member.country, 'member_birth_date', v_member.birth_date,
    'language', p_language, 'signed_at', now(),
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name,
    -- C3 #740: explicit contracting party + issuer representation basis.
    'contracting_chapter', 'PMI-' || v_contracting_code,
    'issuer_chapter', 'PMI-' || v_contracting_code,
    'issuer_authority_basis', v_issuer_basis,
    'vep_opportunity_id', v_vep.opportunity_id, 'vep_title', v_vep.title,
    'period_start', v_period_start::text, 'period_end', v_period_end::text,
    'period_source', v_source
  );

  v_code := 'TERM-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));
  v_hash := encode(sha256(convert_to(v_content::text || v_member.id::text || now()::text || 'nucleo-ia-volunteer-salt', 'UTF8')), 'hex');

  BEGIN
    IF p_signed_ip IS NOT NULL AND length(trim(p_signed_ip)) > 0 THEN
      v_ip := p_signed_ip::inet;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
  END;

  INSERT INTO certificates (
    member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
    period_start, period_end, function_role, language, status, signature_hash, content_snapshot, template_id,
    signed_ip, signed_user_agent
  ) VALUES (
    v_member.id, 'volunteer_agreement',
    CASE p_language WHEN 'en-US' THEN 'Volunteer Agreement — Cycle ' || v_cycle
      WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado — Ciclo ' || v_cycle
      ELSE 'Termo de Voluntariado — Ciclo ' || v_cycle END,
    v_template.description, v_cycle, now(), v_issuer_id, v_code,
    v_period_start::text, v_period_end::text,
    v_member.operational_role, p_language, 'issued', v_hash, v_content, v_template.id::text,
    v_ip, p_signed_user_agent
  ) RETURNING id INTO v_cert_id;

  UPDATE public.engagements
  SET agreement_certificate_id = v_cert_id
  WHERE person_id = (SELECT id FROM public.persons WHERE legacy_member_id = v_member.id)
    AND kind = 'volunteer'
    AND status = 'active'
    AND agreement_certificate_id IS NULL;

  IF FOUND THEN v_engagement_updated := true; END IF;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'volunteer_agreement_signed', 'certificate', v_cert_id,
    jsonb_build_object('verification_code', v_code, 'cycle', v_cycle, 'chapter', v_member.chapter,
      'chapter_cnpj', v_chapter_cnpj,
      -- C3 R3: distinguishes chapter_registry-sourced contracting party from the emergency hardcode.
      'chapter_cnpj_source', v_chapter_cnpj_source,
      'contracting_chapter', 'PMI-' || v_contracting_code,
      'period_source', v_source, 'engagement_linked', v_engagement_updated,
      'signed_ip', v_ip::text, 'signed_user_agent', p_signed_user_agent,
      -- #625 §2.8: farol de filiação no momento da assinatura (v1 = farol, não bloqueio).
      -- Permite ao v2 distinguir termos pré-loop × pós-loop ao avaliar política de bloqueio.
      'affiliation_unverified', NOT COALESCE(v_member.pmi_id_verified, false)));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  SELECT m.id, 'volunteer_agreement_signed',
    v_member.name || ' assinou o Termo de Voluntariado',
    'Capitulo: ' || COALESCE(v_member.chapter, '—') || '. Codigo: ' || v_code,
    '/admin/certificates', 'certificate', v_cert_id,
    public._delivery_mode_for('volunteer_agreement_signed')
  FROM members m
  WHERE m.is_active = true AND m.id != v_member.id
    AND (m.operational_role = 'manager' OR m.is_superadmin = true
         OR ('chapter_board' = ANY(m.designations) AND m.chapter = v_member.chapter));

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code,
    'signature_hash', v_hash, 'signed_at', now(),
    'period_start', v_period_start, 'period_end', v_period_end, 'period_source', v_source,
    'engagement_linked', v_engagement_updated,
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name);
END;
$function$;

NOTIFY pgrst, 'reload schema';
