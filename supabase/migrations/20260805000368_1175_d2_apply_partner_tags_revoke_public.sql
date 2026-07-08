-- #1175 D2 follow-up (found by the #965 PUBLIC-grant sweep during the #1181 integration):
-- migration 20260805000365 created apply_partner_chapter_tags and revoked EXECUTE from
-- anon and authenticated, but not from PUBLIC — postgres grants EXECUTE to PUBLIC on
-- CREATE FUNCTION by default, and anon/authenticated inherit through PUBLIC, so the
-- explicit per-role revokes were ineffective. The function is SECURITY DEFINER and
-- mutates selection_applications.tags; it must be callable only via the SECDEF
-- approval RPCs (admin_update_application / finalize_decisions) and service_role.
REVOKE ALL ON FUNCTION public.apply_partner_chapter_tags(uuid) FROM PUBLIC;

NOTIFY pgrst, 'reload schema';
