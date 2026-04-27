-- ============================================================
-- ADR-0041 Section C: defense-in-depth REVOKE FROM anon
-- All 9 fns are SECURITY DEFINER + V4-gated; explicit anon revoke is
-- the established hardening pattern (cf. ADR-0035, ADR-0040).
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.create_document_comment(uuid, text, text, text, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_document_comments(uuid, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.resolve_document_comment(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.assign_curation_reviewer(uuid, uuid, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.assign_member_to_item(uuid, uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.submit_curation_review(uuid, text, jsonb, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.submit_for_curation(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.unassign_member_from_item(uuid, uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.publish_board_item_from_curation(uuid) FROM anon;

NOTIFY pgrst, 'reload schema';
