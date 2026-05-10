-- =====================================================================
-- p138 Ω-E.2-b.b — mcp_usage_log: add response_summary jsonb column
-- =====================================================================
-- Discovered during p138 deploy validation: sync-artia EF has been
-- attempting to insert with `response_summary` field since inception,
-- but the column never existed. supabase-js silently swallowed the
-- 400 from PostgREST (await sb.from().insert() doesn't throw and the
-- EF doesn't destructure {data, error}). Result: 0 rows in
-- mcp_usage_log for any sync-artia tool_name despite 3 active crons
-- (jobid 11 weekly, 34 daily, 35 monthly) firing without errors.
--
-- Two paths considered:
--   (a) strip response_summary from EF, align with canonical RPC
--       log_mcp_usage pattern (loses observability)
--   (b) add the column, EF starts working, observability preserved
--
-- Choosing (b): pre-existing intent of the EF was to log rich
-- summary (folders_created, kpis_synced, etc.) — that's load-bearing
-- for debugging cron health. Adding the column is additive (NULL
-- default), no rewrite, no FK, no impact on existing 332 rows from
-- nucleo-mcp tools using log_mcp_usage RPC.
--
-- Side effect: my p138 commit 09362e3 (Ω-E.2-b) added organization_id
-- to the same failing inserts. This migration unblocks both fields.
--
-- Future: nucleo-mcp's log_mcp_usage RPC could be extended with
-- p_response_summary jsonb to align all writers under RPC pattern.
-- Out of scope here.
--
-- Rollback:
--   ALTER TABLE mcp_usage_log DROP COLUMN response_summary;
-- =====================================================================

ALTER TABLE public.mcp_usage_log
  ADD COLUMN IF NOT EXISTS response_summary jsonb;

COMMENT ON COLUMN public.mcp_usage_log.response_summary IS
  'Optional rich summary of tool execution result (e.g., sync-artia logs folders_created/activities_created/kpis_synced). Nullable. Used by direct-insert EFs (sync-artia); nucleo-mcp tools use log_mcp_usage RPC and leave this NULL.';

NOTIFY pgrst, 'reload schema';
