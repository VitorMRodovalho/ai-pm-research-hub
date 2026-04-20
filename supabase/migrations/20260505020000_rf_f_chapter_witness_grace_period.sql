-- ADR-0016 Amendment 3: chapter_witness grace period (Opção 3c)
-- Legal-counsel (19/Abr p34, peça 3) aprovou Opção 3c: quando capítulo novo
-- ainda não tem liaison/VP estruturado, membros chapter_board podem atuar
-- como testemunhas durante janela de 60d após assinatura do cooperation_agreement.
--
-- Semântica:
--   1. Path principal (pré-existente): chapter_liaison ativo OU VP com ausência de liaison
--   2. Path NOVO (grace): chapter_board AND cooperation_agreement.signed_at + 60d > now()
--
-- Fontes de derivação:
--   - members.chapter: 'PMI-XX' code
--   - governance_documents.parties text[]: ['PMI-GO', 'PMI-XX']
--   - governance_documents.signed_at: momento formalização DocuSign
--   - governance_documents.doc_type='cooperation_agreement' AND status='active'
--
-- Propagação automática:
--   - _enqueue_gate_notifications usa _can_sign_gate como filter → chapter_board
--     do capítulo em grace será notificado no chain_opened / gate_advanced
--   - preview_gate_eligibles usa _can_sign_gate → UI picker mostra chapter_board
--     como opção ao submitter quando chain é para documento novo envolvendo
--     capítulo em grace window
--   - sign_ip_ratification usa _can_sign_gate → assinatura bloqueada/autorizada
--     conforme mesma lógica
--
-- Smoke attendu:
--   - Hoje: nenhum capítulo em grace (último signed_at 2025-12-10, 4m+ atrás).
--     Grace path não ativa para nenhum chapter_board existente — comportamento
--     idêntico ao pré-Amendment 3.
--   - Próximo capítulo novo: ao signed_at ser populado, membros chapter_board
--     deste capítulo passam a ser elegíveis chapter_witness automaticamente
--     pelos 60d seguintes. Liaison designado durante este período continua
--     tendo prioridade (path 1 cobre liaison first).

BEGIN;

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
    WHEN 'curator' THEN 'curator' = ANY(v_member.designations)
    WHEN 'leader' THEN v_member.operational_role IN ('tribe_leader','manager','deputy_manager')
    WHEN 'leader_awareness' THEN v_member.operational_role IN ('tribe_leader','manager','deputy_manager')
    WHEN 'submitter_acceptance' THEN v_submitter_id IS NOT NULL AND v_member.id = v_submitter_id
    WHEN 'president_go' THEN
      v_member.chapter = 'PMI-GO' AND 'chapter_board' = ANY(v_member.designations)
      AND ('legal_signer' = ANY(v_member.designations)
        OR (v_doc_type = 'volunteer_term_template' AND 'voluntariado_director' = ANY(v_member.designations)))
    WHEN 'president_others' THEN
      v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    WHEN 'chapter_witness' THEN (
      -- Path 1 (pré-existente): liaison ativo
      v_member.operational_role = 'chapter_liaison'
      OR 'chapter_liaison' = ANY(v_member.designations)
      -- Path 2 (pré-existente): VP como fallback se não há liaison no capítulo
      OR ('chapter_vice_president' = ANY(v_member.designations) AND NOT EXISTS (
          SELECT 1 FROM public.members m2 WHERE m2.is_active = true
            AND m2.chapter = v_member.chapter
            AND (m2.operational_role = 'chapter_liaison' OR 'chapter_liaison' = ANY(m2.designations))))
      -- Path 3 NOVO (Amendment 3 Opção 3c): grace 60d pós cooperation_agreement
      -- chapter_board designated member elegível se capítulo assinou Acordo nas últimas 8.5 semanas
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
    WHEN 'external_signer' THEN v_member.operational_role = 'external_signer'
    WHEN 'member_ratification' THEN false
    ELSE false
  END;
END;
$function$;

COMMIT;
