-- p282 #411 Wave 2b — selection-stuck-scheduled-rescue daily cron
--
-- WHAT: _selection_stuck_scheduled_rescue_cron() — SECDEF service-role cron. Each run rescues
--       every application parked in interview_scheduled (open cycle) whose latest scheduled
--       interview is past the 48h grace window and was never conducted, by calling the Wave 1d
--       atomic RPC selection_rescue_stuck_interview (which cancels the lapsed interview, resets
--       the app + idempotency guard, and re-dispatches via notify — now cron-safe via mig 105).
--       Per-row BEGIN/EXCEPTION isolation; LIMIT 20/day (stuck is a small cohort); one aggregate
--       audit row (action selection.stuck_rescue_cron_run, actor_id NULL) — read by
--       get_cutoff_dispatch_health (already wired in mig 106). pg_cron at 15:00 UTC (after the
--       14:00 cutoff cron).
--
-- WHY: Issue #411 Wave 2b. Candidates whose evaluator never accepted the Calendar invite sat
--       12 days dark in cycle4 (Rafael/Bruna/Luciana). This automates the permanent rescue.
--
-- THRESHOLD: 48h grace after scheduled_at (covers same-day reschedules / holidays). The cron
--       filter requires app.status='interview_scheduled' to match the rescue RPC's status guard
--       (mig 104 hardening) — an app that already advanced is skipped, never RAISEs into the loop.
--
-- DEPENDS ON: mig 104 (selection_rescue_stuck_interview) + mig 105 (notify cron bypass — the
--       rescue RPC calls notify in service-role context).
--
-- ROLLBACK:
--   SELECT cron.unschedule('selection-stuck-scheduled-rescue-daily');
--   DROP FUNCTION public._selection_stuck_scheduled_rescue_cron();

CREATE OR REPLACE FUNCTION public._selection_stuck_scheduled_rescue_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $func$
DECLARE
  v_app record;
  v_rescued int := 0;
  v_errors int := 0;
  v_run_at timestamptz := now();
BEGIN
  FOR v_app IN
    SELECT a.id AS app_id
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status = 'interview_scheduled'        -- matches the rescue RPC status guard
      AND c.status = 'open'
      AND EXISTS (
        SELECT 1 FROM public.selection_interviews si
        WHERE si.application_id = a.id
          AND si.status = 'scheduled'
          AND si.conducted_at IS NULL
          AND si.scheduled_at IS NOT NULL
          AND si.scheduled_at < now() - interval '48 hours'   -- 48h grace
      )
    ORDER BY a.updated_at ASC                     -- oldest-stuck first
    LIMIT 20                                       -- small-cohort cap
  LOOP
    -- Per-row subtransaction: a single failure (e.g. CUTOFF_NO_BOOKING_URL on re-dispatch,
    -- which rolls that rescue back atomically) never aborts the run.
    BEGIN
      PERFORM public.selection_rescue_stuck_interview(v_app.app_id);
      v_rescued := v_rescued + 1;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.stuck_rescue_cron_run', 'system', NULL,
    jsonb_build_object('rescued_count', v_rescued, 'error_count', v_errors),
    jsonb_build_object(
      'rescued_count', v_rescued,
      'error_count', v_errors,
      'run_at', v_run_at,
      'grace_hours', 48,
      'limit', 20
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'rescued_count', v_rescued,
    'error_count', v_errors,
    'run_at', v_run_at
  );
END;
$func$;

REVOKE ALL ON FUNCTION public._selection_stuck_scheduled_rescue_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_stuck_scheduled_rescue_cron() TO service_role;

COMMENT ON FUNCTION public._selection_stuck_scheduled_rescue_cron() IS
'p282 #411 W2b: daily cron — rescues every interview_scheduled app (open cycle) whose latest '
'scheduled interview is >48h past + never conducted, via selection_rescue_stuck_interview. '
'LIMIT 20/day, per-row exception isolation, one aggregate audit row (selection.stuck_rescue_cron_run).';

-- schedule — daily 15:00 UTC (after the 14:00 cutoff cron). UPSERTS by name.
SELECT cron.schedule(
  'selection-stuck-scheduled-rescue-daily',
  '0 15 * * *',
  $cron$SELECT public._selection_stuck_scheduled_rescue_cron()$cron$
);

NOTIFY pgrst, 'reload schema';
