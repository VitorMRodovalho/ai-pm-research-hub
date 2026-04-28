-- ADR-0061 W8: LGPD cron health observability (Pattern 43 reuse)
-- Wraps the 3 LGPD-critical monthly crons (anonymize-inactive, anonymize-by-kind,
-- log-retention) into one admin-facing health snapshot. Closes the equivalent
-- observability gap that W7 closed for invitations: pre-W8, silent failure of
-- monthly LGPD crons would only surface in pg_cron.job_run_details. Now an admin
-- can spot drift in one MCP call.
-- Authority: view_internal_analytics (org-wide audit-scope).
-- Rollback: DROP FUNCTION public.get_lgpd_cron_health();

CREATE OR REPLACE FUNCTION public.get_lgpd_cron_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_inactive_pending integer;
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

  SELECT count(*) INTO v_inactive_pending
  FROM public.members
  WHERE member_status IN ('alumni','observer','inactive')
    AND updated_at < now() - interval '5 years'
    AND (name IS NULL OR name NOT ILIKE 'Anonymous%');

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
        'last_message', (SELECT return_message FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1),
        'days_since_last_run', (
          SELECT extract(epoch FROM (now() - max(start_time))) / 86400
          FROM cron.job_run_details d WHERE d.jobid = j.jobid
        ),
        'failed_runs_last_90d', (
          SELECT count(*) FROM cron.job_run_details d
          WHERE d.jobid = j.jobid AND d.status = 'failed' AND d.start_time >= now() - interval '90 days'
        )
      ) AS snapshot
    FROM cron.job j
    WHERE j.jobname IN ('lgpd-anonymize-inactive-monthly', 'v4-anonymize-by-kind-monthly', 'log-retention-monthly')
  ) sub;

  -- Worst days-since-last-run across the 3 jobs (NULL counted as 999 — never ran)
  SELECT max(coalesce(days, 999))::integer INTO v_max_days_since
  FROM (
    SELECT extract(epoch FROM (now() - max(d.start_time))) / 86400 AS days
    FROM cron.job j
    LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
    WHERE j.jobname IN ('lgpd-anonymize-inactive-monthly', 'v4-anonymize-by-kind-monthly', 'log-retention-monthly')
    GROUP BY j.jobid
  ) t;

  -- Health: green if all jobs ran within 35 days (monthly cron + 4-day grace).
  -- Yellow if NULL last_run (newly registered, awaiting first firing) and pending=0.
  -- Red if any job has not run within 35 days and there's pending work.
  v_health := CASE
    WHEN v_max_days_since <= 35 THEN 'green'
    WHEN v_max_days_since = 999 AND v_inactive_pending = 0 THEN 'yellow'
    WHEN v_inactive_pending > 0 AND v_max_days_since > 35 THEN 'red'
    ELSE 'yellow'
  END;

  RETURN jsonb_build_object(
    'pending_anonymization_inactive_5y', v_inactive_pending,
    'cron_jobs', coalesce(v_jobs, '{}'::jsonb),
    'max_days_since_any_job_ran', v_max_days_since,
    'health_signal', v_health,
    'note', 'Monthly crons fire on 1st of month at 03:30/03:45/04:00 UTC. days_since=999 means never ran (newly registered).',
    'fetched_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_lgpd_cron_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_lgpd_cron_health() TO authenticated;

COMMENT ON FUNCTION public.get_lgpd_cron_health() IS
'ADR-0061 W8 (Pattern 43 reuse): LGPD compliance cron health snapshot. Wraps 3 monthly crons (anonymize-inactive, anonymize-by-kind, log-retention) + pending inactive-5y count. Authority: view_internal_analytics. Health: green (all <=35d), yellow (newly registered or pending unknown), red (pending work + cron silent >35d).';

NOTIFY pgrst, 'reload schema';
