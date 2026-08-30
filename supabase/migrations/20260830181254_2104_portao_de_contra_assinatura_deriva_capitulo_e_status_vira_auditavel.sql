-- #2104 — o portao de contra-assinatura passa a DERIVAR capitulo, em vez de comparar
-- com constante. Refs #2104, #2083, #2102. ADR-0127 e ADR-0128 ja na main.
--
-- 4 sitios, 2 classes, substitutos DIFERENTES:
--   sede      (president_go, cert_director_go)         -> chapter_registry.is_contracting_chapter
--   parceiros (president_others, partner_consultation) -> partner_chapters.partnership_status='signed', sem a sede
--
-- committee_majority NAO entra: o predicado dele e 'ip_committee' = ANY(designations),
-- sem capitulo. (Entrou por erro no primeiro inventario, porque o split por WHEN
-- levou o comentario do ramo seguinte para o bloco anterior. Corrigido na issue.)
--
-- Os outros 9 ramos ficam byte-identicos ao corpo atual (conferido contra pg_proc).
--
-- A ponte display<->canonico usa partner_chapters, que desde a fase 0 carrega as DUAS
-- formas: chapter_code (display, PMI-GO) e registry_chapter_code (canonica, GO). Por isso
-- nao ha construcao de string em lugar nenhum deste arquivo.
--
-- EQUIVALENCIA PROVADA por diferenca simetrica, nao por contagem (30/08 11:45):
--   sede      literal 40, novo 40, EXCEPT 0 nos dois sentidos
--   parceiros literal 72, novo 72, EXCEPT 0 nos dois sentidos

CREATE OR REPLACE FUNCTION public._can_sign_gate(
  p_member_id uuid, p_chain_id uuid, p_gate_kind text,
  p_doc_type text DEFAULT NULL::text, p_submitter_id uuid DEFAULT NULL::uuid)
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
    SELECT gd.doc_type, gd.initiative_id INTO v_doc_type, v_doc_initiative_id
    FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;
    v_submitter_id := v_chain.opened_by;
  ELSE
    IF p_doc_type IS NULL THEN RETURN false; END IF;
    v_doc_type := p_doc_type;
    v_submitter_id := p_submitter_id;
  END IF;

  RETURN CASE p_gate_kind
    WHEN 'curator' THEN public.can_by_member(v_member.id, 'curate_content')
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

    -- #2104: era `v_member.chapter = 'PMI-GO'`. O capitulo-sede passa a ser lido da flag
    -- canonica em chapter_registry (1 linha true, 14 false, medido 2026-08-30), em vez de
    -- comparado com constante. #1152 mantido: legal_signer SEMPRE exigido.
    WHEN 'president_go' THEN
      EXISTS (SELECT 1 FROM public.partner_chapters pc
              JOIN public.chapter_registry cr ON cr.chapter_code = pc.registry_chapter_code
              WHERE pc.chapter_code = v_member.chapter
                AND cr.is_contracting_chapter)
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)

    -- #2104: era `v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')`. Aquela lista
    -- era um retrato congelado de partnership_status='signed' menos a sede: os 5 signed sao
    -- CE, DF, GO, MG, RS, e tirando a sede sobra exatamente a lista literal. Provado identico
    -- por diferenca simetrica (72 = 72, EXCEPT zero nos dois sentidos) em 2026-08-30.
    -- Capitulo estrangeiro com acordo assinado passa a ser aceito sem tocar em codigo.
    WHEN 'president_others' THEN
      EXISTS (SELECT 1 FROM public.partner_chapters pc
              JOIN public.chapter_registry cr ON cr.chapter_code = pc.registry_chapter_code
              WHERE pc.chapter_code = v_member.chapter
                AND pc.partnership_status = 'signed'
                AND NOT cr.is_contracting_chapter)
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)

    -- #975 PR-3 (WA2) preservado: partner_consultation reusa o MESMO predicado de
    -- president_others de proposito. O carater consultivo / nao-bloqueante / janelado
    -- continua vivendo inteiramente em _gate_threshold_met, NUNCA aqui (#654).
    WHEN 'partner_consultation' THEN
      EXISTS (SELECT 1 FROM public.partner_chapters pc
              JOIN public.chapter_registry cr ON cr.chapter_code = pc.registry_chapter_code
              WHERE pc.chapter_code = v_member.chapter
                AND pc.partnership_status = 'signed'
                AND NOT cr.is_contracting_chapter)
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)

    -- INALTERADO: decide por designation, nao por capitulo.
    WHEN 'committee_majority' THEN 'ip_committee' = ANY(v_member.designations)

    -- #2104: era `v_member.chapter = 'PMI-GO'`. Mesmo tratamento da classe sede.
    -- ADR-0016 Amendment 4 preservado: predicado minimo por designacao de diretoria,
    -- sem chapter_board/legal_signer, e doc_type-scoped.
    WHEN 'cert_director_go' THEN
      EXISTS (SELECT 1 FROM public.partner_chapters pc
              JOIN public.chapter_registry cr ON cr.chapter_code = pc.registry_chapter_code
              WHERE pc.chapter_code = v_member.chapter
                AND cr.is_contracting_chapter)
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


