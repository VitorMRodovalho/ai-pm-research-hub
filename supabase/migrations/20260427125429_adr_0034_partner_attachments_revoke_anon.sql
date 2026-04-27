-- ADR-0034 Phase 2 (p66) defense-in-depth REVOKE
-- pg_policy precondition: zero RLS refs verified pre-apply.

REVOKE EXECUTE ON FUNCTION public.add_partner_attachment(uuid, uuid, text, text, integer, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.delete_partner_attachment(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_partner_entity_attachments(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_partner_interaction_attachments(uuid) FROM PUBLIC, anon;
