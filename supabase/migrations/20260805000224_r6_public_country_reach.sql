-- R6 (Ciclo 4 landing): public named-country reach legend for the "Cobertura & alcance" band.
-- Aggregates members.country normalized to ISO-3166-1 alpha-2, over the SAME canonical
-- population as get_public_platform_stats.active_members (is_active AND current_cycle_active
-- AND NOT pre_onboarding) so the per-country counts sum to the headline "pesquisadores ativos".
-- Zero-PII: returns only (country_code, member_count); no member rows. anon-safe.
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
    WHERE m.is_active
      AND m.current_cycle_active
      AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
  )
  SELECT code AS country_code, count(*)::bigint AS member_count
  FROM normalized
  WHERE code IS NOT NULL
  GROUP BY code
  ORDER BY count(*) DESC, code;
$function$;

REVOKE ALL ON FUNCTION public.get_public_country_reach() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_country_reach() TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_public_country_reach() IS
  'R6 Ciclo 4: zero-PII named-country reach for the public landing coverage band. Aggregates members.country (normalized to ISO-2) over the canonical active_members population so counts sum to "pesquisadores ativos". anon-safe.';
