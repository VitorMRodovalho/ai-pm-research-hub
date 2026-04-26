-- HOTFIX p64 (part 2) — restore can_by_member EXECUTE for authenticated
--
-- Same incident as the auth_org hotfix. Track Q-D batch 3b (migration
-- 20260426145632) revoked EXECUTE on can_by_member() from authenticated as
-- "internal helper", justified by "100 SECDEF V4 admin fns + 1 EF (nucleo-mcp/
-- canV4 wrapper); EF runs as service_role; frontend never calls directly".
--
-- The audit missed that 13 RLS policies call can_by_member() DIRECTLY in their
-- USING/WITH CHECK clauses (verified post-incident via pg_policy.polqual
-- regex scan). Affected:
--   * document_versions_insert_admin
--   * document_versions_delete_drafts
--   * approval_chains_write_admin
--   * approval_chains_update_admin
--   * approval_chains_read_scoped
--   * approval_signoffs_read_scoped
--   * member_doc_sigs_read_self_or_admin
--   * document_comment_edits_read_scoped
--   * document_comments_read_visibility
--   * initiative_kinds_write_admin
--   * initiative_kinds_update_admin
--   * initiative_kinds_delete_admin
--   * imp_insert_write
--
-- For each, when authenticated triggers RLS evaluation, PostgreSQL needs
-- EXECUTE on can_by_member regardless of SECURITY DEFINER status. Result:
-- silent failure of every authenticated PostgREST read on these tables.
--
-- Restore the original GRANT (from migration 20260413400000_v4_phase4_engagement_permissions.sql).

GRANT EXECUTE ON FUNCTION public.can_by_member(uuid, text, text, uuid)
  TO authenticated, anon;

COMMENT ON FUNCTION public.can_by_member(uuid, text, text, uuid) IS
  'V4 authority gate (member_id wrapper around can()). SECDEF. EXECUTE granted
   to authenticated + anon because called directly by 13 RLS policies
   (document_versions, approval_chains, approval_signoffs, member_doc_sigs,
   document_comments, initiative_kinds, imp). Revoking from authenticated
   breaks PostgREST table reads — see hotfix migration 20260426232200 + p64
   incident. Track Q-D internal-helper REVOKE charter must check
   pg_policy.polqual references before applying.';
