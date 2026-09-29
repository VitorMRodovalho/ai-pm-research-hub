-- #2495: o wiki para todas as iniciativas (ADR-0129, emenda 3, decisão do GP em 28/09/2026).
--
-- Medido em 28/09: o banco tem 14 tribos (12 ativas; a 2 e a 3 arquivadas), 10 grupos de trabalho,
-- 5 verticais e 1 grupo de estudos; o início do wiki listava só as 7 tribos que já tinham página. E só
-- tribo escrevia: wiki_save_draft exigia research_tribe e os papéis leader/researcher.
--
--   (1) _wiki_leadership_roles e _wiki_writer_roles: os papéis num lugar só. Publica quem lidera ou
--       coordena (leader, coordinator); escreve também quem participa, pesquisa ou revisa
--       (participant, researcher, reviewer). observer só lê. Nas tribos nada muda: medido, não há
--       coordinator, participant nem reviewer em tribo.
--   (2) _wiki_domain_for_kind: tribo vai para o domínio tribes; grupo de trabalho, vertical e grupo de
--       estudos, para initiatives; congresso e comitê não têm página (NULL).
--   (3) os três auxiliares de papel, o caminho (nucleo/iniciativas/<id> fora das tribos), o rascunho e o
--       contexto de autoria passam a valer para os quatro tipos.
--   (4) wiki_initiatives_overview: a lista do início sai do cadastro de iniciativas, e não das páginas.
--   (5) o domínio initiatives entra no CHECK de wiki_pages e de wiki_page_versions.
--   Corpos de 20260927212811 e 20260928002208 (md5 do prosrc igual ao vivo), com as trocas acima.
--
-- ROLLBACK: reaplicar _wiki_is_initiative_leader, _wiki_initiative_leader_ids e _wiki_can_author de
--   20260927212811; _wiki_initiative_path_prefix, wiki_save_draft e wiki_authoring_context de
--   20260928002208; DROP FUNCTION wiki_initiatives_overview(), _wiki_domain_for_kind(text),
--   _wiki_writer_roles(), _wiki_leadership_roles(); os CHECKs de domínio sem 'initiatives' (só se
--   nenhuma linha usar o valor).

-- ─── (1) papéis ────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._wiki_leadership_roles()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ARRAY['leader', 'coordinator']::text[];
$function$;

CREATE OR REPLACE FUNCTION public._wiki_writer_roles()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ARRAY['leader', 'coordinator', 'researcher', 'participant', 'reviewer']::text[];
$function$;

