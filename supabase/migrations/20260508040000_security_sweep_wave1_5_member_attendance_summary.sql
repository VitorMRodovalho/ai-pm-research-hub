-- Security sweep Onda 1.5 — mini-wave closing member_attendance_summary.
-- Zero callers verified (grep src/, EFs, scripts, pg_proc — all empty).
-- This view was likely designed for future self-service UX but never wired.
-- Conservative fix: flip invoker + revoke anon. Keep authenticated grant for
-- future code paths (RLS on members/attendance/events will restrict appropriately).
--
-- Closes 1 more ERROR advisor finding (5/11 → 4/11 remaining).
-- The 4 remaining need product pass (members_public_safe, public_members,
-- recurring_event_groups) or larger RPC refactor (gamification_leaderboard).

ALTER VIEW public.member_attendance_summary SET (security_invoker = true);
REVOKE SELECT ON public.member_attendance_summary FROM anon;
