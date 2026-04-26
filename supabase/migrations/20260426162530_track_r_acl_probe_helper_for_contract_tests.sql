-- Track R contract test helper — return ACL for a given function name.
-- Used by tests/contracts/track-r-auth-org-acl.test.mjs to assert that
-- auth_org() does not regain PUBLIC/anon/authenticated EXECUTE grant
-- in future migrations (which would silently undo Track R Phase R2
-- D-category 21-table protection).
--
-- Service-role only (REVOKE FROM PUBLIC, anon, authenticated).

CREATE OR REPLACE FUNCTION public._audit_function_acl(p_function_name text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'proname', p.proname,
    'sig', pg_get_function_identity_arguments(p.oid),
    'acl', COALESCE(array_to_string(p.proacl::text[], ' | '), 'NULL')
  )
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = p_function_name
  LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public._audit_function_acl(text) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._audit_function_acl(text) IS
  'Track R contract test helper (p59): returns ACL string for a given public-schema function name. Used by tests/contracts/track-r-auth-org-acl.test.mjs to enforce auth_org() ACL invariant. Service-role only.';

NOTIFY pgrst, 'reload schema';
