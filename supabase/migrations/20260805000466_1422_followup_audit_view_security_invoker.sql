-- #1422 follow-up — test-support audit RPC for view security_invoker state.
-- Recurrence guard for the security_definer_view drift class (see #1422): a later
-- CREATE OR REPLACE VIEW silently resets the security_invoker reloption, regressing a
-- remediated view to SECURITY DEFINER. The Supabase advisor-check detects this but is
-- external (fragile) and non-required. This RPC lets an in-repo contract test in the
-- required `validate` suite assert the critical identity/authority views stay invoker.
--
-- Pattern mirrors _audit_list_public_function_bodies() (test-support SECDEF reader).
-- Read-only: returns, per requested public view, whether it exists and whether it
-- carries security_invoker=true. service_role only (the contract test's role).

CREATE OR REPLACE FUNCTION public._audit_view_security_invoker(p_views text[])
RETURNS TABLE(view_name text, view_exists boolean, is_invoker boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
  SELECT v AS view_name,
         (c.oid IS NOT NULL) AS view_exists,
         COALESCE(c.reloptions::text LIKE '%security_invoker=true%', false) AS is_invoker
  FROM unnest(p_views) AS v
  LEFT JOIN pg_class c
    ON c.relname = v
   AND c.relkind = 'v'
   AND c.relnamespace = 'public'::regnamespace;
$$;

REVOKE ALL ON FUNCTION public._audit_view_security_invoker(text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_view_security_invoker(text[]) TO service_role;

COMMENT ON FUNCTION public._audit_view_security_invoker(text[]) IS
  'Test-support (service_role only): reports whether each named public view exists and has security_invoker=true. Backs the #1422 recurrence guard (tests/contracts/1422-critical-views-security-invoker.test.mjs).';
