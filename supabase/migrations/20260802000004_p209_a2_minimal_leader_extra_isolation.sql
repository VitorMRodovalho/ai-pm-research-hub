-- p209 / A2 minimal mitigation — isolate leader_extra from objective_score_avg
--
-- BUG context (Issue #229, PM Option A urgência ALTA 2026-05-21):
-- =================================================================
-- Cycle4-2026 has 34 applications avaliando. submit_evaluation RPC
-- leader_extra branch was MUTATING objective_score_avg by ADDING the
-- leader_extra PERT score:
--
--   objective_score_avg = COALESCE(objective_score_avg, 0) + v_pert_score
--
-- This conflated 2 distinct dimensions, breaking:
-- - Cohort PERT cutoff comparisons (compute_pert_cutoff over objective_score_avg
--   cohort got inflated with leader_extra values)
-- - Subsequent objective recomputes
-- - Analytics rankings + UI band displays (Francisleila preview "BELOW band 128
--   < 139.87" used OBJECTIVE cutoff for leader_extra dimension)
--
-- Minimal scope this migration (full A2 at #229: cohort cutoff separated,
-- new pert_target/band columns for leader_extra, UI 2 bandas, MCP enrichment):
-- 1. ALTER TABLE: add column leader_extra_pert_score numeric
-- 2. UPDATE RPC submit_evaluation:
--    - leader_extra branch: stores PERT in NEW column, computes final_score
--      from obj+interview+leader_extra (no mutation of obj)
--    - interview branch: includes leader_extra_pert_score in final_score
--      (was previously already excluded since obj was inflated)
-- 3. NOT included (deferred to #229 full scope):
--    - leader_extra-specific pert_target_score/band columns
--    - compute_pert_cutoff branch for leader_extra
--    - UI 2 bandas separadas in /admin/selection
--    - MCP get_selection_rankings enrichment
--
-- Backfill: NONE needed for cycle4-2026 (single existing leader_extra eval by
-- Fabricio on Francisleila — min_evaluators=2 not met yet so mutation never
-- fired; leader_extra_pert_score stays NULL until 2nd evaluator submits).
--
-- Forward state:
-- - All future leader_extra submissions: clean storage in new column
-- - objective_score_avg stays pristine = objective dimension only
-- - final_score = obj + interview + leader_extra (additive 3 dimensions)
-- - Cohort cutoff for objective remains valid (no contamination)
--
-- Rollback (if regression in cycle4 evaluations):
--   ALTER TABLE selection_applications DROP COLUMN leader_extra_pert_score;
--   -- Then restore prior RPC body from 20260802000003
--   -- Note: rollback restores BROKEN mutation behavior. Prefer fix-forward.

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS leader_extra_pert_score numeric;

COMMENT ON COLUMN public.selection_applications.leader_extra_pert_score IS
  'PERT-averaged leader_extra score (separate from objective_score_avg). Populated by submit_evaluation when min_evaluators leader_extra evals are submitted. Added p209/A2-minimal to stop submit_evaluation from mutating objective_score_avg with leader_extra subtotal (which inflated cohort comparisons). Full scope at #229.';

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
      UPDATE public.selection_applications SET interview_score = v_pert_score,
        final_score = COALESCE(objective_score_avg, 0) + v_pert_score + COALESCE(leader_extra_pert_score, 0),
        status = 'final_eval', updated_at = now()
      WHERE id = p_application_id;
    ELSIF p_evaluation_type = 'leader_extra' THEN
      -- p209/A2-minimal: store leader_extra PERT separately (was mutating objective_score_avg, breaking cohort math).
      UPDATE public.selection_applications SET
        leader_extra_pert_score = v_pert_score,
        final_score = COALESCE(objective_score_avg, 0) + COALESCE(interview_score, 0) + v_pert_score,
        updated_at = now()
      WHERE id = p_application_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'evaluation_id', v_eval_id, 'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score, 'new_status', v_new_status
  );
END;
$function$;

INSERT INTO supabase_migrations.schema_migrations (version, name)
VALUES ('20260802000004', 'p209_a2_minimal_leader_extra_isolation')
ON CONFLICT (version) DO NOTHING;
