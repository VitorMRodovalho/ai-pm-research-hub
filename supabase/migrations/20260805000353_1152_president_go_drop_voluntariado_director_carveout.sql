-- #1152 — Gate president_go: remover o carve-out voluntariado_director (Lorena) do Termo de Voluntário.
--
-- Contexto: o predicado president_go em _can_sign_gate fundia dois papéis para volunteer_term_template:
--   (legal_signer)  -> Ivan Lourenço (SEDE, presidente/board) — assinatura JURÍDICA da versão. CORRETO.
--   (voluntariado_director) -> Lorena (diretora de voluntariado) — mas a função real da Lorena é ser a
--     CONTRAPARTE do instrumento assinado JUNTO ao voluntário (pós-aprovação), NÃO um gate de aprovação de
--     versão. O carve-out deixava Lorena elegível a satisfazer o president_go da cadeia (função != gate).
--
-- Fix: president_go passa a exigir SEMPRE 'legal_signer' (uniforme com president_others). O papel de
-- contraparte da diretoria de voluntariado é modelado fora da cadeia de gates (contra-assinatura do
-- instrumento), não aqui. Menor superfície: só a branch president_go muda; demais gates intactos.
--
-- Escopo: apenas o carve-out voluntariado_director. O stub committee_majority (policy) fica como está
-- (fora da Onda 1 do Termo; será tratado no go-live do Comitê de Curadoria — ver #1152 item 2).
--
-- Segurança: mudança é RESTRITIVA (remove um caminho de elegibilidade; nunca amplia). Ivan (legal_signer)
-- permanece elegível. Não há cadeia volunteer_term_template ativa no momento da aplicação.

CREATE OR REPLACE FUNCTION public._can_sign_gate(p_member_id uuid, p_chain_id uuid, p_gate_kind text, p_doc_type text DEFAULT NULL::text, p_submitter_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_chain record; v_doc_type text; v_submitter_id uuid;
  v_doc_initiative_id uuid;  -- #666: scope the 'leader' gate to the doc's initiative leader
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
    -- #666: also resolve the doc's initiative (for the 'leader' scope below).
    SELECT gd.doc_type, gd.initiative_id INTO v_doc_type, v_doc_initiative_id
    FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;
    v_submitter_id := v_chain.opened_by;
  ELSE
    IF p_doc_type IS NULL THEN RETURN false; END IF;
    v_doc_type := p_doc_type;
    v_submitter_id := p_submitter_id;
  END IF;

  RETURN CASE p_gate_kind
    -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
    WHEN 'curator' THEN public.can_by_member(v_member.id, 'curate_content')
    -- #666: 'leader' = leader OF THE DOCUMENT'S INITIATIVE (not any sign_chain_leader). The chain
    -- path resolves v_doc_initiative_id; non-initiative org docs (policy/cooperation/volunteer_term,
    -- which legitimately have no initiative) fall back to the bare capability (back-compat). A
    -- project_charter MUST be initiative-scoped, so a charter with a missing initiative link fails
    -- CLOSED here (security review #666 F1) — never "any leader". `leader_awareness` stays broad.
    WHEN 'leader' THEN
      public.can_by_member(v_member.id, 'sign_chain_leader')
      AND (
        (v_doc_initiative_id IS NULL AND v_doc_type IS DISTINCT FROM 'project_charter')
        OR EXISTS (SELECT 1 FROM public.v_initiative_roster r
                   WHERE r.initiative_id = v_doc_initiative_id
                     AND r.member_id = v_member.id
                     AND r.role = 'leader')
      )
    WHEN 'leader_awareness' THEN public.can_by_member(v_member.id, 'sign_chain_leader')
    WHEN 'submitter_acceptance' THEN v_submitter_id IS NOT NULL AND v_member.id = v_submitter_id
    -- #1152: president_go exige SEMPRE legal_signer (SEDE/board). Removido o carve-out
    -- voluntariado_director (a diretoria de voluntariado é CONTRAPARTE do instrumento junto ao
    -- voluntário, não gate de aprovação de versão). Uniforme com president_others.
    WHEN 'president_go' THEN
      v_member.chapter = 'PMI-GO' AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    WHEN 'president_others' THEN
      v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    -- #975 PR-3 (WA2): partner_consultation reusa o MESMO predicado de president_others
    -- (capítulos CE/DF/MG/RS + chapter_board + legal_signer). O caráter CONSULTIVO /
    -- NÃO-bloqueante / janelado vive inteiramente em _gate_threshold_met (threshold
    -- 'window_optional'), NUNCA aqui — _can_sign_gate permanece o denominador PURO (#654).
    WHEN 'partner_consultation' THEN
      v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    -- #975 PR-3 (WA2): committee_majority — STUB false até §7.1 fixar o roster/quórum
    -- do Comitê de Curadoria (questão aberta legal/PM). False mantém o gate dormente
    -- (snapshot de roster vazio => maioria nunca atingida) sem travar outros gates. No
    -- go-live, trocar por um predicado de designação (ex.: 'ip_committee' = ANY(designations));
    -- a matemática da maioria em _gate_threshold_met já lê o roster do snapshot (gate_state),
    -- então nenhuma outra mudança é necessária — o roster passa a popular na ativação.
    WHEN 'committee_majority' THEN false
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
    -- #625: um voluntário pré-onboarding (active, mas com engagements ativos ainda pendentes do termo)
    -- NÃO é ainda "volunteer in role active" — contá-lo no denominador 'all' da ratificação é o defeito
    -- circular da família #654 (ele teria de ratificar o próprio termo que ainda não assinou). Exclui
    -- via o helper canônico C0 (mig 20260805000143).
    WHEN 'volunteers_in_role_active' THEN
      v_member.member_status = 'active'
      AND NOT public.member_is_pre_onboarding(v_member.person_id, v_member.member_status)
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
