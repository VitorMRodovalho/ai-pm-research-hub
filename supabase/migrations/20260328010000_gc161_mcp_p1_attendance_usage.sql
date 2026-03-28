-- GC-161: MCP P1 — get_my_attendance_history RPC + mcp_usage_log infrastructure
-- Applied via Supabase MCP on 2026-03-28

BEGIN;

-- PART 1: get_my_attendance_history RPC
CREATE OR REPLACE FUNCTION get_my_attendance_history(p_limit int DEFAULT 20)
RETURNS TABLE(event_id uuid, event_title text, event_type text, event_date date, duration_minutes int, present boolean, excused boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
DECLARE v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT e.id, e.title, e.type, e.date, e.duration_minutes,
    COALESCE(a.present, false), COALESCE(a.excused, false)
  FROM events e LEFT JOIN attendance a ON a.event_id = e.id AND a.member_id = v_member_id
  WHERE e.date <= CURRENT_DATE ORDER BY e.date DESC LIMIT p_limit;
END; $$;
GRANT EXECUTE ON FUNCTION get_my_attendance_history(int) TO authenticated;

-- PART 2: mcp_usage_log
CREATE TABLE IF NOT EXISTS mcp_usage_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id uuid REFERENCES members(id),
  auth_user_id uuid,
  tool_name text NOT NULL,
  success boolean DEFAULT true,
  error_message text,
  execution_ms int,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX idx_mcp_usage_log_member ON mcp_usage_log(member_id, created_at DESC);
CREATE INDEX idx_mcp_usage_log_tool ON mcp_usage_log(tool_name, created_at DESC);
ALTER TABLE mcp_usage_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY mcp_usage_log_select_admin ON mcp_usage_log FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role IN ('manager','deputy_manager'))));

CREATE OR REPLACE FUNCTION log_mcp_usage(p_auth_user_id uuid, p_member_id uuid, p_tool_name text, p_success boolean DEFAULT true, p_error_message text DEFAULT NULL, p_execution_ms int DEFAULT NULL)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
  INSERT INTO mcp_usage_log (auth_user_id, member_id, tool_name, success, error_message, execution_ms)
  VALUES (p_auth_user_id, p_member_id, p_tool_name, p_success, p_error_message, p_execution_ms);
$$;
GRANT EXECUTE ON FUNCTION log_mcp_usage TO authenticated;

CREATE OR REPLACE FUNCTION get_mcp_adoption_stats()
RETURNS json LANGUAGE sql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
  SELECT json_build_object(
    'total_calls', COUNT(*), 'unique_users', COUNT(DISTINCT member_id),
    'calls_last_7d', COUNT(*) FILTER (WHERE created_at > now() - interval '7 days'),
    'users_last_7d', COUNT(DISTINCT member_id) FILTER (WHERE created_at > now() - interval '7 days'),
    'top_tools', (SELECT json_agg(row_to_json(t)) FROM (SELECT tool_name, COUNT(*) as calls, COUNT(DISTINCT member_id) as users FROM mcp_usage_log WHERE success = true GROUP BY tool_name ORDER BY calls DESC LIMIT 10) t),
    'error_rate', ROUND(COUNT(*) FILTER (WHERE success = false)::numeric / NULLIF(COUNT(*), 0) * 100, 1)
  ) FROM mcp_usage_log;
$$;
GRANT EXECUTE ON FUNCTION get_mcp_adoption_stats() TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
