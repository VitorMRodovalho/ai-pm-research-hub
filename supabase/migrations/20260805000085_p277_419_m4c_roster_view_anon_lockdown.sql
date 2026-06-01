-- #419 metric 4 PR4-C (paired security remediation) — close the anon PII leak on the canonical roster view.
--
-- public.v_initiative_roster (the canonical member_count primitive shipped in PR4-A, mig 082; made
-- load-bearing on the tribe dashboard by PR4-C, mig 084) leaked member identity to ANON:
--   - Live (verified): SET ROLE anon; SELECT count(*), count(name) FROM public.v_initiative_roster -> 63 / 63.
--     anon could read person_id, member_id, NAME, role, kind across ALL initiatives via PostgREST.
--   - Root cause: mig 082 ran `REVOKE ALL ... FROM PUBLIC; GRANT SELECT TO authenticated, service_role`, but
--     pg_default_acl on schema public auto-grants anon ALL on every new relation/view at CREATE time, and a
--     REVOKE-FROM-PUBLIC does NOT strip a named-role (anon) grant. So anon retained SELECT.
--   - The view is also a SECURITY DEFINER view (security_invoker off) → it bypasses base-table RLS, which the
--     Supabase advisor flags at ERROR (security_definer_view; lint 0010). This violates the CLAUDE.md invariant
--     "anon/ghost gets nothing from PII tables; public data via SECURITY DEFINER RPCs only".
--
-- FIX (two parts):
--   1. ALTER VIEW ... SET (security_invoker = true): the view now honors the INVOKER's privileges + base-table
--      RLS. This is SAFE for every existing consumer because the ONLY two consumers are SECURITY DEFINER
--      functions — get_initiative_roster_count(uuid) and exec_tribe_dashboard(integer,text) — which run as the
--      definer (postgres, rolbypassrls=true), so they still see the full roster (count stays 6 for tribe 8).
--      There is no direct anon/authenticated caller of the view (consumer sweep: frontend + MCP both reach it
--      only through the SECDEF RPCs). Flipping to security_invoker also clears the advisor ERROR.
--   2. REVOKE the anon (and PUBLIC) grants and re-affirm authenticated + service_role. With anon's SELECT gone,
--      PostgREST no longer exposes the view to anon-key callers.
--
-- antes -> depois: has_table_privilege('anon', 'public.v_initiative_roster', 'SELECT') = true -> false;
--   anon row read 63 -> permission denied; advisor security_definer_view(v_initiative_roster) ERROR -> cleared;
--   get_initiative_roster_count(tribe-8 initiative) = 6 -> 6 (unchanged); exec_tribe_dashboard(8).members.total
--   = 6 -> 6 (unchanged). PG 17.6 (security_invoker supported). No function body changes here (view DDL only).

ALTER VIEW public.v_initiative_roster SET (security_invoker = true);

REVOKE ALL ON public.v_initiative_roster FROM anon;
REVOKE ALL ON public.v_initiative_roster FROM PUBLIC;
GRANT SELECT ON public.v_initiative_roster TO authenticated, service_role;
