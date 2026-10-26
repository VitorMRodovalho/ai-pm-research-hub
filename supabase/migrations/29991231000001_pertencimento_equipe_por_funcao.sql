-- Pertencimento, parte 1 (GP 26/10/2026): a página "Equipe" da área do membro.
--
-- PLACEHOLDER: a orquestradora aplica, adota a versão que o apply_migration registrar e renomeia o arquivo.
--
-- get_team_by_function() devolve, só a quem tem vínculo vigente (rls_is_authoritative_member, o mesmo portão que o
-- ranking completo usa), as pessoas de cada função que a home conta em "Quem faz":
--   counts       = public.get_public_home_team(), a MESMA chamada que a home faz. A página não recalcula número;
--   rows         = uma linha por pessoa e papel, com nome, foto, capítulo e a linha ou iniciativa do papel;
--   lines        = o nome de cada linha ativa, para o rótulo;
--   initiatives  = as iniciativas citadas nas linhas e as frentes operacionais (workgroup com landing_arm), com nome,
--                  descrição e se há vagas: o que a OperationalArmsSection mostrava na home antiga.
-- As linhas usam os mesmos predicados de get_public_home_team, grupo a grupo (o guard compara o texto), e a
-- pós-condição confere que cada grupo tem tantas pessoas distintas quanto a contagem da home diz.
-- Nada é guardado: quem sai do papel (engajamento encerrado, ciclo ou cadastro inativo) sai na próxima leitura.
-- Nenhuma chave de contato (e-mail, telefone, LinkedIn, PMI ID) e nenhum id de membro sai na resposta.
--
-- (1) pré-condição: o corpo vivo de get_public_home_team é o da captura medida (PR3, 20261025160648). Se mudou, os
--     predicados copiados aqui podem não ser mais os da home, e a migration para.
-- (2) a função, sem EXECUTE para PUBLIC e anon.
-- (3) pós-condição, só leitura: catálogo; anon recusado pelo Postgres; conta autenticada sem membro e membro sem
--     papel recusados pelo portão; um pesquisador ativo (achado aqui, não escrito) lê as linhas; as contagens são as
--     da home e cada grupo bate com elas; cada linha só leva as chaves nomeadas.
--
-- Rollback: DROP FUNCTION public.get_team_by_function();

-- ── (1) a home é a medida ───────────────────────────────────────────────────────────────────────────────────────
DO $precondition$
BEGIN
  IF (SELECT md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) FROM pg_proc p
      WHERE p.oid = 'public.get_public_home_team()'::regprocedure)
     IS DISTINCT FROM '3d628ba07fef3c63481a04470197731a' THEN
    RAISE EXCEPTION 'pertencimento: get_public_home_team no banco não é a captura medida (20261025160648)';
  END IF;
END;
$precondition$;

-- ── (2) a leitura da página Equipe ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_team_by_function()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_rows jsonb;
  v_lines jsonb;
  v_initiatives jsonb;
