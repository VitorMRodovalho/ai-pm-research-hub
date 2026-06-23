-- #738 fix-forward: minimal probe so edge functions can have PostgREST verify a
-- caller's JWT signature and report its role. Replaces the removed unverified
-- atob() decode. Returns ONLY the caller's own role claim (no secret exposed);
-- PostgREST rejects forged/invalid-signature tokens before this runs.
CREATE OR REPLACE FUNCTION public.current_caller_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$ SELECT auth.role() $$;

REVOKE ALL ON FUNCTION public.current_caller_role() FROM public;
GRANT EXECUTE ON FUNCTION public.current_caller_role() TO anon, authenticated, service_role;
