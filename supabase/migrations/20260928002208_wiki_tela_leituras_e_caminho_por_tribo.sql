-- #2495: piloto do wiki vivo, o que a tela /wiki precisa do banco (ADR-0129, emenda 2).
--
--   (1) _wiki_initiative_path_prefix: o espaço de caminhos de cada tribo (nucleo/tribes/tribo-<n>).
--   (2) wiki_save_draft passa a exigir que uma página nova fique no espaço da PRÓPRIA tribo. Antes,
--       quem participava de uma tribo podia criar a primeira versão em qualquer caminho nucleo/...,
--       e a posse do caminho fica com a iniciativa da primeira versão: um pesquisador da tribo 1
--       ocupava nucleo/tribes/tribo-5 e a tribo 5 passava a receber "esta página pertence a outra
--       iniciativa" no próprio caminho. Medido em 27/09: 0 versões, então a trava entra antes do uso.
--   (3) _wiki_notify: o aviso aponta para a versão (/wiki?version=<id>), não para a raiz do wiki.
--   (4) wiki_authoring_context: as tribos em que quem está logado escreve, e se é do comitê.
--   (5) wiki_page_history: as versões de uma página que quem está logado pode ler, com a tribo dona.
--
-- ROLLBACK: DROP FUNCTION wiki_page_history(text), wiki_authoring_context(), _wiki_initiative_path_prefix(uuid);
--   reaplicar wiki_save_draft e _wiki_notify de 20260927212811.

-- ─── (1) espaço de caminhos da tribo ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._wiki_initiative_path_prefix(p_initiative uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE WHEN i.legacy_tribe_id IS NOT NULL
              THEN 'nucleo/tribes/tribo-' || i.legacy_tribe_id
              ELSE 'nucleo/tribes/' || i.id::text END
    FROM public.initiatives i
   WHERE i.id = p_initiative;
$function$;

-- ─── (2) escrever: rascunho, agora no espaço da própria tribo ──────────────────────────────────
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

  -- Piloto (emenda 1, item 4): só o domínio tribes, em tribo de pesquisa.
  IF p_domain IS DISTINCT FROM 'tribes' THEN
    RAISE EXCEPTION 'wiki: fora do piloto (só o domínio tribes)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.id = p_initiative_id AND i.kind = 'research_tribe') THEN
    RAISE EXCEPTION 'wiki: a iniciativa precisa ser uma tribo de pesquisa';
  END IF;
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RAISE EXCEPTION 'wiki: iniciativa não encontrada' USING ERRCODE = '42501';
  END IF;
  IF NOT public._wiki_can_author(v_caller, p_initiative_id) THEN
    RAISE EXCEPTION 'wiki: só quem participa da tribo, ou o comitê de curadoria, escreve nesta página' USING ERRCODE = '42501';
  END IF;
  IF p_page_path IS NULL OR p_page_path !~ '^nucleo/[a-z0-9][a-z0-9/_-]*$' THEN
    RAISE EXCEPTION 'wiki: caminho inválido (use nucleo/...)';
  END IF;
  -- #2495: a página nova fica no espaço da própria tribo. Fronteira na barra: tribo-1 não abre tribo-12.
  v_prefix := public._wiki_initiative_path_prefix(p_initiative_id);
  IF p_page_path <> v_prefix AND NOT starts_with(p_page_path, v_prefix || '/') THEN
    RAISE EXCEPTION 'wiki: a página desta tribo fica em % (ou abaixo dele)', v_prefix;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('wiki_page_versions:' || p_page_path));
  SELECT initiative_id INTO v_owner FROM public.wiki_page_versions WHERE page_path = p_page_path LIMIT 1;
  IF v_owner IS NOT NULL AND v_owner <> p_initiative_id THEN
    RAISE EXCEPTION 'wiki: esta página pertence a outra iniciativa';
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

