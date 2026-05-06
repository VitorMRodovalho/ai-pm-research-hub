-- p110 Onda 5: compute_ai_calibration_stats lê ai_score_validations
--
-- Estado pré: cron compute_ai_calibration_weekly itera ciclos e chama
-- compute_ai_calibration_stats(cycle_id, threshold). Esse RPC compara
-- ai_triage_score vs final_score normalizado (delta + outliers top-5),
-- mas não consome ai_score_validations capturada em p109 (Onda 4 Fase 2).
-- Resultado: thumbs/override do PM ficam capturados mas não retroalimentam
-- calibração — gap entre signal capture e signal consumption.
--
-- Estado pós:
--   1. ai_calibration_runs ganha coluna validator_breakdown jsonb (preserva
--      sample_payload existente; backward compat para dashboards futuros).
--   2. compute_ai_calibration_stats agrega ai_score_validations por:
--      - global: agree_n, disagree_n, override_n, mean_override_delta
--      - by_validator: per-validator agreement_rate + bias signal
--      - by_purpose: breakdown sonnet_triage vs gemini_eleva_bar
--   3. INSERT em ai_calibration_runs inclui validator_breakdown.
--   4. Retorno jsonb ganha chave 'validator_breakdown'.
--
-- Janela temporal: validações dos últimos 4 weeks (alinha com threshold
-- ADR-0074 baseline). Validações antes disso são consideradas baseline
-- expirado.
--
-- Smoke esperado em DB atual: validator_breakdown global={agree:0, disagree:0,
-- override:0} porque ai_score_validations tem 0 rows. by_validator=[], by_purpose={}.
-- Quando primeiras validações chegarem via UI p109, próxima rodada do cron
-- popula valores reais.
--
-- ADR refs: ADR-0074 (dual-model AI architecture) + footnote validation feedback.
-- Não exige ADR-0075 — refinamento do contrato existente, não decisão nova.
-- Rollback:
--   DROP FUNCTION compute_ai_calibration_stats(uuid, numeric);
--   ALTER TABLE ai_calibration_runs DROP COLUMN validator_breakdown;
--   reaplicar 20260516960000 body.

-- 1. Nova coluna em ai_calibration_runs
ALTER TABLE public.ai_calibration_runs
  ADD COLUMN IF NOT EXISTS validator_breakdown jsonb;

COMMENT ON COLUMN public.ai_calibration_runs.validator_breakdown IS
  'p110 Onda 5: agregação de ai_score_validations (window 4 weeks). Schema: { global: {agree_n, disagree_n, override_n, mean_override_delta_when_override}, by_validator: [{validator_id, name, validations_n, agreement_rate, bias_signal}], by_purpose: {sonnet_triage: {...}, gemini_eleva_bar: {...}} }. Vazio quando nenhuma validação no período.';

