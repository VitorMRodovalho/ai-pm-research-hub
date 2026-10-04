-- #2553 PR 1: a home conta capítulos e pesquisadores por UMA fonte.
--
-- Medido em 03/10/2026, antes desta migration:
--   capítulos: get_homepage_stats.chapters = 5, get_public_platform_stats.total_chapters = 5 e
--     exec_portfolio_health.chapters_participating = 5 de 8, os três em get_chapter_metrics().signed.
--     Na mesma página, a seção de capítulos mostrava 15 (chapter_registry) e o hero 15 (texto fixo).
--   pesquisadores: o hero mostra 76 (v_operational_members, ADR-0126). O mapa contava outra
--     população, 98 pessoas (is_active AND current_cycle_active AND NOT pre-onboarding), e a linha
--     do mapa dizia 97.
--
-- Decisões do GP em 03/10/2026:
--   1. Capítulos = 15 em toda peça externa e também nas Metas internas. Os três leitores passam de
--      'signed' para 'engaged' (assinados + em negociação, a métrica canônica da ADR-0100). O painel
--      admin (get_admin_dashboard) segue mostrando o detalhe; get_executive_kpis e
--      get_public_impact_data não mudam aqui.
--   2. O mapa conta só a equipe de pesquisa. As 4 RPCs do mapa passam a ler v_operational_members, o
--      KPI publicado "Pesquisadores ativos" (ADR-0126 §4: nenhuma superfície re-deriva o tier). Os
--      portões de LGPD ficam como estavam: opt-in, k>=3 no agregado, SECURITY DEFINER.
--
-- antes -> depois (o depois foi simulado por SELECT antes da aplicação; re-meça depois):
--   chapters, total_chapters e chapters_participating.current: 5 -> 15
--   mapa por país: BR 91 -> 69, US 5 -> 5, ZZ 2 -> 2 (Portugal tem 2, abaixo de k=3); preciso PT 1 -> 1
--   pinos de estado: 47 -> 46 pessoas (BR-MG 6 -> 5)
--   soma do mapa: 98 -> 76, igual ao hero
--
-- Os 7 corpos foram copiados das capturas mais novas, cujo md5 normalizado (a fórmula de
-- _audit_list_public_function_bodies) bate com o vivo em 04/10/2026. A única diferença são as linhas
-- marcadas "#2553". Rollback: reaplicar as capturas de 20260824155339, 20260805000467,
-- 20260805000321, 20260805000225, 20260805000251 (duas funções) e 20260805000253.

