-- Issue #99 / ADR-0022 W2/W3: digest delivery health observability
-- Pattern 43 reuse — wraps the 2 weekly digest crons (member-digest + leader-digest)
-- + the older weekly-card-digest into one health snapshot. Closes the
-- observability gap noted in handoff_p78 (digest delivery, rare cadence,
-- high-impact when silent).
-- Authority: view_internal_analytics.
-- Rollback: DROP FUNCTION public.get_digest_health();

CREATE OR REPLACE FUNCTION public.get_digest_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_member_pending integer;
  v_jobs jsonb;
  v_health text;
  v_max_days_since integer;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  SELECT count(*)
  INTO v_member_pending
  FROM public.notifications
  WHERE delivery_mode = 'digest_weekly'
    AND digest_delivered_at IS NULL;

  SELECT jsonb_object_agg(jobname, snapshot)
  INTO v_jobs
  FROM (
    SELECT
      j.jobname,
      jsonb_build_object(
        'jobid', j.jobid,
        'schedule', j.schedule,
        'active', j.active,
        'last_run_at', (SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid),
        'last_status', (SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1),
        'days_since_last_run', (
          SELECT extract(epoch FROM (now() - max(start_time))) / 86400
          FROM cron.job_run_details d WHERE d.jobid = j.jobid
        ),
        'failed_runs_last_30d', (
          SELECT count(*) FROM cron.job_run_details d
          WHERE d.jobid = j.jobid AND d.status = 'failed' AND d.start_time >= now() - interval '30 days'
        )
      ) AS snapshot
    FROM cron.job j
    WHERE j.jobname IN ('send-weekly-member-digest', 'send-weekly-leader-digest', 'weekly-card-digest-saturday')
  ) sub;

  SELECT max(coalesce(days, 999))::integer INTO v_max_days_since
  FROM (
    SELECT extract(epoch FROM (now() - max(d.start_time))) / 86400 AS days
    FROM cron.job j
    LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
    WHERE j.jobname IN ('send-weekly-member-digest', 'send-weekly-leader-digest', 'weekly-card-digest-saturday')
    GROUP BY j.jobid
  ) t;

  v_health := CASE
    WHEN v_max_days_since <= 8 AND v_member_pending < 100 THEN 'green'
    WHEN v_max_days_since = 999 THEN 'yellow'
    WHEN v_member_pending > 0 AND v_max_days_since > 8 THEN 'red'
    WHEN v_member_pending >= 100 THEN 'yellow'
    ELSE 'yellow'
  END;

  RETURN jsonb_build_object(
    'member_digest_pending', v_member_pending,
    'cron_jobs', coalesce(v_jobs, '{}'::jsonb),
    'max_days_since_any_job_ran', v_max_days_since,
    'health_signal', v_health,
    'note', 'Weekly Saturday crons. days_since=999 means never ran (newly registered). pending>100 may indicate digest_weekly mode notifications accumulating without consumer (see issue #99 design gap on attendance_reminder + assignment_new not consumed by get_weekly_member_digest).',
    'fetched_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_digest_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_digest_health() TO authenticated;

COMMENT ON FUNCTION public.get_digest_health() IS
'Issue #99 / ADR-0022 W2/W3 (Pattern 43 reuse): digest delivery health snapshot. Wraps 3 weekly Saturday crons + count of digest_weekly notifications pending delivery. Authority: view_internal_analytics.';

NOTIFY pgrst, 'reload schema';
