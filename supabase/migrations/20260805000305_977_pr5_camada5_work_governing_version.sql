-- =====================================================================
-- #977 (PR-5 of #571) — Camada 5 Material-change backbone: AUDIT-TRAIL POR
-- OBRA + VERSÃO REGENTE (WA4 — Termo 15.4.1 regra + 15.4.7 ledger + 15.4.6
-- tie-break). ÚLTIMO slice; #571 umbrella fecha após.
--
-- Objetivo: stamp IMUTÁVEL da versão regente (Política + Termo) sob a qual
-- cada OBRA foi constituída, ancorado na 1ª contribuição material. Opção A
-- (Adendo consolidado no Termo) => UM governing_termo_version_id, sem composto.
--
-- BEHAVIOR-NEUTRAL / DORMENTE:
--   * stamp_work_governing_version RAISE enquanto a Política não estiver
--     RATIFICADA (governance_documents.current_ratified_version_id IS NULL para
--     doc_type='policy', ao vivo este turno => dormancy enforçada por DB).
--   * member_document_signatures = 0 ao vivo => o Termo regente de qualquer
--     stamp hoje resolveria NULL (sem assinatura prévia do autor) => o caminho
--     real só roda após v2.7 ratificar + as assinaturas existirem (WA2/WA3).
--   * Nenhum dispatch OUTWARD: este PR só escreve um registro de auditoria; não
--     notifica, não fan-out — NÃO é a superfície do leak #648/#653.
--
-- SPEC docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md §5 PR-5 + §9.6 (correções
-- VINCULANTES — sobrescrevem o pseudocódigo de §5). ADR-0117 (amenda família
-- legal-ops ADR-0016/0105). Deps: PR-1 (change_class) + PR-2/PR-3 populando
-- current_ratified_version_id + member_document_signatures.
--
-- GROUNDING (este turno, ao vivo, projeto ldrfrvwhxsmgaabwmaik):
--   * Tabelas de obra + linkagem a initiative (p/ RLS ADR-0105) + org + autor:
--       content_product   37  -> initiative_id direto; org=organization_id; autor=proposer_member_id
--       tribe_deliverable 71  -> initiative_id direto; org=organization_id; autor=assigned_member_id
--       event_showcase    25  -> SEM initiative_id NEM organization_id próprios; via event_id->events
--                                (events tem initiative_id E organization_id, confirmado); autor=member_id; title nullable
--       public_publication 7  -> initiative_id direto; org=organization_id; autor=author_member_ids[1]; created_at NULLABLE
--       knowledge_asset    1  -> SEM initiative E SEM organization_id (org-agnóstico); autor=created_by
--     publication_submission (37) tem content_product_id NOT NULL (1:1) => REMOVIDO do work_type (§9.6).
--   * governance_documents: 1 doc policy (cfb15185, status 'under_review', current_ratified_version_id=NULL);
--     volunteer_term_template TEM 2 docs (v2.7 280c2c56 unratified + legacy a78311fd ratified) => resolução
--     do Termo regente é por doc_type via JOIN, nunca por id hardcoded. status ∈ (active,draft,under_review).
--   * member_document_signatures: 0 rows; member_id/document_id/signed_version_id(NOT NULL)/is_current/
--     signed_at/created_at; SEM organization_id.
--   * rls_can_see_initiative(uuid) SECDEF: TRUE p/ initiative NULL, non-confidential, engajado, superadmin, manage_platform.
--   * auth_org(), hashtextextended(text,int8), members.name, events.organization_id confirmados.
--   * 41 invariantes / 0 violações. Esta PR NÃO adiciona invariante (DORMENTE: 0 rows; um invariante
--     "toda obra published tem stamp" falharia já — fica em 41; o mecanismo é coberto por contract test).
--   * document_versions.id = uuid.
--
-- DECISÃO DE PROJETO (D1 — reconciliação da contradição na SPEC §9.6 / #977, ADJUDICADA pela revisão
--   adversarial 4-lentes wf_408319e9-850 — TODAS as 4 lentes concordam):
--   §9.6 e o #977 dizem AMBOS governing_*_version_id "NOT NULL" **E** "sem signature prévia =>
--   governing_termo_version_id=NULL + requires_legal_review=true" — auto-contraditório. Resolução
--   (legalmente correta — não falhar em silêncio nem fabricar relação contratual inexistente, Lei 9.610/98):
--     - governing_politica_version_id NOT NULL  -> o gate de dormancy (RAISE quando current_ratified_version_id
--       IS NULL) garante o valor ANTES da constraint ser testada => NOT NULL É o gate, não constraint violável.
--     - governing_termo_version_id NULLABLE      -> a assinatura por-autor pode genuinamente faltar (co-autor
--       convidado, obra anterior à adesão; mds=0 hoje); NULL + requires_legal_review=true defere ao DPO
--       (tie-break 15.4.6). NOT NULL aqui bloquearia o stamp das 37+ obras pré-existentes.
--
-- Revisão adversarial 4-lentes (wf_408319e9-850) ANTES do apply => 12 fixes incorporados (M0–M12):
--   M0 org_id NULLABLE (knowledge_asset org-agnóstico, NULL=universalmente legível); M1 event_showcase org via
--   events.organization_id (es.organization_id NÃO existe — seria crash); M2 trigger imutável protege id;
--   M3 superseded_by_id FK DEFERRABLE INITIALLY DEFERRED (+ ON DELETE RESTRICT) p/ cadeia de retificação futura;
--   M4 get_ guarda cross-org (SECDEF bypassa RLS — evita vazar attribution_text/nome PII cross-org);
--   M5 attribution_text bifurca em requires_review + embute labels reais (não afirmar Termo inexistente =
--   registro probatório falso, classe vedada no PR-2); M6 dormancy gate determinístico + count guard
--   (status<>'superseded'); M7 tie-break por signed_at (ato de assinar), não created_at; M8 trigger sem
--   SECURITY DEFINER (puro); M9 retorno idempotente inclui work_type/work_id; M10 remove dead code v_init;
--   M11 v_first RAISE se ambos NULL (não silenciar p/ now()); M12 stamp guarda cross-org. R1 (rejeitado):
--   `OR organization_id IS NULL` é LOAD-BEARING sob M0 (não é dead code).
-- =====================================================================

