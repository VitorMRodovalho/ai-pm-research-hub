-- Track Q-A Batch L — orphan recovery: misc readers (10 fns)
--
-- Captures live bodies as-of 2026-04-25 for misc reader surface
-- (selection result self-view, my tasks aggregate, notification badge,
-- impact hours scalar, platform settings/usage, tribe counts, cron health,
-- board tags + project timeline). Bodies preserved verbatim from
-- `pg_get_functiondef` — no behavior change.
--
-- Notes:
-- - get_cron_status crosses into cron.job + cron.job_run_details (pg_cron
--   extension schema); search_path is the default 'public' but cron schema
--   is reachable because pg_cron is installed at the cluster level.
-- - get_platform_usage references storage.objects (Supabase storage); same
--   cross-schema pattern.
-- - get_tribe_counts is INVOKER (only non-SECDEF function in this batch).
-- - get_my_selection_result deliberately suppresses rank disclosure unless
--   the application reaches a final status — anti-anxiety UX choice baked
--   into the reader.

CREATE OR REPLACE FUNCTION public.get_board_tags(p_board_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  -- First try tags from this specific board
  SELECT jsonb_agg(DISTINCT tag ORDER BY tag) INTO v_result
  FROM (SELECT unnest(tags) as tag FROM board_items WHERE board_id = p_board_id AND tags IS NOT NULL AND array_length(tags, 1) > 0) sub
  WHERE tag IS NOT NULL AND tag != '';

  -- If empty, fallback to tags from ALL active boards (global suggestions)
  IF v_result IS NULL OR jsonb_array_length(v_result) = 0 THEN
    SELECT jsonb_agg(DISTINCT tag ORDER BY tag) INTO v_result
    FROM (
      SELECT unnest(tags) as tag FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      WHERE pb.is_active = true AND bi.tags IS NOT NULL AND array_length(bi.tags, 1) > 0
    ) sub
    WHERE tag IS NOT NULL AND tag != '';
  END IF;

  RETURN COALESCE(v_result, '[]'::jsonb);
END; $function$;

CREATE OR REPLACE FUNCTION public.get_board_timeline(p_board_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_board record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  SELECT pb.* INTO v_board FROM project_boards pb WHERE pb.id = p_board_id;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', bi.id,
      'title', bi.title,
      'status', bi.status,
      'baseline_date', bi.baseline_date,
      'forecast_date', bi.forecast_date,
      'actual_completion_date', bi.actual_completion_date,
      'due_date', bi.due_date,
      'is_portfolio_item', coalesce(bi.is_portfolio_item, false),
      'assignee_id', bi.assignee_id,
      'assignee_name', m.name,
      'tags', bi.tags,
      'deviation_days', CASE
        WHEN bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
        THEN bi.forecast_date - bi.baseline_date
        ELSE 0 END,
      'activities', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'id', bic.id,
          'text', bic.text,
          'target_date', bic.target_date,
          'is_completed', bic.is_completed,
          'completed_at', bic.completed_at,
          'assigned_to', bic.assigned_to,
          'assigned_name', am.name
        ) ORDER BY bic.position)
        FROM board_item_checklists bic
        LEFT JOIN members am ON am.id = bic.assigned_to
        WHERE bic.board_item_id = bi.id
      ), '[]'::jsonb)
    ) ORDER BY
      COALESCE(bi.baseline_date, bi.forecast_date, bi.due_date, '2099-12-31'::date),
      bi.position)
    FROM board_items bi
    LEFT JOIN members m ON m.id = bi.assignee_id
    WHERE bi.board_id = p_board_id AND bi.status != 'archived'
  ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_cron_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
  ) THEN
    RETURN jsonb_build_object('error', 'Admin only');
  END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'jobs', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'jobid', j.jobid,
        'jobname', j.jobname,
        'schedule', j.schedule,
        'active', j.active,
        'last_run', (
          SELECT jsonb_build_object(
            'status', rd.status,
            'start_time', rd.start_time,
            'end_time', rd.end_time,
            'return_message', LEFT(rd.return_message, 500)
          )
          FROM cron.job_run_details rd
          WHERE rd.jobid = j.jobid
          ORDER BY rd.start_time DESC LIMIT 1
        ),
        'recent_failures', (
          SELECT count(*)
          FROM cron.job_run_details rd2
          WHERE rd2.jobid = j.jobid
            AND rd2.status = 'failed'
            AND rd2.start_time > now() - interval '7 days'
        ),
        'total_runs_7d', (
          SELECT count(*)
          FROM cron.job_run_details rd3
          WHERE rd3.jobid = j.jobid
            AND rd3.start_time > now() - interval '7 days'
        )
      ) ORDER BY j.jobname), '[]'::jsonb)
      FROM cron.job j
    ),
    'health', jsonb_build_object(
      'total_jobs', (SELECT count(*) FROM cron.job),
      'jobs_with_recent_failure', (
        SELECT count(DISTINCT rd.jobid)
        FROM cron.job_run_details rd
        WHERE rd.status = 'failed'
          AND rd.start_time > now() - interval '24 hours'
      ),
      'overall_status', CASE
        WHEN EXISTS (
          SELECT 1 FROM cron.job_run_details rd
          WHERE rd.status = 'failed'
          AND rd.start_time > now() - interval '24 hours'
        ) THEN 'warning'
        ELSE 'healthy'
      END
    ),
    'last_artia_sync', (
      SELECT jsonb_build_object(
        'synced_at', mul.created_at,
        'success', mul.success
      )
      FROM mcp_usage_log mul
      WHERE mul.tool_name = 'sync-artia'
      ORDER BY mul.created_at DESC
      LIMIT 1
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_impact_hours_excluding_excused()
 RETURNS numeric
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT round(sum(e.duration_minutes * att.present_count)::numeric / 60, 1)
  FROM events e
  JOIN (
    SELECT event_id, count(*) as present_count
    FROM attendance
    WHERE excused IS NOT TRUE
    GROUP BY event_id
  ) att ON att.event_id = e.id
  WHERE e.date >= '2026-01-01' AND e.date <= current_date;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_selection_result()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_apps jsonb;
  v_is_final boolean;
BEGIN
  SELECT id, email, name INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Find all applications matching this member's email (could be 2 for dual-track)
  SELECT coalesce(jsonb_agg(row_to_json(app_data) ORDER BY (app_data->>'created_at') DESC), '[]'::jsonb)
  INTO v_apps
  FROM (
    SELECT
      a.id as application_id,
      a.cycle_id,
      sc.cycle_code,
      sc.title as cycle_title,
      a.role_applied,
      a.promotion_path,
      a.status,
      a.created_at,
      -- Status is "final" if approved, converted, rejected, withdrawn, cancelled, or objective_cutoff
      a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled']) as is_final,
      -- Own scores (always visible when stage is complete)
      a.objective_score_avg as objective_score,
      a.interview_score,
      a.research_score,
      a.leader_score,
      -- Rank — ONLY shown when status is final (avoid oscillation anxiety)
      CASE
        WHEN a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled'])
        THEN a.rank_researcher
        ELSE NULL
      END as rank_researcher,
      CASE
        WHEN a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled'])
        THEN a.rank_leader
        ELSE NULL
      END as rank_leader,
      -- Breakdown of evaluations (own rows only)
      (
        SELECT jsonb_object_agg(
          e.evaluation_type,
          jsonb_build_object(
            'pert_score', e.weighted_subtotal,
            'submitted_at', e.submitted_at
          )
        )
        FROM selection_evaluations e
        WHERE e.application_id = a.id AND e.submitted_at IS NOT NULL
        AND e.evaluator_id IN (
          -- Average across evaluators — one row per type
          SELECT evaluator_id FROM selection_evaluations WHERE application_id = a.id AND submitted_at IS NOT NULL LIMIT 1
        )
      ) as own_evaluations_sample,
      -- Total pool size for relative context
      (
        SELECT count(*) FROM selection_applications sa2
        WHERE sa2.cycle_id = a.cycle_id
          AND sa2.role_applied = a.role_applied
          AND sa2.status NOT IN ('withdrawn','cancelled')
      ) as track_pool_size
    FROM selection_applications a
    JOIN selection_cycles sc ON sc.id = a.cycle_id
    WHERE lower(trim(a.email)) = lower(trim(v_caller.email))
  ) app_data;

  RETURN jsonb_build_object(
    'member_id', v_caller.id,
    'member_name', v_caller.name,
    'applications', v_apps,
    'note', 'Ranks são exibidos apenas após o status final da seleção. Durante o processo, você vê apenas seu status e notas próprias.'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_tasks(p_status_filter text DEFAULT 'all'::text, p_period_filter text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb;
  v_total_pending bigint;
  v_total_completed bigint;
  v_total_overdue bigint;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT jsonb_agg(row_data ORDER BY board_name, card_title, position) INTO v_result
  FROM (
    SELECT
      jsonb_build_object(
        'id', c.id,
        'board_id', pb.id,
        'board_name', pb.board_name,
        'card_id', bi.id,
        'card_title', bi.title,
        'card_status', bi.status,
        'text', c.text,
        'done', c.is_completed,
        'target_date', c.target_date,
        'completed_at', c.completed_at
      ) as row_data,
      pb.board_name,
      bi.title as card_title,
      c.position
    FROM board_item_checklists c
    JOIN board_items bi ON bi.id = c.board_item_id
    JOIN project_boards pb ON pb.id = bi.board_id
    WHERE pb.is_active = true
      AND bi.status != 'archived'
      AND c.assigned_to = v_member_id
      AND (p_status_filter = 'all'
        OR (p_status_filter = 'pending' AND c.is_completed = false)
        OR (p_status_filter = 'completed' AND c.is_completed = true))
      AND (p_period_filter = 'all'
        OR (p_period_filter = 'overdue' AND c.target_date < CURRENT_DATE AND c.is_completed = false)
        OR (p_period_filter = 'week' AND c.target_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 7)
        OR (p_period_filter = 'month' AND c.target_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30))
  ) sub;

  -- Summary counts
  SELECT
    count(*) FILTER (WHERE NOT c.is_completed),
    count(*) FILTER (WHERE c.is_completed),
    count(*) FILTER (WHERE NOT c.is_completed AND c.target_date < CURRENT_DATE)
  INTO v_total_pending, v_total_completed, v_total_overdue
  FROM board_item_checklists c
  JOIN board_items bi ON bi.id = c.board_item_id
  JOIN project_boards pb ON pb.id = bi.board_id
  WHERE pb.is_active AND bi.status != 'archived' AND c.assigned_to = v_member_id;

  RETURN jsonb_build_object(
    'tasks', COALESCE(v_result, '[]'::jsonb),
    'total_pending', v_total_pending,
    'total_completed', v_total_completed,
    'total_overdue', v_total_overdue
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_platform_setting(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ BEGIN RETURN (SELECT value FROM platform_settings WHERE key = p_key); END; $function$;

CREATE OR REPLACE FUNCTION public.get_platform_usage()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_db_size bigint; v_storage_size bigint; v_member_count int; v_event_count int; v_notification_count int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  SELECT pg_database_size(current_database()) INTO v_db_size;
  SELECT COALESCE(sum((metadata->>'size')::bigint), 0) INTO v_storage_size FROM storage.objects;
  SELECT count(*) INTO v_member_count FROM members WHERE is_active;
  SELECT count(*) INTO v_event_count FROM events;
  SELECT count(*) INTO v_notification_count FROM notifications;
  RETURN jsonb_build_object(
    'database', jsonb_build_object('used_bytes', v_db_size, 'used_mb', round(v_db_size / 1048576.0, 1), 'limit_mb', 500,
      'pct', round(100.0 * v_db_size / (500 * 1048576.0), 1),
      'status', CASE WHEN v_db_size > 400*1048576 THEN 'critical' WHEN v_db_size > 300*1048576 THEN 'warning' ELSE 'healthy' END),
    'storage', jsonb_build_object('used_bytes', v_storage_size, 'used_mb', round(v_storage_size / 1048576.0, 1), 'limit_mb', 1024,
      'pct', round(100.0 * v_storage_size / (1024 * 1048576.0), 1),
      'status', CASE WHEN v_storage_size > 800*1048576 THEN 'critical' WHEN v_storage_size > 600*1048576 THEN 'warning' ELSE 'healthy' END),
    'counts', jsonb_build_object('members', v_member_count, 'events', v_event_count, 'notifications', v_notification_count),
    'thresholds', jsonb_build_object('tier2_trigger', 'Any service > 80% of free limit', 'db_alert_mb', 400, 'storage_alert_mb', 800),
    'checked_at', now()
  );
END; $function$;

CREATE OR REPLACE FUNCTION public.get_tribe_counts()
 RETURNS TABLE(tribe_id integer, member_count bigint)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY SELECT ts.tribe_id, COUNT(*) FROM tribe_selections ts GROUP BY ts.tribe_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_unread_notification_count()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; v_count int;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN 0; END IF;
  SELECT count(*) INTO v_count FROM notifications WHERE recipient_id = v_member_id AND is_read = false;
  RETURN v_count;
END; $function$;
