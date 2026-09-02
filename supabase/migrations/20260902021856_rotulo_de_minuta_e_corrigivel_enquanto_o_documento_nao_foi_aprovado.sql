-- WHAT: (1) helper governance_document_is_unsigned_draft; (2) trg_document_version_immutable passa a
--       permitir corrigir version_label enquanto o documento pai nunca foi aprovado; (3) a RPC do
--       #2136 passa a usar o helper, para a regra existir em UM lugar so; (4) renomeia os rotulos
--       das versoes 1 e 2 do TAP de R00/R01 para M01/M02.
-- WHY:  decisao do dono 2026-09-02 (opcao A). O selo de `locked_at` existe para que um comentario
--       ancorado numa clausula continue apontando para o MESMO TEXTO. `version_label` nomeia a
--       RODADA, nao o texto: renomear nao move uma virgula. O trigger nao fazia essa distincao e
--       congelava identidade junto com conteudo, o que impedia corrigir rotulo de rascunho que
--       nunca vigorou.
-- O CUSTO DE NAO FAZER: UNIQUE (document_id, version_label) + a convencao de numeracao vigente
--       (minuta M01/M02/M03; aprovado R00/R01) fazem a publicacao da versao aprovada como `R00`
--       VIOLAR a constraint, porque a versao 1 ja ocupa o rotulo. Falha dura no dia da aprovacao.
-- SCOPE LOCK: conteudo segue absolutamente imutavel. content_html, content_markdown, version_number,
--       document_id, locked_at e change_class continuam congelados em linha lacrada, sem excecao.
--       A unica folga e version_label, e so enquanto o documento pai e rascunho nao assinado.
-- ROLLBACK: restaurar o corpo anterior de trg_document_version_immutable (sem o ramo de
--       version_label) e UPDATE ... SET version_label='R00'/'R01' nas versoes 1 e 2.
-- CROSS-REF: #2136 · #571 PR-1 §9.2 (origem do congelamento de change_class)

-- 1. A regra, em UM lugar. Consumida pelo trigger e pela RPC.
CREATE OR REPLACE FUNCTION public.governance_document_is_unsigned_draft(p_document_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT gd.status = 'draft'
     AND gd.signed_at IS NULL
     AND gd.first_ratified_at IS NULL
     AND gd.current_ratified_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.member_document_signatures s WHERE s.document_id = gd.id)
     AND NOT EXISTS (SELECT 1 FROM public.approval_chains ac
                      WHERE ac.document_id = gd.id AND ac.status = 'active')
  FROM public.governance_documents gd
  WHERE gd.id = p_document_id;
$function$;