-- =====================================================================
-- 1. TABELA — work_governing_version. Polimórfica (sem FK em work_id;
--    integridade via RPC + contract test). UNIQUE parcial = 1 stamp ATIVO por obra.
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.work_governing_version (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid,                                    -- M0: NULLABLE (knowledge_asset é org-agnóstico)
  work_type text NOT NULL CHECK (work_type IN (
    'content_product',     -- 37; âncora canônica de obra
    'tribe_deliverable',   -- 71
    'event_showcase',      -- 25
    'public_publication',  -- 7
    'knowledge_asset'      -- 1 (sem initiative / sem org)
    -- 'publication_submission' REMOVIDO (§9.6): 1:1 com content_product => double-stamp.
  )),
  work_id uuid NOT NULL,                                   -- polimórfico; sem FK
  author_member_id uuid REFERENCES public.members(id),     -- nullable; forward-compat Q5 (per-autor)
  first_material_contribution_at timestamptz NOT NULL,     -- âncora 15.4.6 (default = work.created_at, Q4)
  -- Versão regente (FK + snapshot denormalizado p/ durabilidade):
  governing_politica_version_id uuid NOT NULL REFERENCES public.document_versions(id),  -- dormancy gate (D1)
  governing_termo_document_id uuid REFERENCES public.governance_documents(id),          -- qual doc Termo (2 existem)
  governing_termo_version_id uuid REFERENCES public.document_versions(id),              -- NULLABLE (D1; tie-break)
  attribution_text text,                                   -- snapshot denormalizado (autor + obra + versões)
  enquadramento jsonb NOT NULL DEFAULT '{}'::jsonb,        -- {lei_principal, fundamentos, natureza} (9.610/9.609/9.279)
  requires_legal_review boolean NOT NULL DEFAULT false,    -- true quando o Termo regente não pôde ser resolvido
  stamped_at timestamptz NOT NULL DEFAULT now(),
  stamped_by uuid REFERENCES public.members(id),
  -- M3: DEFERRABLE INITIALLY DEFERRED habilita a cadeia de retificação futura (UPDATE old.superseded_by_id=:new
  -- antes do INSERT do :new, dentro de 1 tx, sem violar o UNIQUE parcial); ON DELETE RESTRICT (write-once).
  superseded_by_id uuid REFERENCES public.work_governing_version(id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.work_governing_version IS
  '#977 Camada 5 PR-5 (WA4): stamp imutável da versão regente (Politica+Termo) por OBRA, '
  'ancorado na 1a contribuicao material (Termo 15.4.1/15.4.6/15.4.7). Opcao A: um governing_termo. '
  'DORMENTE: stamp_work_governing_version RAISE ate a Politica ratificar. write-once via trigger; '
  'correcao apenas pela cadeia superseded_by_id. organization_id NULL = obra org-agnostica (knowledge_asset).';

-- 1 stamp ATIVO por obra (superseded_by_id IS NULL). Forward-compat Q5: quando a regência virar
-- por-autor, recriar como (work_type, work_id, author_member_id) WHERE superseded_by_id IS NULL.
CREATE UNIQUE INDEX IF NOT EXISTS wgv_active_unique
  ON public.work_governing_version(work_type, work_id) WHERE superseded_by_id IS NULL;
CREATE INDEX IF NOT EXISTS wgv_work ON public.work_governing_version(work_type, work_id);
CREATE INDEX IF NOT EXISTS wgv_author ON public.work_governing_version(author_member_id) WHERE author_member_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS wgv_legal_review ON public.work_governing_version(requires_legal_review) WHERE requires_legal_review = true;

-- =====================================================================
-- 2. _work_initiative_id — helper polimórfico (SECDEF STABLE) p/ a RLS de
--    confidencialidade (ADR-0105). Retorna o initiative_id da obra (ou NULL).
-- =====================================================================
CREATE OR REPLACE FUNCTION public._work_initiative_id(p_work_type text, p_work_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_init uuid;
BEGIN
  IF p_work_id IS NULL THEN RETURN NULL; END IF;
  CASE p_work_type
    WHEN 'content_product'    THEN SELECT initiative_id INTO v_init FROM public.content_products   WHERE id = p_work_id;
    WHEN 'tribe_deliverable'  THEN SELECT initiative_id INTO v_init FROM public.tribe_deliverables  WHERE id = p_work_id;
    WHEN 'public_publication' THEN SELECT initiative_id INTO v_init FROM public.public_publications WHERE id = p_work_id;
    WHEN 'event_showcase'     THEN SELECT e.initiative_id INTO v_init
                                     FROM public.event_showcases es JOIN public.events e ON e.id = es.event_id
                                     WHERE es.id = p_work_id;
    WHEN 'knowledge_asset'    THEN v_init := NULL;  -- knowledge_assets não liga a initiative
    ELSE v_init := NULL;
  END CASE;
  RETURN v_init;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._work_initiative_id(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._work_initiative_id(text, uuid) TO authenticated, service_role;

-- =====================================================================
-- 3. RLS (GC-162 + ADR-0105). Espelha tribe_deliverables: PERMISSIVE read p/
--    authenticated + RESTRICTIVE confidential gate (AJ) via rls_can_see_initiative
--    do helper polimórfico + RESTRICTIVE org-scope. Escritas SÓ via SECDEF.
-- =====================================================================
ALTER TABLE public.work_governing_version ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS wgv_read ON public.work_governing_version;
CREATE POLICY wgv_read ON public.work_governing_version
  FOR SELECT TO authenticated
  USING ((SELECT auth.role()) = 'authenticated');

-- RESTRICTIVE confidential-visibility gate (ADR-0105 / §4.10): nenhuma linha de obra
-- ligada a initiative confidencial vaza a não-engajado.
DROP POLICY IF EXISTS "AJ_wgv_confidential_visibility" ON public.work_governing_version;
CREATE POLICY "AJ_wgv_confidential_visibility" ON public.work_governing_version
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (public.rls_can_see_initiative(public._work_initiative_id(work_type, work_id)));

-- RESTRICTIVE org-scope (paridade com as 8 tabelas initiative-dependentes).
-- R1 (review): `OR organization_id IS NULL` é LOAD-BEARING sob M0 (knowledge_asset org-agnóstico = legível cross-org).
DROP POLICY IF EXISTS wgv_org_scope ON public.work_governing_version;
CREATE POLICY wgv_org_scope ON public.work_governing_version
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (organization_id = public.auth_org() OR organization_id IS NULL);

GRANT SELECT ON public.work_governing_version TO authenticated;

-- =====================================================================
-- 4. trg_work_governing_version_immutable — write-once. Bloqueia toda mutação
--    EXCETO superseded_by_id (cadeia de retificação legal) + updated_at; bloqueia
--    DELETE. (pi_exclusion_assets NÃO tem trigger imutável — §9.6 — escrito do zero.)
--    M8: SEM SECURITY DEFINER (puro: só compara OLD/NEW + RAISE).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.trg_work_governing_version_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'work_governing_version e write-once (id=%); correcao apenas pela cadeia superseded_by_id, nunca DELETE', OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  -- UPDATE: só superseded_by_id (+ updated_at) pode mudar. M2: id incluído (PK UPDATE é permitido em PG).
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.work_type IS DISTINCT FROM OLD.work_type
     OR NEW.work_id IS DISTINCT FROM OLD.work_id
     OR NEW.author_member_id IS DISTINCT FROM OLD.author_member_id
     OR NEW.first_material_contribution_at IS DISTINCT FROM OLD.first_material_contribution_at
     OR NEW.governing_politica_version_id IS DISTINCT FROM OLD.governing_politica_version_id
     OR NEW.governing_termo_document_id IS DISTINCT FROM OLD.governing_termo_document_id
     OR NEW.governing_termo_version_id IS DISTINCT FROM OLD.governing_termo_version_id
     OR NEW.attribution_text IS DISTINCT FROM OLD.attribution_text
     OR NEW.enquadramento IS DISTINCT FROM OLD.enquadramento
     OR NEW.requires_legal_review IS DISTINCT FROM OLD.requires_legal_review
     OR NEW.stamped_at IS DISTINCT FROM OLD.stamped_at
     OR NEW.stamped_by IS DISTINCT FROM OLD.stamped_by
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'work_governing_version row % e imutavel (write-once); apenas superseded_by_id pode mudar', OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_wgv_immutable ON public.work_governing_version;
CREATE TRIGGER trg_wgv_immutable
  BEFORE UPDATE OR DELETE ON public.work_governing_version
  FOR EACH ROW EXECUTE FUNCTION public.trg_work_governing_version_immutable();

-- =====================================================================
-- 5. stamp_work_governing_version — SECDEF, manage_platform. DORMENTE (RAISE
--    enquanto a Politica nao ratificar). Idempotente por (work_type,work_id)
--    ativo. Termo regente = signature do autor com signed_at <= 1a contribuicao
--    material (tie-break 15.4.6), NUNCA is_current no stamp-time; sem signature =>
--    NULL + requires_legal_review. advisory lock serializa stamps concorrentes.
--    Nota (M10): o write-path NAO aplica gate ADR-0105 — manage_platform (GP) ve
--    confidencial por design; o gate confidencial vive no read-path (get_).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.stamp_work_governing_version(
  p_work_type text,
  p_work_id uuid,
  p_author_member_id uuid DEFAULT NULL,
  p_first_material_contribution_at timestamptz DEFAULT NULL,
  p_enquadramento jsonb DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_pol_count int;
  v_pol_ratified uuid;
  v_pol_label text;
  v_title text;
  v_derived_author uuid;
  v_created timestamptz;
  v_org uuid;
  v_author uuid;
  v_first timestamptz;
  v_termo_ver uuid;
  v_termo_doc uuid;
  v_termo_label text;
  v_requires_review boolean := false;
  v_enq jsonb;
  v_attr text;
  v_author_name text;
  v_existing record;
  v_id uuid;
BEGIN
  -- Auth: manage_platform (GP/jurídico).
  SELECT m.id, m.organization_id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RAISE EXCEPTION 'Access denied: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_work_type NOT IN ('content_product','tribe_deliverable','event_showcase','public_publication','knowledge_asset') THEN
    RAISE EXCEPTION 'work_type invalido: %', p_work_type USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- DORMANCY GATE (§9.6 / D1 / M6): determinístico + count guard. Impede congelar NULLs antes do v2.7
  -- ratificar E impede planner escolher arbitrariamente entre múltiplos docs de policy (multi-doc é
  -- padrão vivo — há 2 volunteer_term_template). status 'superseded' reservado p/ docs revogados.
  SELECT count(*) INTO v_pol_count FROM public.governance_documents
   WHERE doc_type = 'policy' AND status <> 'superseded';
  IF v_pol_count <> 1 THEN
    RAISE EXCEPTION 'documento de Politica ativo ambiguo ou ausente (encontrados %)', v_pol_count USING ERRCODE = 'data_exception';
  END IF;
  SELECT current_ratified_version_id INTO v_pol_ratified FROM public.governance_documents
   WHERE doc_type = 'policy' AND status <> 'superseded';
  IF v_pol_ratified IS NULL THEN
    RAISE EXCEPTION 'dormant: a Politica de PI ainda nao foi ratificada (current_ratified_version_id IS NULL) — o stamp de versao regente nao pode congelar uma Politica nao-vigente (§9.6)'
      USING ERRCODE = 'object_not_in_prerequisite_state';
  END IF;

  -- Serializa stamps concorrentes da MESMA obra (evita corrida no pre-check de idempotencia).
  PERFORM pg_advisory_xact_lock(hashtextextended(p_work_type || ':' || p_work_id::text, 0));

  -- Idempotência: já existe stamp ativo? retorna-o (M9: shape inclui work_type/work_id).
  SELECT * INTO v_existing FROM public.work_governing_version
  WHERE work_type = p_work_type AND work_id = p_work_id AND superseded_by_id IS NULL;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object('stamped', false, 'idempotent', true, 'id', v_existing.id,
      'work_type', p_work_type, 'work_id', p_work_id,
      'governing_politica_version_id', v_existing.governing_politica_version_id,
      'governing_termo_version_id', v_existing.governing_termo_version_id,
      'requires_legal_review', v_existing.requires_legal_review);
  END IF;

  -- Resolve obra: título, autor derivado, created_at, org. (M10: sem v_init — initiative é
  -- resolvido no read-time pelo helper _work_initiative_id, não armazenado.)
  -- M1: event_showcase org via events.organization_id (es NÃO tem organization_id).
  CASE p_work_type
    WHEN 'content_product' THEN
      SELECT title, proposer_member_id, created_at, organization_id
        INTO v_title, v_derived_author, v_created, v_org
      FROM public.content_products WHERE id = p_work_id;
    WHEN 'tribe_deliverable' THEN
      SELECT title, assigned_member_id, created_at, organization_id
        INTO v_title, v_derived_author, v_created, v_org
      FROM public.tribe_deliverables WHERE id = p_work_id;
    WHEN 'event_showcase' THEN
      SELECT es.title, es.member_id, es.created_at, e.organization_id
        INTO v_title, v_derived_author, v_created, v_org
      FROM public.event_showcases es JOIN public.events e ON e.id = es.event_id WHERE es.id = p_work_id;
    WHEN 'public_publication' THEN
      SELECT title, (author_member_ids)[1], COALESCE(created_at, publication_date::timestamptz), organization_id
        INTO v_title, v_derived_author, v_created, v_org
      FROM public.public_publications WHERE id = p_work_id;
    WHEN 'knowledge_asset' THEN
      SELECT title, created_by, created_at, NULL::uuid
        INTO v_title, v_derived_author, v_created, v_org
      FROM public.knowledge_assets WHERE id = p_work_id;
  END CASE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'obra nao encontrada: % %', p_work_type, p_work_id USING ERRCODE = 'no_data_found';
  END IF;

  -- M0: knowledge_asset (org NULL) fica org-agnóstico (NÃO pinar na org do caller). M12: guard cross-org.
  IF v_org IS NOT NULL AND v_caller.organization_id IS NOT NULL AND v_org IS DISTINCT FROM v_caller.organization_id THEN
    RAISE EXCEPTION 'obra (org %) nao pertence a org do caller (%)', v_org, v_caller.organization_id USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_author := COALESCE(p_author_member_id, v_derived_author);

  -- M11: âncora obrigatória — não silenciar p/ now() (geraria tie-break perverso + review espúrio).
  IF v_created IS NULL AND p_first_material_contribution_at IS NULL THEN
    RAISE EXCEPTION 'first_material_contribution_at obrigatorio para obras sem created_at (work_type=%, work_id=%)', p_work_type, p_work_id
      USING ERRCODE = 'not_null_violation';
  END IF;
  v_first := COALESCE(p_first_material_contribution_at, v_created);

  -- TERMO regente (tie-break 15.4.6 / M7): assinatura do autor vigente À DATA da 1a contribuicao
  -- material (signed_at <= v_first; o ato de assinar, não o insert da linha), NUNCA is_current no
  -- stamp-time. Resolve por doc_type (há 2 volunteer_term_template — o autor pode ter assinado qualquer).
  -- Sem autor OU sem assinatura previa => NULL + review.
  IF v_author IS NOT NULL THEN
    SELECT mds.signed_version_id, mds.document_id INTO v_termo_ver, v_termo_doc
    FROM public.member_document_signatures mds
    JOIN public.governance_documents gd ON gd.id = mds.document_id AND gd.doc_type = 'volunteer_term_template'
    WHERE mds.member_id = v_author AND COALESCE(mds.signed_at, mds.created_at) <= v_first
    ORDER BY COALESCE(mds.signed_at, mds.created_at) DESC LIMIT 1;
  END IF;
  IF v_termo_ver IS NULL THEN v_requires_review := true; END IF;

  -- Labels reais p/ o snapshot de atribuição (M5).
  SELECT version_label INTO v_pol_label FROM public.document_versions WHERE id = v_pol_ratified;
  IF v_termo_ver IS NOT NULL THEN
    SELECT version_label INTO v_termo_label FROM public.document_versions WHERE id = v_termo_ver;
  END IF;

  -- Enquadramento: default derivado (todas as obras = autoral 9.610); override por param.
  v_enq := COALESCE(p_enquadramento, jsonb_build_object(
    'lei_principal', '9.610/1998',
    'fundamentos', jsonb_build_array('9.610/1998'),
    'natureza', 'obra_autoral',
    'work_type', p_work_type,
    'derivado_automaticamente', true,
    'observacao', 'Enquadramento preliminar; revisao juridica pode reclassificar (9.609/1998 software, 9.279/1996 propriedade industrial).'));

  -- Snapshot de atribuição denormalizado (M5: bifurca em requires_review — NUNCA afirmar um Termo
  -- inexistente; write-once => um snapshot errado só seria corrigível pela cadeia superseded).
  SELECT name INTO v_author_name FROM public.members WHERE id = v_author;
  IF v_requires_review THEN
    v_attr := 'Obra "' || COALESCE(v_title, '(sem titulo)') || '"'
      || COALESCE(' de ' || v_author_name, '')
      || ', constituida sob a Politica de PI (versao ' || COALESCE(v_pol_label, '?') || '). '
      || 'AVISO: Termo de Voluntariado NAO verificado para o autor a ' || to_char(v_first, 'DD/MM/YYYY')
      || ' — requer revisao juridica (tie-break Termo 15.4.6).';
  ELSE
    v_attr := 'Obra "' || COALESCE(v_title, '(sem titulo)') || '"'
      || COALESCE(' de ' || v_author_name, '')
      || ', constituida sob a Politica de PI (versao ' || COALESCE(v_pol_label, '?') || ')'
      || ' e o Termo de Voluntariado (versao ' || COALESCE(v_termo_label, '?') || ') vigente para o autor a '
      || to_char(v_first, 'DD/MM/YYYY') || '.';
  END IF;

  INSERT INTO public.work_governing_version (
    organization_id, work_type, work_id, author_member_id, first_material_contribution_at,
    governing_politica_version_id, governing_termo_document_id, governing_termo_version_id,
    attribution_text, enquadramento, requires_legal_review, stamped_by)
  VALUES (
    v_org, p_work_type, p_work_id, v_author, v_first,
    v_pol_ratified, v_termo_doc, v_termo_ver,
    v_attr, v_enq, v_requires_review, v_caller.id)
  RETURNING id INTO v_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'work_governing_version.stamped', 'work_governing_version', v_id,
    jsonb_build_object('work_type', p_work_type, 'work_id', p_work_id, 'author_member_id', v_author,
      'first_material_contribution_at', v_first, 'governing_politica_version_id', v_pol_ratified,
      'governing_termo_version_id', v_termo_ver, 'requires_legal_review', v_requires_review,
      'legal_basis', 'Termo 15.4.1/15.4.6/15.4.7'));

  RETURN jsonb_build_object('stamped', true, 'idempotent', false, 'id', v_id,
    'work_type', p_work_type, 'work_id', p_work_id,
    'governing_politica_version_id', v_pol_ratified, 'governing_termo_version_id', v_termo_ver,
    'requires_legal_review', v_requires_review);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.stamp_work_governing_version(text, uuid, uuid, timestamptz, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.stamp_work_governing_version(text, uuid, uuid, timestamptz, jsonb) TO authenticated, service_role;

-- =====================================================================
-- 6. get_work_governing_version — read SECDEF. Aplica rls_can_see_initiative
--    (ADR-0105) inline (SECDEF bypassa RLS) + guard cross-org (M4: SECDEF bypassa
--    wgv_org_scope => evita vazar attribution_text/nome PII cross-org). Retorna o
--    stamp ATIVO ou null.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.get_work_governing_version(p_work_type text, p_work_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member record; v_row record;
BEGIN
  SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;

  -- ADR-0105: respeita a confidencialidade da initiative da obra.
  IF NOT public.rls_can_see_initiative(public._work_initiative_id(p_work_type, p_work_id)) THEN
    RAISE EXCEPTION 'Access denied' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_row FROM public.work_governing_version
  WHERE work_type = p_work_type AND work_id = p_work_id AND superseded_by_id IS NULL;
  IF v_row.id IS NULL THEN RETURN NULL; END IF;

  -- M4: SECDEF bypassa o RESTRICTIVE wgv_org_scope; reaplica o tenancy aqui. org NULL
  -- (knowledge_asset org-agnóstico) permanece universalmente legível, por design (M0).
  IF v_row.organization_id IS NOT NULL AND v_row.organization_id IS DISTINCT FROM public.auth_org() THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'id', v_row.id, 'work_type', v_row.work_type, 'work_id', v_row.work_id,
    'author_member_id', v_row.author_member_id, 'first_material_contribution_at', v_row.first_material_contribution_at,
    'governing_politica_version_id', v_row.governing_politica_version_id,
    'governing_termo_document_id', v_row.governing_termo_document_id,
    'governing_termo_version_id', v_row.governing_termo_version_id,
    'attribution_text', v_row.attribution_text, 'enquadramento', v_row.enquadramento,
    'requires_legal_review', v_row.requires_legal_review, 'stamped_at', v_row.stamped_at);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.get_work_governing_version(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_work_governing_version(text, uuid) TO authenticated, service_role;

-- =====================================================================
-- 7. PostgREST reload
-- =====================================================================
NOTIFY pgrst, 'reload schema';