BEGIN
  -- só membro com vínculo vigente; anon nem chega aqui (sem EXECUTE)
  IF NOT public.rls_is_authoritative_member() THEN
    RAISE EXCEPTION 'get_team_by_function: só para membro com vínculo vigente' USING ERRCODE = 'insufficient_privilege';
  END IF;

  WITH active_members AS (
    SELECT m.id, m.operational_role, coalesce(m.designations, '{}'::text[]) AS designations
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
  ),
  live_engagements AS (
    SELECT e.person_id, e.role, i.id AS initiative_id, i.legacy_tribe_id, i.kind, i.metadata
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.status = 'active'
      AND e.start_date <= CURRENT_DATE
      AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
      AND i.status = 'active'
      AND coalesce(i.visibility, 'standard') <> 'confidential'
      AND public.rls_can_see_initiative(i.id)
  ),
  roster AS (
    -- who é a mesma chave que a home conta em cada grupo: o membro nos grupos lidos de members, a pessoa nos grupos
    -- lidos de engagements, e coalesce(pessoa, membro) no comitê de curadoria
    SELECT 'management'::text AS team_group, a.id AS who, a.id AS member_id, NULL::uuid AS person_id,
           CASE WHEN a.operational_role IN ('manager', 'deputy_manager') THEN a.operational_role ELSE 'co_gp' END AS role,
           NULL::integer AS tribe_id, NULL::uuid AS initiative_id
    FROM active_members a
    WHERE a.operational_role IN ('manager', 'deputy_manager') OR 'co_gp' = ANY (a.designations)
    UNION ALL
    SELECT 'line_leaders', le.person_id, NULL, le.person_id, le.role, le.legacy_tribe_id, le.initiative_id
    FROM live_engagements le
    WHERE le.legacy_tribe_id IS NOT NULL AND le.role IN ('leader', 'co_leader')
    UNION ALL
    SELECT 'initiative_leaders', le.person_id, NULL, le.person_id, le.role, NULL, le.initiative_id
    FROM live_engagements le
    WHERE le.legacy_tribe_id IS NULL AND le.kind <> 'community_vertical'
        AND le.role IN ('leader', 'co_leader', 'coordinator', 'owner')
    UNION ALL
    SELECT 'curators', le.person_id, NULL, le.person_id, 'curator', NULL, le.initiative_id
    FROM live_engagements le WHERE le.role = 'curator'
    UNION ALL
    SELECT 'curators', coalesce(m.person_id, m.id), m.id, m.person_id, 'committee', NULL, NULL
    FROM public.members m WHERE m.id IN (SELECT public._wiki_committee_ids())
    UNION ALL
    SELECT 'hub_members', le.person_id, NULL, le.person_id, le.role, NULL, le.initiative_id
    FROM live_engagements le
    WHERE le.kind = 'workgroup' AND coalesce((le.metadata->>'landing_arm')::boolean, false) = true
    UNION ALL
    SELECT 'chapter_focal_points', a.id, a.id, NULL,
           CASE WHEN a.operational_role = 'sponsor' OR 'sponsor' = ANY (a.designations) THEN 'sponsor' ELSE 'chapter_liaison' END,
           NULL, NULL
    FROM active_members a
    WHERE a.operational_role IN ('sponsor', 'chapter_liaison')
         OR a.designations && ARRAY['sponsor', 'chapter_liaison']::text[]
    UNION ALL
    SELECT 'researchers', om.id, om.id, NULL, om.operational_role, om.tribe_id, NULL
    FROM public.v_operational_members om
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'group', r.team_group,
           'role', r.role,
           'key', md5(r.who::text),
           'name', coalesce(d.name, p.name),
           'photo_url', coalesce(d.photo_url, p.photo_url),
           'chapter', d.chapter,
           'tribe_id', r.tribe_id,
           'initiative_id', r.initiative_id
         ) ORDER BY r.team_group, coalesce(d.name, p.name), r.tribe_id, r.initiative_id), '[]'::jsonb)
  INTO v_rows
  FROM roster r
  LEFT JOIN LATERAL (
    SELECT mm.name, mm.photo_url, mm.chapter
    FROM public.members mm
    WHERE mm.id = r.member_id OR (r.member_id IS NULL AND mm.person_id = r.person_id)
    ORDER BY mm.is_active DESC, mm.id
    LIMIT 1
  ) d ON true
  LEFT JOIN public.persons p ON p.id = r.person_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id,
           'name_i18n', coalesce(t.name_i18n, jsonb_build_object('pt', t.name))
         ) ORDER BY t.id), '[]'::jsonb)
  INTO v_lines
  FROM public.tribes t
  WHERE t.is_active = true;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id,
           'kind', i.kind,
           'name_i18n', coalesce(i.metadata->'name_i18n', jsonb_build_object('pt', i.title)),
           'front', (i.kind = 'workgroup' AND coalesce((i.metadata->>'landing_arm')::boolean, false)),
           'description', CASE WHEN i.kind = 'workgroup' AND coalesce((i.metadata->>'landing_arm')::boolean, false)
                               THEN i.description END,
           'has_openings', CASE WHEN i.kind = 'workgroup' AND coalesce((i.metadata->>'landing_arm')::boolean, false)
                                THEN coalesce((i.metadata->>'has_openings')::boolean, true) END
         ) ORDER BY i.title), '[]'::jsonb)
  INTO v_initiatives
  FROM public.initiatives i
  WHERE i.status = 'active'
    AND coalesce(i.visibility, 'standard') <> 'confidential'
    AND public.rls_can_see_initiative(i.id)
    AND (
      i.id IN (SELECT (e->>'initiative_id')::uuid FROM jsonb_array_elements(v_rows) e WHERE e->>'initiative_id' IS NOT NULL)
      OR (i.kind = 'workgroup' AND coalesce((i.metadata->>'landing_arm')::boolean, false) = true)
    );

  RETURN jsonb_build_object(
    'counts', public.get_public_home_team(),
    'rows', v_rows,
    'lines', v_lines,
    'initiatives', v_initiatives
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_team_by_function() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_team_by_function() TO authenticated, service_role;

COMMENT ON FUNCTION public.get_team_by_function() IS
  'Pertencimento (GP 26/10/2026): a página Equipe da área do membro. Só membro com vínculo vigente (rls_is_authoritative_member). counts = get_public_home_team(), a fonte da home; rows = as pessoas de cada função pelos mesmos predicados, lidas ao vivo; sem chave de contato e sem id de membro.';

-- ── (3) pós-condição (só leitura) ───────────────────────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_role text := current_user;
  v_home jsonb := public.get_public_home_team();
  v_auth uuid;
  v_guest uuid;
  v_out jsonb;
  v_denied int := 0;
  v_expected_denied int := 2;
  v_bad text;
BEGIN
  -- catálogo: SECURITY DEFINER, search_path fixo, sem EXECUTE de anon, com EXECUTE de authenticated
  IF NOT EXISTS (SELECT 1 FROM pg_proc p
                 WHERE p.oid = 'public.get_team_by_function()'::regprocedure AND p.prosecdef
                   AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
     OR has_function_privilege('anon', 'public.get_team_by_function()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_team_by_function()', 'EXECUTE')
  THEN
    RAISE EXCEPTION 'pertencimento: catálogo de get_team_by_function fora do esperado';
  END IF;

  -- anon: o Postgres recusa a chamada
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  EXECUTE 'SET LOCAL ROLE anon';
  BEGIN
    PERFORM public.get_team_by_function();
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := v_denied + 1;
  END;
  EXECUTE format('SET LOCAL ROLE %I', v_role);

  -- conta autenticada sem membro (uuid sintético): o portão recusa
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-4000-8000-000000000000', 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.get_team_by_function();
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := v_denied + 1;
  END;
  EXECUTE format('SET LOCAL ROLE %I', v_role);

  -- membro cadastrado ainda sem papel (guest), quando existe um com login: o portão recusa
  SELECT m.auth_id INTO v_guest FROM public.members m
  WHERE m.is_active AND m.operational_role = 'guest' AND m.auth_id IS NOT NULL
  ORDER BY m.created_at, m.id LIMIT 1;
  IF v_guest IS NOT NULL THEN
    v_expected_denied := 3;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_guest, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      PERFORM public.get_team_by_function();
    EXCEPTION WHEN insufficient_privilege THEN
      v_denied := v_denied + 1;
    END;
    EXECUTE format('SET LOCAL ROLE %I', v_role);
  END IF;

  IF v_denied <> v_expected_denied THEN
    RAISE EXCEPTION 'pertencimento: % de % chamadas sem vínculo foram recusadas', v_denied, v_expected_denied;
  END IF;

  -- um pesquisador ativo, com login (achado aqui, sem id fixo), lê como authenticated
  SELECT m.auth_id INTO v_auth FROM public.members m
  JOIN public.v_operational_members om ON om.id = m.id
  WHERE m.auth_id IS NOT NULL AND m.operational_role = 'researcher'
  ORDER BY m.created_at, m.id LIMIT 1;
  IF v_auth IS NULL THEN
    RAISE EXCEPTION 'pertencimento: nenhum pesquisador ativo com login para exercer a leitura';
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_auth, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_out := public.get_team_by_function();
  EXECUTE format('SET LOCAL ROLE %I', v_role);
  PERFORM set_config('request.jwt.claims', '', true);

  -- as contagens são as da home, e cada grupo tem tantas pessoas distintas quanto ela diz
  IF v_out->'counts' IS DISTINCT FROM v_home THEN
    RAISE EXCEPTION 'pertencimento: counts % difere da home %', v_out->'counts', v_home;
  END IF;
  SELECT string_agg(k || '=' || (SELECT count(DISTINCT e->>'key') FROM jsonb_array_elements(v_out->'rows') e
                                 WHERE e->>'group' = k) || '/' || (v_home->>k), ', ')
  INTO v_bad
  FROM jsonb_object_keys(v_home) k
  WHERE (SELECT count(DISTINCT e->>'key') FROM jsonb_array_elements(v_out->'rows') e WHERE e->>'group' = k)
        <> (v_home->>k)::int;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'pertencimento: grupos fora da contagem da home (pessoas/home): %', v_bad;
  END IF;

  -- cada linha só leva as chaves nomeadas, e nenhuma linha fica sem nome
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_out->'rows') e, jsonb_object_keys(e) k
             WHERE k NOT IN ('group', 'role', 'key', 'name', 'photo_url', 'chapter', 'tribe_id', 'initiative_id'))
  THEN
    RAISE EXCEPTION 'pertencimento: uma linha leva chave fora da lista';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_out->'rows') e WHERE coalesce(e->>'name', '') = '') THEN
    RAISE EXCEPTION 'pertencimento: uma linha da equipe saiu sem nome';
  END IF;
END;
$postcondition$;

NOTIFY pgrst, 'reload schema';
