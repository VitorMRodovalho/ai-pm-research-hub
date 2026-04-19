-- ============================================================================
-- Migration: Phase IP-2b (B4) — UE consent gate for sign_ip_ratification
-- ADR-0016 D2 (GDPR Art. 49(1)(a) consent) + source docs Cláusula 14 / Art. 8.
--
-- Adds:
--   1. public.is_eu_resident(p_person_id uuid) — boolean helper matching
--      country against EU/EEA list (EN + PT-BR + ISO variants).
--   2. sign_ip_ratification: new p_ue_consent_49_1_a param. When caller is
--      EU resident AND signing Termo or Adendo Retif member_ratification gate,
--      p_ue_consent_49_1_a MUST be true (else access_denied). Stored in
--      content_snapshot.ue_consent_recorded for audit.
--
-- Rollback: restore previous sign_ip_ratification signature (stored in comment
-- at bottom of this file for reference) + DROP FUNCTION is_eu_resident.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Helper: is_eu_resident
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_eu_resident(p_person_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_country text;
BEGIN
  SELECT country INTO v_country FROM public.persons WHERE id = p_person_id;
  IF v_country IS NULL THEN RETURN false; END IF;

  -- Case-insensitive match against EU/EEA list (EN + PT-BR + ISO variants).
  -- Note: includes EEA non-EU (Iceland, Norway, Liechtenstein) since GDPR applies.
  RETURN lower(trim(v_country)) = ANY (ARRAY[
    -- EN names
    'austria', 'belgium', 'bulgaria', 'croatia', 'cyprus', 'czech republic',
    'czechia', 'denmark', 'estonia', 'finland', 'france', 'germany',
    'greece', 'hungary', 'ireland', 'italy', 'latvia', 'lithuania',
    'luxembourg', 'malta', 'netherlands', 'poland', 'portugal', 'romania',
    'slovakia', 'slovenia', 'spain', 'sweden',
    'iceland', 'liechtenstein', 'norway',
    -- PT-BR names
    'áustria', 'austria', 'bélgica', 'belgica', 'bulgária', 'bulgaria',
    'croácia', 'croacia', 'chipre', 'república tcheca', 'republica tcheca',
    'tchéquia', 'tchequia', 'dinamarca', 'estônia', 'estonia', 'finlândia',
    'finlandia', 'frança', 'franca', 'alemanha', 'grécia', 'grecia',
    'hungria', 'irlanda', 'itália', 'italia', 'letônia', 'letonia',
    'lituânia', 'lituania', 'luxemburgo', 'malta', 'países baixos',
    'paises baixos', 'holanda', 'polônia', 'polonia', 'portugal', 'romênia',
    'romenia', 'eslováquia', 'eslovaquia', 'eslovênia', 'eslovenia',
    'espanha', 'suécia', 'suecia', 'islândia', 'islandia', 'liechtenstein',
    'noruega',
    -- ISO 3166-1 alpha-2 codes
    'at', 'be', 'bg', 'hr', 'cy', 'cz', 'dk', 'ee', 'fi', 'fr', 'de',
    'gr', 'hu', 'ie', 'it', 'lv', 'lt', 'lu', 'mt', 'nl', 'pl', 'pt',
    'ro', 'sk', 'si', 'es', 'se',
    'is', 'li', 'no'
  ]);
END;
$function$;

COMMENT ON FUNCTION public.is_eu_resident(uuid) IS
  'Boolean helper: returns true if persons.country maps to an EU/EEA country (GDPR applies). Matches EN/PT-BR names + ISO 3166-1 alpha-2 codes, case-insensitive. Used by sign_ip_ratification to gate UE consent (ADR-0016 D2 / Política §2.5 / Termo Cláusula 14 / Adendo Retif Art. 8).';

GRANT EXECUTE ON FUNCTION public.is_eu_resident(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- sign_ip_ratification: extend signature with p_ue_consent_49_1_a param
-- ---------------------------------------------------------------------------
-- DROP + CREATE required because signature changes (new param, same return type)
DROP FUNCTION IF EXISTS public.sign_ip_ratification(uuid, text, text, jsonb, text);

CREATE OR REPLACE FUNCTION public.sign_ip_ratification(
  p_chain_id uuid,
  p_gate_kind text,
  p_signoff_type text DEFAULT 'approval'::text,
  p_sections_verified jsonb DEFAULT NULL::jsonb,
  p_comment_body text DEFAULT NULL::text,
  p_ue_consent_49_1_a boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_member record;
  v_chain record;
  v_version record;
  v_doc record;
  v_signoff_id uuid;
  v_hash text;
  v_snapshot jsonb;
  v_existing uuid;
  v_all_satisfied boolean;
  v_cert_id uuid;
  v_cert_code text;
  v_gates_remaining int;
  v_mbr_signature_id uuid;
  v_is_eu boolean := false;
  v_ue_consent_required boolean := false;
  v_ue_docs text[] := ARRAY[
    'Termo de Compromisso de Voluntário — Núcleo de IA & GP',
    'Adendo Retificativo ao Termo de Compromisso de Voluntario'
  ];
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
         m.designations, m.member_status, m.person_id
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error','not_authenticated'); END IF;

  IF NOT public._can_sign_gate(v_member.id, p_chain_id, p_gate_kind) THEN
    RETURN jsonb_build_object('error','access_denied','message','Member not authorized for gate_kind=' || p_gate_kind);
  END IF;

  SELECT ac.id, ac.status, ac.document_id, ac.version_id, ac.gates
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN jsonb_build_object('error','chain_not_found'); END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html, dv.locked_at
  INTO v_version FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT id INTO v_existing FROM public.approval_signoffs
  WHERE approval_chain_id = p_chain_id AND gate_kind = p_gate_kind AND signer_id = v_member.id;
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error','already_signed','signoff_id',v_existing); END IF;

  -- UE consent gate: required for EU residents signing member_ratification on
  -- Termo or Adendo Retificativo (ADR-0016 D2, Política §2.5, Termo Cl. 14,
  -- Adendo Retif Art. 8).
  IF p_gate_kind = 'member_ratification' AND v_doc.title = ANY(v_ue_docs) THEN
    v_is_eu := public.is_eu_resident(v_member.person_id);
    IF v_is_eu THEN
      v_ue_consent_required := true;
      IF p_ue_consent_49_1_a IS NULL OR p_ue_consent_49_1_a = false THEN
        RETURN jsonb_build_object(
          'error', 'ue_consent_required',
          'message', 'EU resident must explicitly consent to Art. 49(1)(a) GDPR data transfer. See Política §2.5, Termo Cláusula 14 (or Adendo Retif Art. 8).',
          'document_title', v_doc.title,
          'applicable_clause', CASE
            WHEN v_doc.title = 'Termo de Compromisso de Voluntário — Núcleo de IA & GP' THEN 'Cláusula 14'
            ELSE 'Art. 8'
          END
        );
      END IF;
    END IF;
  END IF;

  v_snapshot := jsonb_build_object(
    'document_id', v_doc.id, 'document_title', v_doc.title, 'doc_type', v_doc.doc_type,
    'version_id', v_version.id, 'version_number', v_version.version_number, 'version_label', v_version.version_label,
    'version_locked_at', v_version.locked_at,
    'signer_id', v_member.id, 'signer_name', v_member.name, 'signer_email', v_member.email,
    'signer_role', v_member.operational_role, 'signer_chapter', v_member.chapter,
    'signer_pmi_id', v_member.pmi_id, 'signer_designations', to_jsonb(v_member.designations),
    'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type, 'signed_at', now(),
    'signer_is_eu_resident', v_is_eu,
    'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
    'ue_consent_required_by_policy', v_ue_consent_required);

  v_hash := encode(sha256(convert_to(v_snapshot::text || v_member.id::text || now()::text || 'nucleo-ia-ip-ratify-salt', 'UTF8')), 'hex');

  INSERT INTO public.approval_signoffs (
    approval_chain_id, gate_kind, signer_id, signoff_type,
    signed_at, signature_hash, content_snapshot, sections_verified, comment_body
  ) VALUES (
    p_chain_id, p_gate_kind, v_member.id, p_signoff_type,
    now(), v_hash, v_snapshot, p_sections_verified, p_comment_body
  ) RETURNING id INTO v_signoff_id;

  SELECT COUNT(*) INTO v_gates_remaining
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE (g->>'threshold') = 'all'
     OR ((g->>'threshold') ~ '^[0-9]+$'
        AND (SELECT COUNT(*) FROM public.approval_signoffs s
             WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (g->>'kind')
               AND s.signoff_type IN ('approval','acknowledge')) < (g->>'threshold')::int);

  v_all_satisfied := (v_gates_remaining = 0);

  IF p_gate_kind = 'member_ratification' AND p_signoff_type = 'approval' THEN
    v_cert_code := 'IPRAT-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));

    INSERT INTO public.certificates (
      member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
      function_role, language, status, signature_hash, content_snapshot, template_id
    ) VALUES (
      v_member.id, 'ip_ratification',
      'Ratificacao IP — ' || v_doc.title,
      'Ratificacao do documento ' || v_doc.title || ' versao ' || v_version.version_label,
      EXTRACT(YEAR FROM now())::int, now(), v_member.id, v_cert_code,
      v_member.operational_role, 'pt-BR', 'issued', v_hash, v_snapshot, v_doc.id::text
    ) RETURNING id INTO v_cert_id;

    INSERT INTO public.member_document_signatures (
      member_id, document_id, signed_version_id, approval_chain_id,
      signoff_id, certificate_id, signed_at, is_current
    ) VALUES (v_member.id, v_doc.id, v_version.id, p_chain_id, v_signoff_id, v_cert_id, now(), true)
    RETURNING id INTO v_mbr_signature_id;
  END IF;

  IF v_all_satisfied AND v_chain.status = 'review' THEN
    UPDATE public.approval_chains SET status = 'approved', approved_at = now(), updated_at = now()
      WHERE id = p_chain_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'ip_ratification_signoff', 'approval_signoff', v_signoff_id,
    jsonb_build_object('chain_id', p_chain_id, 'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type,
      'document_id', v_doc.id, 'document_title', v_doc.title, 'version_label', v_version.version_label,
      'chain_satisfied', v_all_satisfied, 'certificate_id', v_cert_id,
      'signer_is_eu_resident', v_is_eu,
      'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false)));

  RETURN jsonb_build_object('success', true, 'signoff_id', v_signoff_id, 'signature_hash', v_hash,
    'gates_remaining', v_gates_remaining, 'chain_satisfied', v_all_satisfied,
    'certificate_id', v_cert_id, 'certificate_code', v_cert_code,
    'member_signature_id', v_mbr_signature_id, 'signed_at', now(),
    'signer_is_eu_resident', v_is_eu,
    'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false));
END;
$function$;

COMMENT ON FUNCTION public.sign_ip_ratification(uuid, text, text, jsonb, text, boolean) IS
  'Signoff em approval_chain gate. Extende IP-1 com p_ue_consent_49_1_a (ADR-0016 D2). Para residentes UE assinando Termo ou Adendo Retif no gate member_ratification, consentimento GDPR Art. 49(1)(a) é OBRIGATÓRIO (retorna access_denied/ue_consent_required se ausente). Estado do consentimento registrado em content_snapshot.ue_consent_recorded + admin_audit_log.changes.';

GRANT EXECUTE ON FUNCTION public.sign_ip_ratification(uuid, text, text, jsonb, text, boolean) TO authenticated;
