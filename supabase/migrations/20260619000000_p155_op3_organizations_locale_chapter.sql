-- p155 Op 3: organizations + initiatives admin CRUD prep
-- Adds host_chapter / primary_language / country / federated_chapters to organizations
-- to support multi-tenant replicas (each Núcleo replica has its own host chapter, language, country).
-- Backfills current row (Nucleo IA & GP) with PMI-GO sede, pt-BR primary, BR country, 5 federated chapters.
-- Creates get_my_organization + update_organization RPCs for /admin/organization.astro.
--
-- Schema rationale (PM directive 2026-05-13):
-- - chapter scope é organization-level (sede de cada réplica), NÃO initiative-level
-- - todas as iniciativas atuais são portfolio do Núcleo (organization-wide)
-- - réplicas futuras (Núcleo USA, Núcleo LATAM, Núcleo English) terão organizations.host_chapter diferente
--
-- Out of scope: tabela initiatives mantém schema atual (sem chapter column).

-- =============== SCHEMA ===============

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS host_chapter        text,
  ADD COLUMN IF NOT EXISTS primary_language    text DEFAULT 'pt-BR' NOT NULL,
  ADD COLUMN IF NOT EXISTS country             text DEFAULT 'BR'    NOT NULL,
  ADD COLUMN IF NOT EXISTS federated_chapters  text[] DEFAULT '{}'::text[] NOT NULL;

COMMENT ON COLUMN public.organizations.host_chapter IS
  'Capítulo PMI sede da organização (ex: PMI-GO). NULL apenas para orgs em transição. Réplicas internacionais teriam outros (PMI-WDC, PMI-LIM, etc).';

COMMENT ON COLUMN public.organizations.primary_language IS
  'Idioma primário desta instância do Núcleo (pt-BR | en-US | es-LATAM). Réplicas em outras línguas terão default diferente. Usado para fallback quando member não tem preferência de idioma definida.';

COMMENT ON COLUMN public.organizations.country IS
  'País sede ISO-alpha2 (BR | US | MX | …). Drives compliance defaults (LGPD vs GDPR vs CCPA).';

COMMENT ON COLUMN public.organizations.federated_chapters IS
  'Capítulos PMI federados sob esta org. Substitui texto livre que estava em description.';

-- =============== BACKFILL ===============

UPDATE public.organizations
SET host_chapter        = 'PMI-GO',
    primary_language    = 'pt-BR',
    country             = 'BR',
    federated_chapters  = ARRAY['PMI-GO','PMI-CE','PMI-DF','PMI-MG','PMI-RS']::text[]
WHERE slug = 'nucleo-ia';

-- =============== RPCs ===============

CREATE OR REPLACE FUNCTION public.get_my_organization()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_org_id uuid;
  v_result jsonb;
BEGIN
  v_org_id := public.auth_org();
  IF v_org_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated or no organization scope');
  END IF;

  SELECT jsonb_build_object(
    'id', id,
    'name', name,
    'slug', slug,
    'description', description,
    'website_url', website_url,
    'logo_url', logo_url,
    'status', status,
    'host_chapter', host_chapter,
    'primary_language', primary_language,
    'country', country,
    'federated_chapters', federated_chapters,
    'created_at', created_at,
    'updated_at', updated_at
  )
  INTO v_result
  FROM public.organizations
  WHERE id = v_org_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Organization not found');
  END IF;
  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_organization() FROM PUBLIC, anon;

COMMENT ON FUNCTION public.get_my_organization() IS
  'Returns the caller authenticated organization (auth_org()) as jsonb. Used by /admin/organization.astro to render the org info panel. p155 Op 3.';

CREATE OR REPLACE FUNCTION public.update_organization(
  p_name text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_website_url text DEFAULT NULL,
  p_logo_url text DEFAULT NULL,
  p_host_chapter text DEFAULT NULL,
  p_primary_language text DEFAULT NULL,
  p_country text DEFAULT NULL,
  p_federated_chapters text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_org_id uuid;
  v_changes jsonb := '{}'::jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform');
  END IF;

  v_org_id := public.auth_org();
  IF v_org_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No organization scope');
  END IF;

  IF p_primary_language IS NOT NULL AND p_primary_language NOT IN ('pt-BR','en-US','es-LATAM') THEN
    RETURN jsonb_build_object('error', 'Invalid primary_language: must be pt-BR | en-US | es-LATAM');
  END IF;

  UPDATE public.organizations
  SET name               = COALESCE(p_name, name),
      description        = COALESCE(p_description, description),
      website_url        = COALESCE(p_website_url, website_url),
      logo_url           = COALESCE(p_logo_url, logo_url),
      host_chapter       = COALESCE(p_host_chapter, host_chapter),
      primary_language   = COALESCE(p_primary_language, primary_language),
      country            = COALESCE(p_country, country),
      federated_chapters = COALESCE(p_federated_chapters, federated_chapters),
      updated_at         = now()
  WHERE id = v_org_id;

  v_changes := jsonb_build_object(
    'name', p_name, 'description', p_description, 'website_url', p_website_url,
    'logo_url', p_logo_url, 'host_chapter', p_host_chapter,
    'primary_language', p_primary_language, 'country', p_country,
    'federated_chapters', p_federated_chapters
  );

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'organization_updated', 'info',
    'Organization ' || v_org_id::text || ' updated by member ' || v_caller_id::text,
    jsonb_build_object('organization_id', v_org_id, 'caller_id', v_caller_id, 'changes', v_changes)
  );

  RETURN jsonb_build_object('ok', true, 'organization_id', v_org_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.update_organization(text, text, text, text, text, text, text, text[]) FROM PUBLIC, anon;

COMMENT ON FUNCTION public.update_organization(text, text, text, text, text, text, text, text[]) IS
  'Admin-only (manage_platform) update of organization fields. Validates primary_language. Audit em data_anomaly_log. p155 Op 3.';
