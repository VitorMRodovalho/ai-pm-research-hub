-- Track Q-D — curation/governance readers hardening (batch 3a.6)
--
-- Discovery (p58 continuation, post 3a.5 + batch 1 amendment):
-- 22 SECDEF readers/helpers in curation/governance bucket. Per-fn
-- callsite + body analysis classified into:
--
-- (a) Live with authenticated callers — REVOKE-from-anon (9 fns):
-- - get_chain_workflow_detail(uuid) — approval chain workflow detail
--   (gates, signers, eligible_pending). Caller:
--   ReviewChainIsland.tsx + admin/governance/documents.astro. Body
--   uses operational_role for output formatting (display, not gate).
-- - get_cr_approval_status(uuid) — change_request approval status +
--   sponsor list. Caller: GovernanceApprovalTab.tsx. Body filters
--   sponsors via operational_role (display, not gate).
-- - get_decision_log(text) — wiki_pages query for governance/adr/*
--   paths. Caller: MCP tool. Returns ADR titles/summaries.
-- - get_document_detail(uuid) — full governance document detail
--   (current_version, active_chain, signed_gates, comments_total).
--   Caller: MCP tool. Has hard auth check (RAISE EXCEPTION).
-- - get_pending_ratifications() — pending ratifications for member
--   IP-2 sign flow. Caller: governance/ip-agreement.astro +
--   admin/governance/ip-ratification.astro + MCP. Soft auth check
--   (returns empty for non-member).
-- - get_version_diff(uuid, uuid, boolean) — version diff between
--   two document versions. Caller: MCP tool. Hard auth check.
-- - list_curation_board(text) — hub_resources curation board.
--   Caller: CuratorshipBoardIsland.tsx. No auth check (pre-existing
--   pattern; member-tier callsite); REVOKE-from-anon closes anon
--   gap.
-- - list_document_comments(uuid, boolean) — document version
--   comments with visibility filtering. Caller:
--   ClauseCommentDrawer.tsx + MCP. Soft auth + visibility filter
--   via curator/manager designations (display-time, not gate).
-- - list_document_versions(uuid) — version list for a document.
--   Caller: MCP tool. Soft auth check.
--
-- (b) Dead — REVOKE-only full lock-down (2 fns):
-- - get_curation_cross_board() — cross-board curation aggregator.
--   0 callers in src/, supabase/functions/. Returns board_items +
--   project_boards data.
-- - get_governance_preview() — change_requests aggregates by
--   category + manual_structure status. 0 callers (likely
--   superseded by get_governance_dashboard for admin views).
--
-- Out-of-scope (Phase B'' V3 admin gate candidates, 3 fns):
-- - get_change_requests(text, text) — V3 gate (is_superadmin +
--   operational_role + designations).
-- - get_governance_dashboard() — V3 gate.
-- - get_governance_documents(text) — V3 gate.
--
-- Excluded (already V4-compliant via can_by_member, 8 fns):
-- - get_chain_audit_report(uuid)
-- - get_chain_for_pdf(uuid)
-- - get_curation_dashboard()
-- - get_governance_change_log(...)
-- - get_governance_stats()
-- - get_ratification_reminder_targets(uuid)
-- - list_curation_pending_board_items()
-- - list_pending_curation(text)
--
-- Total: 11 fns triaged in batch 3a.6 (9 live REVOKE-from-anon +
-- 2 dead REVOKE-only). 3 V3 fns out-of-scope (Phase B''). 8 fns
-- already V4-compliant.
--
-- Risk: low. Authenticated callers via admin pages, member
-- components, and MCP preserved on the 9 live fns. Dead fns
-- become un-callable externally; postgres + service_role retained.

-- ============================================================
-- (a) Live with authenticated callers — REVOKE-from-anon
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.get_chain_workflow_detail(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_cr_approval_status(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_decision_log(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_document_detail(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_pending_ratifications() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_version_diff(uuid, uuid, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_curation_board(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_document_comments(uuid, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_document_versions(uuid) FROM PUBLIC, anon;

-- ============================================================
-- (b) Dead — REVOKE-only full lock-down
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.get_curation_cross_board() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_governance_preview() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
