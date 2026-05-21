-- p209 / A1.2 — submit_evaluation: enforce schema max + non-negative score
--
-- BUG context (PM-surfaced 2026-05-21):
-- =========================================
-- The submit_evaluation RPC accepted scores OUTSIDE the schema-declared max
-- silently. PM e.g.: Fabricio submitted Francisleila leader_extra scores 7-8
-- when schema max was 5 (now 10 per migration 20260802000002). UI showed
-- "out_of_range" but RPC INSERT succeeded with weighted_subtotal=162.
--
-- Result: schema/UI/RPC tri-layer drift undetected by audit until manually
-- noticed. Same bug class would silently corrupt cohort comparisons if any
-- future criterion bumps max without UI sync.
--
-- Fix: add `IF v_score < 0 OR v_score > v_max THEN RAISE EXCEPTION` inside
-- the scores loop, immediately after numeric parse. v_max defaults to 10
-- when criterion lacks `max` field (extremely defensive — current schemas
-- all specify max explicitly).
--
-- This is forward-defense: the schema/UI/RPC tri-state must align. Any
-- evaluator now gets a clear error instead of silent corruption.
--
-- Pairs with migration 20260802000002 (leader_extra max:5→10 data fix).
--
-- Backward compatibility:
--   - All existing valid submissions (within 0..max) keep working.
--   - All existing invalid submissions (e.g. legacy if any) would be rejected
--     on RE-SUBMIT, but not retroactively voided.
--   - Cycle4-2026 today: 0 historical submissions exceed max:10 (Vitor's
--     William scored 1-4; Fabricio's Francisleila scored 5-8). All preserved.
--
-- Rollback (only if a downstream regression appears):
--   - Re-apply prior body (saved at 20260802000001 Phase B capture).
--   - Note: rollback restores BROKEN silent-accept behavior. Prefer fix-forward.
--
-- Drift note: submit_evaluation body is being modified AFTER PR #228 Phase B
-- drift capture window. Phase C body-hash audit will flag drift on next run;
-- this migration IS the new canonical body capture, so drift = 0 after apply.

CREATE OR REPLACE FUNCTION public.submit_evaluation(
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
  v_max numeric;
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
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found'; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluator_id = v_caller.id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Evaluation already submitted and locked';
  END IF;

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
    v_max := COALESCE((v_criterion ->> 'max')::numeric, 10);
    IF NOT (p_scores ? v_key) THEN RAISE EXCEPTION 'Missing score for criterion: %', v_key; END IF;
    v_score := (p_scores ->> v_key)::numeric;
    IF v_score IS NULL THEN RAISE EXCEPTION 'Score for % must be numeric', v_key; END IF;
    -- p209/A1.2 — enforce schema max + non-negative (was silently accepted before).
    IF v_score < 0 OR v_score > v_max THEN
      RAISE EXCEPTION 'Score % for criterion "%" must be between 0 and % (schema max)', v_score, v_key, v_max;
    END IF;
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

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

  SELECT COUNT(*) INTO v_total_evaluators FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND role IN ('evaluator', 'lead');

  SELECT COUNT(*) INTO v_submitted_count FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

  IF v_submitted_count >= v_cycle.min_evaluators THEN
    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal) INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);
    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    IF p_evaluation_type = 'objective' THEN
      UPDATE public.selection_applications SET objective_score_avg = v_pert_score, updated_at = now() WHERE id = p_application_id;
      SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY objective_score_avg) INTO v_median
      FROM public.selection_applications WHERE cycle_id = v_app.cycle_id AND objective_score_avg IS NOT NULL;
      v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);
      IF v_pert_score < v_cutoff AND v_cutoff > 0 THEN v_new_status := 'objective_cutoff'; ELSE v_new_status := 'interview_pending'; END IF;
      UPDATE public.selection_applications SET status = v_new_status, updated_at = now()
      WHERE id = p_application_id AND status IN ('submitted', 'screening', 'objective_eval');
    ELSIF p_evaluation_type = 'interview' THEN
      UPDATE public.selection_applications SET interview_score = v_pert_score, final_score = COALESCE(objective_score_avg, 0) + v_pert_score, status = 'final_eval', updated_at = now() WHERE id = p_application_id;
    ELSIF p_evaluation_type = 'leader_extra' THEN
      UPDATE public.selection_applications SET objective_score_avg = COALESCE(objective_score_avg, 0) + v_pert_score, final_score = COALESCE(objective_score_avg, 0) + v_pert_score + COALESCE(interview_score, 0), updated_at = now() WHERE id = p_application_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'evaluation_id', v_eval_id, 'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score, 'new_status', v_new_status
  );
END;
$function$
;

-- Register version
INSERT INTO supabase_migrations.schema_migrations (version, name)
VALUES ('20260802000003', 'p209_a1_2_submit_evaluation_max_validation')
ON CONFLICT (version) DO NOTHING;