-- 2. Recriar compute_ai_calibration_stats com JOIN ai_score_validations
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
  v_validator_breakdown jsonb;
  v_run_id uuid;
  v_triggered_by text;
  v_window_start timestamptz := now() - interval '4 weeks';
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

  -- ====================================================================
  -- BLOCO 1 (preservado da v1): delta ai_triage_score vs final_score
  -- ====================================================================
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

  -- Top-5 outliers
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

  -- ====================================================================
  -- BLOCO 2 (NOVO p110): validator breakdown
  -- Lê ai_score_validations dos últimos 4 weeks, escopado por cycle.
  -- Agrega 3 dimensões: global, by_validator, by_purpose.
  -- ====================================================================
  WITH cycle_validations AS (
    -- Apenas validações de apps deste ciclo + window 4 weeks
    SELECT v.*, m.name AS validator_name
    FROM public.ai_score_validations v
    JOIN public.selection_applications a ON a.id = v.application_id
    LEFT JOIN public.members m ON m.id = v.validator_id
    WHERE a.cycle_id = p_cycle_id
      AND v.validated_at >= v_window_start
  ),
  global_agg AS (
    SELECT jsonb_build_object(
      'total_validations', COUNT(*),
      'agree_n', COUNT(*) FILTER (WHERE validation_action = 'agree'),
      'disagree_n', COUNT(*) FILTER (WHERE validation_action = 'disagree'),
      'override_n', COUNT(*) FILTER (WHERE validation_action = 'override'),
      'mean_override_delta', ROUND(AVG(override_score - ai_score) FILTER (WHERE validation_action = 'override' AND override_score IS NOT NULL), 3),
      'window_start', v_window_start,
      'window_end', now()
    ) AS payload
    FROM cycle_validations
  ),
  by_validator AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'validator_id', validator_id,
      'name', validator_name,
      'validations_n', validations_n,
      'agreement_rate', ROUND(agreement_rate, 3),
      'bias_signal', ROUND(bias_signal, 3),
      'override_n', override_n
    ) ORDER BY validations_n DESC), '[]'::jsonb) AS payload
    FROM (
      SELECT
        validator_id,
        validator_name,
        COUNT(*) AS validations_n,
        COUNT(*) FILTER (WHERE validation_action = 'agree')::numeric / NULLIF(COUNT(*), 0) AS agreement_rate,
        AVG(override_score - ai_score) FILTER (WHERE validation_action = 'override' AND override_score IS NOT NULL) AS bias_signal,
        COUNT(*) FILTER (WHERE validation_action = 'override') AS override_n
      FROM cycle_validations
      WHERE validator_id IS NOT NULL
      GROUP BY validator_id, validator_name
    ) v
  ),
  by_purpose AS (
    SELECT COALESCE(jsonb_object_agg(ai_purpose, purpose_payload), '{}'::jsonb) AS payload
    FROM (
      SELECT
        ai_purpose,
        jsonb_build_object(
          'total', COUNT(*),
          'agree_n', COUNT(*) FILTER (WHERE validation_action = 'agree'),
          'disagree_n', COUNT(*) FILTER (WHERE validation_action = 'disagree'),
          'override_n', COUNT(*) FILTER (WHERE validation_action = 'override'),
          'mean_override_delta', ROUND(AVG(override_score - ai_score) FILTER (WHERE validation_action = 'override' AND override_score IS NOT NULL), 3)
        ) AS purpose_payload
      FROM cycle_validations
      WHERE ai_purpose IS NOT NULL
      GROUP BY ai_purpose
    ) p
  )
  SELECT jsonb_build_object(
    'global', (SELECT payload FROM global_agg),
    'by_validator', (SELECT payload FROM by_validator),
    'by_purpose', (SELECT payload FROM by_purpose)
  )
  INTO v_validator_breakdown;

  -- ====================================================================
  -- INSERT (sample_payload preservado + validator_breakdown novo)
  -- ====================================================================
  INSERT INTO public.ai_calibration_runs (
    cycle_id, n_compared, mean_delta_signed, mean_delta_abs, drift_count_high,
    drift_threshold, triggered_by, sample_payload, validator_breakdown
  ) VALUES (
    p_cycle_id, COALESCE(v_n, 0),
    v_mean_signed, v_mean_abs,
    COALESCE(v_drift_high, 0),
    p_drift_threshold, v_triggered_by,
    v_sample_payload, v_validator_breakdown
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
    'validator_breakdown', v_validator_breakdown,
    'ran_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.compute_ai_calibration_stats(uuid, numeric) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.compute_ai_calibration_stats(uuid, numeric) TO authenticated;

COMMENT ON FUNCTION public.compute_ai_calibration_stats(uuid, numeric) IS
  'p110 Onda 5 (extends p108 960000): computes Sonnet vs human deltas + validator breakdown (agree/disagree/override + per-validator agreement_rate + per-purpose). Window 4 weeks for validations. Auth: cron OR view_internal_analytics. Inserts row in ai_calibration_runs with validator_breakdown jsonb.';

NOTIFY pgrst, 'reload schema';
