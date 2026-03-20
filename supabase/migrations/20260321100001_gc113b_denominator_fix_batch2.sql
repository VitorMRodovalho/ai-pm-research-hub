-- GC-113b: Fix future events denominator in 4 RPCs
-- All RPCs counted future events in attendance rate denominators,
-- making rates appear much lower than reality.
--
-- Fix pattern: add AND e.date <= CURRENT_DATE to event queries
-- Fix 4 (portfolio): add 'overdue' status for past-due items
--
-- Applied via execute_sql; this file records the changes for git history.
-- Affected RPCs:
--   1. exec_cross_tribe_comparison — 6 queries bounded
--   2. exec_tribe_dashboard — 5 queries bounded
--   3. get_annual_kpis — 4 v_cycle_end replaced with LEAST(v_cycle_end, CURRENT_DATE)
--   4. get_portfolio_dashboard — added 'overdue' WHEN clause before 'on_track'

NOTIFY pgrst, 'reload schema';
