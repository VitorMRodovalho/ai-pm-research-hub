-- p111 Onda 5 Fase 2: list_ai_calibration_runs RPC para drift dashboard
--
-- Source para /admin/ai-calibration. Retorna runs históricas + cycle code
-- joinado + validator_breakdown jsonb (já populado por p110b 020000).
--
-- Auth: cron (service_role) OR view_internal_analytics (V4 permission).
-- Filtro opcional por cycle_id; default = todos os ciclos.
-- Limit default 50 (caps em 200 para evitar abuso).
--
-- ADR-0011 V4 auth pattern.

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
  v_cron_context boolean;
  v_runs jsonb;
  v_effective_limit integer;
BEGIN
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF NOT v_cron_context THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RETURN jsonb_build_object('error','Not authenticated');
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
      RETURN jsonb_build_object('error','Not authorized: requires view_internal_analytics');
    END IF;
  END IF;

  v_effective_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'cycle_id', r.cycle_id,
    'cycle_code', c.cycle_code,
    'ran_at', r.ran_at,
    'n_compared', r.n_compared,
    'mean_delta_signed', r.mean_delta_signed,
    'mean_delta_abs', r.mean_delta_abs,
    'drift_count_high', r.drift_count_high,
    'drift_threshold', r.drift_threshold,
    'triggered_by', r.triggered_by,
    'sample_payload', r.sample_payload,
    'validator_breakdown', r.validator_breakdown
  ) ORDER BY r.ran_at DESC), '[]'::jsonb) INTO v_runs
  FROM (
    SELECT * FROM public.ai_calibration_runs
    WHERE p_cycle_id IS NULL OR cycle_id = p_cycle_id
    ORDER BY ran_at DESC
    LIMIT v_effective_limit
  ) r
  LEFT JOIN public.selection_cycles c ON c.id = r.cycle_id;

  RETURN jsonb_build_object(
    'runs', v_runs,
    'count', jsonb_array_length(v_runs),
    'cycle_filter', p_cycle_id,
    'limit', v_effective_limit
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.list_ai_calibration_runs(uuid, integer) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_ai_calibration_runs(uuid, integer) TO authenticated;

COMMENT ON FUNCTION public.list_ai_calibration_runs(uuid, integer) IS
  'p111 Onda 5 Fase 2: lista runs de calibração para drift dashboard. Filtro opcional por cycle. Auth: view_internal_analytics. Inclui cycle_code joinado + validator_breakdown jsonb.';

NOTIFY pgrst, 'reload schema';
