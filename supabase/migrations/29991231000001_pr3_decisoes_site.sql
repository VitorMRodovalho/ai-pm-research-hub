-- PR3: decisões do GP de 25/10/2026 para o site público (A1, A3, A4, C2).
--
-- (A1) get_public_impact_data.chapters_summary, a seção "Capítulos participantes" do /about: lista os capítulos PMI
--      engajados no Brasil (status active ou negotiation, não internacionais, a mesma base de get_chapter_metrics
--      'engaged') sem dizer quais são assinados e quais estão em negociação (decisão do GP de 20/10: nenhum status
--      jurídico no site). A contagem de pessoas passa de members.is_active para v_operational_members, a base do
--      cabeçalho da página (active_members), e só aparece quando é 3 ou mais, o mesmo k do mapa da home
--      (get_public_country_reach e get_public_state_reach_v3 usam o literal 3; não existe constante nomeada a reusar).
--      Abaixo de 3, member_count volta NULL e o card mostra só o capítulo. O membro guarda 'PMI-' || código, e um
--      capítulo tem no CRM nome diferente do código; por isso a contagem casa pelo nome ou por 'PMI-' || chapter.
--      A ordem é a do número exibido (os capítulos sem número ficam por último, em ordem alfabética), para a posição
--      não revelar a contagem que o k esconde. A chave de cada linha continua sendo só chapter e member_count.
-- (A4) get_public_impact_data.timeline ganha uma entrada, depois de 2026.2, sem nome de pessoa: a apresentação do
--      Núcleo no Volunteer Live! do PMI Global Summit 2026. A timeline segue só em português (timeline_is_narrative):
--      levar outras línguas pede mudar a forma da resposta e da página, fora do escopo desta PR.
--      O resto de get_public_impact_data é o corpo de 20261024145605, letra por letra (o guard do DB-4 continua).
-- (A3) exec_portfolio_health, meta "Entidades Parceiras": o filtro procurava ('academia', 'governo', 'empresa') e o
--      CRM grava 'academic'. Passa a aceitar os tipos que o CRM grava para as três classes do acordo (governo,
--      academia, empresas) e a contar só parceria com termo assinado: cooperation_agreement ativo com signed_at em
--      governance_documents, ligado à entidade por partner_entity_id. mou_stage não serve: a coluna é documentada
--      como do ciclo de capítulo e NULL para as outras entidades, e partnership_date é só a data do cadastro. O
--      resto da função é o corpo de 20261004153332, letra por letra.
-- (C2) get_public_home_team.curators conta também o Comitê de Curadoria (_wiki_committee_ids), sem repetir quem já
--      tem engajamento de curador. management não muda. O resto é o corpo de 20261024024922, letra por letra.
--
-- (1) pré-condição: os três corpos vivos são os das capturas acima (md5 do corpo com espaço normalizado, a conta do
--     gate de deriva). Outro corpo no banco para a migration em vez de sobrescrever o que não foi medido.
-- (2) as três funções (CREATE OR REPLACE mantém assinatura, dono e grants; nenhum GRANT ou REVOKE muda).
-- (3) pós-condição, só leitura: SECURITY DEFINER, search_path fixo e EXECUTE de anon nas três; os cards somam a base
--     operacional filtrada pelo k, a lista é a dos engajados e nenhuma linha leva outra chave; a resposta do /about
--     segue sem chave de nome de pessoa; a timeline não repete ano; a meta conta os tipos reais e só com termo
--     assinado; a curadoria inclui o comitê e a gestão segue igual.
--
-- Rollback: reaplicar get_public_impact_data de 20261024145605, exec_portfolio_health de 20261004153332 e
-- get_public_home_team de 20261024024922.

-- ── (1) o banco é o medido ──────────────────────────────────────────────────────────────────────────────────────
DO $precondition$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('public.get_public_impact_data()', '5ef3748000f81b7733fafc6fc1b4f143'),
      ('public.exec_portfolio_health(text)', '571d507917d5b9643033fff5f9af1ed6'),
      ('public.get_public_home_team()', '31f757d68dc994ac2860207596b3a3d0')
    ) AS t(sig, expected)
  LOOP
    IF (SELECT md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) FROM pg_proc p WHERE p.oid = r.sig::regprocedure)
       IS DISTINCT FROM r.expected THEN
      RAISE EXCEPTION 'PR3: % no banco não é a da captura medida', r.sig;
    END IF;
  END LOOP;
