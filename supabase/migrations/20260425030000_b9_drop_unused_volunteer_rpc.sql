-- ============================================================
-- B9 — Drop unused list_volunteer_applications RPC
--
-- B9 audit (18/Abr/2026):
--   - volunteer_applications: 143 rows, all inserted 10/Mar bulk import,
--     zero writes since. Frozen historical snapshot.
--   - selection_applications: 80 rows, active since 14/Mar. Source of truth
--     for ongoing cycle 3 selection.
--   - list_volunteer_applications RPC: not called from frontend, MCP, or EF.
--     /admin/selection migrated to selection_applications (~14/Mar).
--   - volunteer_funnel_summary RPC + MCP tool #62 get_volunteer_funnel:
--     still functional but aggregates stale data (frozen 10/Mar). Migration
--     to selection_applications deferred to future session — not in B9 scope.
--
-- Decision: B9 is a no-op archive — keep volunteer_applications as
-- historical reference (cheap: 143 rows). Drop only the truly unused RPC.
--
-- Rollback: recreate RPC from 20260312030000_list_volunteer_applications_rpc.sql
-- ============================================================

DROP FUNCTION IF EXISTS public.list_volunteer_applications(integer, text, integer, integer);

NOTIFY pgrst, 'reload schema';
