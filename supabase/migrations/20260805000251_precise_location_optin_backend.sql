-- PR-1 (backend) — "precise location" geo opt-in (Opção B unificada, parecer legal-counsel 2026-06-25).
-- Inert until the PR-2 frontend switches to the new RPCs. Adds a SECOND consent flag (k=1, explicit
-- "mesmo que eu seja o único") ALONGSIDE the legacy allow_state_in_public_map (k≥3, "nunca individual").
-- The two consent populations are NEVER summed below k (parecer rule d): a state/country pin shows
--   count_precise + (count_aggregate ONLY IF count_aggregate >= k).
-- New layers: state (BR/US) dual-population · precise country (non-BR/US, k=1) · continent residual (k≥3).
-- Legal: new flag = Art. 7,I (specific consent for individual display); residual continent = Art. 7,IX.

-- 1) New consent column (mirrors 20260805000226_pd_map_2_allow_state_column.sql).
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS allow_precise_location_in_public_map boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.members.allow_precise_location_in_public_map IS
  'LGPD opt-in (Art. 7,I): authorizes displaying the member''s state (BR/US) or country (other) on '
  'the public map EVEN AT k=1 (sole member). Distinct from legacy allow_state_in_public_map (k>=3, '
  '"nunca individual"). Re-consent required; the two are never merged. RoPA H.4.';

-- 2) update_my_profile: allow the new field + persist it (allowlist gate stays intact).
CREATE OR REPLACE FUNCTION public.update_my_profile(p_fields jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_allowed_fields text[] := ARRAY['name','phone','linkedin_url','credly_url','share_whatsapp','pmi_id','state','country','photo_url','signature_url','address','city','birth_date','share_address','share_birth_date','allow_state_in_public_map','allow_precise_location_in_public_map'];
  v_field text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  FOR v_field IN SELECT jsonb_object_keys(p_fields) LOOP
    IF NOT (v_field = ANY(v_allowed_fields)) THEN
      RETURN jsonb_build_object('error', 'Field not allowed: ' || v_field);
    END IF;
  END LOOP;

  UPDATE members SET
    name = CASE WHEN p_fields ? 'name' AND length(p_fields->>'name') >= 2 THEN p_fields->>'name' ELSE name END,
    phone = CASE WHEN p_fields ? 'phone' THEN p_fields->>'phone' ELSE phone END,
    linkedin_url = CASE WHEN p_fields ? 'linkedin_url' THEN p_fields->>'linkedin_url' ELSE linkedin_url END,
    credly_url = CASE WHEN p_fields ? 'credly_url' THEN p_fields->>'credly_url' ELSE credly_url END,
    share_whatsapp = CASE WHEN p_fields ? 'share_whatsapp' THEN (p_fields->>'share_whatsapp')::boolean ELSE share_whatsapp END,
    share_address = CASE WHEN p_fields ? 'share_address' THEN (p_fields->>'share_address')::boolean ELSE share_address END,
    share_birth_date = CASE WHEN p_fields ? 'share_birth_date' THEN (p_fields->>'share_birth_date')::boolean ELSE share_birth_date END,
    allow_state_in_public_map = CASE WHEN p_fields ? 'allow_state_in_public_map' THEN (p_fields->>'allow_state_in_public_map')::boolean ELSE allow_state_in_public_map END,
    allow_precise_location_in_public_map = CASE WHEN p_fields ? 'allow_precise_location_in_public_map' THEN (p_fields->>'allow_precise_location_in_public_map')::boolean ELSE allow_precise_location_in_public_map END,
    pmi_id = CASE WHEN p_fields ? 'pmi_id' THEN p_fields->>'pmi_id' ELSE pmi_id END,
    state = CASE WHEN p_fields ? 'state' THEN p_fields->>'state' ELSE state END,
    country = CASE WHEN p_fields ? 'country' THEN p_fields->>'country' ELSE country END,
    photo_url = CASE WHEN p_fields ? 'photo_url' THEN p_fields->>'photo_url' ELSE photo_url END,
    signature_url = CASE WHEN p_fields ? 'signature_url' THEN p_fields->>'signature_url' ELSE signature_url END,
    address = CASE WHEN p_fields ? 'address' THEN p_fields->>'address' ELSE address END,
    city = CASE WHEN p_fields ? 'city' THEN p_fields->>'city' ELSE city END,
    birth_date = CASE WHEN p_fields ? 'birth_date' THEN (p_fields->>'birth_date')::date ELSE birth_date END,
    profile_completed_at = CASE WHEN profile_completed_at IS NULL THEN now() ELSE profile_completed_at END,
    -- Any profile update counts as a data review
    data_last_reviewed_at = CASE WHEN array_length(ARRAY(SELECT jsonb_object_keys(p_fields)), 1) > 0 THEN now() ELSE data_last_reviewed_at END,
    updated_at = now()
  WHERE id = v_caller.id;

  RETURN jsonb_build_object('ok', true, 'updated_fields', (SELECT array_agg(k) FROM jsonb_object_keys(p_fields) k));
END;
$function$;

-- 3) get_member_by_auth: surface the new flag so the /profile checkbox reflects the saved value.
--    Body byte-identical to live (mig 228) EXCEPT the single new column in the returned JSON.
CREATE OR REPLACE FUNCTION public.get_member_by_auth()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member_id uuid;
  v_existing_auth_id uuid;
  v_result json;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  -- Step 1: direct match on members.auth_id (the common case)
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_uid LIMIT 1;

  -- Step 2: match on secondary_auth_ids (admin-pre-approved alternates -> safe to rotate)
  IF v_member_id IS NULL THEN
    SELECT id INTO v_member_id
      FROM public.members
     WHERE v_uid = ANY(COALESCE(secondary_auth_ids, '{}'))
     LIMIT 1;

    IF v_member_id IS NOT NULL THEN
      SELECT auth_id INTO v_existing_auth_id FROM public.members WHERE id = v_member_id;

      UPDATE public.members
         SET auth_id            = v_uid,
             secondary_auth_ids = array_append(
                                    array_remove(COALESCE(secondary_auth_ids, '{}'::uuid[]), v_uid),
                                    v_existing_auth_id
                                  ),
             updated_at         = now()
       WHERE id = v_member_id;

      -- p177 D=1 fix: sync persons.auth_id to the new primary (mirror try_auto_link_ghost).
      UPDATE public.persons
         SET auth_id = v_uid
       WHERE legacy_member_id = v_member_id
         AND (auth_id IS NULL OR auth_id <> v_uid);

      INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_member_id,
        'members.auth_id.rotated_secondary_to_primary',
        'member',
        v_member_id,
        jsonb_build_object(
          'promoted_auth_id', v_uid,
          'demoted_auth_id', v_existing_auth_id
        ),
        jsonb_build_object('via', 'get_member_by_auth.step2_secondary_auth_ids_match')
      );
    END IF;
  END IF;

  -- Step 3: PRIMARY email first-link (only when auth_id IS NULL -- genuine ghost first login).
  -- P168 R3-a: dropped the (a) secondary_emails match branch and (b) replace-existing-auth_id
  -- branch. Both were the mechanism behind Paulo Alves identity hijack.
  IF v_member_id IS NULL THEN
    SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;

    IF v_email IS NOT NULL THEN
      SELECT id INTO v_member_id
        FROM public.members
       WHERE lower(email) = v_email
         AND auth_id IS NULL
       LIMIT 1;

      IF v_member_id IS NOT NULL THEN
        UPDATE public.members
           SET auth_id    = v_uid,
               updated_at = now()
         WHERE id = v_member_id;

        -- p177 D=1 fix: sync persons.auth_id on first-link (mirror try_auto_link_ghost).
        UPDATE public.persons
           SET auth_id = v_uid
         WHERE legacy_member_id = v_member_id
           AND (auth_id IS NULL OR auth_id <> v_uid);

        INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_member_id,
          'members.auth_id.first_link',
          'member',
          v_member_id,
          jsonb_build_object(
            'linked_auth_id', v_uid,
            'matched_via',    'primary_email',
            'matched_email',  v_email
          ),
          jsonb_build_object('via', 'get_member_by_auth.step3_primary_email_when_null')
        );
      END IF;
    END IF;
  END IF;

  IF v_member_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Return JSON shape -- adds allow_precise_location_in_public_map (Cycle4 PD-MAP unified opt-in); rest UNCHANGED.
  SELECT row_to_json(q) INTO v_result FROM (
    SELECT m.id, m.name, m.email, m.secondary_emails,
      m.pmi_id, m.phone, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations)  AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter, m.tribe_id, m.current_cycle_active, m.is_superadmin, m.is_active,
      m.member_status, m.state, m.country, m.share_whatsapp, m.signature_url,
      m.address, m.city, m.birth_date,
      m.share_address, m.share_birth_date, m.allow_state_in_public_map, m.allow_precise_location_in_public_map,
      m.privacy_consent_accepted_at, m.privacy_consent_version, m.data_last_reviewed_at,
      m.inactivated_at, m.inactivation_reason,
      m.photo_url, m.linkedin_url, m.auth_id,
      m.credly_url, m.credly_badges, m.cpmai_certified,
      m.created_at, m.updated_at
    FROM public.members m
    WHERE m.id = v_member_id
  ) q;

  RETURN v_result;
