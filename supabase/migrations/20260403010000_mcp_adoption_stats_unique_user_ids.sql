-- Add unique_user_ids to get_mcp_adoption_stats() for adoption dashboard MCP column
-- Previously returned unique_users count but not the actual member IDs

CREATE OR REPLACE FUNCTION get_mcp_adoption_stats()
RETURNS json LANGUAGE sql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
  SELECT json_build_object(
    'total_calls', COUNT(*),
    'unique_users', COUNT(DISTINCT member_id),
    'unique_user_ids', (SELECT json_agg(DISTINCT member_id) FROM mcp_usage_log WHERE member_id IS NOT NULL),
    'calls_last_7d', COUNT(*) FILTER (WHERE created_at > now() - interval '7 days'),
    'users_last_7d', COUNT(DISTINCT member_id) FILTER (WHERE created_at > now() - interval '7 days'),
    'top_tools', (
      SELECT json_agg(row_to_json(t)) FROM (
        SELECT tool_name, COUNT(*) as calls, COUNT(DISTINCT member_id) as users
        FROM mcp_usage_log WHERE success = true
        GROUP BY tool_name ORDER BY calls DESC LIMIT 10
      ) t
    ),
    'error_rate', ROUND(COUNT(*) FILTER (WHERE success = false)::numeric / NULLIF(COUNT(*), 0) * 100, 1),
    'route_health', (
      SELECT json_agg(row_to_json(rh) ORDER BY rh.tool_name) FROM (
        SELECT
          tool_name,
          COUNT(*) as total_calls,
          COUNT(*) FILTER (WHERE success = true) as success_count,
          COUNT(*) FILTER (WHERE success = false) as fail_count,
          ROUND(COUNT(*) FILTER (WHERE success = false)::numeric / NULLIF(COUNT(*), 0) * 100, 1) as error_rate,
          ROUND(AVG(execution_ms) FILTER (WHERE success = true)::numeric, 0) as avg_latency_ms,
          MAX(execution_ms) FILTER (WHERE success = true) as max_latency_ms,
          MAX(created_at) as last_call,
          MAX(created_at) FILTER (WHERE success = false) as last_error,
          (SELECT error_message FROM mcp_usage_log m2
           WHERE m2.tool_name = mcp_usage_log.tool_name AND m2.success = false
           ORDER BY m2.created_at DESC LIMIT 1) as last_error_message
        FROM mcp_usage_log
        GROUP BY tool_name
      ) rh
    ),
    'daily_calls', (
      SELECT json_agg(row_to_json(dc) ORDER BY dc.day) FROM (
        SELECT created_at::date as day, COUNT(*) as calls,
          COUNT(*) FILTER (WHERE success = true) as ok,
          COUNT(*) FILTER (WHERE success = false) as fail
        FROM mcp_usage_log
        WHERE created_at > now() - interval '30 days'
        GROUP BY created_at::date
      ) dc
    )
  ) FROM mcp_usage_log;
$$;

NOTIFY pgrst, 'reload schema';
