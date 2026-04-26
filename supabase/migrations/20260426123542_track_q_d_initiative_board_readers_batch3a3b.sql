-- Track Q-D — initiative/board member-tier readers hardening (batch 3a.3b)
--
-- Continuation of p58 batch 3a.3a. After 3a.3a (4 fns dead/internal
-- REVOKE-only), this batch tightens 18 member-tier readers via
-- REVOKE-from-anon (keep authenticated for member UI callers).
--
-- Per-page tier verification (this commit):
-- - All 18 fns are called from member-tier pages where client-side
--   navGetMember() bails the script before the rpc call:
--   - initiative/[id].astro, tribe/[id].astro, profile.astro
--     (currentMember = navGetMember() pattern)
--   - initiatives.astro (if !sb || !member return)
--   - admin/portfolio.astro (if !member return false)
--   - PresentationLayer.astro (if !member return)
--   - TribeKanbanIsland.tsx, PublicationsBoardIsland.tsx
--     (if !member return false)
--   - TribeAttendanceTab.tsx, TribeGamificationTab.tsx (use navGetMember)
-- - React island components (BoardActivitiesView, CardDetail,
--   InitiativeBoardWrapper, etc.) only render when their parent page
--   has loaded a member; effectively member-tier.
-- - search_initiative_board_items only callsite is MCP tool (runs as
--   authenticated user via OAuth2.1 → JWT → PostgREST authenticated
--   role).
--
-- Treatment: REVOKE EXECUTE FROM PUBLIC, anon (KEEP authenticated,
-- postgres, service_role). Anon callers (e.g., direct PostgREST
-- requests with the ANON key) will receive permission denied;
-- authenticated members get unchanged access.
--
-- Excluded from 3a.3b (kept public-by-design):
-- - list_meeting_artifacts(integer, integer) — published meeting
--   recordings/artifacts. Caller: presentations.astro (page only
--   checks `!sb`, NOT `!member` — public showcase pattern matching
--   Public Path /presentations). Returns ma.* from meeting_artifacts
--   filtered by is_published=true. Columns audited (this commit):
--   id, event_id, title, meeting_date, recording_url, agenda_items,
--   page_data_snapshot, cycle_code, created_by, is_published,
--   deliberations, organization_id, initiative_id. No PII columns
--   (no email/phone/auth_id leaks). Documented as verified
--   public-by-design (Q-D batch 2 pattern extended).
--
-- Post-state: each fn ACL = postgres + authenticated + service_role.
-- Anon explicitly removed.
--
-- Risk assessment: low. Frontend pages do client-side member checks
-- BEFORE calling these RPCs, so legitimate auth flow unaffected.
-- Direct anon-key PostgREST callers will hit permission denied —
-- this is the security improvement (closes the gap that Q-D was
-- chartered to address).

REVOKE EXECUTE ON FUNCTION public.get_board(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_board_activities(uuid, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_board_activities(uuid, uuid, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_board_by_domain(text, integer, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_board_tags(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_initiative_attendance_grid(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_initiative_detail(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_initiative_events_timeline(uuid, integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_initiative_gamification(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_initiative_members(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_initiative_stats(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_board_items(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_initiative_boards(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_initiative_deliverables(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_initiatives(text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_project_boards(integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_tribe_deliverables(integer, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.search_initiative_board_items(text, uuid) FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';
