-- #1383 Wave 6b (knowledge/gamification/admin/audit/lgpd) raw-side hardening.
-- (1) knowledge_assets_latest is SECDEF but only service_role held EXECUTE, so authenticated MCP
--     callers hit "permission denied" (2/2 fails/180d). Its content is non-personal narrative
--     knowledge (ADR-0010). GRANT authenticated so the semantic knowledge_search 'latest' mode works.
-- (2) REVOKE anon/PUBLIC EXECUTE drift on 10 admin/audit/lgpd RPCs. Every one is fail-closed
--     internally (manage_platform / view_chapter_dashboards / view_internal_analytics / manage_member
--     / self-scope), so the anon/PUBLIC grant is unnecessary attack surface (#965 trap). Keep
--     authenticated. Public feeds (get_public_impact_data, get_public_trail_ranking,
--     get_cpmai_leaderboard) are intentionally left anon and are NOT touched here.

-- (1) knowledge_assets_latest reachable to authenticated
GRANT EXECUTE ON FUNCTION public.knowledge_assets_latest(text, integer) TO authenticated;

-- (2) REVOKE anon/PUBLIC on fail-closed admin/audit/lgpd RPCs (keep authenticated)
REVOKE EXECUTE ON FUNCTION public.exec_cycle_report(text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.export_audit_log_csv(text, text, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_admin_dashboard() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_audit_log(uuid, uuid, text, timestamptz, timestamptz, integer, integer) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_pii_access_log(integer) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_vep_divergence_report() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_volunteer_funnel_stats(uuid) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_ai_suggestions(uuid, text, boolean) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.lgpd_execute_retroactive_deletion(uuid, uuid, text, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.lgpd_record_retroactive_notification(uuid, text, text, text, timestamptz) FROM anon, PUBLIC;
