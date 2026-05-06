-- ARM P1 (post Onda 2): get_evaluator_calibration_stats RPC — calibration metrics
--
-- Estado pré: zero observabilidade de calibração entre avaliadores. Anomaly trigger
-- (selection_evaluation_anomalies) detecta pontual >2σ mas não há agregado para
-- comitê ver "este avaliador é consistentemente mais duro/mole?" ou "este par
-- discorda muito?".
--
-- RPC retorna:
--   - cycle_summary: total_applications, total_evaluators, total_evaluations,
--     overall_mean, overall_stddev
--   - per_evaluator: {member_id, name, evaluations_count, mean_score, stddev,
--     bias_signed (= mean - overall_mean), bias_abs, anomaly_count}
--   - pair_divergence (top 5): pairs (eval_a, eval_b) com mean diff > 0 — útil
--     para sessão de calibração
--
-- Auth: view_internal_analytics (mesmo de get_selection_dashboard).
-- Não-trivial gain: dispensa Krippendorff/Cohen exato — desvio simples + anomalia
-- já é actionable.
--
-- Rollback:
--   DROP FUNCTION public.get_evaluator_calibration_stats(text);

CREATE OR REPLACE FUNCTION public.get_evaluator_calibration_stats(p_cycle_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_overall_mean numeric;
  v_overall_stddev numeric;
  v_total_apps integer;
  v_total_evals integer;
  v_per_evaluator jsonb;
  v_pair_divergence jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found');
  END IF;

  -- Overall mean + stddev (de todas evaluations submitted no ciclo)
  SELECT
    AVG(e.weighted_subtotal),
    STDDEV_POP(e.weighted_subtotal),
    COUNT(DISTINCT e.application_id),
    COUNT(*)
  INTO v_overall_mean, v_overall_stddev, v_total_apps, v_total_evals
  FROM public.selection_evaluations e
  JOIN public.selection_applications a ON a.id = e.application_id
  WHERE a.cycle_id = v_cycle_id AND e.submitted_at IS NOT NULL;

  -- Per evaluator: mean, stddev, bias signed, bias abs, anomaly count
  SELECT jsonb_agg(jsonb_build_object(
    'member_id', t.evaluator_id,
    'name', m.name,
    'evaluations_count', t.eval_count,
    'mean_score', round(t.eval_mean, 2),
    'stddev', round(COALESCE(t.eval_stddev, 0), 2),
    'bias_signed', round(t.eval_mean - v_overall_mean, 2),
    'bias_abs', round(abs(t.eval_mean - v_overall_mean), 2),
    'anomaly_count', COALESCE(an.cnt, 0)
  ) ORDER BY abs(t.eval_mean - v_overall_mean) DESC)
  INTO v_per_evaluator
  FROM (
    SELECT
      e.evaluator_id,
      COUNT(*) AS eval_count,
      AVG(e.weighted_subtotal) AS eval_mean,
      STDDEV_POP(e.weighted_subtotal) AS eval_stddev
    FROM public.selection_evaluations e
    JOIN public.selection_applications a ON a.id = e.application_id
    WHERE a.cycle_id = v_cycle_id AND e.submitted_at IS NOT NULL
    GROUP BY e.evaluator_id
    HAVING COUNT(*) >= 1
  ) t
  JOIN public.members m ON m.id = t.evaluator_id
  LEFT JOIN (
    SELECT
      (payload->>'evaluator_id')::uuid AS evaluator_id,
      COUNT(*) AS cnt
    FROM public.selection_evaluation_anomalies
    WHERE cycle_id = v_cycle_id
      AND payload ? 'evaluator_id'
    GROUP BY (payload->>'evaluator_id')::uuid
  ) an ON an.evaluator_id = t.evaluator_id;

  -- Pair divergence: top 5 pares com maior |mean_a - mean_b| no MESMO conjunto
  -- de candidatos (intersect só)
  SELECT jsonb_agg(jsonb_build_object(
    'evaluator_a_id', p.eval_a,
    'evaluator_a_name', ma.name,
    'evaluator_b_id', p.eval_b,
    'evaluator_b_name', mb.name,
    'shared_applications', p.shared,
    'mean_diff_abs', round(p.diff, 2)
  ) ORDER BY p.diff DESC)
  INTO v_pair_divergence
  FROM (
    SELECT
      e1.evaluator_id AS eval_a,
      e2.evaluator_id AS eval_b,
      COUNT(*) AS shared,
      ABS(AVG(e1.weighted_subtotal - e2.weighted_subtotal)) AS diff
    FROM public.selection_evaluations e1
    JOIN public.selection_evaluations e2
      ON e2.application_id = e1.application_id
      AND e2.evaluation_type = e1.evaluation_type
      AND e2.evaluator_id > e1.evaluator_id  -- avoid (a,b) and (b,a) duplicates
      AND e2.submitted_at IS NOT NULL
    JOIN public.selection_applications a ON a.id = e1.application_id
    WHERE a.cycle_id = v_cycle_id AND e1.submitted_at IS NOT NULL
    GROUP BY e1.evaluator_id, e2.evaluator_id
    HAVING COUNT(*) >= 2  -- pares com pelo menos 2 avaliações compartilhadas
    ORDER BY diff DESC
    LIMIT 5
  ) p
  JOIN public.members ma ON ma.id = p.eval_a
  JOIN public.members mb ON mb.id = p.eval_b;

  RETURN jsonb_build_object(
    'cycle_summary', jsonb_build_object(
      'cycle_id', v_cycle_id,
      'total_applications', v_total_apps,
      'total_evaluators', (SELECT COUNT(DISTINCT evaluator_id) FROM public.selection_evaluations e
                           JOIN public.selection_applications a ON a.id=e.application_id
                           WHERE a.cycle_id=v_cycle_id AND e.submitted_at IS NOT NULL),
      'total_evaluations', v_total_evals,
      'overall_mean', round(COALESCE(v_overall_mean, 0), 2),
      'overall_stddev', round(COALESCE(v_overall_stddev, 0), 2)
    ),
    'per_evaluator', COALESCE(v_per_evaluator, '[]'::jsonb),
    'pair_divergence', COALESCE(v_pair_divergence, '[]'::jsonb),
    'fetched_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.get_evaluator_calibration_stats(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_evaluator_calibration_stats(text) TO authenticated;

COMMENT ON FUNCTION public.get_evaluator_calibration_stats(text) IS
  'ARM P1 post-Onda 2 (#140 follow-up): calibration metrics agregadas. Per evaluator: bias_signed/abs vs overall_mean + anomaly_count + std. Top 5 pair divergence em candidatos compartilhados. Útil para sessão de calibração pré-decisão final ou entre ciclos. Auth: view_internal_analytics. Não usa Krippendorff/Cohen exato — desvio simples é actionable.';

NOTIFY pgrst, 'reload schema';