-- ==== AUDITORIA ====
--
-- POR QUE: com a #2104, partnership_status passa a DECIDIR autoridade de
-- contra-assinatura. Antes era campo descritivo; depois e portao. Um UPDATE nele
-- concede ou revoga poder de assinar, e hoje isso nao deixa rastro:
--   partner_chapters tem 0 triggers (medido 2026-08-30).
--
-- REUSO, nao tabela nova: admin_audit_log ja existe e ja e o destino do padrao.
--
-- ESCOPO DELIBERADAMENTE ESTREITO: so registra quando partnership_status MUDA.
-- Auditar todo UPDATE de partner_chapters encheria o log com edicao de nome e URL,
-- e log ruidoso vira log nao lido.

CREATE OR REPLACE FUNCTION public._audit_partner_chapter_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Trigger de coluna: so dispara quando o valor REALMENTE muda. IS DISTINCT FROM
  -- cobre NULL dos dois lados; `<>` deixaria passar transicao de/para NULL em silencio.
  IF NEW.partnership_status IS DISTINCT FROM OLD.partnership_status THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      auth.uid(),                          -- NULL em cron/service_role: e informacao, nao falha
      'partner_chapter_status_changed',
      'partner_chapter',
      NEW.id,
      jsonb_build_object(
        'partnership_status', jsonb_build_object('from', OLD.partnership_status,
                                                 'to',   NEW.partnership_status)),
      jsonb_build_object(
        'chapter_code', NEW.chapter_code,
        -- Por que a autoridade importa aqui, para quem ler o log daqui a um ano
        -- sem saber da #2104:
        'gates_afetados', jsonb_build_array('president_others','partner_consultation'),
        'concede_autoridade', (NEW.partnership_status = 'signed'),
        'revoga_autoridade',  (OLD.partnership_status = 'signed'
                               AND NEW.partnership_status IS DISTINCT FROM 'signed'))
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_audit_partner_chapter_status ON public.partner_chapters;
CREATE TRIGGER trg_audit_partner_chapter_status
  AFTER UPDATE OF partnership_status ON public.partner_chapters
  FOR EACH ROW EXECUTE FUNCTION public._audit_partner_chapter_status();

-- ARMADILHA CONHECIDA, e por isso o WHEN nao esta na clausula do trigger:
-- `AFTER UPDATE OF partnership_status` dispara quando a coluna e ATRIBUIDA, mesmo com
-- valor igual. O IS DISTINCT FROM dentro do corpo e que decide se grava. Trigger que
-- vigia UMA coluna com predicado de N colunas ja mordeu neste projeto; aqui o predicado
-- e de uma coluna so, e fica DENTRO, onde da para ler.
--
-- INSERT nao e auditado de proposito: linha nova de parceria e criacao, nao mudanca de
-- autoridade, e o created_at da propria tabela ja registra. Se a #2104 vier a aceitar
-- capitulo estrangeiro por INSERT direto com 'signed', reconsiderar.
