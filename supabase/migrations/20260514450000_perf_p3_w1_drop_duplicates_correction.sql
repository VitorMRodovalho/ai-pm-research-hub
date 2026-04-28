-- Performance P3 Wave 1 CORRECTION: drop 7 duplicate indexes from previous
-- migration 20260514440000. The discovery query checked pg_index.indkey[0]
-- but the comparison missed indexes named with different conventions
-- (idx_attendance_event vs idx_attendance_event_id). Advisor flagged 5
-- duplicate_index post-deploy.
--
-- Pattern 46 sedimented: when verifying "is this FK already indexed?", do
-- a strict pg_index existence check by (indrelid, indkey[0]) without filtering
-- by index name — name conventions vary across migration eras.
--
-- Kept 3 real improvements with no prior coverage:
--   idx_members_auth_id          (used on EVERY authed request)
--   idx_members_organization_id  (multi-org isolation predicate)
--   idx_notifications_actor_id   (admin "by actor" lookups)

DROP INDEX IF EXISTS public.idx_attendance_event_id;
DROP INDEX IF EXISTS public.idx_attendance_member_id;
DROP INDEX IF EXISTS public.idx_board_items_assignee_id;
DROP INDEX IF EXISTS public.idx_gamification_points_member_id;
DROP INDEX IF EXISTS public.idx_members_person_id;
DROP INDEX IF EXISTS public.idx_notifications_recipient_id;
DROP INDEX IF EXISTS public.idx_selection_applications_cycle_id;
