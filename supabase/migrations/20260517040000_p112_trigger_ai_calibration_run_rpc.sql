-- p112 — Onda 5 Fase 2.5: trigger ai calibration run via admin button.
-- Gates on view_internal_analytics (consistent with /admin/ai-calibration page access).
-- Calls compute_ai_calibration_weekly() then patches triggered_by='admin' for the new runs.
-- Logs to admin_audit_log for audit trail.
-- Returns same shape as compute_ai_calibration_weekly().
-- Rollback: DROP FUNCTION public.trigger_ai_calibration_run();

CREATE OR REPLACE FUNCTION public.trigger_ai_calibration_run()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycles_processed int;
  v_run_ids uuid[];
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  v_result := public.compute_ai_calibration_weekly();
  v_cycles_processed := COALESCE((v_result->>'cycles_processed')::int, 0);

  -- Patch triggered_by='admin' on the runs we just generated (compute_ai_calibration_weekly hardcodes 'cron').
  IF v_cycles_processed > 0 THEN
    SELECT array_agg((pc->>'run_id')::uuid)
      INTO v_run_ids
      FROM jsonb_array_elements(v_result->'per_cycle') AS pc;

    UPDATE public.ai_calibration_runs
       SET triggered_by = 'admin'
     WHERE id = ANY(v_run_ids);
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_caller_id,
    'trigger_ai_calibration_run',
    'ai_calibration_runs',
    NULL,
    jsonb_build_object(
      'cycles_processed', v_cycles_processed,
      'ran_at', v_result->>'ran_at',
      'run_ids', to_jsonb(v_run_ids)
    )
  );

  -- Return result with patched triggered_by reflected
  IF v_cycles_processed > 0 THEN
    v_result := jsonb_set(v_result, '{triggered_by}', '"admin"'::jsonb);
  END IF;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.trigger_ai_calibration_run() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.trigger_ai_calibration_run() TO authenticated;

NOTIFY pgrst, 'reload schema';
