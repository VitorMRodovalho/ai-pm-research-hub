-- ============================================================================
-- Migration: 20260805000152_adr0016_amendment_4_cert_director_go
--
-- WHAT:  Introduces governance approval gate_kind `cert_director_go` — the PMI-GO
--        sede Certification Directorate validates a project_charter before the
--        Chapter President's final signature. Touches 4 functions:
--          1. _validate_gates_shape   — add 'cert_director_go' to the shape allowlist
--                                       (CHECK approval_chains_gates_shape backing fn)
--          2. _can_sign_gate          — add eligibility branch (PMI-GO + certificacao_director
--                                       designation, doc_type-scoped to project_charter)
--          3. _ip_ratify_cta_link     — route the gate's notification CTA to the
--                                       member-facing /governance/documents/X page
--          4. _enqueue_gate_notifications — human-readable label/role/verb for the gate
--
-- WHY:   The TAP "Grupo de Estudos CPMAI Prep Course · Ciclo 4" (doc d7447a94, R01
--        8f57a321) recirculates through a 4-gate chain where the sede Certification
--        Directorate (Welma, certificacao_director) signs between the Initiative
--        Leader and the President. No existing gate_kind fit that authority.
--
-- SPEC:  ADR-0016 Amendment 4 (docs/adr/ADR-0016-ip-ratification-governance-model.md)
-- SCOPE-LOCK: gate is INERT until a chain explicitly carries it (gates-as-data, ADR-0016 D1).
--        chapter_board / legal_signer intentionally OMITTED (programmatic validation,
--        not a juridical countersignature; legal_signer would transitively unlock
--        president_go on cooperation_agreements). NOT added to resolve_default_gates —
--        hand-built-chain-only for now.
-- ROLLBACK: re-apply each function from the prior migration capture; remove
--        'cert_director_go' from the allowlist + CTA bucket + CASE branches. The gate
--        is additive — no data migration, no rows depend on it until Phase B.
-- INVARIANTS: J/K unaffected (no version/chain/signoff mutation). _can_sign_gate stays
--        fail-closed; is_active guard in the function header unchanged.
-- CROSS-REF: ADR-0016 D1/D3/Amendment 1-3; chain 897aeddf; council wf_52119163-8b1.
-- ============================================================================


-- 1) _validate_gates_shape: add 'cert_director_go' to the allowlist
CREATE OR REPLACE FUNCTION public._validate_gates_shape(p_gates jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    -- gates é jsonb array não-vazio
    jsonb_typeof(p_gates) = 'array'
    AND jsonb_array_length(p_gates) > 0
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_gates) g
      WHERE NOT (
        -- cada elemento é jsonb object
        jsonb_typeof(g) = 'object'
        -- required keys presentes
        AND g ? 'kind' AND g ? 'order' AND g ? 'threshold'
        -- kind é string no allowlist
        AND (g->>'kind') IN (
          'curator','leader','leader_awareness','submitter_acceptance',
          'chapter_witness','president_go','president_others',
          'volunteers_in_role_active','member_ratification','external_signer',
          'cert_director_go'
        )
        -- order é integer >= 1
        AND jsonb_typeof(g->'order') = 'number'
        AND (g->>'order')::int >= 1
        -- threshold é integer >= 0 OU string 'all'
        AND (
          (jsonb_typeof(g->'threshold') = 'number' AND (g->>'threshold')::int >= 0)
          OR (jsonb_typeof(g->'threshold') = 'string' AND g->>'threshold' = 'all')
        )
      )
    );
$function$;

