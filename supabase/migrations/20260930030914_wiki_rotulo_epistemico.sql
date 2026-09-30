-- #2495 / ADR-0132: o rotulo epistemico da pagina do wiki (decisao do GP em 29/09/2026).
--
-- A decisao de 26/09 (#2495, item 2) pedia que cada proposta levasse um rotulo epistemico (fonte, observacao
-- de membro, sintese de IA, pesquisa externa); medido em 29/09, nenhuma tabela, funcao ou tela o tinha. Ele
-- entra agora, antes do MCP de escrita, que grava 'sintese_ia' por padrao.
--
--   (1) wiki_page_versions.epistemic_label, obrigatorio, padrao 'observacao_membro' (o padrao da tela). As 4
--       versoes existentes recebem o padrao: nao ha como saber se as autoras usaram IA.
--   (2) wiki_pages.epistemic_label, opcional (pagina do repositorio nao tem); as 2 paginas da plataforma
--       recebem o rotulo da versao publicada.
--   (3) wiki_save_draft ganha p_epistemic_label no fim (DROP + CREATE: troca de assinatura); NULL mantem o
--       rotulo que a versao ja tem, e rascunho novo usa o padrao.
--   (4) wiki_decide e wiki_audit gravam o rotulo na pagina publicada; a versao alterada pelo comite herda o da
--       versao que ela altera. CREATE OR REPLACE a partir do corpo vivo (md5 igual a captura de 20260928205842).
--   (5) get_wiki_page e search_wiki_pages devolvem o rotulo no fim (DROP + CREATE: troca de retorno).
--   wiki_get_version devolve to_jsonb(versao) e ja traz a coluna nova sem mudanca.
--
-- ROLLBACK: reaplicar wiki_save_draft de 20260930010052, wiki_decide/wiki_audit/get_wiki_page/search_wiki_pages de
--   20260928205842 (com DROP das duas leituras e de wiki_save_draft), e DROP COLUMN epistemic_label nas duas tabelas.

-- ─── (1) e (2) ─────────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.wiki_page_versions ADD COLUMN IF NOT EXISTS epistemic_label text NOT NULL DEFAULT 'observacao_membro';
ALTER TABLE public.wiki_page_versions DROP CONSTRAINT IF EXISTS wiki_page_versions_epistemic_label_check;
ALTER TABLE public.wiki_page_versions ADD CONSTRAINT wiki_page_versions_epistemic_label_check
  CHECK (epistemic_label = ANY (ARRAY['fonte', 'observacao_membro', 'sintese_ia', 'pesquisa_externa']));
ALTER TABLE public.wiki_pages ADD COLUMN IF NOT EXISTS epistemic_label text;
ALTER TABLE public.wiki_pages DROP CONSTRAINT IF EXISTS wiki_pages_epistemic_label_check;
ALTER TABLE public.wiki_pages ADD CONSTRAINT wiki_pages_epistemic_label_check
  CHECK (epistemic_label IS NULL OR epistemic_label = ANY (ARRAY['fonte', 'observacao_membro', 'sintese_ia', 'pesquisa_externa']));
UPDATE public.wiki_pages w SET epistemic_label = v.epistemic_label
  FROM public.wiki_page_versions v
 WHERE w.platform_version_id = v.id AND w.source_repo = 'plataforma';

