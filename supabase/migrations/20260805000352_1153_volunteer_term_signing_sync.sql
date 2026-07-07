-- #1153 — Sincronizar o texto jurídico aprovado com o instrumento de Termo assinado (Direção 1).
--
-- Contexto (SPEC docs/reference/SPEC-1153-volunteer-term-signing-sync.md):
-- O Termo de Voluntariado tinha DUAS representações não sincronizadas — o leitor/aprovação
-- (document_versions.content_html, governado pela cadeia de gates) e a assinatura
-- (governance_documents.content, slots clauseN). Aprovar/travar a versão jurídica no leitor
-- NÃO alterava o que o voluntário assinava. Direção 1 (ratificada PM Vitor 2026-07-06):
-- o instrumento assinado passa a renderizar a partir da VERSÃO APROVADA DA CADEIA
-- (governance_documents.current_version_id -> document_versions.content_html). Fonte única.
--
-- Esta migração entrega a ARQUITETURA/tubulação (sem tocar no texto jurídico). A lavra v9
-- (do .docx V2) + lock via curator->president_go/Ivan + ativação da linha = Onda 1 governança
-- (depois). Enquanto nenhuma linha estiver 'active', a assinatura continua bloqueada (correto).

-- ─────────────────────────────────────────────────────────────────────────────
-- INV-1 — no máximo UMA linha volunteer_term_template 'active' (índice único parcial).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_one_active_volunteer_term
  ON public.governance_documents ((doc_type))
  WHERE status = 'active' AND doc_type = 'volunteer_term_template';

-- ─────────────────────────────────────────────────────────────────────────────
-- activate_volunteer_term_version — RPC admin explícita (decisão PM 2026-07-06):
-- flip atômico da ativação, gated por manage_platform. Governança roda 1x após o lock da
-- versão jurídica (Onda 1). Não toca o RPC de lock da cadeia (menor blast radius).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.activate_volunteer_term_version(p_doc_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_member uuid;
  v_doc record;
  v_html text;
  v_deactivated int := 0;
BEGIN
  SELECT id INTO v_actor_member FROM members WHERE auth_id = auth.uid();
  IF v_actor_member IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- Authority SSOT: can()/can_by_member() (ADR-0007). manage_platform = GP-only.
  IF NOT public.can_by_member(v_actor_member, 'manage_platform', NULL, NULL) THEN
    RETURN jsonb_build_object('error', 'forbidden',
      'message', 'Apenas manage_platform pode ativar uma versão do Termo de Voluntariado.');
  END IF;

  SELECT g.id, g.doc_type, g.status, g.current_version_id, g.version
    INTO v_doc
  FROM governance_documents g WHERE g.id = p_doc_id;
  IF v_doc.id IS NULL THEN RETURN jsonb_build_object('error', 'document_not_found'); END IF;
  IF v_doc.doc_type <> 'volunteer_term_template' THEN
    RETURN jsonb_build_object('error', 'wrong_doc_type', 'doc_type', v_doc.doc_type);
  END IF;

  -- A versão corrente deve estar TRAVADA (locked) na cadeia e ter corpo HTML — não se ativa
  -- um rascunho não-aprovado. locked_at IS NOT NULL == passou pela conclusão de cadeia.
  SELECT dv.content_html INTO v_html
  FROM document_versions dv
  WHERE dv.id = v_doc.current_version_id AND dv.locked_at IS NOT NULL;
  IF v_html IS NULL OR length(btrim(v_html)) = 0 THEN
    RETURN jsonb_build_object('error', 'no_locked_body',
      'message', 'A versão corrente não está travada (locked) ou não tem corpo HTML. Trave a versão na cadeia antes de ativar.',
      'current_version_id', v_doc.current_version_id);
  END IF;

  -- Flip atômico (INV-1): supersede qualquer outra ativa, então ativa esta.
  UPDATE governance_documents
     SET status = 'superseded', updated_at = now()
   WHERE doc_type = 'volunteer_term_template' AND status = 'active' AND id <> p_doc_id;
  GET DIAGNOSTICS v_deactivated = ROW_COUNT;

  UPDATE governance_documents SET status = 'active', updated_at = now() WHERE id = p_doc_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_actor_member, 'volunteer_term_activated', 'governance_document', p_doc_id,
    jsonb_build_object('version', v_doc.version, 'current_version_id', v_doc.current_version_id,
      'superseded_count', v_deactivated));

  RETURN jsonb_build_object('success', true, 'activated', p_doc_id,
    'version', v_doc.version, 'superseded', v_deactivated);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.activate_volunteer_term_version(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- sign_volunteer_agreement — Direção 1: snapshota o content_html APROVADO da cadeia em
-- content_snapshot.html_body (imutável, #648), com {chapterName} resolvido (#1048). Mantém
-- 'clauses' por segurança de rollback + para o invariante de dados do #648. CREATE OR REPLACE
-- (mesma assinatura text,text,text).
-- ─────────────────────────────────────────────────────────────────────────────
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
  v_contracting_code text;                         -- C3: registry code of the contracting chapter (GO)
  v_chapter_cnpj_source text := 'chapter_registry'; -- C3 R3: audit observability of the fallback
  v_issuer_basis text := 'contracting_chapter_board'; -- C3 R2: representation basis for issued_by
  v_ip inet := NULL;
  v_html_body text; v_body_version_label text; v_chapter_display text;  -- #1153 Direção 1
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

  -- #1153 Direção 1: o instrumento assinado renderiza a partir da VERSÃO APROVADA DA CADEIA
  -- (current_version_id -> document_versions.content_html), não dos slots clauseN. Snapshota
  -- esse corpo imutavelmente (#648) para que o assinado == o que a cadeia travou.
  SELECT dv.content_html, dv.version_label INTO v_html_body, v_body_version_label
  FROM document_versions dv WHERE dv.id = v_template.current_version_id;
  IF v_html_body IS NULL OR length(btrim(v_html_body)) = 0 THEN
    RETURN jsonb_build_object('error', 'approved_body_unavailable',
      'message', 'A versão aprovada do Termo não possui corpo HTML. Ative uma versão aprovada da cadeia via activate_volunteer_term_version.',
      'template_id', v_template.id, 'version_id', v_template.current_version_id);
  END IF;

  -- #1048/#1153: resolve o placeholder {chapterName} para o nome do capítulo contratante
  -- derivado do SSOT (chapter_registry.legal_name; forma curta entre parênteses quando houver),
  -- para que nenhum instrumento assinado congele um placeholder cru. Parte contratante = SEMPRE
  -- PMI-GO, independente da filiação do voluntário.
  v_chapter_display := COALESCE(
    NULLIF((regexp_match(v_chapter_legal_name, '\(([^)]+)\)\s*$'))[1], ''),
    v_chapter_legal_name);
  v_html_body := replace(v_html_body, '{chapterName}', v_chapter_display);

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
    -- Mantido para rollback + invariante de dados; o render de novos certos usa html_body.
    'clauses', v_template.content,
    -- #1153 Direção 1: corpo HTML APROVADO da cadeia, imutável, com {chapterName} resolvido.
    -- É este o texto que o novo render usa (fonte única = versão aprovada da cadeia).
    'html_body', v_html_body,
    'body_version_id', v_template.current_version_id,
    'body_version_label', v_body_version_label,
    'chapter_display_name', v_chapter_display,
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
      -- #1153: qual versão da cadeia foi congelada no instrumento assinado.
      'body_version_id', v_template.current_version_id,
      'body_version_label', v_body_version_label,
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
