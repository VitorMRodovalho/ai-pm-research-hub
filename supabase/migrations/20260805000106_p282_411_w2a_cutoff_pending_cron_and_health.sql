-- p282 #411 Wave 2a (part 2) — selection-cutoff-pending daily cron + get_cutoff_dispatch_health
--
-- WHAT:
--   1. _selection_cutoff_pending_cron() — SECDEF service-role cron. Each run dispatches the
--      cutoff-approved invite to every STRICTLY-above-target candidate still awaiting it, via
--      notify_selection_cutoff_approved (which now has the ADR-0028 cron bypass, mig 105).
--      Pre-flight filters cutoff_approved_email_sent_at IS NULL; per-row BEGIN/EXCEPTION so one
--      failure never aborts the loop; LIMIT 50/day runaway cap. One aggregate audit row per run
--      (action selection.cutoff_pending_cron_run, actor_id NULL).
--   2. pg_cron job selection-cutoff-pending-daily at 14:00 UTC.
--   3. get_cutoff_dispatch_health() — view_internal_analytics-gated observability RPC. Returns
--      the last-7-runs trend for BOTH the cutoff-pending cron AND the stuck-rescue cron (the
--      latter ships its schedule in Wave 2b mig 107 — the health RPC reads its audit action now
--      so 2b needs no re-edit), the live pending cohorts, and a green/yellow/red health_signal.
--
-- WHY: Issue #411 Wave 2a. notify_selection_cutoff_approved had zero automated trigger — 7
--      above-band researchers sat 21 days un-invited because dispatch was manual-only. This
--      cron makes the invite automatic for the unambiguous above-target case (in_band stays a
--      GP/PM decision per directive — never auto-invited).
--
-- POLICY: STRICT above-target only (objective_score_avg >= pert_target_score). in_band excluded.
--
-- ROLLBACK:
--   SELECT cron.unschedule('selection-cutoff-pending-daily');
--   DROP FUNCTION public._selection_cutoff_pending_cron();
--   DROP FUNCTION public.get_cutoff_dispatch_health();

-- ── 1. cutoff-pending dispatch cron ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._selection_cutoff_pending_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $func$
DECLARE
  v_app record;
  v_dispatched int := 0;
  v_errors int := 0;
  v_cycles text[] := '{}';
  v_run_at timestamptz := now();
BEGIN
  FOR v_app IN
    SELECT a.id AS app_id, c.cycle_code
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status IN ('screening', 'interview_pending')
      AND a.objective_score_avg IS NOT NULL
      AND a.pert_target_score IS NOT NULL
      AND a.objective_score_avg >= a.pert_target_score   -- STRICT above-target only (NOT in_band)
      AND a.cutoff_approved_email_sent_at IS NULL          -- pre-flight idempotency
      AND c.status = 'open'
    ORDER BY a.objective_score_avg DESC
    LIMIT 50                                               -- runaway cap
  LOOP
    -- Per-row subtransaction: one bad app (e.g. CUTOFF_NO_BOOKING_URL) never aborts the run.
    BEGIN
      PERFORM public.notify_selection_cutoff_approved(v_app.app_id);
      v_dispatched := v_dispatched + 1;
      IF NOT (v_app.cycle_code = ANY (v_cycles)) THEN
        v_cycles := array_append(v_cycles, v_app.cycle_code);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.cutoff_pending_cron_run', 'system', NULL,
    jsonb_build_object('dispatched_count', v_dispatched, 'error_count', v_errors),
    jsonb_build_object(
      'dispatched_count', v_dispatched,
      'error_count', v_errors,
      'cycle_codes_touched', to_jsonb(v_cycles),
      'run_at', v_run_at,
      'limit', 50,
      'policy', 'strict_above_target'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'dispatched_count', v_dispatched,
    'error_count', v_errors,
    'cycle_codes_touched', to_jsonb(v_cycles),
    'run_at', v_run_at
  );
END;
$func$;

REVOKE ALL ON FUNCTION public._selection_cutoff_pending_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_cutoff_pending_cron() TO service_role;

COMMENT ON FUNCTION public._selection_cutoff_pending_cron() IS
'p282 #411 W2a: daily cron — dispatches the cutoff-approved interview invite to every strictly-'
'above-target (objective_score_avg >= pert_target_score) candidate still awaiting it in an open '
'cycle, via notify_selection_cutoff_approved. in_band excluded (GP/PM decision). LIMIT 50/day, '
'per-row exception isolation, one aggregate audit row (selection.cutoff_pending_cron_run).';

-- ── 2. schedule — daily 14:00 UTC (cron.schedule UPSERTS by name; idempotent re-run) ──
SELECT cron.schedule(
  'selection-cutoff-pending-daily',
  '0 14 * * *',
  $cron$SELECT public._selection_cutoff_pending_cron()$cron$
);

-- ── 3. observability RPC — cutoff + rescue dispatch health ──────────────────
CREATE OR REPLACE FUNCTION public.get_cutoff_dispatch_health()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller_id uuid;
  v_cutoff_runs jsonb;
  v_rescue_runs jsonb;
  v_cutoff_last timestamptz;
  v_rescue_last timestamptz;
  v_cutoff_job jsonb;
  v_rescue_job jsonb;
  v_pending_cutoff int;
  v_pending_stuck int;
  v_signal text;