END;
$precondition$;

-- ── (2a) /about: capítulos participantes e a linha do Summit ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_public_impact_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
  v_chapters jsonb := public.get_chapter_metrics();
BEGIN
  SELECT jsonb_build_object(
    'chapters', (v_chapters->>'engaged')::int,
    'chapters_engaged', (v_chapters->>'engaged')::int,
    'chapters_signed', (v_chapters->>'signed')::int,
    'active_members', (SELECT COUNT(*) FROM public.v_operational_members),
    'tribes', (SELECT COUNT(*) FROM tribes WHERE is_active),
    'articles_published', (SELECT COUNT(*) FROM public_publications WHERE is_published = true),
    'articles_approved', (
      SELECT COUNT(*) FROM board_lifecycle_events WHERE action = 'curation_review' AND new_status = 'approved'
    ),
    'total_events', (SELECT COUNT(*) FROM events e WHERE e.date >= '2026-03-01' AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')),
    'total_attendance_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE e.date >= '2026-03-01' AND a.present AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')
    ),
    'impact_hours', public.get_impact_hours_canonical('2000-01-01'::date, CURRENT_DATE),
    'impact_hours_since', (
      SELECT EXTRACT(year FROM min(e.date))::int
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE a.present AND a.excused IS NOT TRUE AND e.date <= CURRENT_DATE
        AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')
    ),
    'webinars', public.get_webinars_count(NULL, NULL, 'realized'),
    'ia_pilots', (SELECT COUNT(*) FROM ia_pilots WHERE status IN ('active','completed')),
    'partner_count', (SELECT COUNT(*) FROM partner_entities WHERE status = 'active'),
    'courses_count', (SELECT COUNT(*) FROM courses),
    'recent_publications', COALESCE((
      SELECT jsonb_agg(sub ORDER BY sub.publication_date DESC NULLS LAST)
      FROM (SELECT title, external_platform AS platform, publication_date, external_url
            FROM public_publications WHERE is_published = true
            ORDER BY publication_date DESC NULLS LAST LIMIT 5) sub
    ), '[]'::jsonb),
    'tribes_summary', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'quadrant_name', t.quadrant_name,
        'member_count', (SELECT COUNT(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active)
      ) ORDER BY t.id)
      FROM tribes t
      WHERE t.is_active
    ), '[]'::jsonb),
    -- PR3 A1 (GP 25/10/2026): os capítulos engajados (assinados e em negociação, sem dizer qual é qual), contando
    -- pessoas na base do cabeçalho (v_operational_members). O número só aparece com 3 pessoas ou mais, o mesmo k do
    -- mapa da home (get_public_country_reach: n >= 3); abaixo disso o card mostra só o capítulo. O membro guarda
    -- 'PMI-' || código do capítulo, e há capítulo cujo nome no CRM é outro: casa pelo nome ou pelo código.
    'chapters_summary', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object('chapter', c.chapter, 'member_count', c.member_count)
        ORDER BY c.member_count DESC NULLS LAST, c.chapter
      )
      FROM (
        SELECT pe.name AS chapter,
               CASE WHEN n.people >= 3 THEN n.people END AS member_count
        FROM partner_entities pe
        CROSS JOIN LATERAL (
          SELECT COUNT(*) AS people FROM public.v_operational_members om
          WHERE om.chapter = pe.name OR om.chapter = 'PMI-' || pe.chapter
        ) n
        WHERE pe.entity_type = 'pmi_chapter' AND pe.status IN ('active', 'negotiation')
          AND NOT COALESCE(pe.is_international, false)
      ) c
    ), '[]'::jsonb),
    'timeline_is_narrative', true,
    'timeline', jsonb_build_array(
      jsonb_build_object('year', '2024', 'title', 'Fase Piloto', 'description', 'Concepção pelo PMI-GO. Experimentação e lições aprendidas.'),
      jsonb_build_object('year', '2025.1', 'title', 'Oficialização', 'description', 'Parceria PMI-GO + PMI-CE. 7 artigos submetidos ao ProjectManagement.com. 1º Webinar.'),
      jsonb_build_object('year', '2025.2', 'title', 'Amadurecimento', 'description', 'Manual de Governança R2. 13 pesquisadores selecionados. Expansão para PMI-DF, PMI-MG, PMI-RS.'),
      jsonb_build_object('year', '2026.1', 'title', 'Escala', 'description', 'Início do ciclo 3: 44+ colaboradores, 8 tribos, 5 capítulos PMI. Plataforma digital própria. Processo seletivo estruturado. Abertura de negociação com novos capítulos.'),
      jsonb_build_object('year', '2026.2', 'title', 'Expansão', 'description', 'Ciclo 4: novas tribos de pesquisa e vitrine pública do Núcleo, com podcast, webinars gravados e indicadores atualizados em tempo real.'),
      jsonb_build_object('year', 'Out 2026', 'title', 'PMI Global Summit 2026', 'description', 'Apresentação do Núcleo no Volunteer Live! (Detroit, EUA, 21/10/2026).')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ── (2b) meta Entidades Parceiras: tipos reais e termo assinado ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.exec_portfolio_health(p_cycle_code text DEFAULT 'cycle3-2026'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb := '[]'::jsonb;
  v_cycle_code text;
  v_target record;
  v_current numeric;
  v_progress numeric;
  v_status text;
  v_year_start date;
  v_current_quarter int;
  v_q_target numeric;
  v_q_cumulative numeric;
  v_q_progress numeric;
  v_q_status text;
BEGIN
  v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  v_current_quarter := EXTRACT(quarter FROM now())::int;

  -- GI-3 resilient cycle resolution: never silently return zero metrics. If the requested
  -- code has no targets (NULL/blank, or a namespace-mismatched code like cycles 'cycle_3'),
  -- fall back to the most-recently-created cycle_code that has targets.
  v_cycle_code := NULLIF(trim(p_cycle_code), '');
  IF v_cycle_code IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.portfolio_kpi_targets WHERE cycle_code = v_cycle_code) THEN
    SELECT cycle_code INTO v_cycle_code
    FROM public.portfolio_kpi_targets
    GROUP BY cycle_code
    ORDER BY MAX(created_at) DESC
    LIMIT 1;
  END IF;

  FOR v_target IN
    SELECT * FROM public.portfolio_kpi_targets
    WHERE cycle_code = v_cycle_code
    ORDER BY display_order
  LOOP
    CASE v_target.metric_key

      WHEN 'chapters_participating' THEN
        -- #2553: capítulos = engaged (assinados + em negociação), decisão do GP de 03/10/2026.
        v_current := (public.get_chapter_metrics()->>'engaged')::numeric;

      WHEN 'partner_entities' THEN
        -- PR3 A3 (GP 25/10/2026): governo, academia e empresa pelos tipos que o CRM grava ('academic' e o legado
        -- 'academia'), e só parceria com termo assinado. O termo assinado de uma entidade é o cooperation_agreement
        -- ativo com signed_at em governance_documents, ligado a ela por partner_entity_id (o registro que
        -- link_attachment_to_governance cria e que auto_generate_cr_for_partnership lê como acordo assinado).
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.partner_entities pe
        WHERE pe.entity_type IN ('academia', 'academic', 'governo', 'empresa')
          AND pe.status = 'active'
          AND pe.partnership_date >= v_year_start
          AND EXISTS (
            SELECT 1 FROM public.governance_documents gd
            WHERE gd.partner_entity_id = pe.id
              AND gd.doc_type = 'cooperation_agreement'
              AND gd.status = 'active'
              AND gd.signed_at IS NOT NULL
          );

      WHEN 'certification_trail' THEN
        SELECT calc_trail_completion_pct() INTO v_current;

      WHEN 'cpmai_certified' THEN
        v_current := public.get_cpmai_certified_goal_count(EXTRACT(year FROM v_year_start)::int);

      WHEN 'articles_published' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
          AND bi.curation_status = 'approved'
          AND bi.created_at >= v_year_start::timestamptz AND NOT public.is_confidential_board(bi.board_id);

      WHEN 'webinars_completed' THEN
        v_current := public.get_webinars_count(v_year_start, current_date, 'realized');

      WHEN 'ia_pilots' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.ia_pilots
        WHERE start_date >= v_year_start
          AND status IN ('active', 'completed');

      WHEN 'meeting_hours' THEN
        SELECT COALESCE(ROUND(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0)), 0)
        INTO v_current
        FROM public.events e
        WHERE e.date >= v_year_start AND e.date <= current_date AND NOT public.is_confidential_initiative(e.initiative_id);

      WHEN 'impact_hours' THEN
        v_current := public.get_impact_hours_canonical(v_year_start, current_date);

      ELSE
        v_current := 0;
    END CASE;

    v_progress := CASE
      WHEN v_target.target_value > 0 THEN ROUND((v_current / v_target.target_value) * 100)
      ELSE 0
    END;

    v_status := CASE
      WHEN v_current >= v_target.target_value THEN 'green'
      WHEN v_current >= v_target.warning_threshold THEN 'yellow'
      ELSE 'red'
    END;

    SELECT qt.quarter_target, qt.quarter_cumulative_target
    INTO v_q_target, v_q_cumulative
    FROM public.portfolio_kpi_quarterly_targets qt
    WHERE qt.kpi_target_id = v_target.id
      AND qt.quarter = v_current_quarter;

    v_q_progress := CASE
      WHEN COALESCE(v_q_cumulative, 0) > 0 THEN ROUND((v_current / v_q_cumulative) * 100)
      ELSE 0
    END;

    v_q_status := CASE
      WHEN v_current >= COALESCE(v_q_cumulative, 0) THEN 'green'
      WHEN COALESCE(v_q_cumulative, 0) > 0 AND v_current >= v_q_cumulative * 0.5 THEN 'yellow'
      ELSE 'red'
    END;

    v_result := v_result || jsonb_build_object(
      'metric_key', v_target.metric_key,
      'label', v_target.metric_label,
      'target', ROUND(v_target.target_value),
      'current', ROUND(v_current),
      'progress_pct', v_progress,
      'status', v_status,
      'unit', v_target.unit,
      'display_order', v_target.display_order,
      'quarter', v_current_quarter,
      'quarter_target', ROUND(COALESCE(v_q_target, 0)),
      'quarter_cumulative', ROUND(COALESCE(v_q_cumulative, 0)),
      'quarter_progress_pct', v_q_progress,
      'quarter_status', v_q_status
    );
  END LOOP;

  RETURN v_result;
