-- PD-MAP-WORLD (Ciclo 4, 2026-06-23): camada de ESTADO para o mapa-mundi publico.
-- Estende get_public_state_reach (BR-only) para BR + EUA, retornando country_code + region_code
-- separados (p/ o front-end posicionar pins por centroide). Mesma populacao canonica de membros
-- ativos. LGPD: WHERE allow_state_in_public_map (opt-in explicito, Art. 7 I) + supressao k>=p_min_k.
--
-- k DEFAULT 3 (nao mais 5): parecer legal-counsel 2026-06-23 confirmou Cenario A — o texto do opt-in
-- ("estado de residencia ... apenas de forma agregada (nunca individual)") NAO menciona um k especifico,
-- entao baixar o teto NAO exige novo consentimento (so atualizar COMMENT/RoPA). k>=3 e consistente com
-- get_public_country_reach, honra a promessa "nunca individual" (k<=2 exporia membro unico) e torna a
-- camada util. Escopo internacional coberto: o texto diz "estado de residencia" (pais-agnostico), nao "UF".
--
-- Normaliza members.state (texto livre) -> sigla via lookups VALUES; ELSE NULL descarta nao-mapeavel.
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
        WHEN 'US' THEN COALESCE((SELECT l.code FROM us_lookup l WHERE l.nm = pop.st_raw),
                                (SELECT l.code FROM us_lookup l WHERE l.code = upper(pop.st_raw)))
        WHEN 'BR' THEN COALESCE((SELECT l.code FROM br_lookup l WHERE l.nm = pop.st_raw),
                                (SELECT l.code FROM br_lookup l WHERE l.code = upper(pop.st_raw)))
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

REVOKE ALL ON FUNCTION public.get_public_state_reach_v2(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_state_reach_v2(integer) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_public_state_reach_v2(integer) IS
  'PD-MAP-WORLD (Ciclo4, 2026-06-23): cobertura agregada de membros por estado (BR UFs + US states) p/ o mapa-mundi publico. country_code + region_code separados p/ posicionar pins. LGPD: opt-in (allow_state_in_public_map, Art.7 I) + supressao k>=GREATEST(p_min_k,3) (piso fixo de 3 honra a promessa "nunca individual" do texto de consentimento e e consistente com get_public_country_reach). Espelha a populacao de get_public_country_reach. SECURITY DEFINER, zero-PII. Parecer legal-counsel 2026-06-23 (Cenario A: texto do opt-in nao cita k, escopo "estado de residencia" e pais-agnostico).';

-- Atualiza o COMMENT da coluna p/ refletir k>=3 + escopo internacional (parecer 4.2 / RoPA-consistency).
COMMENT ON COLUMN public.members.allow_state_in_public_map IS
  'LGPD Art. 7 I (consentimento) + privacy-by-design opt-out por padrao (DEFAULT false). Autorizacao explicita do membro para inclusao do seu estado de residencia (UF brasileira OU estado estrangeiro, ex. US state) em mapas de distribuicao geografica AGREGADOS exibidos publicamente. Consumido por get_public_state_reach (BR, legado k>=5) e get_public_state_reach_v2 (BR+US, k>=3). Supressao k garante exibicao apenas agregada (nunca individual), honrando o texto do opt-in (profile.allowStateMapLabel). Revogavel a qualquer tempo (Art. 18). Finalidade distinta da coleta original de members.state (verificacao de afiliacao) - base legal no RoPA. k baixado de 5->3 em 2026-06-23 (Cenario A, parecer legal-counsel: texto nao cita k; risco residual de inferencia-por-exclusao registrado no RoPA). Cycle4 PD-MAP-2 / PD-MAP-WORLD.';
