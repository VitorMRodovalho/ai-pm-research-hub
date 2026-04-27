-- ADR-0033 Phase 1 (p66) defense-in-depth REVOKE
-- pg_policy precondition: zero RLS refs verified pre-apply.

REVOKE EXECUTE ON FUNCTION public.admin_manage_partner_entity(text, uuid, text, text, text, date, text, text, text, text, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_update_partner_status(uuid, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_partner_pipeline() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.auto_generate_cr_for_partnership(uuid) FROM PUBLIC, anon;