-- 2) _can_sign_gate: add WHEN 'cert_director_go' branch (PMI-GO sede certification director,
--    doc_type-scoped to project_charter as defense-in-depth)
CREATE OR REPLACE FUNCTION public._can_sign_gate(p_member_id uuid, p_chain_id uuid, p_gate_kind text, p_doc_type text DEFAULT NULL::text, p_submitter_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_chain record; v_doc_type text; v_submitter_id uuid;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.chapter, m.is_active,
         m.member_status, m.person_id
  INTO v_member FROM public.members m WHERE m.id = p_member_id;
  IF v_member.id IS NULL OR v_member.is_active = false THEN RETURN false; END IF;

  IF p_chain_id IS NOT NULL THEN
    SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.opened_by INTO v_chain
    FROM public.approval_chains ac WHERE ac.id = p_chain_id;
    IF v_chain.id IS NULL OR v_chain.status NOT IN ('review','approved') THEN RETURN false; END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_chain.gates) g WHERE g->>'kind' = p_gate_kind) THEN
      RETURN false;
    END IF;
    SELECT gd.doc_type INTO v_doc_type FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;
    v_submitter_id := v_chain.opened_by;
  ELSE
    IF p_doc_type IS NULL THEN RETURN false; END IF;
    v_doc_type := p_doc_type;
    v_submitter_id := p_submitter_id;
  END IF;

  RETURN CASE p_gate_kind
    -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
    WHEN 'curator' THEN public.can_by_member(v_member.id, 'curate_content')
    WHEN 'leader' THEN public.can_by_member(v_member.id, 'sign_chain_leader')
    WHEN 'leader_awareness' THEN public.can_by_member(v_member.id, 'sign_chain_leader')
    WHEN 'submitter_acceptance' THEN v_submitter_id IS NOT NULL AND v_member.id = v_submitter_id
    WHEN 'president_go' THEN
      v_member.chapter = 'PMI-GO' AND 'chapter_board' = ANY(v_member.designations)
      AND ('legal_signer' = ANY(v_member.designations)
        OR (v_doc_type = 'volunteer_term_template' AND 'voluntariado_director' = ANY(v_member.designations)))
    WHEN 'president_others' THEN
      v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    -- ADR-0016 Amendment 4: Diretoria de Certificação do capítulo sede (PMI-GO) valida
    -- charters do tema certificação antes da assinatura presidencial. Predicado mínimo
    -- por designação de diretoria (sem chapter_board/legal_signer — validação programática
    -- interna, não contra-assinatura jurídica). doc_type-scoped (defense-in-depth).
    WHEN 'cert_director_go' THEN
      v_member.chapter = 'PMI-GO'
      AND 'certificacao_director' = ANY(v_member.designations)
      AND (v_doc_type IS NULL OR v_doc_type = 'project_charter')
    WHEN 'chapter_witness' THEN (
      v_member.operational_role = 'chapter_liaison'
      OR 'chapter_liaison' = ANY(v_member.designations)
      OR ('chapter_vice_president' = ANY(v_member.designations) AND NOT EXISTS (
          SELECT 1 FROM public.members m2 WHERE m2.is_active = true
            AND m2.chapter = v_member.chapter
            AND (m2.operational_role = 'chapter_liaison' OR 'chapter_liaison' = ANY(m2.designations))))
      OR ('chapter_board' = ANY(v_member.designations) AND EXISTS (
          SELECT 1 FROM public.governance_documents gd
          WHERE gd.doc_type = 'cooperation_agreement'
            AND gd.status = 'active'
            AND v_member.chapter = ANY(gd.parties)
            AND gd.signed_at IS NOT NULL
            AND gd.signed_at + interval '60 days' > now()))
    )
    WHEN 'volunteers_in_role_active' THEN
      v_member.member_status = 'active'
      AND EXISTS (SELECT 1 FROM public.engagements e
        WHERE e.person_id = v_member.person_id AND e.kind = 'volunteer'
          AND e.status = 'active'
          AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
          AND e.role IN ('researcher','leader','manager'))
    WHEN 'external_signer' THEN EXISTS (
      SELECT 1 FROM public.auth_engagements ae
      WHERE ae.person_id = v_member.person_id
        AND ae.kind = 'external_signer'
        AND ae.is_authoritative = true
    )
    WHEN 'member_ratification' THEN false
    ELSE false
  END;
END;
$function$;

