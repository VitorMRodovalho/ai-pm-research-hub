-- ============================================================================
-- Phase IP-1: RPCs
-- - _can_sign_gate(member_id, chain_id, gate_kind) helper
-- - create_external_signer_invite(p_email, p_name, p_organization, p_relationship, p_chapter_code)
-- - sign_ip_ratification(p_chain_id, p_gate_kind, p_signoff_type, p_sections_verified, p_comment_body)
-- - get_pending_ratifications() para o membro autenticado
-- Rollback: DROP FUNCTION <names>
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Helper: can_sign_gate
-- Retorna true se member pode assinar para gate_kind no approval_chain
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._can_sign_gate(
  p_member_id uuid,
  p_chain_id uuid,
  p_gate_kind text
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $function$
DECLARE
  v_member record;
  v_chain record;
BEGIN
  SELECT m.operational_role, m.designations, m.chapter, m.is_active, m.member_status
  INTO v_member FROM public.members m WHERE m.id = p_member_id;
  IF v_member.id IS NULL OR v_member.is_active = false THEN RETURN false; END IF;

  SELECT ac.status, ac.gates INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.status NOT IN ('review','approved') THEN RETURN false; END IF;

  -- gate_kind must be listed in chain.gates config
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_chain.gates) g WHERE g->>'kind' = p_gate_kind) THEN
    RETURN false;
  END IF;

  RETURN CASE p_gate_kind
    WHEN 'curator' THEN 'curator' = ANY(v_member.designations)
    WHEN 'leader' THEN v_member.operational_role IN ('tribe_leader','manager','deputy_manager')
    WHEN 'president_go' THEN v_member.chapter = 'PMI-GO' AND 'chapter_board' = ANY(v_member.designations)
    WHEN 'president_others' THEN v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS') AND 'chapter_board' = ANY(v_member.designations)
    WHEN 'member_ratification' THEN v_member.member_status = 'active'
    WHEN 'external_signer' THEN v_member.operational_role = 'external_signer'
    ELSE false
  END;
END;
$function$;

COMMENT ON FUNCTION public._can_sign_gate(uuid,uuid,text) IS
  'Helper: member pode assinar gate_kind neste approval_chain? Valida role, chapter, engagement + gate config. Phase IP-1.';

