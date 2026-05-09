-- p133 ARM-10 hygiene: accelerate stale digest purge from monthly to weekly
-- Driver: 14d-30d window where digest_weekly notifications sit idle (consumed by digest = 7d/14d windows; purged = 30d).
-- Weekly cadence (Sunday 14h UTC, day after Saturday digest 12h UTC) closes the gap.
-- ADR-0022 W3 cadence refinement. Migration purely operational; no schema change.
-- Sediment: feedback_arm10_hygiene_purge_window.md captures rationale.

DO $do$
DECLARE
  v_old_jobid bigint;
  v_new_jobid bigint;
BEGIN
  -- Unschedule old monthly cron (jobid was 38, but query by jobname to be safe)
  SELECT jobid INTO v_old_jobid FROM cron.job WHERE jobname='digest-stale-purge-monthly';
  IF v_old_jobid IS NOT NULL THEN
    PERFORM cron.unschedule(v_old_jobid);
    RAISE NOTICE 'Unscheduled digest-stale-purge-monthly jobid=%', v_old_jobid;
  END IF;

  -- Schedule new weekly cron: every Sunday at 14:00 UTC (day after Saturday 12:00 UTC member digest)
  v_new_jobid := cron.schedule(
    'digest-stale-purge-weekly',
    '0 14 * * 0',
    'SELECT public.purge_stale_digest_notifications_cron();'
  );
  RAISE NOTICE 'Scheduled digest-stale-purge-weekly jobid=%', v_new_jobid;
END $do$;

-- Audit log entry recording the cadence change
INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
VALUES (
  NULL,
  'cron_cadence_change',
  'cron.job',
  NULL,
  jsonb_build_object(
    'job_name_old', 'digest-stale-purge-monthly',
    'job_name_new', 'digest-stale-purge-weekly',
    'schedule_old', '0 14 5 * *',
    'schedule_new', '0 14 * * 0',
    'rationale', 'ADR-0022 W3 hygiene: closes 14d-30d gap window where attendance_reminder/assignment_new fossils accumulated. Monthly cadence missed first window (2026-05-05 fired 0 times because cron created post-day-5).',
    'source', 'p133'
  )
);
