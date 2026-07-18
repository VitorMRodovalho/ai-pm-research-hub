-- #1422 — restore security_invoker on two SECURITY DEFINER views flagged by the
-- (now-working) Supabase advisor check. Both are consumed only by postgres-owned
-- SECURITY DEFINER functions (invoker is functionally identical inside them) and by
-- zero direct frontend callsites; neither grants SELECT to anon. No RLS policy
-- references either view, so there is no security_invoker-view-in-RLS recursion risk.
--
-- auth_engagements: regressed to DEFINER because 20260805000341 (interim leader grant)
--   used CREATE OR REPLACE VIEW without restating the reloption, silently dropping the
--   security_invoker=true set in 20260508030000 (Onda 1). This restores that known-good
--   state (~3 months in prod) while keeping the interim-grant column logic intact.
-- v_active_members: DEFINER since creation (20260805000062), never flipped. As DEFINER +
--   authenticated write grants it bypassed the members_read hardening (20260805000243)
--   AND, being auto-updatable (single-table, simple WHERE), exposed a live UPDATE/DELETE
--   primitive over members that ran as postgres and bypassed members write RLS. The flip
--   bounds reads/writes to the caller's members RLS; the REVOKE below removes the write
--   surface entirely (defense-in-depth on a read-only reporting view).
--
-- Rollback:
--   ALTER VIEW public.auth_engagements SET (security_invoker = false);
--   ALTER VIEW public.v_active_members  SET (security_invoker = false);
--   GRANT INSERT, UPDATE, DELETE ON public.v_active_members TO authenticated;

ALTER VIEW public.auth_engagements SET (security_invoker = true);
ALTER VIEW public.v_active_members  SET (security_invoker = true);

-- v_active_members is a read-only reporting view over members; authenticated has no
-- legitimate reason to write through it (all 5 real callers are SECDEF/postgres).
REVOKE INSERT, UPDATE, DELETE ON public.v_active_members FROM authenticated;