REVOKE ALL ON FUNCTION public.governance_document_is_unsigned_draft(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.governance_document_is_unsigned_draft(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.governance_document_is_unsigned_draft(uuid) IS
  'TRUE quando o documento e rascunho que nunca foi assinado nem ratificado e nao tem cadeia ativa. Fonte unica da regra de ciclo de vida usada pelo trigger de imutabilidade de versao e pela RPC de metadado (#2136). NULL se o documento nao existe: quem chama usa COALESCE(...,false).';

-- 2. O trigger distingue TEXTO de IDENTIDADE.
CREATE OR REPLACE FUNCTION public.trg_document_version_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF OLD.locked_at IS NOT NULL THEN
    -- Conteudo e estrutura: congelados sem excecao. change_class incluido (#571 PR-1 §9.2).
    IF NEW.content_html IS DISTINCT FROM OLD.content_html
       OR NEW.content_markdown IS DISTINCT FROM OLD.content_markdown
       OR NEW.version_number IS DISTINCT FROM OLD.version_number
       OR NEW.document_id IS DISTINCT FROM OLD.document_id
       OR NEW.locked_at IS DISTINCT FROM OLD.locked_at
       OR NEW.change_class IS DISTINCT FROM OLD.change_class
    THEN
      RAISE EXCEPTION 'document_versions row locked at % is immutable (id=%, document=%)', OLD.locked_at, OLD.id, OLD.document_id
        USING ERRCODE = 'check_violation';
    END IF;

    -- #2136: version_label nomeia a RODADA, nao o texto. Enquanto o documento pai nunca foi
    -- aprovado, corrigir o rotulo nao viola nada que a lacracao exista para proteger.
    IF NEW.version_label IS DISTINCT FROM OLD.version_label
       AND NOT COALESCE(public.governance_document_is_unsigned_draft(OLD.document_id), false)
    THEN
      RAISE EXCEPTION 'document_versions row locked at % belongs to an approved document: version_label is immutable (id=%, document=%)', OLD.locked_at, OLD.id, OLD.document_id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

-- 3. A RPC do #2136 passa a consumir o helper: a regra deixa de existir em dois lugares.
CREATE OR REPLACE FUNCTION public.update_governance_document_meta(
  p_document_id uuid,
  p_title       text DEFAULT NULL,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_doc       record;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member');
  END IF;

  SELECT * INTO v_doc FROM public.governance_documents WHERE id = p_document_id;
  IF v_doc IS NULL THEN
    RETURN jsonb_build_object('error', 'Document not found');
  END IF;

  IF p_title IS NULL AND p_description IS NULL THEN
    RETURN jsonb_build_object('error', 'nothing_to_update');
  END IF;

  -- A REGRA, agora de fonte unica.
  IF NOT COALESCE(public.governance_document_is_unsigned_draft(p_document_id), false) THEN
    RETURN jsonb_build_object(
      'error', 'frozen: document metadata is immutable once signed or out of draft',
      'status', v_doc.status,
      'first_ratified_at', v_doc.first_ratified_at
    );
  END IF;

  UPDATE public.governance_documents SET
    title       = COALESCE(p_title, title),
    description = COALESCE(p_description, description),
    updated_at  = now()
  WHERE id = p_document_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'governance_document_meta_change', 'governance_document', p_document_id,
    jsonb_build_object(
      'from', jsonb_build_object('title', v_doc.title, 'description', v_doc.description),
      'to',   jsonb_build_object('title', COALESCE(p_title, v_doc.title),
                                 'description', COALESCE(p_description, v_doc.description))));

  RETURN jsonb_build_object('ok', true, 'document_id', p_document_id,
    'title', COALESCE(p_title, v_doc.title));
END;
$function$;

-- 4. O rename, com pre e pos-condicoes.
DO $$
DECLARE v_doc_id uuid; v_n int; v_antes text; v_depois text;
BEGIN
  SELECT document_id INTO v_doc_id FROM public.document_versions
   WHERE id = '43f3bb5c-7e39-45a1-b548-800b6ad22ff5';
  IF v_doc_id IS NULL THEN
    RAISE EXCEPTION 'versao de referencia nao encontrada: o documento alvo mudou';
  END IF;

  IF NOT COALESCE(public.governance_document_is_unsigned_draft(v_doc_id), false) THEN
    RAISE EXCEPTION 'documento nao e mais rascunho nao assinado: rename abortado';
  END IF;

  SELECT string_agg(version_number||'='||version_label, ' | ' ORDER BY version_number)
    INTO v_antes FROM public.document_versions WHERE document_id = v_doc_id;

  SELECT count(*) INTO v_n FROM public.document_versions
   WHERE document_id = v_doc_id AND version_label IN ('M01','M02','M03');
  IF v_n <> 0 THEN RAISE EXCEPTION 'rotulo de destino ja ocupado (% linhas)', v_n; END IF;

  UPDATE public.document_versions SET version_label='M01'
   WHERE document_id=v_doc_id AND version_number=1 AND version_label='R00';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'v1 R00->M01: renomeei % linhas', v_n; END IF;

  UPDATE public.document_versions SET version_label='M02'
   WHERE document_id=v_doc_id AND version_number=2 AND version_label='R01';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'v2 R01->M02: renomeei % linhas', v_n; END IF;

  -- Normalizacao do zero a esquerda. Sem ela o acervo sai com M01, M02, M3, e a proxima
  -- rodada nao tem forma obvia: M4 ou M04. Duas familias de numeracao na mesma pagina de
  -- assinaturas e defeito barato de evitar agora e caro de corrigir depois, porque esta
  -- janela fecha junto com a pre-condicao de rascunho nao assinado logo acima.
  UPDATE public.document_versions SET version_label='M03'
   WHERE document_id=v_doc_id AND version_number=3 AND version_label='M3';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'v3 M3->M03: renomeei % linhas (rotulo de origem nao era M3?)', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.document_versions
   WHERE document_id = v_doc_id AND version_label ~ '^R[0-9]';
  IF v_n <> 0 THEN RAISE EXCEPTION 'o espaco aprovado ainda tem % rotulo(s) ocupado(s)', v_n; END IF;

  -- Pos-condicao de forma: toda minuta deste documento passa a ser M seguido de dois digitos.
  SELECT count(*) INTO v_n FROM public.document_versions
   WHERE document_id = v_doc_id AND version_label !~ '^M[0-9]{2}$';
  IF v_n <> 0 THEN RAISE EXCEPTION '% rotulo(s) fora do formato M99', v_n; END IF;

  SELECT string_agg(version_number||'='||version_label, ' | ' ORDER BY version_number)
    INTO v_depois FROM public.document_versions WHERE document_id = v_doc_id;
  RAISE NOTICE 'antes: % | depois: %', v_antes, v_depois;
END $$;

NOTIFY pgrst, 'reload schema';
