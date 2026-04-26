-- Track R batch 2 — pg_graphql anon table exposure REVOKE Phase R2
-- See docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md (Track R section).
--
-- Phase R2 per-policy review of 70 tables that retained anon SELECT after
-- batch 1 (because their RLS policies could permit anon reads). Per-policy
-- examination via pg_policy.polqual + pg_policy.polroles classified each:
--
-- A. RLS USING `false` (rpc_only_deny_all): RLS denies all anon reads
--    regardless of grant. REVOKE-safe — defense-in-depth, no behavior
--    change. (14 tables)
-- B. RLS USING `auth.uid() = ...` (member-scoped): anon's auth.uid() is
--    NULL → policy fails → 0 rows. REVOKE-safe. (7 tables)
-- C. RLS USING `rls_is_member()` or `auth.role() = 'authenticated'`:
--    explicit non-anon gate. REVOKE-safe. (2 tables)
-- D. RLS USING `org_id = auth_org() OR org_id IS NULL` (V4 org-scope):
--    anon's auth_org() returns NULL after batch 3b REVOKE on auth_org()
--    → only rows with org_id IS NULL would be visible (rare).
--    Cross-referenced with .from() callers: only member/admin-tier flows
--    detected; queries always use MEMBER.id filter or admin context.
--    REVOKE-safe. (20 tables + visitor_leads SELECT-only)
-- E. z_archive.* legacy with public USING true: archived, 0 callers.
--    REVOKE-safe. (1 table)
-- F. impact_hours_total view (member-tier attendance.astro caller).
--    REVOKE-safe.
--
-- PRESERVED for Phase R3 (gamification.astro public-tier leaderboard
-- queries OR explicit public-by-design policies):
--   * public.gamification_points (loadLeaderboard may run for anon
--     when no JWT — intentional public leaderboard data per ADR-0024)
--   * public.courses (Public courses policy USING true + loadMyTrailClarity
--     may run for anon)
--   * public.tribe_selections (TribesSection homepage + gamification
--     leaderboard — anon access intentional)
--   * public.announcements, blog_posts, events, home_schedule,
--     tribe_meeting_slots, tribes, help_journeys, ia_pilots,
--     offboard_reason_categories, portfolio_kpi_quarterly_targets,
--     portfolio_kpi_targets, public_publications, quadrants,
--     release_items, releases, webinars (explicit public-by-design
--     policies; documented in audit doc)
--
-- Pattern: REVOKE SELECT ON <table> FROM anon.
-- INSERT/UPDATE/DELETE grants retained where present (e.g., visitor_leads
-- INSERT for "Anyone can submit lead" form).
-- authenticated + service_role grants retained throughout.

-- ============================================================
-- A. RLS USING `false` (rpc_only_deny_all) — RLS denies anon (14)
-- ============================================================
REVOKE SELECT ON public.blog_likes FROM anon;
REVOKE SELECT ON public.board_members FROM anon;
REVOKE SELECT ON public.board_source_tribe_map FROM anon;
REVOKE SELECT ON public.board_taxonomy_alerts FROM anon;
REVOKE SELECT ON public.campaign_recipients FROM anon;
REVOKE SELECT ON public.knowledge_insights_ingestion_log FROM anon;
REVOKE SELECT ON public.onboarding_progress FROM anon;
REVOKE SELECT ON public.partner_attachments FROM anon;
REVOKE SELECT ON public.selection_applications FROM anon;
REVOKE SELECT ON public.selection_committee FROM anon;
REVOKE SELECT ON public.selection_cycles FROM anon;
REVOKE SELECT ON public.selection_diversity_snapshots FROM anon;
REVOKE SELECT ON public.selection_evaluations FROM anon;
REVOKE SELECT ON public.selection_interviews FROM anon;

-- ============================================================
-- B. RLS USING `auth.uid() = ...` — member-scoped, anon fails (7)
-- ============================================================
REVOKE SELECT ON public.analysis_results FROM anon;
REVOKE SELECT ON public.comparison_results FROM anon;
REVOKE SELECT ON public.evm_analyses FROM anon;
REVOKE SELECT ON public.risk_simulations FROM anon;
REVOKE SELECT ON public.tia_analyses FROM anon;
REVOKE SELECT ON public.user_profiles FROM anon;
REVOKE SELECT ON public.campaign_sends FROM anon;

-- ============================================================
-- C. RLS USING `rls_is_member()` or `auth.role() = 'authenticated'` (2)
-- ============================================================
REVOKE SELECT ON public.publication_series FROM anon;
REVOKE SELECT ON public.tribe_deliverables FROM anon;

-- ============================================================
-- D. V4 org_scope only — member/admin-tier (20)
-- ============================================================
REVOKE SELECT ON public.annual_kpi_targets FROM anon;
REVOKE SELECT ON public.attendance FROM anon;
REVOKE SELECT ON public.board_items FROM anon;
REVOKE SELECT ON public.board_lifecycle_events FROM anon;
REVOKE SELECT ON public.board_sla_config FROM anon;
REVOKE SELECT ON public.certificates FROM anon;
REVOKE SELECT ON public.change_requests FROM anon;
REVOKE SELECT ON public.chapters FROM anon;
REVOKE SELECT ON public.comms_channel_config FROM anon;
REVOKE SELECT ON public.curation_review_log FROM anon;
REVOKE SELECT ON public.event_showcases FROM anon;
REVOKE SELECT ON public.member_activity_sessions FROM anon;
REVOKE SELECT ON public.member_cycle_history FROM anon;
REVOKE SELECT ON public.members FROM anon;
REVOKE SELECT ON public.meeting_artifacts FROM anon;
REVOKE SELECT ON public.partner_entities FROM anon;
REVOKE SELECT ON public.pilots FROM anon;
REVOKE SELECT ON public.project_boards FROM anon;
REVOKE SELECT ON public.project_memberships FROM anon;
REVOKE SELECT ON public.publication_submissions FROM anon;
REVOKE SELECT ON public.volunteer_applications FROM anon;

-- visitor_leads: REVOKE SELECT only (KEEP INSERT for "Anyone can submit lead")
REVOKE SELECT ON public.visitor_leads FROM anon;

-- ============================================================
-- E. z_archive.* legacy (4)
-- ============================================================
REVOKE SELECT ON z_archive.member_chapter_affiliations FROM anon;
REVOKE SELECT ON z_archive.portfolio_data_sanity_runs FROM anon;
REVOKE SELECT ON z_archive.publication_submission_events FROM anon;
REVOKE SELECT ON z_archive.presentations FROM anon;

-- ============================================================
-- F. View — impact_hours_total (member-tier attendance.astro)
-- ============================================================
REVOKE SELECT ON public.impact_hours_total FROM anon;
