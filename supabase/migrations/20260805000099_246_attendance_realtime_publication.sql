-- 20260805000099_246_attendance_realtime_publication.sql
--
-- Issue #246: /attendance grid does not refresh live during meetings — leaders must F5
-- to see new presence marks.
--
-- Root cause (grounded live 2026-06-03): `public.attendance` was never added to the
-- `supabase_realtime` publication (its peers `engagements` / `members` / `tribe_selections`
-- are), so Postgres emits NO logical-replication change events for it — any
-- `postgres_changes` subscription on `attendance` is silent. The frontend grid
-- (AttendanceGridTab) also had no subscription at all; that is wired in the same PR.
--
-- RLS is NOT a blocker: `attendance_read_members` (SELECT) = `rls_is_member()` is
-- permissive for authenticated members, so the realtime broadcast is delivered.
--
-- REPLICA IDENTITY FULL: so UPDATE/DELETE realtime payloads carry `event_id` + `member_id`
-- (and the prior row image for RLS filtering on updates). The default (`pkey`) only ships
-- the PK on the old image, which is not enough for the grid to locate the changed cell.
--
-- ROLLBACK:
--   ALTER PUBLICATION supabase_realtime DROP TABLE public.attendance;
--   ALTER TABLE public.attendance REPLICA IDENTITY DEFAULT;
--   NOTE: REPLICA IDENTITY DEFAULT = PK-only old image → DELETE/UPDATE realtime payloads
--   would lose event_id/member_id again. Do not treat DEFAULT as safe for this table.

-- Idempotent: ADD TABLE errors with duplicate_object if already published (re-apply / local reset).
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

ALTER TABLE public.attendance REPLICA IDENTITY FULL;
