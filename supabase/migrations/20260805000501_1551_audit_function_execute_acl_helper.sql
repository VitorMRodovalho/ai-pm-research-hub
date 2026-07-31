-- #1551 — reusable audit probe for EXECUTE privilege on public functions.
--
-- The contract guard for the ACL sweep needs to read privilege state, and this project
-- deliberately exposes no generic exec_sql (see the note in engagements-legal-basis-lgpd-
-- canonical.test.mjs). The house pattern is a dedicated SECURITY DEFINER _audit_* probe, e.g.
-- _audit_get_all_certificates_anon_execute. This one is generalised over a name array so the
-- next ACL guard reuses it instead of adding another single-purpose probe.
--
-- Reports EFFECTIVE privilege via has_function_privilege() rather than parsing proacl text.
-- That is the question that actually matters: a grant inherited from PUBLIC makes anon able
-- to execute just as surely as an explicit anon grant, and text parsing misses it.
--
-- Its own ACL is closed to service_role, which is the very invariant this migration series
-- exists to enforce.
--
-- Refs #1551

CREATE OR REPLACE FUNCTION public._audit_function_execute_acl(p_names text[])
RETURNS TABLE (
  proname text,
  identity_args text,
  anon_exec boolean,
  authenticated_exec boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p.proname::text,
         pg_get_function_identity_arguments(p.oid),
         has_function_privilege('anon', p.oid, 'EXECUTE'),
         has_function_privilege('authenticated', p.oid, 'EXECUTE')
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = ANY (p_names)
  ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);
$function$;

REVOKE ALL ON FUNCTION public._audit_function_execute_acl(p_names text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_function_execute_acl(p_names text[]) TO service_role;

COMMENT ON FUNCTION public._audit_function_execute_acl(p_names text[]) IS
  'Audit probe (#1551): effective anon/authenticated EXECUTE privilege for named public functions. service_role only.';
