-- Audit helper for pg_policy precondition contract test (p65, Bug B sediment)
--
-- Returns SECDEF functions where:
--   1. authenticated EXECUTE is revoked (via has_function_privilege check)
--   2. AND the function name appears in any RLS policy qual or with_check
--      (word-boundary regex `\m(public\.)?<fn>\(` to avoid substring matches
--      across rls_can/can_by_member/can family — see false-alarm note in p65)
--
-- Used by tests/contracts/rpc-migration-coverage.test.mjs to enforce the
-- p64 incident lesson at CI time. Without this guard, future REVOKE EXECUTE
-- migrations on SECDEF helpers can silently break PostgREST table reads when
-- the helper is referenced inside an RLS policy expression — the policy
-- evaluates in caller's role context, requiring authenticated EXECUTE.
--
-- Cross-references:
--   - docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md § "Charter amendment — pg_policy
--     precondition (added p65, 2026-04-26 post-incident)"
--   - hotfix migrations 20260426232108 (auth_org) + 20260426232200
--     (can_by_member) — the original p64 incident remediation
--   - feedback_revoke_pg_policy_word_boundary.md (operational rule)

CREATE OR REPLACE FUNCTION public._audit_list_revoked_secdef_fns_with_rls_refs()
RETURNS TABLE(
  qualified_name text,
  args text,
  table_name text,
  policy_name text,
  policy_clause text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH revoked_fns AS (
    SELECT n.nspname AS schema_name,
           p.proname,
           p.oid AS proid,
           pg_catalog.pg_get_function_identity_arguments(p.oid) AS fn_args
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
  )
  SELECT (r.schema_name || '.' || r.proname)::text AS qualified_name,
         r.fn_args::text AS args,
         (pol.schemaname || '.' || pol.tablename)::text AS table_name,
         pol.policyname::text AS policy_name,
         (CASE
            WHEN pol.qual ~* ('\m(public\.)?' || r.proname || '\(') THEN 'qual'
            WHEN pol.with_check ~* ('\m(public\.)?' || r.proname || '\(') THEN 'with_check'
            ELSE 'unknown'
          END)::text AS policy_clause
  FROM revoked_fns r
  JOIN pg_catalog.pg_policies pol
    ON pol.qual ~* ('\m(public\.)?' || r.proname || '\(')
    OR pol.with_check ~* ('\m(public\.)?' || r.proname || '\(')
  ORDER BY r.proname, pol.tablename, pol.policyname;
$$;

REVOKE EXECUTE ON FUNCTION public._audit_list_revoked_secdef_fns_with_rls_refs()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_list_revoked_secdef_fns_with_rls_refs()
  TO service_role;

COMMENT ON FUNCTION public._audit_list_revoked_secdef_fns_with_rls_refs() IS
  'Audit helper (p65 Bug B sediment): lists SECDEF fns where authenticated EXECUTE is revoked AND the fn name is referenced in any RLS policy qual or with_check (word-boundary regex). p64 incident class — see Track Q-D charter amendment in docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md and hotfix migrations 20260426232108+232200. SECDEF, service_role only.';