END;
$function$;

-- ── (2c) quem faz: a curadoria conta o Comitê de Curadoria ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_public_home_team()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH active_members AS (
    SELECT m.id, m.operational_role, coalesce(m.designations, '{}'::text[]) AS designations
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
  ),
  live_engagements AS (
    SELECT e.person_id, e.role, i.legacy_tribe_id, i.kind, i.metadata
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.status = 'active'
      AND e.start_date <= CURRENT_DATE
      AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
      AND i.status = 'active'
      AND coalesce(i.visibility, 'standard') <> 'confidential'
      AND public.rls_can_see_initiative(i.id)
  )
  SELECT jsonb_build_object(
    'management', (
      SELECT count(*) FROM active_members a
      WHERE a.operational_role IN ('manager', 'deputy_manager') OR 'co_gp' = ANY (a.designations)
    ),
    'line_leaders', (
      SELECT count(DISTINCT le.person_id) FROM live_engagements le
      WHERE le.legacy_tribe_id IS NOT NULL AND le.role IN ('leader', 'co_leader')
    ),
    'initiative_leaders', (
      SELECT count(DISTINCT le.person_id) FROM live_engagements le
      WHERE le.legacy_tribe_id IS NULL AND le.kind <> 'community_vertical'
        AND le.role IN ('leader', 'co_leader', 'coordinator', 'owner')
    ),
    -- PR3 C2 (GP 25/10/2026): a curadoria conta também o Comitê de Curadoria (_wiki_committee_ids: ativos, com
    -- login e com curate_content), sem repetir quem já tem engajamento de curador. Membro sem pessoa conta pelo id.
    'curators', (
      SELECT count(DISTINCT c.who) FROM (
        SELECT le.person_id AS who FROM live_engagements le WHERE le.role = 'curator'
        UNION ALL
        SELECT coalesce(m.person_id, m.id) FROM public.members m WHERE m.id IN (SELECT public._wiki_committee_ids())
      ) c
    ),
    'hub_members', (
      SELECT count(DISTINCT le.person_id) FROM live_engagements le
      WHERE le.kind = 'workgroup' AND coalesce((le.metadata->>'landing_arm')::boolean, false) = true
    ),
    'chapter_focal_points', (
      SELECT count(*) FROM active_members a
      WHERE a.operational_role IN ('sponsor', 'chapter_liaison')
         OR a.designations && ARRAY['sponsor', 'chapter_liaison']::text[]
    ),
    'researchers', (SELECT count(*) FROM public.v_operational_members)
  );
