-- #897 fix — get_public_continent_reach: keep every unmapped-country (XX) member in the residual.
-- continent_reach is the SOLE source of the ZZ "Internacional" chip on the public home map
-- (get_public_country_reach's own ZZ is filtered out client-side; namedReach drops ZZ/XX).
-- The old residual filter (ct.total<3 AND NOT is_precise) was written for RECOGNIZED countries
-- (PT/IT/...) — which DO become named pins at >=3 or precise pins when consented — but it was also
-- applied to the synthetic XX bucket. XX is never a named pin (country_reach always folds XX->ZZ)
-- and never a precise pin (no centroid), so any XX member caught by those filters vanished from the
-- map entirely. Two latent cases (both behavior-neutral today: 0 XX, 0 precise members live):
--   (a) #897: a precise-consenter in an unsupported country (NOT is_precise dropped them, and the
--       precise-country layer maps them to NULL -> no pin);
--   (b) >=3 members spread across unmapped countries (ct.total<3 false -> the whole XX bucket dropped).
-- Fix: XX bypasses BOTH filters and always stays in the residual -> lands in the ZZ chip, the same
-- aggregate (Art. 7,IX) exposure a non-consenter already gets. Recognized-country behavior unchanged.
-- Option 1 (precise pins for arbitrary countries) needs new centroids in src/lib/worldMap.ts and stays
-- a separate enhancement. RoPA H.4 (residual continent layer).
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
    WHERE m.is_active
      AND m.current_cycle_active
      AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
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

-- ACL: this zero-PII public surface is REVOKE-PUBLIC + granted only to the three roles (RoPA pattern,
-- mig `…242`/`…252`). CREATE OR REPLACE above preserves existing grants, so this is a no-op against a DB
-- that already ran `…252` (verified live 2026-06-26: PUBLIC has no EXECUTE) — restated here only so this
-- migration reproduces the hardened end-state on a from-baseline apply, instead of depending on `…252`.
REVOKE ALL ON FUNCTION public.get_public_continent_reach() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_continent_reach() TO anon, authenticated, service_role;