BEGIN
  -- Authority: same gate as the other selection read surfaces.
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- last 7 runs of each cron, newest first (source: aggregate audit rows).
  SELECT COALESCE(jsonb_agg(r ORDER BY (r->>'run_at') DESC), '[]'::jsonb), MAX((r->>'run_at')::timestamptz)
  INTO v_cutoff_runs, v_cutoff_last
  FROM (
    SELECT jsonb_build_object(
             'run_at', COALESCE(l.metadata->>'run_at', l.created_at::text),
             'dispatched_count', (l.metadata->>'dispatched_count'),
             'error_count', (l.metadata->>'error_count'),
             'cycle_codes_touched', l.metadata->'cycle_codes_touched'
           ) AS r
    FROM public.admin_audit_log l
    WHERE l.action = 'selection.cutoff_pending_cron_run'
    ORDER BY l.created_at DESC
    LIMIT 7
  ) s;

  SELECT COALESCE(jsonb_agg(r ORDER BY (r->>'run_at') DESC), '[]'::jsonb), MAX((r->>'run_at')::timestamptz)
  INTO v_rescue_runs, v_rescue_last
  FROM (
    SELECT jsonb_build_object(
             'run_at', COALESCE(l.metadata->>'run_at', l.created_at::text),
             'rescued_count', (l.metadata->>'rescued_count'),
             'error_count', (l.metadata->>'error_count')
           ) AS r
    FROM public.admin_audit_log l
    WHERE l.action = 'selection.stuck_rescue_cron_run'
    ORDER BY l.created_at DESC
    LIMIT 7
  ) s;

  -- cron registrations
  SELECT jsonb_build_object('registered', count(*) > 0, 'active', bool_or(active), 'schedule', MAX(schedule))
  INTO v_cutoff_job FROM cron.job WHERE jobname = 'selection-cutoff-pending-daily';
  SELECT jsonb_build_object('registered', count(*) > 0, 'active', bool_or(active), 'schedule', MAX(schedule))
  INTO v_rescue_job FROM cron.job WHERE jobname = 'selection-stuck-scheduled-rescue-daily';

  -- live pending cohorts (the work the crons would pick up next).
  SELECT count(*) INTO v_pending_cutoff
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.status IN ('screening', 'interview_pending')
    AND a.objective_score_avg IS NOT NULL
    AND a.pert_target_score IS NOT NULL
    AND a.objective_score_avg >= a.pert_target_score
    AND a.cutoff_approved_email_sent_at IS NULL
    AND c.status = 'open';

  SELECT count(*) INTO v_pending_stuck
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.status = 'interview_scheduled'
    AND c.status = 'open'
    AND EXISTS (
      SELECT 1 FROM public.selection_interviews si
      WHERE si.application_id = a.id
        AND si.status = 'scheduled'
        AND si.conducted_at IS NULL
        AND si.scheduled_at IS NOT NULL
        AND si.scheduled_at < now() - interval '48 hours'
    );

  -- health: red if there is pending work and the relevant cron is silent > 26h (daily + grace);
  -- yellow if a cron is unregistered/inactive or has never fired; green otherwise.
  v_signal := 'green';
  IF COALESCE((v_cutoff_job->>'registered')::boolean, false) = false
     OR COALESCE((v_cutoff_job->>'active')::boolean, false) = false
     OR COALESCE((v_rescue_job->>'registered')::boolean, false) = false
     OR COALESCE((v_rescue_job->>'active')::boolean, false) = false
     OR v_cutoff_last IS NULL THEN
    v_signal := 'yellow';
  END IF;
  IF (v_pending_cutoff > 0 AND (v_cutoff_last IS NULL OR v_cutoff_last < now() - interval '26 hours'))
     OR (v_pending_stuck > 0 AND (v_rescue_last IS NULL OR v_rescue_last < now() - interval '26 hours')) THEN
    v_signal := 'red';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'health_signal', v_signal,
    'cutoff_pending', jsonb_build_object(
      'job', v_cutoff_job,
      'last_run_at', v_cutoff_last,
      'recent_runs', v_cutoff_runs,
      'pending_now', v_pending_cutoff
    ),
    'stuck_rescue', jsonb_build_object(
      'job', v_rescue_job,
      'last_run_at', v_rescue_last,
      'recent_runs', v_rescue_runs,
      'pending_now', v_pending_stuck
    ),
    'generated_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.get_cutoff_dispatch_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cutoff_dispatch_health() TO authenticated, service_role;

COMMENT ON FUNCTION public.get_cutoff_dispatch_health() IS
'p282 #411 W2a: observability for the selection interview-invite crons. Returns last-7-run trend '
'(dispatched/rescued counts) for selection-cutoff-pending-daily + selection-stuck-scheduled-rescue-daily, '
'live pending cohorts, and a green/yellow/red health_signal (red = pending work + cron silent >26h). '
'Authority: view_internal_analytics. Exposed as MCP tool get_cutoff_dispatch_health.';

NOTIFY pgrst, 'reload schema';
