-- PD-MAP-1 (Ciclo 4, 2026-06-21): LGPD k-anonimidade no alcance por país.
-- Países com < 3 membros (e os não-reconhecidos 'XX') são agrupados num bucket genérico 'ZZ'
-- ("Internacional") para que NENHUM país de membro único seja NOMEADO na superfície pública
-- (parecer legal-counsel 2026-06-21). O total continua somando a população canônica de
-- active_members (o bucket preserva a contagem; só esconde a identidade do país).
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

REVOKE ALL ON FUNCTION public.get_public_country_reach() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_country_reach() TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_public_country_reach() IS
  'R6 + PD-MAP-1 (Ciclo 4): zero-PII named-country reach para a landing. Países com <3 membros (e não-reconhecidos) agrupados em ZZ ("Internacional") por k-anonimidade LGPD — nenhum país de membro único é nomeado. Base legal/finalidade: estatística de alcance agregada. anon-safe.';
