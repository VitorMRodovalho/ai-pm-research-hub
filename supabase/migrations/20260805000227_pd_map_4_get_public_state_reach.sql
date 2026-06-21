CREATE OR REPLACE FUNCTION public.get_public_state_reach()
 RETURNS TABLE(state_code text, member_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- Cobertura por estado (UF) p/ heatmap publico — Cycle4 PD-MAP. Zero-PII, agregado.
  -- Populacao = MESMA de get_public_country_reach (denominador canonico de membros ativos).
  -- LGPD: WHERE allow_state_in_public_map (opt-in, Art. 7 I) + supressao k>=5 (anti-reidentificacao,
  -- Art. 6 III minimizacao). Normaliza members.state (texto livre) -> sigla UF p/ deduplicar
  -- 'GO'/'Goias' e descartar nao-Brasil (ELSE NULL).
  WITH normalized AS (
    SELECT
      CASE lower(btrim(m.state))
        WHEN 'ac' THEN 'AC' WHEN 'acre' THEN 'AC'
        WHEN 'al' THEN 'AL' WHEN 'alagoas' THEN 'AL'
        WHEN 'ap' THEN 'AP' WHEN 'amapá' THEN 'AP' WHEN 'amapa' THEN 'AP'
        WHEN 'am' THEN 'AM' WHEN 'amazonas' THEN 'AM'
        WHEN 'ba' THEN 'BA' WHEN 'bahia' THEN 'BA'
        WHEN 'ce' THEN 'CE' WHEN 'ceará' THEN 'CE' WHEN 'ceara' THEN 'CE'
        WHEN 'df' THEN 'DF' WHEN 'distrito federal' THEN 'DF'
        WHEN 'es' THEN 'ES' WHEN 'espírito santo' THEN 'ES' WHEN 'espirito santo' THEN 'ES'
        WHEN 'go' THEN 'GO' WHEN 'goiás' THEN 'GO' WHEN 'goias' THEN 'GO'
        WHEN 'ma' THEN 'MA' WHEN 'maranhão' THEN 'MA' WHEN 'maranhao' THEN 'MA'
        WHEN 'mt' THEN 'MT' WHEN 'mato grosso' THEN 'MT'
        WHEN 'ms' THEN 'MS' WHEN 'mato grosso do sul' THEN 'MS'
        WHEN 'mg' THEN 'MG' WHEN 'minas gerais' THEN 'MG'
        WHEN 'pa' THEN 'PA' WHEN 'pará' THEN 'PA' WHEN 'para' THEN 'PA'
        WHEN 'pb' THEN 'PB' WHEN 'paraíba' THEN 'PB' WHEN 'paraiba' THEN 'PB'
        WHEN 'pr' THEN 'PR' WHEN 'paraná' THEN 'PR' WHEN 'parana' THEN 'PR'
        WHEN 'pe' THEN 'PE' WHEN 'pernambuco' THEN 'PE'
        WHEN 'pi' THEN 'PI' WHEN 'piauí' THEN 'PI' WHEN 'piaui' THEN 'PI'
        WHEN 'rj' THEN 'RJ' WHEN 'rio de janeiro' THEN 'RJ'
        WHEN 'rn' THEN 'RN' WHEN 'rio grande do norte' THEN 'RN'
        WHEN 'rs' THEN 'RS' WHEN 'rio grande do sul' THEN 'RS'
        WHEN 'ro' THEN 'RO' WHEN 'rondônia' THEN 'RO' WHEN 'rondonia' THEN 'RO'
        WHEN 'rr' THEN 'RR' WHEN 'roraima' THEN 'RR'
        WHEN 'sc' THEN 'SC' WHEN 'santa catarina' THEN 'SC'
        WHEN 'sp' THEN 'SP' WHEN 'são paulo' THEN 'SP' WHEN 'sao paulo' THEN 'SP'
        WHEN 'se' THEN 'SE' WHEN 'sergipe' THEN 'SE'
        WHEN 'to' THEN 'TO' WHEN 'tocantins' THEN 'TO'
        ELSE NULL
      END AS uf
    FROM public.members m
    WHERE m.is_active
      AND m.current_cycle_active
      AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
      AND m.allow_state_in_public_map
  )
  SELECT uf AS state_code, count(*)::bigint AS member_count
  FROM normalized
  WHERE uf IS NOT NULL
  GROUP BY uf
  HAVING count(*) >= 5
  ORDER BY member_count DESC, state_code;
$function$;

GRANT EXECUTE ON FUNCTION public.get_public_state_reach() TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_public_state_reach() IS
  'Cobertura agregada de membros por UF p/ heatmap publico (Cycle4 PD-MAP). LGPD: opt-in (allow_state_in_public_map, Art. 7 I) + supressao k>=5 (Art. 6 III). Zero-PII, SECURITY DEFINER. Espelha a populacao de get_public_country_reach.';