CREATE OR REPLACE FUNCTION public.get_homepage_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN jsonb_build_object(
    'members', (SELECT count(*) FROM public.v_operational_members),
    'observers', (SELECT count(*) FROM members WHERE member_status = 'observer'),
    'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni'),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
        AND visibility <> 'confidential'
    ),
    'total_initiatives', (
      SELECT count(*) FROM initiatives WHERE status = 'active'
        AND visibility <> 'confidential'
    ),
    'active_leaders', (
      SELECT count(DISTINCT person_id) FROM auth_engagements
      WHERE status = 'active' AND role IN ('leader', 'co_leader', 'co_gp')
    ),
    -- #2553: capítulos = engaged (assinados + em negociação), decisão do GP de 03/10/2026.
    'chapters', (public.get_chapter_metrics()->>'engaged')::int,
    'impact_hours', round(public.get_impact_hours_canonical()),
    'max_members_per_tribe', public.tribe_capacity_limit()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_platform_stats()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT json_build_object(
    'active_members', (SELECT COUNT(*) FROM public.v_operational_members),
    'total_tribes', (SELECT COUNT(*) FROM public.tribes WHERE is_active),
    'total_initiatives', (
      SELECT count(*) FROM public.initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
        AND visibility <> 'confidential'
    ),
    'total_verticals', (
      SELECT count(*) FROM public.initiatives
      WHERE kind = 'community_vertical' AND status = 'active'
        AND visibility <> 'confidential'
    ),
    -- #2553: capítulos = engaged (assinados + em negociação), decisão do GP de 03/10/2026.
    'total_chapters', (public.get_chapter_metrics()->>'engaged')::int,
    'total_events', (SELECT COUNT(*) FROM public.events e WHERE e.date >= '2026-01-01' AND NOT EXISTS (SELECT 1 FROM public.initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')),
    'total_resources', (SELECT COUNT(*) FROM public.hub_resources WHERE is_active),
    'retention_rate', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
    'impact_hours', round(public.get_impact_hours_canonical())
  );
$function$;

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
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.partner_entities
        WHERE entity_type IN ('academia', 'governo', 'empresa')
          AND status = 'active'
          AND partnership_date >= v_year_start;

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

CREATE OR REPLACE FUNCTION public.get_public_country_reach()
RETURNS TABLE(country_code text, member_count bigint)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH normalized AS (
    SELECT
      CASE
        WHEN lower(trim(m.country)) ~ 'bras|brazil'                     OR lower(trim(m.country)) = 'br'            THEN 'BR'
        WHEN lower(trim(m.country)) ~ 'portug'                          OR lower(trim(m.country)) = 'pt'            THEN 'PT'
        WHEN lower(trim(m.country)) ~ 'estados unidos|united states|usa' OR lower(trim(m.country)) IN ('us','eua')  THEN 'US'
        WHEN lower(trim(m.country)) ~ 'ital'                            OR lower(trim(m.country)) = 'it'            THEN 'IT'
        WHEN lower(trim(m.country)) ~ 'espanha|spain|espana'            OR lower(trim(m.country)) = 'es'            THEN 'ES'
        WHEN lower(trim(m.country)) ~ 'argentin'                        OR lower(trim(m.country)) = 'ar'            THEN 'AR'
        WHEN lower(trim(m.country)) ~ 'reino unido|united kingdom'      OR lower(trim(m.country)) IN ('uk','gb')    THEN 'GB'
        WHEN lower(trim(m.country)) ~ 'canad'                           OR lower(trim(m.country)) = 'ca'            THEN 'CA'
        WHEN lower(trim(m.country)) ~ 'fran'                            OR lower(trim(m.country)) = 'fr'            THEN 'FR'
        WHEN lower(trim(m.country)) ~ 'aleman|german|deutsch'           OR lower(trim(m.country)) = 'de'            THEN 'DE'
        WHEN m.country IS NULL OR trim(m.country) = ''                                                              THEN NULL
        ELSE 'XX'
      END AS code
    FROM public.members m
    -- #2553: população = equipe de pesquisa (v_operational_members, ADR-0126), a MESMA do hero.
    WHERE EXISTS (SELECT 1 FROM public.v_operational_members om WHERE om.id = m.id)
  ),
  counted AS (
    SELECT code, count(*)::bigint AS n
    FROM normalized
    WHERE code IS NOT NULL
    GROUP BY code
  )
  SELECT
    CASE WHEN n >= 3 AND code <> 'XX' THEN code ELSE 'ZZ' END AS country_code,
    sum(n)::bigint AS member_count
  FROM counted
  GROUP BY CASE WHEN n >= 3 AND code <> 'XX' THEN code ELSE 'ZZ' END
  ORDER BY member_count DESC, country_code;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_precise_country_reach()
 RETURNS TABLE(country_code text, member_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  WITH normalized AS (
    SELECT
      CASE
        WHEN lower(trim(m.country)) ~ 'portug'                     OR lower(trim(m.country)) = 'pt'         THEN 'PT'
        WHEN lower(trim(m.country)) ~ 'ital'                       OR lower(trim(m.country)) = 'it'         THEN 'IT'
        WHEN lower(trim(m.country)) ~ 'espanha|spain|espana'       OR lower(trim(m.country)) = 'es'         THEN 'ES'
        WHEN lower(trim(m.country)) ~ 'argentin'                   OR lower(trim(m.country)) = 'ar'         THEN 'AR'
        WHEN lower(trim(m.country)) ~ 'reino unido|united kingdom' OR lower(trim(m.country)) IN ('uk','gb') THEN 'GB'
        WHEN lower(trim(m.country)) ~ 'canad'                      OR lower(trim(m.country)) = 'ca'         THEN 'CA'
        WHEN lower(trim(m.country)) ~ 'fran'                       OR lower(trim(m.country)) = 'fr'         THEN 'FR'
        WHEN lower(trim(m.country)) ~ 'aleman|german|deutsch'      OR lower(trim(m.country)) = 'de'         THEN 'DE'
        ELSE NULL
      END AS code
    FROM public.members m
    -- #2553: população = equipe de pesquisa (v_operational_members, ADR-0126), a MESMA do hero.
    WHERE EXISTS (SELECT 1 FROM public.v_operational_members om WHERE om.id = m.id)
      AND m.allow_precise_location_in_public_map
  )
  SELECT code AS country_code, count(*)::bigint AS member_count
  FROM normalized
  WHERE code IS NOT NULL
  GROUP BY code
  ORDER BY count(*) DESC, code;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_continent_reach()
 RETURNS TABLE(continent_code text, member_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  WITH normalized AS (
    SELECT
      m.allow_precise_location_in_public_map AS is_precise,
      CASE
        WHEN lower(trim(m.country)) ~ 'bras|brazil'                     OR lower(trim(m.country)) = 'br'         THEN 'BR'
        WHEN lower(trim(m.country)) ~ 'portug'                          OR lower(trim(m.country)) = 'pt'         THEN 'PT'
        WHEN lower(trim(m.country)) ~ 'estados unidos|united states|usa' OR lower(trim(m.country)) IN ('us','eua') THEN 'US'
        WHEN lower(trim(m.country)) ~ 'ital'                           OR lower(trim(m.country)) = 'it'         THEN 'IT'
        WHEN lower(trim(m.country)) ~ 'espanha|spain|espana'           OR lower(trim(m.country)) = 'es'         THEN 'ES'
        WHEN lower(trim(m.country)) ~ 'argentin'                       OR lower(trim(m.country)) = 'ar'         THEN 'AR'
        WHEN lower(trim(m.country)) ~ 'reino unido|united kingdom'     OR lower(trim(m.country)) IN ('uk','gb') THEN 'GB'
        WHEN lower(trim(m.country)) ~ 'canad'                          OR lower(trim(m.country)) = 'ca'         THEN 'CA'
        WHEN lower(trim(m.country)) ~ 'fran'                           OR lower(trim(m.country)) = 'fr'         THEN 'FR'
        WHEN lower(trim(m.country)) ~ 'aleman|german|deutsch'          OR lower(trim(m.country)) = 'de'         THEN 'DE'
        WHEN m.country IS NULL OR trim(m.country) = ''                                                          THEN NULL
        ELSE 'XX'
      END AS code
    FROM public.members m
    -- #2553: população = equipe de pesquisa (v_operational_members, ADR-0126), a MESMA do hero.
    WHERE EXISTS (SELECT 1 FROM public.v_operational_members om WHERE om.id = m.id)
  ),
  country_totals AS (
    SELECT code, count(*) AS total FROM normalized WHERE code IS NOT NULL GROUP BY code
  ),
  residual AS (
    SELECT
      CASE n.code
        WHEN 'PT' THEN 'EU' WHEN 'IT' THEN 'EU' WHEN 'ES' THEN 'EU'
        WHEN 'GB' THEN 'EU' WHEN 'FR' THEN 'EU' WHEN 'DE' THEN 'EU'
        WHEN 'AR' THEN 'SA'
        WHEN 'CA' THEN 'NA'
        ELSE 'ZZ'  -- XX / unmapped -> Internacional
      END AS continent
    FROM normalized n
    JOIN country_totals ct ON ct.code = n.code
    WHERE n.code NOT IN ('BR','US')   -- always-named country pins (or the BR/US state-pin layer)
      AND (
        n.code = 'XX'                 -- #897: XX is the catch-all for unmapped countries and is NEVER a
                                      -- named pin (country_reach folds XX->ZZ) nor a precise pin (no
                                      -- centroid) -> every XX member must stay in the residual (-> ZZ),
                                      -- else it vanishes from the map. Replaces the old, too-greedy
                                      -- `ct.total<3 AND NOT is_precise` for the XX case.
        OR (ct.total < 3 AND NOT n.is_precise)  -- recognized small countries not already shown as a
                                                -- named (>=3) or precise country pin
      )
  ),
  grouped AS (
    SELECT continent, count(*)::bigint AS n FROM residual GROUP BY continent
  )
  SELECT
    CASE WHEN n >= 3 AND continent <> 'ZZ' THEN continent ELSE 'ZZ' END AS continent_code,
    sum(n)::bigint AS member_count
  FROM grouped
  GROUP BY CASE WHEN n >= 3 AND continent <> 'ZZ' THEN continent ELSE 'ZZ' END
  ORDER BY member_count DESC, continent_code;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_state_reach_v3(p_min_k integer DEFAULT 3)
 RETURNS TABLE(country_code text, region_code text, member_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  WITH us_lookup(nm, code) AS (VALUES
    ('alabama','AL'),('alaska','AK'),('arizona','AZ'),('arkansas','AR'),('california','CA'),
    ('colorado','CO'),('connecticut','CT'),('delaware','DE'),('florida','FL'),('georgia','GA'),
    ('hawaii','HI'),('idaho','ID'),('illinois','IL'),('indiana','IN'),('iowa','IA'),
    ('kansas','KS'),('kentucky','KY'),('louisiana','LA'),('maine','ME'),('maryland','MD'),
    ('massachusetts','MA'),('michigan','MI'),('minnesota','MN'),('mississippi','MS'),('missouri','MO'),
    ('montana','MT'),('nebraska','NE'),('nevada','NV'),('new hampshire','NH'),('new jersey','NJ'),
    ('new mexico','NM'),('new york','NY'),('north carolina','NC'),('north dakota','ND'),('ohio','OH'),
    ('oklahoma','OK'),('oregon','OR'),('pennsylvania','PA'),('rhode island','RI'),('south carolina','SC'),
    ('south dakota','SD'),('tennessee','TN'),('texas','TX'),('utah','UT'),('vermont','VT'),
    ('virginia','VA'),('washington','WA'),('west virginia','WV'),('wisconsin','WI'),('wyoming','WY'),
    ('district of columbia','DC')
  ),
  br_lookup(nm, code) AS (VALUES
    ('acre','AC'),('alagoas','AL'),('amapá','AP'),('amapa','AP'),('amazonas','AM'),('bahia','BA'),
    ('ceará','CE'),('ceara','CE'),('distrito federal','DF'),('espírito santo','ES'),('espirito santo','ES'),
    ('goiás','GO'),('goias','GO'),('maranhão','MA'),('maranhao','MA'),('mato grosso','MT'),
    ('mato grosso do sul','MS'),('minas gerais','MG'),('pará','PA'),('para','PA'),('paraíba','PB'),
    ('paraiba','PB'),('paraná','PR'),('parana','PR'),('pernambuco','PE'),('piauí','PI'),('piaui','PI'),
    ('rio de janeiro','RJ'),('rio grande do norte','RN'),('rio grande do sul','RS'),('rondônia','RO'),
    ('rondonia','RO'),('roraima','RR'),('santa catarina','SC'),('são paulo','SP'),('sao paulo','SP'),
    ('sergipe','SE'),('tocantins','TO')
  ),
  pop AS (
    SELECT
      CASE
        WHEN lower(trim(m.country)) ~ 'bras|brazil' OR lower(trim(m.country)) = 'br' THEN 'BR'
        WHEN lower(trim(m.country)) ~ 'estados unidos|united states|usa' OR lower(trim(m.country)) IN ('us','eua') THEN 'US'
        ELSE NULL
      END AS cc,
      lower(btrim(m.state)) AS st_raw,
      m.allow_precise_location_in_public_map AS is_precise,
      (m.allow_state_in_public_map AND NOT m.allow_precise_location_in_public_map) AS is_aggregate
    FROM public.members m
    -- #2553: população = equipe de pesquisa (v_operational_members, ADR-0126), a MESMA do hero.
    WHERE EXISTS (SELECT 1 FROM public.v_operational_members om WHERE om.id = m.id)
      AND (m.allow_state_in_public_map OR m.allow_precise_location_in_public_map)
  ),
  resolved AS (
    SELECT cc AS country_code,
      CASE cc
        WHEN 'US' THEN COALESCE((SELECT l.code FROM us_lookup l WHERE l.nm = pop.st_raw LIMIT 1),
                                (SELECT l.code FROM us_lookup l WHERE l.code = upper(pop.st_raw) LIMIT 1))
        WHEN 'BR' THEN COALESCE((SELECT l.code FROM br_lookup l WHERE l.nm = pop.st_raw LIMIT 1),
                                (SELECT l.code FROM br_lookup l WHERE l.code = upper(pop.st_raw) LIMIT 1))
      END AS region_code,
      is_precise,
      is_aggregate
    FROM pop
    WHERE cc IS NOT NULL
  ),
  counts AS (
    SELECT country_code, region_code,
      count(*) FILTER (WHERE is_precise)   AS count_precise,
      count(*) FILTER (WHERE is_aggregate) AS count_aggregate
    FROM resolved
    WHERE region_code IS NOT NULL
    GROUP BY country_code, region_code
  )
  SELECT country_code, region_code,
    (count_precise + CASE WHEN count_aggregate >= GREATEST(p_min_k, 3) THEN count_aggregate ELSE 0 END)::bigint AS member_count
  FROM counts
  WHERE count_precise >= 1 OR count_aggregate >= GREATEST(p_min_k, 3)
  ORDER BY member_count DESC, country_code, region_code;
$function$;
