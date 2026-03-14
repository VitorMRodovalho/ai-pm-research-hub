-- W139 Item 5: Remove deprecated functions not called by any frontend or trigger
-- Backup saved in docs/audit/DEPRECATED_FUNCTIONS_BACKUP.sql
-- Verified: no trigger bindings, no inter-function calls, no frontend references
--
-- NOTE: exec_funnel_v2 was originally listed but is called by exec_analytics_v2_quality
-- (which IS used by /admin/analytics). Keeping exec_funnel_v2 to avoid breaking analytics.

-- comms_metrics_latest — replaced by comms_metrics_latest_by_channel
DROP FUNCTION IF EXISTS public.comms_metrics_latest();

-- kpi_summary — replaced by exec_portfolio_health
DROP FUNCTION IF EXISTS public.kpi_summary();

-- move_board_item_to_board — duplicate of move_item_to_board
DROP FUNCTION IF EXISTS public.move_board_item_to_board(bigint, bigint, text);

-- finalize_decisions — legacy selection v1
DROP FUNCTION IF EXISTS public.finalize_decisions(uuid, jsonb);