-- ─── (2) domínio por tipo de iniciativa ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._wiki_domain_for_kind(p_kind text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE p_kind
    WHEN 'research_tribe'     THEN 'tribes'
    WHEN 'workgroup'          THEN 'initiatives'
    WHEN 'community_vertical' THEN 'initiatives'
    WHEN 'study_group'        THEN 'initiatives'
  END;
$function$;

-- ─── (5) o domínio novo nas duas tabelas (antes das funções que o gravam) ─────────────────────
ALTER TABLE public.wiki_pages DROP CONSTRAINT IF EXISTS wiki_pages_domain_check;
ALTER TABLE public.wiki_pages ADD CONSTRAINT wiki_pages_domain_check
  CHECK (domain = ANY (ARRAY['research', 'governance', 'tribes', 'initiatives', 'partnerships', 'platform', 'onboarding']));
ALTER TABLE public.wiki_page_versions DROP CONSTRAINT IF EXISTS wiki_page_versions_domain_check;
ALTER TABLE public.wiki_page_versions ADD CONSTRAINT wiki_page_versions_domain_check
  CHECK (domain = ANY (ARRAY['research', 'governance', 'tribes', 'initiatives', 'partnerships', 'platform', 'onboarding']));

-- ─── (3) auxiliares, caminho, rascunho e contexto de autoria ───────────────────────────────────
CREATE OR REPLACE FUNCTION public._wiki_is_initiative_leader(p_member uuid, p_initiative uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.engagements e JOIN public.members m ON m.person_id = e.person_id
     WHERE m.id = p_member AND e.initiative_id = p_initiative
       AND e.status = 'active' AND e.role = ANY (public._wiki_leadership_roles()));
$function$;

CREATE OR REPLACE FUNCTION public._wiki_initiative_leader_ids(p_initiative uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT DISTINCT m.id
    FROM public.engagements e JOIN public.members m ON m.person_id = e.person_id
   WHERE e.initiative_id = p_initiative AND e.status = 'active' AND e.role = ANY (public._wiki_leadership_roles())
     AND m.is_active AND m.member_status = 'active';
$function$;

CREATE OR REPLACE FUNCTION public._wiki_can_author(p_member uuid, p_initiative uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.engagements e JOIN public.members m ON m.person_id = e.person_id
     WHERE m.id = p_member AND e.initiative_id = p_initiative
       AND e.status = 'active' AND e.role = ANY (public._wiki_writer_roles()))
    OR public.can_by_member(p_member, 'curate_content');
$function$;

CREATE OR REPLACE FUNCTION public._wiki_initiative_path_prefix(p_initiative uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE WHEN i.kind = 'research_tribe' AND i.legacy_tribe_id IS NOT NULL
              THEN 'nucleo/tribes/tribo-' || i.legacy_tribe_id
              WHEN i.kind = 'research_tribe' THEN 'nucleo/tribes/' || i.id::text
              ELSE 'nucleo/iniciativas/' || i.id::text END
    FROM public.initiatives i
   WHERE i.id = p_initiative;
$function$;

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
    'initiatives', coalesce((
      -- is_engaged separa "participa da iniciativa" de "escreve porque é do comitê": a tela chama para a
      -- página da PRÓPRIA iniciativa, e o comitê alcança todas.
      SELECT jsonb_agg(jsonb_build_object(
               'id', i.id, 'title', i.title, 'legacy_tribe_id', i.legacy_tribe_id, 'status', i.status,
               'kind', i.kind, 'domain', public._wiki_domain_for_kind(i.kind),
               'is_leader', public._wiki_is_initiative_leader(v_caller, i.id),
               'is_engaged', EXISTS (
                 SELECT 1 FROM public.engagements e JOIN public.members m ON m.person_id = e.person_id
                  WHERE m.id = v_caller AND e.initiative_id = i.id
                    AND e.status = 'active' AND e.role = ANY (public._wiki_writer_roles())),
               'path_prefix', public._wiki_initiative_path_prefix(i.id))
             ORDER BY (i.kind = 'research_tribe') DESC, (i.status = 'active') DESC, i.legacy_tribe_id NULLS LAST, i.title)
        FROM public.initiatives i
       WHERE public._wiki_domain_for_kind(i.kind) IS NOT NULL
         AND public.rls_can_see_initiative(i.id)
         AND public._wiki_can_author(v_caller, i.id)), '[]'::jsonb));
END;
$function$;

-- ─── (4) a lista do início, a partir do cadastro de iniciativas ────────────────────────────────
-- Tribo aparece mesmo arquivada (a tela marca como congelada); os outros tipos, só ativos. O portão de
-- iniciativa confidencial vale linha a linha.
CREATE OR REPLACE FUNCTION public.wiki_initiatives_overview()
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

  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'id', x.id, 'kind', x.kind, 'domain', x.domain, 'title', x.title, 'status', x.status,
             'legacy_tribe_id', x.legacy_tribe_id, 'path_prefix', x.prefix, 'has_team', x.has_team,
             'platform_page', (SELECT w.path FROM public.wiki_pages w WHERE w.path = x.prefix),
             'repo_page', CASE WHEN x.legacy_tribe_id IS NOT NULL THEN
               (SELECT w.path FROM public.wiki_pages w
                 WHERE w.source_repo <> 'plataforma' AND w.path ~ ('^tribes/tribo-' || x.legacy_tribe_id || '-')
                 ORDER BY w.path LIMIT 1) END,
             'can_author', public._wiki_can_author(v_caller, x.id))
           ORDER BY (x.kind = 'research_tribe') DESC, x.legacy_tribe_id NULLS LAST, x.kind, x.title)
      FROM (
        SELECT i.id, i.kind, i.title, i.status, i.legacy_tribe_id,
               public._wiki_domain_for_kind(i.kind) AS domain,
               public._wiki_initiative_path_prefix(i.id) AS prefix,
               EXISTS (SELECT 1 FROM public.engagements e
                        WHERE e.initiative_id = i.id AND e.status = 'active'
                          AND e.role = ANY (public._wiki_writer_roles())) AS has_team
          FROM public.initiatives i
         WHERE public._wiki_domain_for_kind(i.kind) IS NOT NULL
           AND (i.status = 'active' OR i.kind = 'research_tribe')
           AND public.rls_can_see_initiative(i.id)) x), '[]'::jsonb);
END;
$function$;

-- ─── permissões ────────────────────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public._wiki_leadership_roles() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._wiki_writer_roles() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._wiki_domain_for_kind(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._wiki_leadership_roles() TO service_role;
GRANT EXECUTE ON FUNCTION public._wiki_writer_roles() TO service_role;
GRANT EXECUTE ON FUNCTION public._wiki_domain_for_kind(text) TO service_role;

REVOKE ALL ON FUNCTION public.wiki_initiatives_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wiki_initiatives_overview() TO authenticated, service_role;
