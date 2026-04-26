-- Track Q-D batch 3a.8 — legacy/utility readers REVOKE
-- See docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md (Phase Q-D charter).
--
-- 32 fns triaged in legacy/utility bucket via per-fn body + callsite review:
--   * 9 dead readers (no callers in src/ or supabase/functions/) → full lock-down
--   * 2 service-role-only callers (MCP EF only) → full lock-down
--     (MCP tools authenticate via service_role; `authenticated` grant unused)
--   * 19 member-tier readers → REVOKE FROM PUBLIC, anon (keep authenticated)
--   * 2 verified public-by-design (docs-only, no migration):
--       - get_manual_sections (governance.astro public; dev comment marks anon-safe;
--         returns public regulamento sections)
--       - get_gp_whatsapp (help.astro intentional GP contact exposure for support)
--
-- Pattern:
--   REVOKE FROM PUBLIC, anon, authenticated  → fns with no human caller
--   REVOKE FROM PUBLIC, anon                 → fns with verified bail-on-no-member
--                                              client guards (member-tier readers)
-- postgres + service_role retained throughout (cron + MCP/EF still work).
--
-- No body change. No new gate added. No privilege expansion.

-- (a) Dead readers (0 callers in src/ + supabase/functions/) — full lock-down
REVOKE EXECUTE ON FUNCTION public.get_communication_template(text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_event_audience(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_manual_diff() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_platform_setting(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_publication_detail(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_section_change_history(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.list_admin_links() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tribe_impact_ranking() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.why_denied(uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;

-- (b) Service-role-only callers (MCP EF only — calls go via service_role) — full lock-down
REVOKE EXECUTE ON FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.search_partner_cards(text, text, text, integer) FROM PUBLIC, anon, authenticated;

-- (c) Member-tier readers — REVOKE FROM PUBLIC, anon (keep authenticated for admin UI / member pages)
-- All callers verified to bail on `!member` client-side OR sit behind an admin-tier gate.
REVOKE EXECUTE ON FUNCTION public.get_card_timeline(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_event_tags(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_event_tags_batch(uuid[]) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_events_with_attendance(integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_global_research_pipeline() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_item_assignments(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_item_curation_history(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_member_cycle_xp(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_mirror_target_boards(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_near_events(uuid, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_previous_locked_version(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_publication_pipeline_summary() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_publication_submission_detail(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_publication_submissions(submission_status, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_recent_events(integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_tags(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_cycles() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_radar_global(integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.search_hub_resources(text, text, integer) FROM PUBLIC, anon;