$function$;
COMMENT ON FUNCTION public.get_public_home_team() IS
  '#2553 D3 (GP 21/10/2026): a equipe por função, em contagem de pessoas distintas, para a home pública. researchers = v_operational_members, a mesma população do hero (get_homepage_stats.members). PR3 C2 (GP 25/10/2026): curators = engajamento de curador vigente mais o Comitê de Curadoria (_wiki_committee_ids), sem repetir pessoa.';

-- ── (3) pós-condição (só leitura) ───────────────────────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v jsonb := public.get_public_impact_data();
  v_health jsonb := public.exec_portfolio_health();
  v_team jsonb := public.get_public_home_team();
  v_engaged int := (public.get_chapter_metrics()->>'engaged')::int;
  v_year_start date := make_date(EXTRACT(year FROM now())::int, 1, 1);
  v_cards_sum bigint;
  v_expected_sum bigint;
  v_goal numeric;
  v_goal_expected bigint;
  v_reach_new bigint;
  v_reach_old bigint;
  v_committee int;
  v_curator_eng int;
BEGIN
  -- as três seguem SECURITY DEFINER, com search_path fixo e EXECUTE de anon
  IF EXISTS (
    SELECT 1
    FROM (VALUES ('public.get_public_impact_data()'), ('public.exec_portfolio_health(text)'),
                 ('public.get_public_home_team()')) AS t(sig)
    WHERE NOT EXISTS (SELECT 1 FROM pg_proc p
                      WHERE p.oid = t.sig::regprocedure AND p.prosecdef
                        AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
       OR NOT has_function_privilege('anon', t.sig, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'PR3: pós-condição violada (SECURITY DEFINER, search_path ou EXECUTE de anon)';
  END IF;

  -- DB-4 continua: nenhuma chave com nome de pessoa
  IF v ? 'recognitions' OR v ? 'partners'
     OR jsonb_path_exists(v, '$.tribes_summary[*].leader_name')
     OR jsonb_path_exists(v, '$.chapters_summary[*].sponsor')
     OR jsonb_path_exists(v, '$.recent_publications[*].authors')
  THEN
    RAISE EXCEPTION 'PR3: a resposta do /about leva uma chave com nome de pessoa';
  END IF;

  -- A1: a lista é a dos engajados, só com chapter e member_count, e nenhum número abaixo do k
  IF jsonb_array_length(v->'chapters_summary') <> v_engaged THEN
    RAISE EXCEPTION 'PR3 A1: chapters_summary tem % linhas e engaged é %', jsonb_array_length(v->'chapters_summary'), v_engaged;
  END IF;
  IF EXISTS (
    (SELECT e->>'chapter' FROM jsonb_array_elements(v->'chapters_summary') e
     EXCEPT
     SELECT pe.name FROM public.partner_entities pe
     WHERE pe.entity_type = 'pmi_chapter' AND pe.status IN ('active', 'negotiation') AND NOT COALESCE(pe.is_international, false))
    UNION ALL
    (SELECT pe.name FROM public.partner_entities pe
     WHERE pe.entity_type = 'pmi_chapter' AND pe.status IN ('active', 'negotiation') AND NOT COALESCE(pe.is_international, false)
     EXCEPT
     SELECT e->>'chapter' FROM jsonb_array_elements(v->'chapters_summary') e)
  ) THEN
    RAISE EXCEPTION 'PR3 A1: os capítulos da lista não são os engajados';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v->'chapters_summary') e, jsonb_object_keys(e) k
             WHERE k NOT IN ('chapter', 'member_count')) THEN
    RAISE EXCEPTION 'PR3 A1: uma linha de chapters_summary leva chave além de chapter e member_count';
  END IF;
  IF jsonb_path_exists(v, '$.chapters_summary[*].member_count ? (@ < 3)') THEN
    RAISE EXCEPTION 'PR3 A1: um card mostra contagem abaixo de 3';
  END IF;

  -- A1: a soma dos cards é a base operacional por capítulo engajado com 3 ou mais pessoas (outra forma da conta)
  SELECT COALESCE(sum((e->>'member_count')::bigint), 0) INTO v_cards_sum
  FROM jsonb_array_elements(v->'chapters_summary') e;
  SELECT COALESCE(sum(g.people), 0) INTO v_expected_sum
  FROM (
    SELECT pe.id, count(om.id) AS people
    FROM public.partner_entities pe
    JOIN public.v_operational_members om ON om.chapter IN (pe.name, 'PMI-' || pe.chapter)
    WHERE pe.entity_type = 'pmi_chapter' AND pe.status IN ('active', 'negotiation') AND NOT COALESCE(pe.is_international, false)
    GROUP BY pe.id
    HAVING count(om.id) >= 3
  ) g;
  IF v_cards_sum = 0 OR v_cards_sum <> v_expected_sum OR v_cards_sum > (v->>'active_members')::bigint THEN
    RAISE EXCEPTION 'PR3 A1: os cards somam %, a base filtrada pelo k dá % e o cabeçalho diz %',
      v_cards_sum, v_expected_sum, v->>'active_members';
  END IF;

  -- A4: a linha do Summit entrou e nenhum ano se repete (a página usa o ano como chave)
  IF NOT jsonb_path_exists(v, '$.timeline[*] ? (@.title == "PMI Global Summit 2026")')
     OR (SELECT count(*) FROM jsonb_array_elements(v->'timeline'))
        <> (SELECT count(DISTINCT e->>'year') FROM jsonb_array_elements(v->'timeline') e)
  THEN
    RAISE EXCEPTION 'PR3 A4: a timeline não tem a linha do Summit ou repete um ano';
  END IF;

  -- A3: a meta conta o mesmo que a regra escrita de outra forma (JOIN no termo assinado)
  SELECT (x->>'current')::numeric INTO v_goal
  FROM jsonb_array_elements(v_health) x WHERE x->>'metric_key' = 'partner_entities';
  SELECT count(DISTINCT pe.id) INTO v_goal_expected
  FROM public.partner_entities pe
  JOIN public.governance_documents gd
    ON gd.partner_entity_id = pe.id AND gd.doc_type = 'cooperation_agreement' AND gd.status = 'active'
   AND gd.signed_at IS NOT NULL
  WHERE pe.entity_type IN ('academia', 'academic', 'governo', 'empresa') AND pe.status = 'active'
    AND pe.partnership_date >= v_year_start;
  IF v_goal IS DISTINCT FROM v_goal_expected::numeric THEN
    RAISE EXCEPTION 'PR3 A3: a meta Entidades Parceiras diz % e a regra dá %', v_goal, v_goal_expected;
  END IF;
  -- A3, controle: a lista nova de tipos alcança um cadastro ativo que a lista antiga não via, e a meta não passa dele
  SELECT count(*) INTO v_reach_new FROM public.partner_entities
  WHERE entity_type IN ('academia', 'academic', 'governo', 'empresa') AND status = 'active' AND partnership_date >= v_year_start;
  SELECT count(*) INTO v_reach_old FROM public.partner_entities
  WHERE entity_type IN ('academia', 'governo', 'empresa') AND status = 'active' AND partnership_date >= v_year_start;
  IF v_reach_new <= v_reach_old OR v_goal > v_reach_new THEN
    RAISE EXCEPTION 'PR3 A3: controle dos tipos não discrimina (nova %, antiga %, meta %)', v_reach_new, v_reach_old, v_goal;
  END IF;

  -- C2: a curadoria inclui o comitê e quem tem engajamento de curador, sem passar da soma; a gestão segue igual
  SELECT count(*) INTO v_committee FROM public._wiki_committee_ids();
  SELECT count(DISTINCT e.person_id) INTO v_curator_eng
  FROM public.engagements e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.status = 'active' AND e.start_date <= CURRENT_DATE AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
    AND i.status = 'active' AND coalesce(i.visibility, 'standard') <> 'confidential' AND e.role = 'curator';
  IF v_committee = 0
     OR (v_team->>'curators')::int < GREATEST(v_committee, v_curator_eng)
     OR (v_team->>'curators')::int > v_committee + v_curator_eng
  THEN
    RAISE EXCEPTION 'PR3 C2: curadoria % fora de [%, %]', v_team->>'curators', GREATEST(v_committee, v_curator_eng), v_committee + v_curator_eng;
  END IF;
  IF (v_team->>'management')::int <> (
    SELECT count(*) FROM public.members m
    WHERE m.is_active AND m.current_cycle_active
      AND (m.operational_role IN ('manager', 'deputy_manager') OR 'co_gp' = ANY (coalesce(m.designations, '{}'::text[])))
  ) THEN
    RAISE EXCEPTION 'PR3 C2: a gestão mudou';
  END IF;
END;
$postcondition$;

NOTIFY pgrst, 'reload schema';
