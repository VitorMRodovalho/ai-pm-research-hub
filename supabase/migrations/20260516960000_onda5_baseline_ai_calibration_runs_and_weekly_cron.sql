-- Onda 5 baseline (p108 cont. ADR-0074 follow-up #5): AI calibration delta cron.
--
-- Pré-fix: ai_triage_score (Sonnet 4.6) é shipped sem feedback loop. Não há detection
-- automática de drift entre score do AI e score humano final, dificulta detectar
-- recalibration need ou model regression entre cycles.
--
-- Pós: weekly cron (Mondays 14 UTC) computa stats por cycle: mean delta signed/abs,
-- count drift > N (default 2.0 em scale 0-10), insere em ai_calibration_runs para audit.
-- Não dispara notificações ainda (Onda 5 é baseline observacional). Future Onda 5 deep
-- dive pode adicionar threshold-based alerts ou auto-recalibration prompts.
--
-- Schema:
--   ai_calibration_runs table: per-run audit (cycle_id, ran_at, n_compared, mean_delta_*,
--     drift_count_high, sample_payload). RLS rpc-only.
--
-- Note: final_score em selection_applications é em scale 0-100 (sum de evaluations);
-- ai_triage_score é em scale 0-10. Para calibração: normalizar final_score / 10 antes
-- de delta. Documentado no comentário do RPC.
--
-- Rollback:
--   DROP TABLE ai_calibration_runs;
--   DROP FUNCTION compute_ai_calibration_stats(uuid, numeric);
--   DROP FUNCTION compute_ai_calibration_weekly();
--   DROP FUNCTION list_ai_calibration_runs(uuid, integer);
--   SELECT cron.unschedule('compute-ai-calibration-weekly');

-- 1. Observability table
CREATE TABLE IF NOT EXISTS public.ai_calibration_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid REFERENCES public.selection_cycles(id) ON DELETE CASCADE,
  ran_at timestamptz NOT NULL DEFAULT now(),
  n_compared integer NOT NULL DEFAULT 0,
  mean_delta_signed numeric,
  mean_delta_abs numeric,
  drift_count_high integer NOT NULL DEFAULT 0,
  drift_threshold numeric NOT NULL DEFAULT 2.0,
  triggered_by text NOT NULL DEFAULT 'cron',
  sample_payload jsonb,
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906',
  CONSTRAINT ai_calibration_runs_n_compared_nonneg CHECK (n_compared >= 0),
  CONSTRAINT ai_calibration_runs_drift_count_nonneg CHECK (drift_count_high >= 0),
  CONSTRAINT ai_calibration_runs_threshold_positive CHECK (drift_threshold > 0)
);

CREATE INDEX IF NOT EXISTS ix_ai_calibration_runs_cycle_ran
  ON public.ai_calibration_runs (cycle_id, ran_at DESC);
CREATE INDEX IF NOT EXISTS ix_ai_calibration_runs_ran_at
  ON public.ai_calibration_runs (ran_at DESC);

ALTER TABLE public.ai_calibration_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_calibration_runs_no_anon ON public.ai_calibration_runs;
CREATE POLICY ai_calibration_runs_no_anon
  ON public.ai_calibration_runs FOR ALL TO anon USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS ai_calibration_runs_rpc_only ON public.ai_calibration_runs;
CREATE POLICY ai_calibration_runs_rpc_only
  ON public.ai_calibration_runs FOR ALL TO authenticated USING (false) WITH CHECK (false);

REVOKE INSERT, UPDATE, DELETE ON public.ai_calibration_runs FROM authenticated, anon;

COMMENT ON TABLE public.ai_calibration_runs IS
  'p108 Onda 5 baseline (ADR-0074): per-run AI vs human score calibration audit. Delta = (final_score / 10) - ai_triage_score (normalized to 0-10 scale). RLS rpc-only — admin via compute_ai_calibration_stats RPC.';

