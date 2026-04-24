-- ADR-0018 W3 (Track W3, 2026-04-24 p44 extended):
-- Scans mcp_usage_log for anomalous patterns and records alerts in admin_audit_log.
-- Runs via pg_cron every 15 minutes.
--
-- Patterns detected (all per member_id, minimum thresholds chosen conservatively
-- to minimize false positives on current ~300 events/48 tools/23-day baseline):
--   1. burst_execute — same tool executed 50+ times in 10 min
--   2. canv4_enumeration — 5+ Unauthorized failures in 10 min
--   3. destructive_burst — 10+ executes on destructive tools in 15 min
--   4. preview_without_execute — 5+ previews on destructive tool without
--      follow-up execute within 5min (injection rejected by human)
--
-- Dedup: won't insert same (target_id, pattern, tool_name) within 30min
-- window — prevents alert fatigue when pattern is sustained.
--
-- Output: admin_audit_log row with action='mcp_anomaly_detected', target_type='mcp_usage',
-- target_id=member_id, metadata jsonb with pattern + tool_name + count + window + severity.
-- Admin reads via existing superadmin RLS SELECT policy on admin_audit_log.

CREATE OR REPLACE FUNCTION detect_mcp_anomalies()
RETURNS TABLE(pattern text, member_id uuid, tool_name text, count bigint, inserted boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
DECLARE
  r record;
  v_exists boolean;
  v_destructive_tools text[] := ARRAY[
    'drop_event_instance',
    'delete_card',
    'archive_card',
    'offboard_member',
    'manage_initiative_engagement'
  ];
BEGIN
  -- Pattern 1: burst_execute (50+ same tool / 10min)
  FOR r IN
    SELECT
      l.member_id AS m_id,
      l.tool_name AS t_name,
      COUNT(*)::bigint AS c
    FROM mcp_usage_log l
    WHERE l.created_at > now() - interval '10 minutes'
      AND l.member_id IS NOT NULL
      AND l.success = true
      AND l.result_kind = 'execute'
    GROUP BY l.member_id, l.tool_name
    HAVING COUNT(*) >= 50
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM admin_audit_log
      WHERE action = 'mcp_anomaly_detected'
        AND target_id = r.m_id
        AND metadata->>'pattern' = 'burst_execute'
        AND metadata->>'tool_name' = r.t_name
        AND created_at > now() - interval '30 minutes'
    ) INTO v_exists;

    IF NOT v_exists THEN
      INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, metadata)
      VALUES (
        NULL, 'mcp_anomaly_detected', 'mcp_usage', r.m_id,
        jsonb_build_object(
          'pattern', 'burst_execute',
          'tool_name', r.t_name,
          'count', r.c,
          'window_minutes', 10,
          'threshold', 50,
          'severity', 'medium',
          'detected_at', now()
        )
      );
    END IF;

    RETURN QUERY SELECT 'burst_execute'::text, r.m_id, r.t_name, r.c, NOT v_exists;
  END LOOP;

  -- Pattern 2: canv4_enumeration (5+ Unauthorized / 10min)
  FOR r IN
    SELECT
      l.member_id AS m_id,
      NULL::text AS t_name,
      COUNT(*)::bigint AS c
    FROM mcp_usage_log l
    WHERE l.created_at > now() - interval '10 minutes'
      AND l.member_id IS NOT NULL
      AND l.success = false
      AND l.error_message LIKE 'Unauthorized%'
    GROUP BY l.member_id
    HAVING COUNT(*) >= 5
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM admin_audit_log
      WHERE action = 'mcp_anomaly_detected'
        AND target_id = r.m_id
        AND metadata->>'pattern' = 'canv4_enumeration'
        AND created_at > now() - interval '30 minutes'
    ) INTO v_exists;

    IF NOT v_exists THEN
      INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, metadata)
      VALUES (
        NULL, 'mcp_anomaly_detected', 'mcp_usage', r.m_id,
        jsonb_build_object(
          'pattern', 'canv4_enumeration',
          'tool_name', NULL,
          'count', r.c,
          'window_minutes', 10,
          'threshold', 5,
          'severity', 'high',
          'detected_at', now()
        )
      );
    END IF;

    RETURN QUERY SELECT 'canv4_enumeration'::text, r.m_id, NULL::text, r.c, NOT v_exists;
  END LOOP;

  -- Pattern 3: destructive_burst (10+ executes on destructive tools / 15min)
  FOR r IN
    SELECT
      l.member_id AS m_id,
      NULL::text AS t_name,
      COUNT(*)::bigint AS c
    FROM mcp_usage_log l
    WHERE l.created_at > now() - interval '15 minutes'
      AND l.member_id IS NOT NULL
      AND l.success = true
      AND l.result_kind = 'execute'
      AND l.tool_name = ANY(v_destructive_tools)
    GROUP BY l.member_id
    HAVING COUNT(*) >= 10
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM admin_audit_log
      WHERE action = 'mcp_anomaly_detected'
        AND target_id = r.m_id
        AND metadata->>'pattern' = 'destructive_burst'
        AND created_at > now() - interval '30 minutes'
    ) INTO v_exists;

    IF NOT v_exists THEN
      INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, metadata)
      VALUES (
        NULL, 'mcp_anomaly_detected', 'mcp_usage', r.m_id,
        jsonb_build_object(
          'pattern', 'destructive_burst',
          'tool_name', NULL,
          'count', r.c,
          'window_minutes', 15,
          'threshold', 10,
          'severity', 'high',
          'detected_at', now()
        )
      );
    END IF;

    RETURN QUERY SELECT 'destructive_burst'::text, r.m_id, NULL::text, r.c, NOT v_exists;
  END LOOP;

  -- Pattern 4: preview_without_execute (5+ previews on destructive tool without
  -- matching execute in 5min window / 15min lookback). Signal of cross-MCP
  -- injection where human rejected the confirmation step.
  FOR r IN
    SELECT
      p.member_id AS m_id,
      p.tool_name AS t_name,
      COUNT(*)::bigint AS c
    FROM mcp_usage_log p
    WHERE p.created_at > now() - interval '15 minutes'
      AND p.member_id IS NOT NULL
      AND p.success = true
      AND p.result_kind = 'preview'
      AND p.tool_name = ANY(v_destructive_tools)
      AND NOT EXISTS (
        SELECT 1 FROM mcp_usage_log e
        WHERE e.member_id = p.member_id
          AND e.tool_name = p.tool_name
          AND e.result_kind = 'execute'
          AND e.success = true
          AND e.created_at > p.created_at
          AND e.created_at < p.created_at + interval '5 minutes'
      )
    GROUP BY p.member_id, p.tool_name
    HAVING COUNT(*) >= 5
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM admin_audit_log
      WHERE action = 'mcp_anomaly_detected'
        AND target_id = r.m_id
        AND metadata->>'pattern' = 'preview_without_execute'
        AND metadata->>'tool_name' = r.t_name
        AND created_at > now() - interval '30 minutes'
    ) INTO v_exists;

    IF NOT v_exists THEN
      INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, metadata)
      VALUES (
        NULL, 'mcp_anomaly_detected', 'mcp_usage', r.m_id,
        jsonb_build_object(
          'pattern', 'preview_without_execute',
          'tool_name', r.t_name,
          'count', r.c,
          'window_minutes', 15,
          'threshold', 5,
          'severity', 'medium',
          'detected_at', now(),
          'hypothesis', 'possible cross-MCP prompt injection rejected by human via W1 confirm checkpoint'
        )
      );
    END IF;

    RETURN QUERY SELECT 'preview_without_execute'::text, r.m_id, r.t_name, r.c, NOT v_exists;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION detect_mcp_anomalies() IS
  'ADR-0018 W3: scans mcp_usage_log every 15min (via pg_cron) for anomalous patterns and records alerts in admin_audit_log. Returns detected rows for smoke-testing / manual review. Dedup via 30min window prevents alert fatigue.';

-- Allow execute from cron (postgres role owns cron jobs) + authenticated admins
-- for manual smoke. Non-admins see nothing useful since admin_audit_log SELECT
-- is superadmin-only.
GRANT EXECUTE ON FUNCTION detect_mcp_anomalies() TO authenticated;

-- Register pg_cron job: every 15 minutes
-- Safe re-run: unschedule existing if present
DO $$
DECLARE
  v_job_id bigint;
BEGIN
  SELECT jobid INTO v_job_id FROM cron.job WHERE jobname = 'mcp-anomaly-detection-15min';
  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;
  PERFORM cron.schedule(
    'mcp-anomaly-detection-15min',
    '*/15 * * * *',
    $cron$SELECT public.detect_mcp_anomalies()$cron$
  );
END $$;

NOTIFY pgrst, 'reload schema';