-- ─── (3) o aviso leva à versão ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._wiki_notify(p_recipients uuid[], p_type text, p_title text, p_body text, p_version uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_n  integer := 0;
BEGIN
  FOR v_id IN SELECT DISTINCT u FROM unnest(p_recipients) u WHERE u IS NOT NULL LOOP
    PERFORM public.create_notification(v_id, p_type, p_title, p_body, '/wiki?version=' || p_version::text,
                                       'wiki_page_version', p_version);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;

-- ─── (4) contexto de autoria de quem está logado ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.wiki_authoring_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'is_committee', public.can_by_member(v_caller, 'curate_content'),
    'tribes', coalesce((
      -- is_engaged separa "participa da tribo" de "escreve porque é do comitê": a tela chama para a
      -- página da PRÓPRIA tribo, e o comitê alcança as 14.
      SELECT jsonb_agg(jsonb_build_object(
               'id', i.id, 'title', i.title, 'legacy_tribe_id', i.legacy_tribe_id, 'status', i.status,
               'is_leader', public._wiki_is_initiative_leader(v_caller, i.id),
               'is_engaged', EXISTS (
                 SELECT 1 FROM public.engagements e JOIN public.members m ON m.person_id = e.person_id
                  WHERE m.id = v_caller AND e.initiative_id = i.id
                    AND e.status = 'active' AND e.role IN ('leader', 'researcher')),
               'path_prefix', public._wiki_initiative_path_prefix(i.id))
             ORDER BY (i.status = 'active') DESC, i.legacy_tribe_id NULLS LAST, i.title)
        FROM public.initiatives i
       WHERE i.kind = 'research_tribe'
         AND public.rls_can_see_initiative(i.id)
         AND public._wiki_can_author(v_caller, i.id)), '[]'::jsonb));
END;
$function$;

-- ─── (5) histórico de uma página ───────────────────────────────────────────────────────────────
-- Mesma regra de leitura de wiki_get_version, linha a linha: publicada ou substituída para membro
-- ativo; rascunho, pendente, devolvida e despublicada só para quem escreveu, a liderança e o comitê.
CREATE OR REPLACE FUNCTION public.wiki_page_history(p_page_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller       uuid;
  v_init         uuid;
  v_is_leader    boolean;
  v_is_committee boolean;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'wiki: requer membro ativo' USING ERRCODE = '42501';
  END IF;

  SELECT initiative_id INTO v_init FROM public.wiki_page_versions WHERE page_path = p_page_path LIMIT 1;
  IF v_init IS NULL OR NOT public.rls_can_see_initiative(v_init) THEN
    RETURN jsonb_build_object('page_path', p_page_path, 'initiative', NULL, 'can_author', false,
                              'versions', '[]'::jsonb);
  END IF;
  v_is_leader    := public._wiki_is_initiative_leader(v_caller, v_init);
  v_is_committee := public.can_by_member(v_caller, 'curate_content');

  RETURN jsonb_build_object(
    'page_path', p_page_path,
    'initiative', (SELECT jsonb_build_object('id', i.id, 'title', i.title) FROM public.initiatives i WHERE i.id = v_init),
    'can_author', public._wiki_can_author(v_caller, v_init),
    'versions', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', v.id, 'version_no', v.version_no, 'status', v.status, 'title', v.title,
               'author', m.name, 'submitted_at', v.submitted_at, 'published_at', v.published_at,
               'audit_due_at', v.audit_due_at, 'audited_at', v.audited_at, 'audit_outcome', v.audit_outcome,
               'updated_at', v.updated_at) ORDER BY v.version_no DESC)
        FROM public.wiki_page_versions v LEFT JOIN public.members m ON m.id = v.author_id
       WHERE v.page_path = p_page_path
         AND (v.status IN ('published', 'superseded')
              OR v.author_id = v_caller OR v_is_leader OR v_is_committee)), '[]'::jsonb));
END;
$function$;

-- ─── permissões ────────────────────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public._wiki_initiative_path_prefix(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._wiki_initiative_path_prefix(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.wiki_authoring_context() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.wiki_page_history(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wiki_authoring_context() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.wiki_page_history(text) TO authenticated, service_role;
