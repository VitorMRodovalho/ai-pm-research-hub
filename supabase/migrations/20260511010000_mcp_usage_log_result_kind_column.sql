-- ADR-0018 W3 prerequisite (Track T, 2026-04-24 p44 extended):
-- Distinguish preview vs execute calls in mcp_usage_log so W3 anomaly detection
-- cron can accurately count destructive EXECUTIONS (not previews).
--
-- Security-engineer recommended this split during p44 Track R review.
-- Defaults to 'execute' — existing rows and callers unchanged; only the 5
-- preview branches in nucleo-mcp (drop_event_instance, delete_card,
-- archive_card, manage_initiative_engagement[remove], offboard_member)
-- will pass 'preview'.

ALTER TABLE mcp_usage_log
  ADD COLUMN result_kind text NOT NULL DEFAULT 'execute'
  CHECK (result_kind IN ('preview', 'execute'));

COMMENT ON COLUMN mcp_usage_log.result_kind IS
  'ADR-0018 W1/W3: "preview" when a destructive tool returned a preview payload (confirm!=true); "execute" when the underlying RPC was actually invoked. Default "execute" preserves historical rows.';

-- Replace RPC to accept new optional result_kind (DROP + CREATE required
-- because param count changes; CREATE OR REPLACE would reject).
DROP FUNCTION IF EXISTS log_mcp_usage(uuid, uuid, text, boolean, text, int);

CREATE FUNCTION log_mcp_usage(
  p_auth_user_id uuid,
  p_member_id uuid,
  p_tool_name text,
  p_success boolean DEFAULT true,
  p_error_message text DEFAULT NULL,
  p_execution_ms int DEFAULT NULL,
  p_result_kind text DEFAULT 'execute'
) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
  INSERT INTO mcp_usage_log (auth_user_id, member_id, tool_name, success, error_message, execution_ms, result_kind)
  VALUES (p_auth_user_id, p_member_id, p_tool_name, p_success, p_error_message, p_execution_ms, p_result_kind);
$$;

GRANT EXECUTE ON FUNCTION log_mcp_usage TO authenticated;

NOTIFY pgrst, 'reload schema';
