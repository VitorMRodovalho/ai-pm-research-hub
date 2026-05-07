-- ADR-0075 Amendment A follow-up: observability RPC for cv extraction pipeline.
-- Mirrors get_invitation_health (#97 W7) + get_lgpd_cron_health patterns.
-- Auth: view_internal_analytics (admin/GP).
--
-- Rollback: DROP FUNCTION IF EXISTS public.get_extraction_health();

CREATE OR REPLACE FUNCTION public.get_extraction_health()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_backlog int;
  v_completed_24h int;
  v_failed_24h int;
  v_last_success timestamptz;
  v_last_failure timestamptz;
  v_failure_samples jsonb;
  v_cron jsonb;
  v_health text;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  -- Backlog: eligible apps that the cron RPC will pick up
  SELECT count(*) INTO v_backlog
  FROM public.selection_applications
  WHERE consent_ai_analysis_at IS NOT NULL
    AND consent_ai_analysis_revoked_at IS NULL
    AND resume_url IS NOT NULL
    AND (cv_extracted_text IS NULL OR length(cv_extracted_text) = 0);

  -- 24h activity for cv extraction (purpose=enrichment + model_id starts with unpdf)
  SELECT
    count(*) FILTER (WHERE status = 'completed'),
    count(*) FILTER (WHERE status = 'failed'),
    max(created_at) FILTER (WHERE status = 'completed'),
    max(created_at) FILTER (WHERE status = 'failed')
  INTO v_completed_24h, v_failed_24h, v_last_success, v_last_failure
  FROM public.ai_processing_log
  WHERE purpose = 'enrichment'
    AND model_id LIKE 'unpdf@%'
    AND created_at >= now() - interval '24 hours';

  -- Sample 3 most-recent failure messages (for triage)
  SELECT jsonb_agg(row_to_json(t))
  INTO v_failure_samples
  FROM (
    SELECT
      application_id,
      created_at,
      substring(error_message FROM 1 FOR 200) AS error_message
    FROM public.ai_processing_log
    WHERE purpose = 'enrichment'
      AND model_id LIKE 'unpdf@%'
      AND status = 'failed'
      AND created_at >= now() - interval '24 hours'
    ORDER BY created_at DESC
    LIMIT 3
  ) t;

  -- Cron job stats (extract-cv-text-15min)
  SELECT jsonb_build_object(
    'jobname', j.jobname,
    'schedule', j.schedule,
    'active', j.active,
    'last_run_at', max(d.start_time),
    'last_status', (
      SELECT status FROM cron.job_run_details dx
      WHERE dx.jobid = j.jobid ORDER BY start_time DESC LIMIT 1
    ),
    'last_5_runs', (
      SELECT jsonb_agg(jsonb_build_object('start', start_time, 'status', status, 'msg', substring(return_message FROM 1 FOR 100)) ORDER BY start_time DESC)
      FROM (
        SELECT start_time, status, return_message
        FROM cron.job_run_details d2
        WHERE d2.jobid = j.jobid
        ORDER BY start_time DESC LIMIT 5
      ) t
    )
  )
  INTO v_cron
  FROM cron.job j
  LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
  WHERE j.jobname = 'extract-cv-text-15min'
  GROUP BY j.jobid, j.jobname, j.schedule, j.active;

  -- Signal:
  --   red    = backlog > 20 OR failures > 3x successes in 24h (with non-trivial volume)
  --   yellow = backlog > 5  OR any failures in 24h
  --   green  = backlog <= 5 AND no failures
  v_health := CASE
    WHEN v_backlog > 20 THEN 'red'
    WHEN v_completed_24h >= 3 AND v_failed_24h > v_completed_24h THEN 'red'
    WHEN v_backlog > 5 THEN 'yellow'
    WHEN v_failed_24h > 0 THEN 'yellow'
    ELSE 'green'
  END;

  RETURN jsonb_build_object(
    'backlog_eligible', v_backlog,
    'completed_24h', coalesce(v_completed_24h, 0),
    'failed_24h', coalesce(v_failed_24h, 0),
    'last_success_at', v_last_success,
    'last_failure_at', v_last_failure,
    'failure_samples_24h', coalesce(v_failure_samples, '[]'::jsonb),
    'cron', coalesce(v_cron, jsonb_build_object('error', 'cron job not found')),
    'health_signal', v_health,
    'fetched_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.get_extraction_health() IS
  'p117 ADR-0075 Amendment A: cv extraction pipeline health. Returns backlog + 24h activity + cron stats + health_signal (green/yellow/red). Auth: view_internal_analytics.';

NOTIFY pgrst, 'reload schema';
