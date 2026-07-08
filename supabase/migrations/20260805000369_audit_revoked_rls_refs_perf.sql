-- p65 Bug B audit helper perf fix (flaked CI run 28911158115 + local full-suite runs on
-- #1186 with SQLSTATE 57014): the revoked_fns × pg_policies join evaluated the dynamic
-- regex against the pg_policies VIEW per pair, re-expanding pg_get_expr for every probe
-- (~138 revoked fns × ~509 policies) — 5.5s at rest vs the 8s statement timeout, so any
-- contention tipped it over. Materialize the policies once and pre-filter with a cheap
-- strpos before the regex: 5514ms → 122ms measured live 2026-07-08, identical output.
-- Semantics unchanged (same columns, same match rule, same ordering).
CREATE OR REPLACE FUNCTION public._audit_list_revoked_secdef_fns_with_rls_refs()
 RETURNS TABLE(qualified_name text, args text, table_name text, policy_name text, policy_clause text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  ),
  pols AS MATERIALIZED (
    SELECT schemaname, tablename, policyname, qual, with_check,
           lower(coalesce(qual, '') || ' ' || coalesce(with_check, '')) AS blob
    FROM pg_catalog.pg_policies
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
  JOIN pols pol
    ON strpos(pol.blob, lower(r.proname)) > 0
   AND (pol.qual ~* ('\m(public\.)?' || r.proname || '\(')
        OR pol.with_check ~* ('\m(public\.)?' || r.proname || '\('))
  ORDER BY r.proname, pol.tablename, pol.policyname;
$function$;

NOTIFY pgrst, 'reload schema';
