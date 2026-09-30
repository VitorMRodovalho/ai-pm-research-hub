-- #2495: uma versao aberta por pessoa e por pagina do wiki.
--
-- Medido em 29/09/2026, no piloto em uso: nas paginas da Tribo 4 e do Grupo de Estudos CPMAI, a autora
-- salvou um rascunho (v1) e, 21 s depois na primeira, criou e enviou uma v2 da mesma pagina. A v1 ficou
-- como rascunho orfao. wiki_save_draft sem p_version_id SEMPRE inseria uma versao nova, e a tela so
-- redirecionava ao rascunho existente quando o endereco trazia o caminho (o Voltar do navegador reabria o
-- editor em modo novo, ja preenchido).
--
-- wiki_save_draft recriado a partir do corpo vivo (md5 normalizado 52ec4a8f..., igual a captura de
-- 20260929105534): sem p_version_id, um rascunho ou versao devolvida da mesma pessoa na mesma pagina e
-- atualizado (volta a rascunho, como na edicao); uma versao dela aguardando decisao faz a chamada recusar.
-- A checagem vem depois da trava por pagina (pg_advisory_xact_lock), entao duas chamadas simultaneas nao
-- abrem duas versoes. Atributos e ACL inalterados (CREATE OR REPLACE com a mesma assinatura).
--
-- ROLLBACK: reaplicar wiki_save_draft de 20260929105534.

CREATE OR REPLACE FUNCTION public.wiki_save_draft(
  p_page_path text, p_initiative_id uuid, p_title text, p_summary text, p_content text,
  p_doc_type text, p_sources jsonb DEFAULT '[]'::jsonb, p_domain text DEFAULT 'tribes',
  p_version_id uuid DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_ver      public.wiki_page_versions%ROWTYPE;
  v_owner    uuid;
  v_no       integer;
  v_id       uuid;
  v_prefix   text;
  v_domain   text;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;

  -- Editar um rascunho (ou versão devolvida) do próprio autor.
  IF p_version_id IS NOT NULL THEN
    SELECT * INTO v_ver FROM public.wiki_page_versions WHERE id = p_version_id FOR UPDATE;
    IF NOT FOUND OR v_ver.author_id IS DISTINCT FROM v_caller THEN
      RAISE EXCEPTION 'wiki: rascunho não encontrado' USING ERRCODE = '42501';
    END IF;
    IF v_ver.status NOT IN ('draft', 'returned') THEN
      RAISE EXCEPTION 'wiki: só rascunho ou versão devolvida pode ser editada (estado atual: %)', v_ver.status;
    END IF;
    UPDATE public.wiki_page_versions
       SET title = p_title, summary = p_summary, content = coalesce(p_content, ''),
           doc_type = p_doc_type, sources = coalesce(p_sources, '[]'::jsonb),
           status = 'draft', updated_at = now()
     WHERE id = p_version_id;
    RETURN p_version_id;
  END IF;

  -- Emenda 3 (28/09): tribo, grupo de trabalho, vertical ou grupo de estudos. O domínio vem do tipo.
  SELECT public._wiki_domain_for_kind(i.kind) INTO v_domain FROM public.initiatives i WHERE i.id = p_initiative_id;
  IF v_domain IS NULL THEN
    RAISE EXCEPTION 'wiki: esta iniciativa não tem página no wiki (só tribo, grupo de trabalho, vertical ou grupo de estudos)';
  END IF;
  IF p_domain IS DISTINCT FROM v_domain THEN
    RAISE EXCEPTION 'wiki: o domínio desta iniciativa é %', v_domain;
  END IF;
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RAISE EXCEPTION 'wiki: iniciativa não encontrada' USING ERRCODE = '42501';
  END IF;
  IF NOT public._wiki_can_author(v_caller, p_initiative_id) THEN
    RAISE EXCEPTION 'wiki: só quem participa da iniciativa, ou o comitê de curadoria, escreve nesta página' USING ERRCODE = '42501';
  END IF;
  IF p_page_path IS NULL OR p_page_path !~ '^nucleo/[a-z0-9][a-z0-9/_-]*$' THEN
    RAISE EXCEPTION 'wiki: caminho inválido (use nucleo/...)';
  END IF;
  -- #2495: a página nova fica no espaço da própria tribo. Fronteira na barra: tribo-1 não abre tribo-12.
  v_prefix := public._wiki_initiative_path_prefix(p_initiative_id);
  IF p_page_path <> v_prefix AND NOT starts_with(p_page_path, v_prefix || '/') THEN
    RAISE EXCEPTION 'wiki: a página desta iniciativa fica em % (ou abaixo dele)', v_prefix;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('wiki_page_versions:' || p_page_path));
  SELECT initiative_id INTO v_owner FROM public.wiki_page_versions WHERE page_path = p_page_path LIMIT 1;
  IF v_owner IS NOT NULL AND v_owner <> p_initiative_id THEN
    RAISE EXCEPTION 'wiki: esta página pertence a outra iniciativa';
  END IF;
  -- Uma versao aberta por pessoa e por pagina (29/09/2026): duas liderancas salvaram um rascunho e, 21 s
  -- depois, enviaram uma SEGUNDA versao da mesma pagina, e a primeira ficou orfa em "Minhas versoes". "Criar"
  -- com rascunho ou versao devolvida ja aberta atualiza essa versao; com versao aguardando decisao, recusa.
  SELECT * INTO v_ver FROM public.wiki_page_versions
   WHERE page_path = p_page_path AND author_id = v_caller
     AND status IN ('draft', 'returned', 'pending_leader', 'pending_committee')
   ORDER BY version_no DESC LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    IF v_ver.status IN ('pending_leader', 'pending_committee') THEN
      RAISE EXCEPTION 'wiki: você já tem uma versão desta página aguardando decisão (versão %)', v_ver.version_no;
    END IF;
    UPDATE public.wiki_page_versions
       SET title = p_title, summary = p_summary, content = coalesce(p_content, ''),
           doc_type = p_doc_type, sources = coalesce(p_sources, '[]'::jsonb),
           status = 'draft', updated_at = now()
     WHERE id = v_ver.id;
    RETURN v_ver.id;
  END IF;

  SELECT coalesce(max(version_no), 0) + 1 INTO v_no FROM public.wiki_page_versions WHERE page_path = p_page_path;

  INSERT INTO public.wiki_page_versions
    (page_path, initiative_id, domain, version_no, title, summary, content, doc_type, sources, author_id, status)
  VALUES
    (p_page_path, p_initiative_id, p_domain, v_no, p_title, p_summary, coalesce(p_content, ''),
     p_doc_type, coalesce(p_sources, '[]'::jsonb), v_caller, 'draft')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