-- ─── (3) ───────────────────────────────────────────────────────────────────────────────────────
DROP FUNCTION public.wiki_save_draft(text, uuid, text, text, text, text, jsonb, text, uuid);
CREATE FUNCTION public.wiki_save_draft(
  p_page_path text, p_initiative_id uuid, p_title text, p_summary text, p_content text,
  p_doc_type text, p_sources jsonb DEFAULT '[]'::jsonb, p_domain text DEFAULT 'tribes',
  p_version_id uuid DEFAULT NULL, p_epistemic_label text DEFAULT NULL)
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
  -- ADR-0132: o rotulo epistemico. NULL mantem o da versao que ja existe, ou usa o padrao da tabela.
  IF p_epistemic_label IS NOT NULL AND p_epistemic_label <> ALL (ARRAY['fonte', 'observacao_membro', 'sintese_ia', 'pesquisa_externa']) THEN
    RAISE EXCEPTION 'wiki: rótulo inválido (fonte, observacao_membro, sintese_ia ou pesquisa_externa)' USING ERRCODE = '23514';
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
           epistemic_label = coalesce(p_epistemic_label, epistemic_label),
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
           epistemic_label = coalesce(p_epistemic_label, epistemic_label),
           status = 'draft', updated_at = now()
     WHERE id = v_ver.id;
    RETURN v_ver.id;
  END IF;

  SELECT coalesce(max(version_no), 0) + 1 INTO v_no FROM public.wiki_page_versions WHERE page_path = p_page_path;

  INSERT INTO public.wiki_page_versions
    (page_path, initiative_id, domain, version_no, title, summary, content, doc_type, sources, author_id, status,
     epistemic_label)
  VALUES
    (p_page_path, p_initiative_id, p_domain, v_no, p_title, p_summary, coalesce(p_content, ''),
     p_doc_type, coalesce(p_sources, '[]'::jsonb), v_caller, 'draft', coalesce(p_epistemic_label, 'observacao_membro'))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- ─── (4) ───────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.wiki_decide(p_version_id uuid, p_decision text, p_reason text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller       uuid;
  v_ver          public.wiki_page_versions%ROWTYPE;
  v_is_committee boolean;
  v_is_leader    boolean;
  v_author_name  text;
  v_audit_status text;
  v_due          timestamptz;
  v_others       uuid[];
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;
  IF p_decision IS NULL OR p_decision NOT IN ('publish', 'return') THEN
    RAISE EXCEPTION 'wiki: decisão inválida (publish ou return)';
  END IF;
  SELECT * INTO v_ver FROM public.wiki_page_versions WHERE id = p_version_id FOR UPDATE;
  IF NOT FOUND OR NOT public.rls_can_see_initiative(v_ver.initiative_id) THEN
    RAISE EXCEPTION 'wiki: versão não encontrada' USING ERRCODE = '42501';
  END IF;
  IF v_ver.status NOT IN ('pending_leader', 'pending_committee') THEN
    RAISE EXCEPTION 'wiki: esta versão não aguarda decisão (estado atual: %)', v_ver.status;
  END IF;
  IF v_ver.author_id = v_caller THEN
    RAISE EXCEPTION 'wiki: quem escreveu não aprova a própria versão' USING ERRCODE = '42501';
  END IF;

  v_is_committee := public.can_by_member(v_caller, 'curate_content');
  v_is_leader    := public._wiki_is_initiative_leader(v_caller, v_ver.initiative_id);
  IF v_ver.status = 'pending_committee' AND NOT v_is_committee THEN
    RAISE EXCEPTION 'wiki: esta versão aguarda o comitê de curadoria' USING ERRCODE = '42501';
  END IF;
  IF v_ver.status = 'pending_leader' AND NOT (v_is_leader OR v_is_committee) THEN
    RAISE EXCEPTION 'wiki: só a liderança da tribo ou o comitê decidem esta versão' USING ERRCODE = '42501';
  END IF;

  IF p_decision = 'return' THEN
    IF coalesce(btrim(p_reason), '') = '' THEN
      RAISE EXCEPTION 'wiki: devolver exige motivo';
    END IF;
    UPDATE public.wiki_page_versions SET status = 'returned', updated_at = now() WHERE id = p_version_id;
    INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
    VALUES (p_version_id, v_ver.page_path, 'returned', v_caller, p_reason);
    PERFORM public._wiki_notify(ARRAY[v_ver.author_id], 'wiki_page_decision', 'Página do wiki devolvida',
      '"' || v_ver.title || '" foi devolvida: ' || p_reason, p_version_id);
    RETURN 'returned';
  END IF;

  -- publicar
  v_due := CASE WHEN v_is_committee THEN NULL ELSE now() + interval '14 days' END;
  v_audit_status := CASE WHEN v_is_committee THEN 'audited' ELSE 'pending' END;

  UPDATE public.wiki_page_versions SET status = 'superseded', updated_at = now()
   WHERE page_path = v_ver.page_path AND status = 'published';
  UPDATE public.wiki_page_versions
     SET status = 'published', published_by = v_caller, published_at = now(), audit_due_at = v_due,
         audited_at = CASE WHEN v_is_committee THEN now() END,
         audited_by = CASE WHEN v_is_committee THEN v_caller END,
         audit_outcome = CASE WHEN v_is_committee THEN 'kept' END,
         updated_at = now()
   WHERE id = p_version_id;

  SELECT name INTO v_author_name FROM public.members WHERE id = v_ver.author_id;
  INSERT INTO public.wiki_pages
    (path, title, domain, content, summary, tags, authors, source_repo, source_sha, synced_at, updated_at,
     audit_status, platform_version_id, epistemic_label)
  VALUES
    (v_ver.page_path, v_ver.title, v_ver.domain, v_ver.content, v_ver.summary,
     public._wiki_type_tags(v_ver.doc_type),
     CASE WHEN v_author_name IS NULL THEN '{}'::text[] ELSE ARRAY[v_author_name] END,
     'plataforma', p_version_id::text, now(), now(), v_audit_status, p_version_id, v_ver.epistemic_label)
  ON CONFLICT (path) DO UPDATE
     SET title = EXCLUDED.title, domain = EXCLUDED.domain, content = EXCLUDED.content,
         summary = EXCLUDED.summary, tags = EXCLUDED.tags, authors = EXCLUDED.authors, source_sha = EXCLUDED.source_sha,
         synced_at = EXCLUDED.synced_at, updated_at = EXCLUDED.updated_at,
         audit_status = EXCLUDED.audit_status, platform_version_id = EXCLUDED.platform_version_id,
         epistemic_label = EXCLUDED.epistemic_label
   WHERE public.wiki_pages.source_repo = 'plataforma';

  INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
  VALUES (p_version_id, v_ver.page_path, 'published', v_caller,
          CASE WHEN v_is_committee THEN 'pelo comitê de curadoria' ELSE 'pela liderança da tribo' END);

  v_others := array_remove(ARRAY[v_ver.author_id] || ARRAY(SELECT public._wiki_initiative_leader_ids(v_ver.initiative_id)), v_caller);
  PERFORM public._wiki_notify(v_others, 'wiki_page_decision', 'Página do wiki publicada',
    '"' || v_ver.title || '" foi publicada'
      || CASE WHEN v_is_committee THEN ' e já está auditada pelo comitê.'
              ELSE ' e fica com auditoria pendente do comitê até '
                   || to_char(v_due AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') || '.' END,
    p_version_id);
  IF NOT v_is_committee THEN
    PERFORM public._wiki_notify(array_remove(ARRAY(SELECT public._wiki_committee_ids()), v_caller),
      'wiki_audit_requested', 'Página do wiki para auditar',
      '"' || v_ver.title || '" foi publicada pela liderança da tribo. Prazo da auditoria: '
        || to_char(v_due AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') || '.',
      p_version_id);
  END IF;
  RETURN 'published';
END;
$function$;

CREATE OR REPLACE FUNCTION public.wiki_audit(p_version_id uuid, p_outcome text, p_reason text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_summary text DEFAULT NULL::text, p_content text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller  uuid;
  v_ver     public.wiki_page_versions%ROWTYPE;
  v_new     public.wiki_page_versions%ROWTYPE;
  v_no      integer;
  v_pii     text;
  v_others  uuid[];
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member()
     OR NOT public.can_by_member(v_caller, 'curate_content') THEN
    RAISE EXCEPTION 'wiki: auditoria é do comitê de curadoria' USING ERRCODE = '42501';
  END IF;
  IF p_outcome IS NULL OR p_outcome NOT IN ('kept', 'altered', 'unpublished') THEN
    RAISE EXCEPTION 'wiki: resultado inválido (kept, altered ou unpublished)';
  END IF;
  SELECT * INTO v_ver FROM public.wiki_page_versions WHERE id = p_version_id FOR UPDATE;
  IF NOT FOUND OR NOT public.rls_can_see_initiative(v_ver.initiative_id) THEN
    RAISE EXCEPTION 'wiki: versão não encontrada' USING ERRCODE = '42501';
  END IF;
  IF v_ver.status <> 'published' THEN
    RAISE EXCEPTION 'wiki: só versão publicada é auditada (estado atual: %)', v_ver.status;
  END IF;
  IF v_ver.author_id = v_caller THEN
    RAISE EXCEPTION 'wiki: quem escreveu não audita a própria versão' USING ERRCODE = '42501';
  END IF;
  IF p_outcome IN ('altered', 'unpublished') AND coalesce(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'wiki: alterar ou despublicar exige motivo';
  END IF;
  v_others := ARRAY[v_ver.author_id] || ARRAY(SELECT public._wiki_initiative_leader_ids(v_ver.initiative_id));

  IF p_outcome = 'kept' THEN
    IF v_ver.audited_at IS NOT NULL THEN
      RAISE EXCEPTION 'wiki: esta versão já foi auditada';
    END IF;
    UPDATE public.wiki_page_versions
       SET audited_at = now(), audited_by = v_caller, audit_outcome = 'kept', updated_at = now()
     WHERE id = p_version_id;
    UPDATE public.wiki_pages SET audit_status = 'audited'
     WHERE path = v_ver.page_path AND source_repo = 'plataforma';
    INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
    VALUES (p_version_id, v_ver.page_path, 'audited_kept', v_caller, p_reason);
    PERFORM public._wiki_notify(array_remove(v_others, v_caller), 'wiki_page_decision', 'Página do wiki auditada',
      '"' || v_ver.title || '" foi auditada e mantida pelo comitê de curadoria.', p_version_id);
    RETURN p_version_id;
  END IF;

  IF p_outcome = 'unpublished' THEN
    UPDATE public.wiki_page_versions
       SET status = 'unpublished', audited_at = coalesce(audited_at, now()), audited_by = v_caller,
           audit_outcome = 'unpublished', updated_at = now()
     WHERE id = p_version_id;
    DELETE FROM public.wiki_pages WHERE path = v_ver.page_path AND source_repo = 'plataforma';
    INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
    VALUES (p_version_id, v_ver.page_path, 'unpublished', v_caller, p_reason);
    PERFORM public._wiki_notify(array_remove(v_others, v_caller), 'wiki_page_decision', 'Página do wiki despublicada',
      '"' || v_ver.title || '" foi despublicada pelo comitê de curadoria: ' || p_reason, p_version_id);
    RETURN p_version_id;
  END IF;

  -- alterar: o comitê publica uma versão nova, já auditada, e a anterior fica registrada como alterada
  IF p_content IS NULL THEN
    RAISE EXCEPTION 'wiki: alterar exige o texto novo';
  END IF;
  v_pii := public._wiki_pii_detail(concat_ws(E'\n', coalesce(p_title, v_ver.title), coalesce(p_summary, v_ver.summary), p_content));
  IF v_pii IS NOT NULL THEN
    RAISE EXCEPTION 'wiki: o texto novo tem possível dado pessoal (%)', v_pii USING ERRCODE = '23514';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('wiki_page_versions:' || v_ver.page_path));
  SELECT max(version_no) + 1 INTO v_no FROM public.wiki_page_versions WHERE page_path = v_ver.page_path;

  UPDATE public.wiki_page_versions
     SET status = 'superseded', audited_at = coalesce(audited_at, now()), audited_by = v_caller,
         audit_outcome = 'altered', updated_at = now()
   WHERE id = p_version_id;
  INSERT INTO public.wiki_page_versions
    (page_path, initiative_id, domain, version_no, title, summary, content, doc_type, sources,
     author_id, status, review_route, submitted_at, published_at, published_by,
     audited_at, audited_by, audit_outcome, epistemic_label)
  VALUES
    (v_ver.page_path, v_ver.initiative_id, v_ver.domain, v_no, coalesce(p_title, v_ver.title),
     coalesce(p_summary, v_ver.summary), p_content, v_ver.doc_type, v_ver.sources,
     v_caller, 'published', 'committee', now(), now(), v_caller, now(), v_caller, 'kept', v_ver.epistemic_label)
  RETURNING * INTO v_new;

  UPDATE public.wiki_pages
     SET title = v_new.title, summary = v_new.summary, content = v_new.content,
         tags = public._wiki_type_tags(v_new.doc_type),
         source_sha = v_new.id::text, synced_at = now(), updated_at = now(),
         audit_status = 'audited', platform_version_id = v_new.id, epistemic_label = v_new.epistemic_label
   WHERE path = v_ver.page_path AND source_repo = 'plataforma';

  INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
  VALUES (p_version_id, v_ver.page_path, 'altered', v_caller, p_reason),
         (v_new.id, v_ver.page_path, 'published', v_caller, 'alteração do comitê de curadoria');
  PERFORM public._wiki_notify(array_remove(v_others, v_caller), 'wiki_page_decision', 'Página do wiki alterada',
    '"' || v_new.title || '" foi alterada pelo comitê de curadoria: ' || p_reason, v_new.id);
  RETURN v_new.id;
END;
$function$;

-- ─── (5) ───────────────────────────────────────────────────────────────────────────────────────
DROP FUNCTION public.get_wiki_page(text);
CREATE FUNCTION public.get_wiki_page(p_path text)
 RETURNS TABLE(id uuid, path text, title text, domain text, content text, summary text, tags text[], authors text[], license text, ip_track text, source_sha text, synced_at timestamp with time zone, updated_at timestamp with time zone, audit_status text, epistemic_label text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT
    w.id, w.path, w.title, w.domain, w.content, w.summary,
    w.tags, w.authors, w.license, w.ip_track,
    w.source_sha, w.synced_at, w.updated_at, w.audit_status, w.epistemic_label
  FROM wiki_pages w
  WHERE w.path = p_path;
$function$;

DROP FUNCTION public.search_wiki_pages(text, integer, text, text);
CREATE FUNCTION public.search_wiki_pages(p_query text, p_limit integer DEFAULT 10, p_domain text DEFAULT NULL::text, p_tag text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, path text, title text, domain text, summary text, tags text[], license text, ip_track text, rank real, headline text, audit_status text, epistemic_label text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT
    w.id, w.path, w.title, w.domain, w.summary, w.tags,
    w.license, w.ip_track,
    ts_rank(w.fts, websearch_to_tsquery('portuguese', p_query)) AS rank,
    ts_headline('portuguese', w.content, websearch_to_tsquery('portuguese', p_query),
      'MaxWords=60, MinWords=20, StartSel=**, StopSel=**') AS headline,
    w.audit_status, w.epistemic_label
  FROM wiki_pages w
  WHERE w.fts @@ websearch_to_tsquery('portuguese', p_query)
    AND (p_domain IS NULL OR w.domain = p_domain)
    AND (p_tag IS NULL OR p_tag = ANY(w.tags))
  ORDER BY rank DESC
  LIMIT p_limit;
$function$;

-- ─── permissoes (as funcoes recriadas voltam com o mesmo EXECUTE de antes) ─────────────────────
REVOKE ALL ON FUNCTION public.wiki_save_draft(text, uuid, text, text, text, text, jsonb, text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wiki_save_draft(text, uuid, text, text, text, text, jsonb, text, uuid, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_wiki_page(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_wiki_page(text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.search_wiki_pages(text, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_wiki_pages(text, integer, text, text) TO authenticated, service_role;
