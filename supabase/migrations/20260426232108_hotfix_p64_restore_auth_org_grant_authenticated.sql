-- HOTFIX p64 — restore auth_org EXECUTE for authenticated/anon
--
-- Track Q-D batch 3b (migration 20260426145632) revoked EXECUTE on auth_org()
-- as "internal helper defense-in-depth", but missed that auth_org() is called
-- DIRECTLY by RLS policy `members_v4_org_scope` (RESTRICTIVE, polcmd='*',
-- polroles='{-}' = PUBLIC). RLS evaluation runs in caller's role context;
-- when authenticated queries any table that triggers a members read (directly
-- or via EXISTS subquery), PostgreSQL requires the authenticated role to have
-- EXECUTE on auth_org() — regardless of SECURITY DEFINER status.
--
-- Effect of the bad REVOKE: ALL authenticated PostgREST table reads that
-- trigger members RLS evaluation fail with "permission denied for function
-- auth_org". Tested via Sarah (curator, member_id 19b7ff75...): document_versions
-- read returned null → /governance/ip-agreement showed empty content →
-- she clicked sign by accident trying to make doc render → unintended signoff
-- on Adendo IP chain 47362201 at 23:04:10 UTC (separate revert needed).
--
-- Audit at hotfix time: auth_org() is called by 48 RLS policies — every
-- *_v4_org_scope policy on members, tribes, events, webinars, board_items,
-- chapters, meeting_artifacts, tribe_deliverables, publication_*,
-- public_publications, cycles, pilots, ia_pilots, project_boards,
-- project_memberships, volunteer_applications, announcements, blog_posts,
-- event_showcases, attendance, gamification_points, courses, partner_entities,
-- change_requests, curation_review_log, board_lifecycle_events, board_sla_config,
-- annual_kpi_targets, portfolio_kpi_*, selection_*, member_activity_sessions,
-- help_journeys, visitor_leads, comms_channel_config, initiative_kinds,
-- initiatives, engagement_kinds, persons, engagements, ekp,
-- initiative_member_progress.
--
-- Fix: restore the original GRANT from migration 20260411200000.
-- auth_org() is SECDEF and returns a constant UUID today (no PII, no
-- info disclosure) — the original revoke was paranoid without analysis of
-- RLS policy callers.
--
-- Long-term Track Q-D guidance amendment: REVOKE on internal helpers MUST
-- check pg_policy.polqual for direct function references before applying.
-- Will document in audit doc + add to Track Q-D charter.

GRANT EXECUTE ON FUNCTION public.auth_org() TO authenticated, anon;

COMMENT ON FUNCTION public.auth_org() IS
  'V4 org-resolution helper. SECDEF. EXECUTE granted to authenticated + anon
   because called directly by RLS policy members_v4_org_scope (RESTRICTIVE,
   PUBLIC) and 47 other *_v4_org_scope policies. REVOKE from authenticated
   breaks ALL table reads — see hotfix migration 20260426232108 + p64 incident.
   Track Q-D internal-helper REVOKE must check pg_policy.polqual references
   before applying.';
