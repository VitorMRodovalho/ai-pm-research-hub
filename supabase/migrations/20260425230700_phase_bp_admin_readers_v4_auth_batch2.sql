-- Track Q Phase B' — V4 auth migration of captured orphans (batch 2)
--
-- Migrates 5 admin-reader functions from p52 Q-A captures from legacy V3
-- authority (`is_superadmin OR manager OR deputy_manager`) to V4
-- `can_by_member('manage_platform')`. Same migration pattern as batch 1
-- (`20260425224208`).
--
-- Privilege expansion analysis (verified live data 2026-04-25):
--   Safety check returned: legacy_count=2, v4_count=2, would_gain=null,
--   would_lose=null. Zero authorization change in production today.
--   Future expansions: any deputy_manager + co_gp engagements would
--   gain access. All consistent with admin authority semantics.
--
-- Functions migrated:
--   1. get_governance_stats — change-request stats dashboard. Admin only.
--   2. get_member_transitions — member status transition history. Self-read
--      branch preserved + admin OR.
--   3. get_cron_status — pg_cron job status + last_run + recent failures.
--      Admin only.
--   4. get_platform_usage — DB/storage usage + member/event/notification
--      counts. Admin only.
--   5. get_cpmai_admin_dashboard — CPMAI course enrollment + completion
--      stats. Admin only.
--
-- NOT in batch (Phase B'' candidates):
--   - get_application_score_breakdown — has curator branch
--     (`designations && ARRAY['curator']`). manage_platform would TIGHTEN
--     authority (remove curators). Need new V4 action OR keep V3.
--
-- Bodies otherwise verbatim from p52 Q-A captures.

CREATE OR REPLACE FUNCTION public.get_governance_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;

  RETURN jsonb_build_object(
    'by_status', (
      SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb)
      FROM (SELECT status, count(*) as cnt FROM change_requests WHERE status IS NOT NULL GROUP BY status) t
    ),
    'by_type', (
      SELECT COALESCE(jsonb_object_agg(cr_type, cnt), '{}'::jsonb)
      FROM (SELECT cr_type, count(*) as cnt FROM change_requests WHERE cr_type IS NOT NULL GROUP BY cr_type) t
    ),
    'by_impact', (
      SELECT COALESCE(jsonb_object_agg(impact_level, cnt), '{}'::jsonb)
      FROM (SELECT impact_level, count(*) as cnt FROM change_requests WHERE impact_level IS NOT NULL GROUP BY impact_level) t
    ),
    'total', (SELECT count(*) FROM change_requests),
    'pending_review', (SELECT count(*) FROM change_requests WHERE status IN ('submitted', 'under_review')),
    'approved_not_implemented', (SELECT count(*) FROM change_requests WHERE status = 'approved'),
    'implemented', (SELECT count(*) FROM change_requests WHERE status = 'implemented'),
    'withdrawn', (SELECT count(*) FROM change_requests WHERE status = 'withdrawn')
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_member_transitions(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  -- Self-read OR platform admin
  IF v_caller.id != p_member_id
    AND NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  RETURN jsonb_build_object('transitions', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', t.id,
      'previous_status', t.previous_status,
      'new_status', t.new_status,
      'previous_tribe_id', t.previous_tribe_id,
      'new_tribe_id', t.new_tribe_id,
      'reason_category', t.reason_category,
      'reason_detail', t.reason_detail,
      'actor_name', m.name,
      'created_at', t.created_at
    ) ORDER BY t.created_at DESC)
    FROM member_status_transitions t
    LEFT JOIN members m ON m.id = t.actor_member_id
    WHERE t.member_id = p_member_id
  ), '[]'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_cron_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
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

CREATE OR REPLACE FUNCTION public.get_platform_usage()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_db_size bigint;
  v_storage_size bigint;
  v_member_count int;
  v_event_count int;
  v_notification_count int;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;
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
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_cpmai_admin_dashboard(p_course_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_course_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF p_course_id IS NOT NULL THEN
    v_course_id := p_course_id;
  ELSE
    SELECT id INTO v_course_id FROM cpmai_courses ORDER BY created_at DESC LIMIT 1;
  END IF;

  SELECT jsonb_build_object(
    'course', (SELECT row_to_json(c) FROM cpmai_courses c WHERE c.id = v_course_id),
    'enrollment_count', (SELECT count(*) FROM cpmai_enrollments WHERE course_id = v_course_id AND status IN ('active','completed')),
    'completed_count', (SELECT count(*) FROM cpmai_enrollments WHERE course_id = v_course_id AND status = 'completed'),
    'avg_progress_pct', (
      SELECT ROUND(AVG(sub.pct)::numeric, 1) FROM (
        SELECT e.id, COALESCE(count(*) FILTER (WHERE p.status='completed')::numeric / NULLIF(count(*),0) * 100, 0) as pct
        FROM cpmai_enrollments e LEFT JOIN cpmai_progress p ON p.enrollment_id = e.id
        WHERE e.course_id = v_course_id AND e.status = 'active'
        GROUP BY e.id
      ) sub
    ),
    'avg_mock_score', (SELECT ROUND(AVG(ms.score_pct)::numeric,1) FROM cpmai_mock_scores ms JOIN cpmai_enrollments e ON e.id=ms.enrollment_id WHERE e.course_id=v_course_id),
    'enrollments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',e.id,'member_name',m.name,'status',e.status,'enrolled_at',e.enrolled_at,'completed_at',e.completed_at,'ai_experience',e.ai_experience,
        'progress_pct',COALESCE((SELECT ROUND(count(*) FILTER (WHERE p.status='completed')::numeric / NULLIF(count(*),0)*100,1) FROM cpmai_progress p WHERE p.enrollment_id=e.id),0),
        'mock_best',(SELECT max(ms.score_pct) FROM cpmai_mock_scores ms WHERE ms.enrollment_id=e.id)
      ) ORDER BY e.enrolled_at)
      FROM cpmai_enrollments e JOIN members m ON m.id=e.member_id WHERE e.course_id=v_course_id
    ),'[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
