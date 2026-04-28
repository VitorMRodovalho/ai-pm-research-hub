-- Performance P3 Wave 1: index the top 10 unindexed foreign keys by hot-path
-- impact. Tables small enough (<2400 rows / <1.5MB) that non-CONCURRENT index
-- creation is sub-second and safe on production.
-- Closes ~10/161 unindexed_foreign_keys advisor INFO entries.
--
-- Selection criteria: pg_total_relation_size DESC + recognizable hot-path
-- queries (auth lookup, leaderboard, notifications fanout, dashboard joins).
-- Audit excluded: cold audit fields (corrected_by, edited_by, registered_by,
-- anonymized_by, offboarded_by, track_decided_by) — low query rate.

CREATE INDEX IF NOT EXISTS idx_notifications_recipient_id ON public.notifications (recipient_id);
CREATE INDEX IF NOT EXISTS idx_notifications_actor_id ON public.notifications (actor_id);
CREATE INDEX IF NOT EXISTS idx_attendance_event_id ON public.attendance (event_id);
CREATE INDEX IF NOT EXISTS idx_attendance_member_id ON public.attendance (member_id);
CREATE INDEX IF NOT EXISTS idx_gamification_points_member_id ON public.gamification_points (member_id);
CREATE INDEX IF NOT EXISTS idx_members_auth_id ON public.members (auth_id);
CREATE INDEX IF NOT EXISTS idx_members_person_id ON public.members (person_id);
CREATE INDEX IF NOT EXISTS idx_members_organization_id ON public.members (organization_id);
CREATE INDEX IF NOT EXISTS idx_selection_applications_cycle_id ON public.selection_applications (cycle_id);
CREATE INDEX IF NOT EXISTS idx_board_items_assignee_id ON public.board_items (assignee_id);
