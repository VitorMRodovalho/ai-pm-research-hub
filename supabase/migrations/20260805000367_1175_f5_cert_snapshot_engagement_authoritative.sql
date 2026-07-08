-- #1175 F5: the volunteer-term certificate stamped two stale/derived values into a LEGAL
-- snapshot (index case TERM-2026-9EED7D, audited live 2026-07-08):
--
--   1. function_role / content_snapshot.member_role = members.operational_role — a CACHE
--      that, for a FIRST-TIME signer, is structurally 'guest' at sign time: signing the
--      term is precisely what flips the cache to the real role (term gate), so the legal
--      document recorded the pre-sign placeholder, never the volunteer's actual function.
--   2. period_start/end came from the matched VEP OPPORTUNITY window
--      (period_source='application_match', e.g. 2026-01-20 → 2026-12-19) even when the
--      member's own engagement carries the actual service vigency
--      (e.g. 2026-07-05 → 2027-06-30, end_date fed by VEP serviceEndDateUTC, Decision 8).
--
-- Fix (forward-only; issued certificates are immutable — signature_hash covers the
-- snapshot — the index-case cert can be re-issued via reissue_agreement if the PM wants):
--   - Derive role and period from the ACTIVE volunteer engagement (the V4 authoritative
--     record, ADR-0006/0007) when available; content_snapshot gains member_role_source
--     ('engagement' | 'operational_role_cache') and the new period_source value
--     'engagement_vigency'. All previous fallbacks preserved unchanged (opportunity
--     match → year match → cycle_history → founder_role_vep).
--   - The VEP opportunity lookup is kept regardless, for snapshot metadata
--     (vep_opportunity_id / vep_title) and as the period fallback.

CREATE OR REPLACE FUNCTION public.sign_volunteer_agreement(p_language text DEFAULT 'pt-BR'::text, p_signed_ip text DEFAULT NULL::text, p_signed_user_agent text DEFAULT NULL::text)
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
  v_contracting_code text;
  v_chapter_cnpj_source text := 'chapter_registry';
  v_issuer_basis text := 'contracting_chapter_board';
  v_ip inet := NULL;
  v_html_body text; v_body_version_label text; v_chapter_display text;
  v_eng record;
  v_function_role text;
  v_function_role_source text := 'operational_role_cache';