-- 2. Per-cycle compute RPC (callable by admin OR cron)
CREATE OR REPLACE FUNCTION public.compute_ai_calibration_stats(
  p_cycle_id uuid,
  p_drift_threshold numeric DEFAULT 2.0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller_id uuid;
  v_cron_context boolean;
  v_n integer;
  v_mean_signed numeric;
  v_mean_abs numeric;
  v_drift_high integer;
  v_sample_payload jsonb;
  v_run_id uuid;
  v_triggered_by text;
BEGIN
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF v_cron_context THEN
    v_triggered_by := 'cron';
  ELSE
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RETURN jsonb_build_object('error','Not authenticated');
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
      RETURN jsonb_build_object('error','Not authorized: requires view_internal_analytics');
    END IF;
    v_triggered_by := 'admin_request';
  END IF;

  -- Compute deltas: ai_triage_score (0-10) vs final_score normalized (final / 10)
  WITH paired AS (
    SELECT
      a.id AS application_id,
      a.applicant_name,
      a.ai_triage_score::numeric AS ai_score,
      (a.final_score::numeric / 10.0) AS human_score_normalized,
      (a.final_score::numeric / 10.0) - a.ai_triage_score::numeric AS delta_signed
    FROM public.selection_applications a
    WHERE a.cycle_id = p_cycle_id
      AND a.ai_triage_score IS NOT NULL
      AND a.final_score IS NOT NULL
  )
  SELECT
    COUNT(*),
    ROUND(AVG(delta_signed), 3),
    ROUND(AVG(ABS(delta_signed)), 3),
    COUNT(*) FILTER (WHERE ABS(delta_signed) > p_drift_threshold)
  INTO v_n, v_mean_signed, v_mean_abs, v_drift_high
  FROM paired;

  -- Sample top-5 outliers for visibility (signed delta sorted by abs desc)
  SELECT jsonb_agg(jsonb_build_object(
    'application_id', application_id,
    'applicant_name', applicant_name,
    'ai_score', ai_score,
    'human_score_normalized', human_score_normalized,
    'delta_signed', ROUND(delta_signed, 2)
  ) ORDER BY ABS(delta_signed) DESC)
  INTO v_sample_payload
  FROM (
    SELECT
      a.id AS application_id,
      a.applicant_name,
      a.ai_triage_score::numeric AS ai_score,
      (a.final_score::numeric / 10.0) AS human_score_normalized,
      (a.final_score::numeric / 10.0) - a.ai_triage_score::numeric AS delta_signed
    FROM public.selection_applications a
    WHERE a.cycle_id = p_cycle_id
      AND a.ai_triage_score IS NOT NULL
      AND a.final_score IS NOT NULL
    ORDER BY ABS((a.final_score::numeric / 10.0) - a.ai_triage_score::numeric) DESC
    LIMIT 5
  ) top;

  -- Insert run row regardless (n=0 also recorded — useful for "no overlap yet" tracking)
  INSERT INTO public.ai_calibration_runs (
    cycle_id, n_compared, mean_delta_signed, mean_delta_abs, drift_count_high,
    drift_threshold, triggered_by, sample_payload
  ) VALUES (
    p_cycle_id, COALESCE(v_n, 0),
    v_mean_signed, v_mean_abs,
    COALESCE(v_drift_high, 0),
    p_drift_threshold, v_triggered_by,
    v_sample_payload
  )
  RETURNING id INTO v_run_id;

  RETURN jsonb_build_object(
    'run_id', v_run_id,
    'cycle_id', p_cycle_id,
    'n_compared', COALESCE(v_n, 0),
    'mean_delta_signed', v_mean_signed,
    'mean_delta_abs', v_mean_abs,
    'drift_count_high', COALESCE(v_drift_high, 0),
    'drift_threshold', p_drift_threshold,
    'triggered_by', v_triggered_by,
    'top_outliers', COALESCE(v_sample_payload, '[]'::jsonb),
    'ran_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.compute_ai_calibration_stats(uuid, numeric) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.compute_ai_calibration_stats(uuid, numeric) TO authenticated;

COMMENT ON FUNCTION public.compute_ai_calibration_stats(uuid, numeric) IS
  'p108 Onda 5 baseline (ADR-0074): computa delta entre ai_triage_score e final_score humano (normalizado /10). Insert row em ai_calibration_runs + retorna stats + top 5 outliers. Auth: cron-context OR view_internal_analytics.';

-- 3. Cron handler — weekly Mondays 14 UTC (1h depois de detect-onboarding-overdue-daily 13UTC,
--    para evitar burst no horário pico — separa load)
CREATE OR REPLACE FUNCTION public.compute_ai_calibration_weekly()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_cycle record;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_total_cycles integer := 0;
  v_cron_context boolean;
BEGIN
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF NOT v_cron_context THEN
    RAISE EXCEPTION 'Unauthorized: cron-only (called by pg_cron)';
  END IF;

  FOR v_cycle IN
    SELECT id, cycle_code FROM public.selection_cycles
    WHERE status IN ('open', 'evaluating', 'decided', 'closed')
      AND EXISTS (
        SELECT 1 FROM public.selection_applications a
        WHERE a.cycle_id = selection_cycles.id
          AND a.ai_triage_score IS NOT NULL
          AND a.final_score IS NOT NULL
      )
    ORDER BY created_at DESC
  LOOP
    v_result := public.compute_ai_calibration_stats(v_cycle.id, 2.0);
    v_results := v_results || jsonb_build_array(v_result);
    v_total_cycles := v_total_cycles + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'cycles_processed', v_total_cycles,
    'per_cycle', v_results,
    'ran_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.compute_ai_calibration_weekly() FROM public, anon, authenticated;

COMMENT ON FUNCTION public.compute_ai_calibration_weekly() IS
  'p108 Onda 5 baseline (ADR-0074): weekly Mondays 14 UTC. Itera selection_cycles com >= 1 application paired (ai_triage_score AND final_score), computa stats. Baseline observacional — sem alerts (Onda 5 deep dive future).';

-- 4. Admin observability RPC for dashboard
CREATE OR REPLACE FUNCTION public.list_ai_calibration_runs(
  p_cycle_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 50
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller_id uuid;
  v_safe_limit integer;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error','Not authorized: requires view_internal_analytics');
  END IF;

  v_safe_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);

  SELECT jsonb_agg(jsonb_build_object(
    'id', r.id,
    'cycle_id', r.cycle_id,
    'cycle_code', sc.cycle_code,
    'ran_at', r.ran_at,
    'n_compared', r.n_compared,
    'mean_delta_signed', r.mean_delta_signed,
    'mean_delta_abs', r.mean_delta_abs,
    'drift_count_high', r.drift_count_high,
    'drift_threshold', r.drift_threshold,
    'triggered_by', r.triggered_by,
    'top_outliers', r.sample_payload
  ) ORDER BY r.ran_at DESC)
  INTO v_result
  FROM (
    SELECT * FROM public.ai_calibration_runs
    WHERE p_cycle_id IS NULL OR cycle_id = p_cycle_id
    ORDER BY ran_at DESC
    LIMIT v_safe_limit
  ) r
  LEFT JOIN public.selection_cycles sc ON sc.id = r.cycle_id;

  RETURN jsonb_build_object(
    'rows', COALESCE(v_result, '[]'::jsonb),
    'fetched_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.list_ai_calibration_runs(uuid, integer) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_ai_calibration_runs(uuid, integer) TO authenticated;

COMMENT ON FUNCTION public.list_ai_calibration_runs(uuid, integer) IS
  'p108 Onda 5 baseline: admin observability sobre ai_calibration_runs. Auth: view_internal_analytics. Substrato para futuro /admin/ai-calibration dashboard.';

-- 5. Schedule cron Mondays 14 UTC
SELECT cron.schedule(
  'compute-ai-calibration-weekly',
  '0 14 * * 1',
  'SELECT public.compute_ai_calibration_weekly();'
);

NOTIFY pgrst, 'reload schema';