END;
$function$;

-- 4) State reach v3 — dual-population (precise k=1 + aggregate k>=3), populations NEVER summed below k.
--    Carries the BR-lookup LIMIT 1 collision fix (mig 20260805000250). Frontend switches v2 -> v3 in PR-2.
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
    WHERE m.is_active
      AND m.current_cycle_active
      AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
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

-- 5) Precise country reach — non-BR/US countries with >=1 precise-consenter; count = consenters; k=1.
--    BR/US are excluded (always named country pins; their precision is the state layer above).
--    Unrecognized countries (XX) are not precise-pinnable (no centroid) -> stay in continent/ZZ residual.
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
    WHERE m.is_active
      AND m.current_cycle_active
      AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
      AND m.allow_precise_location_in_public_map
  )
  SELECT code AS country_code, count(*)::bigint AS member_count
  FROM normalized
  WHERE code IS NOT NULL
  GROUP BY code
  ORDER BY count(*) DESC, code;
$function$;

-- 6) Continent reach — the residual the finer layers do NOT show, grouped by continent (k>=3),
--    the rest lumped into 'ZZ' (Internacional). Excludes: BR/US (always named), countries with
--    total >=3 (already named pins), and precise-consenters (shown as precise country pins).
--    Replaces the flat ZZ chip; base Art. 7,IX (aggregate, no consent). Today (0 precise) == ZZ:1.
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
    WHERE n.code NOT IN ('BR','US')   -- always-named country pins
      AND ct.total < 3                -- countries with >=3 are already named country pins
      AND NOT n.is_precise            -- precise-consenters shown as precise country pins
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