-- ---------------------------------------------------------------------------
-- 2. create_external_signer_invite
-- Admin cria entrada leve (person + member + engagement) para signer externo.
-- Magic-link real (URL + auth link) vem via Edge Function Phase IP-3.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_external_signer_invite(
  p_email text,
  p_name text,
  p_organization text,
  p_relationship text,
  p_chapter_code text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $function$
DECLARE
  v_actor_member record;
  v_person_id uuid;
  v_member_id uuid;
  v_org_id uuid;
  v_existing_person uuid;
  v_existing_member uuid;
  v_engagement_id uuid;
  v_chapter_id uuid;
BEGIN
  -- Validate caller
  SELECT m.id, m.name, m.operational_role INTO v_actor_member
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_actor_member.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_actor_member.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','access_denied','message','manage_member required');
  END IF;

  -- Validate inputs
  IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
    RETURN jsonb_build_object('error','email_required');
  END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
    RETURN jsonb_build_object('error','name_required');
  END IF;

  -- Check dupes
  SELECT id INTO v_existing_person FROM public.persons WHERE lower(email) = lower(p_email);
  IF v_existing_person IS NOT NULL THEN
    SELECT id INTO v_existing_member FROM public.members WHERE person_id = v_existing_person LIMIT 1;
    IF v_existing_member IS NOT NULL THEN
      RETURN jsonb_build_object('error','already_exists','person_id',v_existing_person,'member_id',v_existing_member);
    END IF;
    v_person_id := v_existing_person;
  END IF;

  -- PMI-GO organization id
  v_org_id := '2b4f58ab-7c45-4170-8718-b77ee69ff906';

  -- Create person if needed
  IF v_person_id IS NULL THEN
    INSERT INTO public.persons (
      organization_id, name, email, consent_status, consent_accepted_at, consent_version
    ) VALUES (
      v_org_id, trim(p_name), lower(trim(p_email)),
      'pending_magic_link', now(), 'v2.1-external-signer'
    ) RETURNING id INTO v_person_id;
  END IF;

  -- Create member
  INSERT INTO public.members (
    person_id, name, email, chapter, operational_role, member_status, is_active,
    organization_id, consent_status, consent_accepted_at, consent_version,
    created_at, updated_at
  ) VALUES (
    v_person_id, trim(p_name), lower(trim(p_email)), COALESCE(p_chapter_code,'EXTERNAL'),
    'external_signer', 'active', true,
    v_org_id, 'pending_magic_link', now(), 'v2.1-external-signer',
    now(), now()
  ) RETURNING id INTO v_member_id;

  -- Create auth_engagement row (kind=external_signer, authoritative)
  INSERT INTO public.auth_engagements (
    person_id, organization_id, kind, role, status,
    start_date, end_date, legal_basis, is_authoritative
  ) VALUES (
    v_person_id, v_org_id, 'external_signer', 'signer', 'active',
    CURRENT_DATE, (CURRENT_DATE + interval '1 year')::date,
    'legitimate_interest', true
  );

  -- Audit
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_actor_member.id, 'external_signer_invite_created', 'member', v_member_id,
    jsonb_build_object(
      'email', lower(trim(p_email)),
      'name', trim(p_name),
      'organization', p_organization,
      'relationship', p_relationship,
      'chapter_code', p_chapter_code
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'person_id', v_person_id,
    'member_id', v_member_id,
    'email', lower(trim(p_email)),
    'note', 'Magic-link URL generation pending Phase IP-3 Edge Function. Member row + engagement ready.'
  );
END;
$function$;

COMMENT ON FUNCTION public.create_external_signer_invite(text,text,text,text,text) IS
  'Cria person + member + engagement kind=external_signer para signatario externo (presidente/parceiro). Magic-link URL via EF Phase IP-3. Auth gate: manage_member. Phase IP-1.';

GRANT EXECUTE ON FUNCTION public.create_external_signer_invite(text,text,text,text,text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. sign_ip_ratification
-- Insere approval_signoff para membro autenticado. Atualiza chain status se
-- todos gates satisfeitos. Emite certificate ip_ratification.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sign_ip_ratification(
  p_chain_id uuid,
  p_gate_kind text,
  p_signoff_type text DEFAULT 'approval',
  p_sections_verified jsonb DEFAULT NULL,
  p_comment_body text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $function$
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
BEGIN
  -- Authenticate caller
  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
    m.designations, m.member_status
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  -- Validate gate authorization
  IF NOT public._can_sign_gate(v_member.id, p_chain_id, p_gate_kind) THEN
    RETURN jsonb_build_object('error','access_denied','message','Member not authorized for gate_kind=' || p_gate_kind);
  END IF;

  -- Fetch chain + version + doc
  SELECT ac.id, ac.status, ac.document_id, ac.version_id, ac.gates
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN
    RETURN jsonb_build_object('error','chain_not_found');
  END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html, dv.locked_at
  INTO v_version FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  -- Idempotence check
  SELECT id INTO v_existing FROM public.approval_signoffs
  WHERE approval_chain_id = p_chain_id AND gate_kind = p_gate_kind AND signer_id = v_member.id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('error','already_signed','signoff_id',v_existing);
  END IF;

  -- Build content_snapshot
  v_snapshot := jsonb_build_object(
    'document_id', v_doc.id, 'document_title', v_doc.title, 'doc_type', v_doc.doc_type,
    'version_id', v_version.id, 'version_number', v_version.version_number, 'version_label', v_version.version_label,
    'version_locked_at', v_version.locked_at,
    'signer_id', v_member.id, 'signer_name', v_member.name, 'signer_email', v_member.email,
    'signer_role', v_member.operational_role, 'signer_chapter', v_member.chapter,
    'signer_pmi_id', v_member.pmi_id, 'signer_designations', to_jsonb(v_member.designations),
    'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type,
    'signed_at', now()
  );

  v_hash := encode(sha256(convert_to(v_snapshot::text || v_member.id::text || now()::text || 'nucleo-ia-ip-ratify-salt', 'UTF8')), 'hex');

  -- Insert signoff
  INSERT INTO public.approval_signoffs (
    approval_chain_id, gate_kind, signer_id, signoff_type,
    signed_at, signature_hash, content_snapshot, sections_verified, comment_body
  ) VALUES (
    p_chain_id, p_gate_kind, v_member.id, p_signoff_type,
    now(), v_hash, v_snapshot, p_sections_verified, p_comment_body
  ) RETURNING id INTO v_signoff_id;

  -- Check if chain is satisfied (todos gates com threshold atendido)
  SELECT COUNT(*) INTO v_gates_remaining
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE (
    (g->>'threshold') = 'all'
      AND NOT EXISTS (
        SELECT 1 FROM public.members m WHERE m.member_status = 'active'
      )
  )
  OR (
    (g->>'threshold') ~ '^[0-9]+$'
      AND (SELECT COUNT(*) FROM public.approval_signoffs s
           WHERE s.approval_chain_id = p_chain_id
             AND s.gate_kind = (g->>'kind')
             AND s.signoff_type IN ('approval','acknowledge'))
          < (g->>'threshold')::int
  );

  v_all_satisfied := (v_gates_remaining = 0);

  -- Emit certificate if member_ratification gate (issuance per member)
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
    ) VALUES (
      v_member.id, v_doc.id, v_version.id, p_chain_id,
      v_signoff_id, v_cert_id, now(), true
    ) RETURNING id INTO v_mbr_signature_id;
  END IF;

  -- Update chain if satisfied
  IF v_all_satisfied AND v_chain.status = 'review' THEN
    UPDATE public.approval_chains
       SET status = 'approved', approved_at = now(), updated_at = now()
     WHERE id = p_chain_id;
  END IF;

  -- Audit
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_member.id, 'ip_ratification_signoff', 'approval_signoff', v_signoff_id,
    jsonb_build_object(
      'chain_id', p_chain_id, 'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type,
      'document_id', v_doc.id, 'document_title', v_doc.title,
      'version_label', v_version.version_label,
      'chain_satisfied', v_all_satisfied,
      'certificate_id', v_cert_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'signoff_id', v_signoff_id,
    'signature_hash', v_hash,
    'gates_remaining', v_gates_remaining,
    'chain_satisfied', v_all_satisfied,
    'certificate_id', v_cert_id,
    'certificate_code', v_cert_code,
    'member_signature_id', v_mbr_signature_id,
    'signed_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.sign_ip_ratification(uuid,text,text,jsonb,text) IS
  'Assinatura de approval_chain gate por membro autenticado. Valida gate via _can_sign_gate. Insere approval_signoff + content_snapshot + signature_hash. Se gate=member_ratification emite certificate type=ip_ratification + member_document_signature. Phase IP-1.';

GRANT EXECUTE ON FUNCTION public.sign_ip_ratification(uuid,text,text,jsonb,text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. get_pending_ratifications
-- Lista chains em status=review que o membro atual pode (ainda nao) assinou
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_pending_ratifications()
RETURNS TABLE (
  chain_id uuid,
  document_id uuid,
  document_title text,
  doc_type text,
  version_id uuid,
  version_label text,
  version_locked_at timestamptz,
  gates jsonb,
  opened_at timestamptz,
  status text,
  eligible_gates text[]
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    ac.id AS chain_id,
    gd.id AS document_id,
    gd.title AS document_title,
    gd.doc_type,
    dv.id AS version_id,
    dv.version_label,
    dv.locked_at AS version_locked_at,
    ac.gates,
    ac.opened_at,
    ac.status,
    (
      SELECT ARRAY_AGG(g->>'kind' ORDER BY (g->>'order')::int)
      FROM jsonb_array_elements(ac.gates) g
      WHERE public._can_sign_gate(v_member_id, ac.id, g->>'kind')
        AND NOT EXISTS (
          SELECT 1 FROM public.approval_signoffs s
          WHERE s.approval_chain_id = ac.id AND s.gate_kind = g->>'kind' AND s.signer_id = v_member_id
        )
    ) AS eligible_gates
  FROM public.approval_chains ac
  JOIN public.governance_documents gd ON gd.id = ac.document_id
  JOIN public.document_versions dv ON dv.id = ac.version_id
  WHERE ac.status IN ('review','approved')
  ORDER BY ac.opened_at DESC NULLS LAST, ac.created_at DESC;
END;
$function$;

COMMENT ON FUNCTION public.get_pending_ratifications() IS
  'Lista approval_chains abertos (review/approved) com gates elegiveis para o membro autenticado. Usado por /governance/ip-agreement page. Phase IP-1.';

GRANT EXECUTE ON FUNCTION public.get_pending_ratifications() TO authenticated;

NOTIFY pgrst, 'reload schema';
