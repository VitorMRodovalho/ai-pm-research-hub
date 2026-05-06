-- ARM Onda 4 Fase 1.1 (p109): criterion_notes na avaliação objetiva
--
-- Atende request PM (2026-05-06): "a nota não tem como deixar uma pre-nota
-- para cada um dos pilares/perguntas tmb?". O padrão já existe na avaliação
-- de entrevista (submit_interview_scores recebe p_criterion_notes); falta
-- aplicar à objetiva.
--
-- Mudança:
--   1. submit_evaluation passa a aceitar p_criterion_notes jsonb DEFAULT NULL
--      → backward compatible, todos os callers existentes continuam funcionando
--   2. Persistência em selection_evaluations.criterion_notes (coluna existente)
--
-- Frontend complementar: textarea por critério em loadEvaluationForm
-- (espelha pattern interview tab).
--
-- Rollback: DROP + CREATE versão de 20260516150000.

DROP FUNCTION IF EXISTS public.submit_evaluation(uuid, text, jsonb, text, uuid);
DROP FUNCTION IF EXISTS public.submit_evaluation(uuid, text, jsonb, text);
DROP FUNCTION IF EXISTS public.submit_evaluation(uuid, text, jsonb, text, jsonb);

CREATE FUNCTION public.submit_evaluation(
  p_application_id uuid,
  p_evaluation_type text,
  p_scores jsonb,
  p_notes text DEFAULT NULL::text,
  p_criterion_notes jsonb DEFAULT NULL::jsonb,
  p_ai_suggestion_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_score numeric;
  v_weight numeric;
  v_weighted_sum numeric := 0;
  v_eval_id uuid;
  v_total_evaluators int;
  v_submitted_count int;
  v_all_subtotals numeric[];
  v_pert_score numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
  v_cutoff numeric;
  v_median numeric;
  v_new_status text;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get application + cycle
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- 3. V4 authorization: committee member (resource) or platform admin
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- 4. Check not already locked
  IF EXISTS (
    SELECT 1 FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluator_id = v_caller.id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Evaluation already submitted and locked';
  END IF;

  -- 5. Get criteria and validate scores
  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);

    IF NOT (p_scores ? v_key) THEN
      RAISE EXCEPTION 'Missing score for criterion: %', v_key;
    END IF;

    v_score := (p_scores ->> v_key)::numeric;

    IF v_score IS NULL THEN
      RAISE EXCEPTION 'Score for % must be numeric', v_key;
    END IF;

    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  -- 6. Upsert evaluation (insert or update draft) — p109 Onda 4 Fase 1.1: criterion_notes
  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at
  ) VALUES (
    p_application_id, v_caller.id, p_evaluation_type,
    p_scores, ROUND(v_weighted_sum, 2), p_notes,
    COALESCE(p_criterion_notes, '{}'::jsonb), now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    criterion_notes = EXCLUDED.criterion_notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  -- 7. Check if all evaluators have submitted for this application + type
  SELECT COUNT(*) INTO v_total_evaluators
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND role IN ('evaluator', 'lead');

  SELECT COUNT(*) INTO v_submitted_count
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = p_evaluation_type
    AND submitted_at IS NOT NULL;

  -- 8. If all submitted: PERT consolidation + auto-advance
  IF v_submitted_count >= v_cycle.min_evaluators THEN
    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal)
    INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);

    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    IF p_evaluation_type = 'objective' THEN
      UPDATE public.selection_applications
      SET objective_score_avg = v_pert_score,
          updated_at = now()
      WHERE id = p_application_id;

      SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY objective_score_avg)
      INTO v_median
      FROM public.selection_applications
      WHERE cycle_id = v_app.cycle_id
        AND objective_score_avg IS NOT NULL;

      v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);

      IF v_pert_score < v_cutoff AND v_cutoff > 0 THEN
        v_new_status := 'objective_cutoff';
      ELSE
        v_new_status := 'interview_pending';
      END IF;

      UPDATE public.selection_applications
      SET status = v_new_status, updated_at = now()
      WHERE id = p_application_id
        AND status IN ('submitted', 'screening', 'objective_eval');

    ELSIF p_evaluation_type = 'interview' THEN
      UPDATE public.selection_applications
      SET interview_score = v_pert_score,
          final_score = COALESCE(objective_score_avg, 0) + v_pert_score,
          status = 'final_eval',
          updated_at = now()
      WHERE id = p_application_id;

    ELSIF p_evaluation_type = 'leader_extra' THEN
      UPDATE public.selection_applications
      SET objective_score_avg = COALESCE(objective_score_avg, 0) + v_pert_score,
          final_score = COALESCE(objective_score_avg, 0) + v_pert_score + COALESCE(interview_score, 0),
          updated_at = now()
      WHERE id = p_application_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'evaluation_id', v_eval_id,
    'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score,
    'new_status', v_new_status
  );
END;
$function$;

COMMENT ON FUNCTION public.submit_evaluation(uuid, text, jsonb, text, jsonb, uuid) IS
  'p109 ARM Onda 4 Fase 1.1 (extends 20260516150000): adiciona p_criterion_notes (jsonb DEFAULT NULL) — pre-nota por critério na avaliação objetiva (espelha pattern submit_interview_scores). Backward compatible.';

NOTIFY pgrst, 'reload schema';
