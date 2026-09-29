-- #2495: fase B1 do wiki (ADR-0129, emenda 2, item 5). O que quem lê e o assistente enxergam.
--
--   (1) get_wiki_page e search_wiki_pages passam a devolver audit_status. A emenda 2 manda a página
--       publicada pela tribo e ainda não auditada dizer isso "a quem lê e ao assistente"; a tela já lia
--       a coluna direto de wiki_pages, o MCP não tinha como. Mudar o RETURNS TABLE exige DROP + CREATE:
--       mesmo corpo, uma coluna a mais no fim, e as duas continuam SECURITY INVOKER (a RLS de membro
--       ativo de wiki_pages é o portão desde 20260925183649) com o mesmo EXECUTE de antes.
--   (2) _wiki_type_tags: o formato da tag de tipo (diataxis-<tipo>) num lugar só.
--   (3) wiki_decide (publicar) e wiki_audit (alterar) gravam a tag. Antes as duas gravavam a página sem
--       tags, e a tela e a busca leem o tipo pela tag: uma página da plataforma não contava nos atalhos
--       do início nem aparecia no filtro por tipo. Medido em 28/09: 0 páginas da plataforma, então não
--       há o que reprocessar. Corpos = os de 20260927212811 (md5 do prosrc igual ao vivo), com a tag.
--
-- ROLLBACK: reaplicar get_wiki_page e search_wiki_pages de 20260925183649 (DROP + CREATE sem
--   audit_status, SECURITY INVOKER, mesmo EXECUTE); reaplicar wiki_decide e wiki_audit de
--   20260927212811; DROP FUNCTION public._wiki_type_tags(text).

-- ─── (1) leituras com o estado de auditoria ────────────────────────────────────────────────────
DROP FUNCTION public.get_wiki_page(text);
CREATE FUNCTION public.get_wiki_page(p_path text)
 RETURNS TABLE(id uuid, path text, title text, domain text, content text, summary text, tags text[], authors text[], license text, ip_track text, source_sha text, synced_at timestamp with time zone, updated_at timestamp with time zone, audit_status text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT
    w.id, w.path, w.title, w.domain, w.content, w.summary,
    w.tags, w.authors, w.license, w.ip_track,
    w.source_sha, w.synced_at, w.updated_at, w.audit_status
  FROM wiki_pages w
  WHERE w.path = p_path;
$function$;

DROP FUNCTION public.search_wiki_pages(text, integer, text, text);
CREATE FUNCTION public.search_wiki_pages(p_query text, p_limit integer DEFAULT 10, p_domain text DEFAULT NULL::text, p_tag text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, path text, title text, domain text, summary text, tags text[], license text, ip_track text, rank real, headline text, audit_status text)
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
    w.audit_status
  FROM wiki_pages w
  WHERE w.fts @@ websearch_to_tsquery('portuguese', p_query)
    AND (p_domain IS NULL OR w.domain = p_domain)
    AND (p_tag IS NULL OR p_tag = ANY(w.tags))
  ORDER BY rank DESC
  LIMIT p_limit;
$function$;

REVOKE ALL ON FUNCTION public.get_wiki_page(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.search_wiki_pages(text, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_wiki_page(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_wiki_pages(text, integer, text, text) TO authenticated, service_role;

-- ─── (2) o formato da tag de tipo ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._wiki_type_tags(p_doc_type text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE WHEN p_doc_type IS NULL THEN '{}'::text[] ELSE ARRAY['diataxis-' || p_doc_type] END;
$function$;

REVOKE ALL ON FUNCTION public._wiki_type_tags(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._wiki_type_tags(text) TO service_role;

-- ─── (3) publicar e alterar gravam a tag ───────────────────────────────────────────────────────
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
     audit_status, platform_version_id)
  VALUES
    (v_ver.page_path, v_ver.title, v_ver.domain, v_ver.content, v_ver.summary,
     public._wiki_type_tags(v_ver.doc_type),
     CASE WHEN v_author_name IS NULL THEN '{}'::text[] ELSE ARRAY[v_author_name] END,
     'plataforma', p_version_id::text, now(), now(), v_audit_status, p_version_id)
  ON CONFLICT (path) DO UPDATE
     SET title = EXCLUDED.title, domain = EXCLUDED.domain, content = EXCLUDED.content,
         summary = EXCLUDED.summary, tags = EXCLUDED.tags, authors = EXCLUDED.authors, source_sha = EXCLUDED.source_sha,
         synced_at = EXCLUDED.synced_at, updated_at = EXCLUDED.updated_at,
         audit_status = EXCLUDED.audit_status, platform_version_id = EXCLUDED.platform_version_id
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
     audited_at, audited_by, audit_outcome)
  VALUES
    (v_ver.page_path, v_ver.initiative_id, v_ver.domain, v_no, coalesce(p_title, v_ver.title),
     coalesce(p_summary, v_ver.summary), p_content, v_ver.doc_type, v_ver.sources,
     v_caller, 'published', 'committee', now(), now(), v_caller, now(), v_caller, 'kept')
  RETURNING * INTO v_new;

  UPDATE public.wiki_pages
     SET title = v_new.title, summary = v_new.summary, content = v_new.content,
         tags = public._wiki_type_tags(v_new.doc_type),
         source_sha = v_new.id::text, synced_at = now(), updated_at = now(),
         audit_status = 'audited', platform_version_id = v_new.id
   WHERE path = v_ver.page_path AND source_repo = 'plataforma';

  INSERT INTO public.wiki_page_events (version_id, page_path, action, actor_id, reason)
  VALUES (p_version_id, v_ver.page_path, 'altered', v_caller, p_reason),
         (v_new.id, v_ver.page_path, 'published', v_caller, 'alteração do comitê de curadoria');
  PERFORM public._wiki_notify(array_remove(v_others, v_caller), 'wiki_page_decision', 'Página do wiki alterada',
    '"' || v_new.title || '" foi alterada pelo comitê de curadoria: ' || p_reason, v_new.id);
  RETURN v_new.id;
END;
$function$;
