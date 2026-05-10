-- =====================================================================
-- p138 Ω-E.2-b.c (C.3) — log_mcp_usage RPC: add p_response_summary jsonb
-- =====================================================================
-- Aligns canonical logging RPC with the new mcp_usage_log.response_summary
-- column added in p138 Ω-E.2-b.b (migration 20260522000000). Allows
-- nucleo-mcp tools (and any future caller) to optionally pass a rich
-- jsonb summary of execution results, instead of being limited to
-- success boolean + error_message text only.
--
-- Pre-state (created GC-161 2026-03-28, expanded result_kind 2026-05-11):
--   log_mcp_usage(p_auth_user_id uuid, p_member_id uuid, p_tool_name text,
--                 p_success boolean DEFAULT true,
--                 p_error_message text DEFAULT NULL,
--                 p_execution_ms integer DEFAULT NULL,
--                 p_result_kind text DEFAULT 'execute')
--   INSERT INTO mcp_usage_log (auth_user_id, member_id, tool_name,
--     success, error_message, execution_ms, result_kind)
--
-- Post-state: 8th param p_response_summary jsonb DEFAULT NULL added at
-- the end. Backward-compatible — all existing 7-arg callers (nucleo-mcp
-- index.ts:127) continue to work unchanged. New callers can opt-in.
--
-- DROP + CREATE required per CLAUDE.md GC-097 (parameter signature
-- change). Postgres overload resolution would otherwise leave the
-- old 7-arg function in place creating ambiguity.
--
-- Note: organization_id is intentionally NOT inserted by this RPC —
-- column DEFAULT auth_org() resolves to the caller's org (per p136
-- Ω-E.1.b auth_org() rewrite). For nucleo-mcp tools, auth.uid() is
-- the calling member's auth_id, so DEFAULT correctly attributes to
-- the member's organization (nucleo-mcp is single-tenant today, but
-- this scales to multi-tenant naturally).
--
-- Rollback:
--   DROP FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text,
--                                      integer, text, jsonb);
--   CREATE OR REPLACE FUNCTION public.log_mcp_usage(...) -- 7 params
-- =====================================================================

DROP FUNCTION IF EXISTS public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text);

CREATE OR REPLACE FUNCTION public.log_mcp_usage(
  p_auth_user_id uuid,
  p_member_id uuid,
  p_tool_name text,
  p_success boolean DEFAULT true,
  p_error_message text DEFAULT NULL::text,
  p_execution_ms integer DEFAULT NULL::integer,
  p_result_kind text DEFAULT 'execute'::text,
  p_response_summary jsonb DEFAULT NULL::jsonb
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  INSERT INTO mcp_usage_log (
    auth_user_id, member_id, tool_name,
    success, error_message, execution_ms, result_kind, response_summary
  )
  VALUES (
    p_auth_user_id, p_member_id, p_tool_name,
    p_success, p_error_message, p_execution_ms, p_result_kind, p_response_summary
  );
$function$;

COMMENT ON FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb) IS
  'Canonical logging RPC for MCP/EF tool usage. Inserts into mcp_usage_log with caller context. organization_id auto-derived via DEFAULT auth_org() (caller-scoped per ADR-0077). p_response_summary added p138 Ω-E.2-b.c — optional jsonb for rich tool execution summary; pass object directly (not JSON.stringify), supabase-js + PostgREST encode jsonb correctly.';

NOTIFY pgrst, 'reload schema';
