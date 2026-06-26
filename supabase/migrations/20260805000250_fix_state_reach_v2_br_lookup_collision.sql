-- Fix: get_public_state_reach_v2() throws "more than one row returned by a subquery"
-- when a consented member's members.state is a 2-letter UF code (e.g. 'go','ce') that
-- collides with br_lookup's duplicate-code aliases (accented + unaccented names share a
-- code: 'goiás'/'goias' both 'GO', 'ceará'/'ceara' both 'CE', etc. — 11 such codes).
-- The scalar subquery WHERE l.code = upper(st_raw) then matches 2 rows and the whole
-- function aborts, silently collapsing the ENTIRE state layer (incl. unrelated US states
-- like VA that have >=3 opt-ins and should render). The ChaptersSection.astro fail-soft
-- swallows the RPC error → stateReachV2=[] → no orange state pins at all.
-- Guard each lookup with LIMIT 1: the code column is constant across the matched alias
-- rows, so LIMIT 1 is deterministic and correct. Signature unchanged → CREATE OR REPLACE.
-- Behavior-neutral for all other inputs (full state names, US codes — unique anyway).
CREATE OR REPLACE FUNCTION public.get_public_state_reach_v2(p_min_k integer DEFAULT 3)
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
      lower(btrim(m.state)) AS st_raw
    FROM public.members m
    WHERE m.is_active
      AND m.current_cycle_active
      AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
      AND m.allow_state_in_public_map
  ),
  resolved AS (
    SELECT cc AS country_code,
      CASE cc
        WHEN 'US' THEN COALESCE((SELECT l.code FROM us_lookup l WHERE l.nm = pop.st_raw LIMIT 1),
                                (SELECT l.code FROM us_lookup l WHERE l.code = upper(pop.st_raw) LIMIT 1))
        WHEN 'BR' THEN COALESCE((SELECT l.code FROM br_lookup l WHERE l.nm = pop.st_raw LIMIT 1),
                                (SELECT l.code FROM br_lookup l WHERE l.code = upper(pop.st_raw) LIMIT 1))
      END AS region_code
    FROM pop
    WHERE cc IS NOT NULL
  )
  SELECT country_code, region_code, count(*)::bigint AS member_count
  FROM resolved
  WHERE region_code IS NOT NULL
  GROUP BY country_code, region_code
  HAVING count(*) >= GREATEST(p_min_k, 3)
  ORDER BY member_count DESC, country_code, region_code;
$function$;
