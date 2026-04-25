-- Track Q-C — audit helper RPC for orphan/drift coverage tests.
--
-- Used by tests/contracts/rpc-migration-coverage.test.mjs to enumerate
-- public-schema functions for migration-coverage assertions. Excludes
-- extension-owned functions dynamically via pg_depend so the test surface
-- stays current as extensions are added/removed.
--
-- Returns one row per (proname, identity_args, prosecdef) — overloads are
-- distinct rows; the contract test collapses them to names since "any
-- overload captured ⇒ name covered" is the relevant invariant for drift
-- prevention at this granularity.
--
-- Granted to authenticated + service_role; not anon. The rows expose only
-- pg_catalog metadata, no PII.

CREATE OR REPLACE FUNCTION public._audit_list_public_functions()
RETURNS TABLE(
  proname        text,
  identity_args  text,
  is_secdef      boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p.proname::text,
    pg_catalog.pg_get_function_identity_arguments(p.oid)::text,
    p.prosecdef
  FROM pg_catalog.pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.prokind = 'f'
    AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_depend d
      JOIN pg_catalog.pg_extension e ON e.oid = d.refobjid
      WHERE d.objid = p.oid AND d.deptype = 'e'
    )
  ORDER BY p.proname, p.oid;
$$;

REVOKE ALL ON FUNCTION public._audit_list_public_functions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._audit_list_public_functions() TO authenticated, service_role;

COMMENT ON FUNCTION public._audit_list_public_functions() IS
  'Track Q-C audit helper. Returns project-defined functions in public schema (extension-owned excluded via pg_depend). Used by tests/contracts/rpc-migration-coverage.test.mjs to compute orphan/drift coverage.';
