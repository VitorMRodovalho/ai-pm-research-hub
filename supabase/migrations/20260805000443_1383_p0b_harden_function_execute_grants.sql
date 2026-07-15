-- Tighten EXECUTE grants on a set of authenticated-only RPCs: drop the implicit
-- PUBLIC grant so these functions are reachable only by authenticated callers
-- (the web app + MCP) and service_role (EF/cron), not through the anon key.
--
-- Live ACL confirmed 2026-07-15 on all 8 targets carried the default PUBLIC (`=X`)
-- grant plus explicit `authenticated` and `service_role` grants, and no direct
-- `anon` grant. REVOKE ... FROM anon is therefore a no-op (anon's EXECUTE comes
-- purely from PUBLIC); REVOKE ... FROM PUBLIC is the effective change. `authenticated`
-- is re-GRANTed explicitly (idempotent) so the app can never lose access here.
--
-- Follow GC-097 / Track Q-C: applied to remote via apply_migration, then version
-- 20260805000443 registered in schema_migrations + NOTIFY pgrst.

REVOKE EXECUTE ON FUNCTION public.exec_portfolio_health(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.exec_portfolio_health(text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_pii_access_log_admin(uuid, uuid, integer, integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_pii_access_log_admin(uuid, uuid, integer, integer) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.link_partner_to_card(uuid, uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.link_partner_to_card(uuid, uuid, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.unlink_partner_from_card(uuid, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.unlink_partner_from_card(uuid, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.list_partner_cards(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_partner_cards(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.list_card_partners(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_card_partners(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.approve_change_request(uuid, text, text, inet, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.approve_change_request(uuid, text, text, inet, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.review_change_request(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.review_change_request(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