BEGIN
  p_signed_user_agent := left(p_signed_user_agent, 500);

  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
    m.phone, m.address, m.city, m.state, m.country, m.birth_date,
    m.pmi_id_verified,
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

  SELECT cr.cnpj, cr.legal_name, cr.chapter_code
    INTO v_chapter_cnpj, v_chapter_legal_name, v_contracting_code
  FROM chapter_registry cr
  WHERE cr.is_contracting_chapter = true AND cr.is_active = true
  LIMIT 1;

  IF v_chapter_cnpj IS NULL THEN
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

  SELECT dv.content_html, dv.version_label INTO v_html_body, v_body_version_label
  FROM document_versions dv WHERE dv.id = v_template.current_version_id;
  IF v_html_body IS NULL OR length(btrim(v_html_body)) = 0 THEN
    RETURN jsonb_build_object('error', 'approved_body_unavailable',
      'message', 'A versão aprovada do Termo não possui corpo HTML. Ative uma versão aprovada da cadeia via activate_volunteer_term_version.',
      'template_id', v_template.id, 'version_id', v_template.current_version_id);
  END IF;

  v_chapter_display := COALESCE(
    NULLIF((regexp_match(v_chapter_legal_name, '\(([^)]+)\)\s*$'))[1], ''),
    v_chapter_legal_name);
  v_html_body := replace(v_html_body, '{chapterName}', v_chapter_display);

  SELECT id INTO v_issuer_id FROM members
  WHERE chapter = 'PMI-' || v_contracting_code AND 'chapter_board' = ANY(designations) AND is_active = true
  ORDER BY operational_role = 'sponsor' DESC LIMIT 1;
  IF v_issuer_id IS NULL THEN
    SELECT id INTO v_issuer_id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1;
    v_issuer_basis := 'manager_fallback';
  END IF;

  -- #1175 F5: the ACTIVE volunteer engagement is the authoritative record for the
  -- volunteer's function and service vigency (ADR-0006/0007). The operational_role
  -- cache is structurally 'guest' for a first-time signer (the term gate flips it
  -- only AFTER this signature), so it must never be the primary source of a legal
  -- snapshot. Fallback to the cache only when no active engagement exists.
  SELECT e.role, e.start_date, e.end_date INTO v_eng
  FROM engagements e
  JOIN persons p ON p.id = e.person_id
  WHERE p.legacy_member_id = v_member.id
    AND e.kind = 'volunteer' AND e.status = 'active'
  ORDER BY e.granted_at DESC LIMIT 1;

  IF v_eng.role IS NOT NULL THEN
    v_function_role := v_eng.role;
    v_function_role_source := 'engagement';
  ELSE
    v_function_role := v_member.operational_role;
  END IF;

  -- Tolerates both vocabularies (engagement roles and operational_role cache values).
  v_member_role_for_vep := CASE
    WHEN v_function_role IN ('manager', 'deputy_manager') THEN 'manager'
    WHEN v_function_role IN ('tribe_leader', 'leader') THEN 'leader'
    ELSE 'researcher'
  END;

  -- VEP opportunity lookup kept regardless of the period source: it feeds the snapshot
  -- metadata (vep_opportunity_id / vep_title) and the period fallback chain.
  SELECT vo.* INTO v_vep FROM selection_applications sa
  JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
  WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
    AND vo.role_default = v_member_role_for_vep
    AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
  ORDER BY sa.created_at DESC LIMIT 1;

  IF v_eng.start_date IS NOT NULL AND v_eng.end_date IS NOT NULL THEN
    -- #1175 F5: the engagement vigency is the member's ACTUAL service period (end_date
    -- fed by VEP serviceEndDateUTC, Decision 8) — it wins over the opportunity window.
    v_period_start := v_eng.start_date; v_period_end := v_eng.end_date; v_source := 'engagement_vigency';
  ELSIF v_vep.opportunity_id IS NOT NULL THEN
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
    'clauses', v_template.content,
    'html_body', v_html_body,
    'body_version_id', v_template.current_version_id,
    'body_version_label', v_body_version_label,
    'chapter_display_name', v_chapter_display,
    'member_name', v_member.name, 'member_email', v_member.email, 'member_role', v_function_role,
    'member_role_source', v_function_role_source,
    'member_tribe', v_member.tribe_name, 'member_pmi_id', v_member.pmi_id, 'member_chapter', v_member.chapter,
    'member_phone', v_member.phone, 'member_address', v_member.address,
    'member_city', v_member.city, 'member_state', v_member.state,
    'member_country', v_member.country, 'member_birth_date', v_member.birth_date,
    'language', p_language, 'signed_at', now(),
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name,
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
    v_function_role, p_language, 'issued', v_hash, v_content, v_template.id::text,
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
      'chapter_cnpj_source', v_chapter_cnpj_source,
      'contracting_chapter', 'PMI-' || v_contracting_code,
      'body_version_id', v_template.current_version_id,
      'body_version_label', v_body_version_label,
      'function_role', v_function_role,
      'function_role_source', v_function_role_source,
      'period_source', v_source, 'engagement_linked', v_engagement_updated,
      'signed_ip', v_ip::text, 'signed_user_agent', p_signed_user_agent,
      'affiliation_unverified', NOT COALESCE(v_member.pmi_id_verified, false)));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  SELECT m.id, 'volunteer_agreement_signed',
    v_member.name || ' assinou o Termo de Voluntariado',
    'Capitulo: ' || COALESCE(v_member.chapter, '—') || '. Codigo: ' || v_code,
    '/admin/certificates', 'certificate', v_cert_id,
    public._delivery_mode_for('volunteer_agreement_signed')
  FROM members m
  WHERE m.is_active = true AND m.id != v_member.id
    AND (public.can_by_member(m.id, 'manage_platform')
         OR ('voluntariado_director' = ANY(m.designations) AND m.chapter = 'PMI-' || v_contracting_code));

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code,
    'signature_hash', v_hash, 'signed_at', now(),
    'period_start', v_period_start, 'period_end', v_period_end, 'period_source', v_source,
    'engagement_linked', v_engagement_updated,
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name);
END;
$function$;

NOTIFY pgrst, 'reload schema';
