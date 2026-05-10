-- =====================================================================
-- p136 Ω-E.1.b — auth_org() rewrite (proper caller-scoped multi-tenancy)
-- =====================================================================
-- Pre-state: auth_org() returned hardcoded '2b4f58ab-...' (PMI-GO) for any
-- caller — single-tenant placeholder. This made V4 RLS policies that use
-- `((organization_id = auth_org()) OR (organization_id IS NULL))` evaluate
-- as "any authenticated user sees the single org's data", including ghost
-- auths (no member record). Combined with Ω-E.1's RF-1 hardening, ghost
-- exposure was still wide open at the table layer.
--
-- Post-state: auth_org() looks up the caller's organization via
-- members.auth_id. Returns NULL for ghosts and inactive members.
--
-- Impact (30+ V4 tables using this helper):
--   - Real active members → see their org's data (same as before in single-org)
--   - Ghost auths (no member record) → NULL → blocked from org-scoped reads
--   - Inactive members (11 today) → NULL → blocked
--   - Superadmin → still bypasses via rls_is_superadmin() OR ... (every policy)
--   - PMI-CE pilot (future multi-tenant) → finally scopes correctly per caller
--
-- Performance: STABLE function (cached per-query). Uses partial index
-- idx_members_auth_id for sub-ms lookup. Net cost ~0 in steady state.
--
-- Rollback (if needed):
--   CREATE OR REPLACE FUNCTION auth_org() RETURNS uuid
--   LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
--   AS $$ SELECT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid $$;
-- =====================================================================

CREATE OR REPLACE FUNCTION public.auth_org()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT m.organization_id
  FROM public.members m
  WHERE m.auth_id = auth.uid()
    AND m.is_active = true
  ORDER BY m.created_at DESC
  LIMIT 1
$function$;

COMMENT ON FUNCTION public.auth_org() IS
  'Returns calling auth user''s organization_id via members.auth_id lookup. NULL for ghost/inactive. Used by 30+ V4 RLS policies for org scoping. STABLE (per-query cache, partial idx_members_auth_id).';