-- 3) _ip_ratify_cta_link: route cert_director_go to the member-facing review-chain page
--    (Welma is manage_member=false; non-admin signers sign at /governance/documents/X)
CREATE OR REPLACE FUNCTION public._ip_ratify_cta_link(p_chain_id uuid, p_gate_kind text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    -- Volunteer/member ratification gates keep the dedicated IP-agreement signing page.
    WHEN p_gate_kind IN ('volunteers_in_role_active','member_ratification','external_signer')
      THEN '/governance/ip-agreement?chain_id=' || p_chain_id::text
    -- Other non-admin signer gates → member review-chain page (#171). Same ReviewChainIsland
    -- as the admin route, BaseLayout (no admin shell). Curators, tribe leaders, chapter
    -- witnesses, chapter presidents and the certification director sign here instead of
    -- being bounced into /admin/.
    WHEN p_gate_kind IN ('curator','leader_awareness','chapter_witness','president_go','president_others','cert_director_go')
      THEN '/governance/documents/' || p_chain_id::text
    -- submitter_acceptance (the GP) and anything unrecognised stay on the admin operations surface.
    ELSE '/admin/governance/documents/' || p_chain_id::text
  END;
$function$;

-- 4) _enqueue_gate_notifications: add cert_director_go label/role/verb branches
--    (chain_opened + gate_advanced CASE blocks). LIMIT-1 next-gate selection unchanged
--    (correct for the sequential chain — one gate per order).
CREATE OR REPLACE FUNCTION public._enqueue_gate_notifications(p_chain_id uuid, p_event text, p_gate_kind text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chain record; v_doc record; v_version record; v_submitter record;
  v_gate jsonb; v_target record; v_link text; v_title text; v_body text;
  v_notif_type text; v_enqueued int := 0;
  v_action_label text; v_role_singular text; v_action_verb text;
BEGIN
  IF p_event NOT IN ('chain_opened','gate_advanced','chain_approved') THEN
    RAISE EXCEPTION 'Invalid event: %', p_event USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id, ac.opened_by
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN 0; END IF;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_label INTO v_version
  FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT m.id, m.name, m.email INTO v_submitter
  FROM public.members m WHERE m.id = v_chain.opened_by;

  IF p_event = 'chain_opened' THEN
    SELECT g INTO v_gate FROM jsonb_array_elements(v_chain.gates) g
    ORDER BY (g->>'order')::int ASC LIMIT 1;
    IF v_gate IS NULL THEN RETURN 0; END IF;

    v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');
    v_notif_type := 'ip_ratification_gate_pending';

    v_action_label := CASE v_gate->>'kind'
      WHEN 'curator' THEN 'Curadoria'
      WHEN 'leader_awareness' THEN 'Ciencia da lideranca'
      WHEN 'submitter_acceptance' THEN 'Aceite do GP'
      WHEN 'chapter_witness' THEN 'Testemunho de capitulo'
      WHEN 'president_go' THEN 'Assinatura da presidencia PMI-GO'
      WHEN 'president_others' THEN 'Assinatura de presidencia de capitulo'
      WHEN 'cert_director_go' THEN 'Validacao da Diretoria de Certificacao (PMI-GO)'
      WHEN 'volunteers_in_role_active' THEN 'Ratificacao de voluntario em funcao ativa'
      WHEN 'member_ratification' THEN 'Ratificacao de membro'
      ELSE v_gate->>'kind' END;
    v_role_singular := CASE v_gate->>'kind'
      WHEN 'curator' THEN 'curador(a)'
      WHEN 'leader_awareness' THEN 'lider do Nucleo'
      WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
      WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
      WHEN 'president_go' THEN 'presidencia do PMI-GO'
      WHEN 'president_others' THEN 'presidencia do seu capitulo'
      WHEN 'cert_director_go' THEN 'Diretoria de Certificacao do PMI-GO'
      WHEN 'volunteers_in_role_active' THEN 'voluntario(a) em funcao ativa'
      WHEN 'member_ratification' THEN 'membro ativo'
      ELSE v_gate->>'kind' END;
    v_action_verb := CASE v_gate->>'kind'
      WHEN 'curator' THEN 'ler o documento completo e decidir se ele avanca para a fase de aprovacao pelas presidencias de capitulo. Voce pode registrar duvidas ou pontos de ajuste como comentarios antes de aprovar'
      WHEN 'leader_awareness' THEN 'ler o documento e registrar ciencia. Este passo nao bloqueia o workflow, mas formaliza que a lideranca esta ciente do que sera ratificado'
      WHEN 'submitter_acceptance' THEN 'confirmar formalmente que o documento esta pronto para circular as presidencias de capitulo'
      WHEN 'chapter_witness' THEN 'confirmar que o documento foi apresentado e e de conhecimento dos membros do seu capitulo'
      WHEN 'president_go' THEN 'ler e assinar como presidencia do capitulo-sede. Apos sua assinatura, as demais presidencias serao notificadas'
      WHEN 'president_others' THEN 'ler e assinar como presidencia do seu capitulo, apos a presidencia PMI-GO ja ter assinado'
      WHEN 'cert_director_go' THEN 'ler o TAP e validar o alinhamento com a area de Certificacao do capitulo sede, confirmando que o projeto opera como Grupo de Estudos complementar ao Prep Course oficial do PMI (nao ATP nem curso substituto). Apos sua validacao, o Patrocinador sera notificado para a assinatura final'
      WHEN 'volunteers_in_role_active' THEN 'ler o documento e ratificar como voluntario(a) em funcao ativa. Sua ratificacao formaliza a adesao pessoal aos termos atualizados enquanto voce mantem funcao ativa no Nucleo'
      WHEN 'member_ratification' THEN 'ler o documento e ratificar como membro ativo. Sua ratificacao formaliza a adesao pessoal aos termos'
      ELSE 'revisar e agir conforme o seu papel neste workflow' END;

    FOR v_target IN
      SELECT m.id AS member_id, m.name FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
        AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
          WHERE s.approval_chain_id = p_chain_id
            AND s.gate_kind = v_gate->>'kind' AND s.signer_id = m.id)
    LOOP
      v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                 ' — ' || v_action_label || ' solicitada por ' || COALESCE(v_submitter.name, 'Gerente de Projeto');
      v_body := COALESCE(v_submitter.name, 'O Gerente de Projeto') ||
                ' submeteu o documento "' || v_doc.title || '" versao ' ||
                COALESCE(v_version.version_label,'') || ' para ratificacao no Nucleo IA & GP. ' ||
                'Como ' || v_role_singular || ', voce deve ' || v_action_verb || '.';
      PERFORM public.create_notification(
        v_target.member_id, v_notif_type, v_title, v_body, v_link,
        'approval_chain', p_chain_id);
      v_enqueued := v_enqueued + 1;
    END LOOP;
    RETURN v_enqueued;
  END IF;

  IF p_event = 'gate_advanced' AND p_gate_kind IS NOT NULL THEN
    SELECT g INTO v_gate FROM jsonb_array_elements(v_chain.gates) g
    WHERE (g->>'order')::int > (
      SELECT (g2->>'order')::int FROM jsonb_array_elements(v_chain.gates) g2
      WHERE g2->>'kind' = p_gate_kind LIMIT 1)
    ORDER BY (g->>'order')::int ASC LIMIT 1;

    IF v_gate IS NOT NULL THEN
      v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');
      v_notif_type := CASE WHEN (v_gate->>'kind') IN ('volunteers_in_role_active','member_ratification')
                          THEN 'ip_ratification_awaiting_members'
                          ELSE 'ip_ratification_gate_pending' END;

      v_action_label := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'Curadoria'
        WHEN 'leader_awareness' THEN 'Ciencia da lideranca'
        WHEN 'submitter_acceptance' THEN 'Aceite do GP'
        WHEN 'chapter_witness' THEN 'Testemunho de capitulo'
        WHEN 'president_go' THEN 'Assinatura da presidencia PMI-GO'
        WHEN 'president_others' THEN 'Assinatura de presidencia de capitulo'
        WHEN 'cert_director_go' THEN 'Validacao da Diretoria de Certificacao (PMI-GO)'
        WHEN 'volunteers_in_role_active' THEN 'Ratificacao de voluntario em funcao ativa'
        WHEN 'member_ratification' THEN 'Ratificacao de membro'
        ELSE v_gate->>'kind' END;
      v_role_singular := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'curador(a)'
        WHEN 'leader_awareness' THEN 'lider do Nucleo'
        WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
        WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
        WHEN 'president_go' THEN 'presidencia do PMI-GO'
        WHEN 'president_others' THEN 'presidencia do seu capitulo'
        WHEN 'cert_director_go' THEN 'Diretoria de Certificacao do PMI-GO'
        WHEN 'volunteers_in_role_active' THEN 'voluntario(a) em funcao ativa'
        WHEN 'member_ratification' THEN 'membro ativo'
        ELSE v_gate->>'kind' END;
      v_action_verb := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'ler o documento e aprovar como curador'
        WHEN 'leader_awareness' THEN 'ler e registrar ciencia'
        WHEN 'submitter_acceptance' THEN 'confirmar que esta pronto para circular presidencias'
        WHEN 'chapter_witness' THEN 'confirmar como ponto focal do seu capitulo'
        WHEN 'president_go' THEN 'assinar como presidencia PMI-GO'
        WHEN 'president_others' THEN 'assinar como presidencia de capitulo'
        WHEN 'cert_director_go' THEN 'validar como Diretoria de Certificacao do PMI-GO'
        WHEN 'volunteers_in_role_active' THEN 'ratificar como voluntario(a) em funcao ativa'
        WHEN 'member_ratification' THEN 'ratificar como membro ativo'
        ELSE 'agir conforme seu papel' END;

      FOR v_target IN
        SELECT m.id AS member_id, m.name FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
          AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
            WHERE s.approval_chain_id = p_chain_id
              AND s.gate_kind = v_gate->>'kind' AND s.signer_id = m.id)
      LOOP
        v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                   ' — sua ' || lower(v_action_label) || ' agora e necessaria';
        v_body := 'O gate anterior foi satisfeito. Voce esta agora elegivel para ' ||
                  v_action_verb || ' no documento "' || v_doc.title || '" versao ' ||
                  COALESCE(v_version.version_label,'') ||
                  ', submetido por ' || COALESCE(v_submitter.name, 'Gerente de Projeto') ||
                  ' para ratificacao no Nucleo IA & GP. Como ' || v_role_singular || ', ' || v_action_verb || '.';
        PERFORM public.create_notification(
          v_target.member_id, v_notif_type, v_title, v_body, v_link,
          'approval_chain', p_chain_id);
        v_enqueued := v_enqueued + 1;
      END LOOP;
    END IF;

    IF v_submitter.id IS NOT NULL THEN
      v_link := '/admin/governance/documents/' || p_chain_id::text;
      v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                 ' — gate "' || p_gate_kind || '" satisfeito';
      v_body := 'O gate "' || p_gate_kind || '" da cadeia de ratificacao do documento "' ||
                v_doc.title || '" versao ' || COALESCE(v_version.version_label,'') ||
                ' foi satisfeito. O workflow avancou automaticamente. Acompanhe o progresso dos proximos gates na plataforma.';
      PERFORM public.create_notification(
        v_submitter.id, 'ip_ratification_gate_advanced', v_title, v_body, v_link,
        'approval_chain', p_chain_id);
      v_enqueued := v_enqueued + 1;
    END IF;
    RETURN v_enqueued;
  END IF;

  IF p_event = 'chain_approved' AND v_submitter.id IS NOT NULL THEN
    v_link := '/admin/governance/documents/' || p_chain_id::text;
    v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
               ' — cadeia de ratificacao concluida';
    v_body := 'Todos os gates da cadeia de ratificacao do documento "' || v_doc.title ||
              '" versao ' || COALESCE(v_version.version_label,'') ||
              ' foram satisfeitos. O documento pode ser ativado como vigente no Nucleo IA & GP.';
    PERFORM public.create_notification(
      v_submitter.id, 'ip_ratification_chain_approved', v_title, v_body, v_link,
      'approval_chain', p_chain_id);
    RETURN 1;
  END IF;

  RETURN 0;
END;
$function$;
