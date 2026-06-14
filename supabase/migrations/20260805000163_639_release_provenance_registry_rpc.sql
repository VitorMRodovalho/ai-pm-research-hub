-- #639 release provenance stamping
-- Adds a service-role-only RPC for GitHub Actions to register release MANIFEST.sha256
-- digests in the existing PI exclusion asset registry. OTS stamping remains delegated
-- to the existing ots-stamp/ots-upgrade cron pipeline from #569/ADR-0101.

CREATE OR REPLACE FUNCTION public.register_release_provenance_asset(
  p_declaration_id uuid,
  p_version text,
  p_commit_sha text,
  p_manifest_sha256 text,
  p_archive_sha256 text,
  p_source_ref text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_decl_org uuid;
  v_status text;
  v_next_seq integer;
  v_id uuid;
BEGIN
  IF p_version !~ '^v[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+)?(\+[a-z0-9]+)?$' THEN
    RAISE EXCEPTION 'Invalid release version: %', p_version;
  END IF;

  IF lower(p_commit_sha) !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'Invalid commit SHA: %', p_commit_sha;
  END IF;

  IF lower(p_manifest_sha256) !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Invalid MANIFEST.sha256 digest';
  END IF;

  IF lower(p_archive_sha256) !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Invalid release archive digest';
  END IF;

  SELECT organization_id, status
    INTO v_decl_org, v_status
  FROM public.pi_exclusion_declarations
  WHERE id = p_declaration_id;

  IF v_decl_org IS NULL THEN
    RAISE EXCEPTION 'Declaration not found';
  END IF;

  IF v_status NOT IN ('draft', 'active') THEN
    RAISE EXCEPTION 'Cannot add release provenance to a % declaration', v_status;
  END IF;

  SELECT COALESCE(max(seq), 0) + 1
    INTO v_next_seq
  FROM public.pi_exclusion_assets
  WHERE declaration_id = p_declaration_id;

  INSERT INTO public.pi_exclusion_assets (
    declaration_id,
    organization_id,
    seq,
    title,
    nature,
    author_label,
    source_ref,
    sha256,
    reinforcement,
    created_by
  ) VALUES (
    p_declaration_id,
    v_decl_org,
    v_next_seq,
    'Release provenance ' || p_version,
    'software-release-manifest',
    'AI & PM Research Hub',
    p_source_ref,
    lower(p_manifest_sha256),
    'GitHub release MANIFEST.sha256; archive_sha256=' || lower(p_archive_sha256) || '; commit=' || lower(p_commit_sha),
    NULL
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.register_release_provenance_asset(uuid,text,text,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_release_provenance_asset(uuid,text,text,text,text,text) TO service_role;

COMMENT ON FUNCTION public.register_release_provenance_asset(uuid,text,text,text,text,text) IS
  '#639 service-role release provenance registry: registers MANIFEST.sha256 digest as pi_exclusion_assets row; existing OTS cron anchors it on Bitcoin.';

NOTIFY pgrst, 'reload schema';
