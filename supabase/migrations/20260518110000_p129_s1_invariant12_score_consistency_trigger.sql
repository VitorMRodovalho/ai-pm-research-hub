-- p129 S1 Item #7: Invariant 12 + trigger for score consistency
-- Driver: ARM_PILLARS_AUDIT_P107 (R2) — score caches in selection_applications can
-- diverge silently from selection_evaluations. Confirmed drift in 2 rows (cycle 2:
-- Hayala Curto, Ana Carla Cavalcante).
--
-- Implements:
--   1. helper _recompute_application_pert(app_id) — recalculates PERT scores from
--      submitted evaluations (idempotent)
--   2. trigger trg_recompute_app_pert AFTER INSERT/UPDATE/DELETE on selection_evaluations
--   3. detection function check_application_score_consistency() — invariant 12 surface
--
-- Trigger does NOT advance application.status — that remains submit_evaluation's
-- responsibility (gated by cycle median × 0.75 cutoff). Trigger only keeps PERT
-- caches in sync with evaluations.

CREATE OR REPLACE FUNCTION public._recompute_application_pert(p_application_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_cycle_min int;
  v_obj_pert numeric;
  v_int_pert numeric;
  v_subtotals numeric[];
  v_min numeric;
  v_max numeric;
  v_avg numeric;
BEGIN
  SELECT c.min_evaluators INTO v_cycle_min
  FROM selection_applications a
  JOIN selection_cycles c ON c.id = a.cycle_id
  WHERE a.id = p_application_id;

  IF v_cycle_min IS NULL THEN v_cycle_min := 2; END IF;

  -- Objective PERT
  SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal) INTO v_subtotals
  FROM selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'objective' AND submitted_at IS NOT NULL;

  IF v_subtotals IS NOT NULL AND array_length(v_subtotals, 1) >= v_cycle_min THEN
    v_min := v_subtotals[1];
    v_max := v_subtotals[array_upper(v_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg FROM unnest(v_subtotals);
    v_obj_pert := ROUND((2 * v_min + 4 * v_avg + 2 * v_max) / 8, 2);
  ELSE
    v_obj_pert := NULL;
  END IF;

  -- Interview PERT
  SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal) INTO v_subtotals
  FROM selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'interview' AND submitted_at IS NOT NULL;

  IF v_subtotals IS NOT NULL AND array_length(v_subtotals, 1) >= 1 THEN
    v_min := v_subtotals[1];
    v_max := v_subtotals[array_upper(v_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg FROM unnest(v_subtotals);
    v_int_pert := ROUND((2 * v_min + 4 * v_avg + 2 * v_max) / 8, 2);
  ELSE
    v_int_pert := NULL;
  END IF;

  -- Idempotent UPDATE: only writes if value differs (avoids trigger recursion + churn)
  UPDATE selection_applications
  SET
    objective_score_avg = v_obj_pert,
    interview_score = v_int_pert,
    updated_at = now()
  WHERE id = p_application_id
    AND (
      COALESCE(objective_score_avg, -999999) <> COALESCE(v_obj_pert, -999999)
      OR COALESCE(interview_score, -999999) <> COALESCE(v_int_pert, -999999)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public._trg_recompute_app_pert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public._recompute_application_pert(OLD.application_id);
  ELSE
    PERFORM public._recompute_application_pert(NEW.application_id);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_recompute_app_pert ON public.selection_evaluations;
CREATE TRIGGER trg_recompute_app_pert
AFTER INSERT OR UPDATE OR DELETE ON public.selection_evaluations
FOR EACH ROW EXECUTE FUNCTION public._trg_recompute_app_pert();

COMMENT ON TRIGGER trg_recompute_app_pert ON public.selection_evaluations IS
  'p129 S1 Item #7 — Defense-in-depth: recomputes objective_score_avg + interview_score PERT caches whenever evaluations change. Idempotent. Does NOT promote application.status (remains submit_evaluation responsibility).';

-- Detection invariant
CREATE OR REPLACE FUNCTION public.check_application_score_consistency()
RETURNS TABLE(application_id uuid, evaluation_type text, cached numeric, computed numeric, n_evals int, drift numeric)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  WITH eval_stats AS (
    SELECT
      e.application_id, e.evaluation_type,
      COUNT(*)::int AS n,
      MIN(e.weighted_subtotal) AS mn,
      AVG(e.weighted_subtotal) AS av,
      MAX(e.weighted_subtotal) AS mx
    FROM selection_evaluations e
    JOIN selection_applications a ON a.id = e.application_id
    JOIN selection_cycles c ON c.id = a.cycle_id
    WHERE e.submitted_at IS NOT NULL
    GROUP BY e.application_id, e.evaluation_type
    HAVING COUNT(*) >= COALESCE((
      SELECT min_evaluators FROM selection_cycles c2
      JOIN selection_applications a2 ON a2.cycle_id = c2.id
      WHERE a2.id = e.application_id
      LIMIT 1
    ), 2)
  )
  SELECT
    a.id,
    es.evaluation_type,
    CASE es.evaluation_type
      WHEN 'objective' THEN a.objective_score_avg
      WHEN 'interview' THEN a.interview_score
    END AS cached,
    ROUND((2*es.mn + 4*es.av + 2*es.mx)/8, 2) AS computed,
    es.n,
    ABS(
      COALESCE(
        CASE es.evaluation_type
          WHEN 'objective' THEN a.objective_score_avg
          WHEN 'interview' THEN a.interview_score
        END, -999999
      ) - ROUND((2*es.mn + 4*es.av + 2*es.mx)/8, 2)
    ) AS drift
  FROM selection_applications a
  JOIN eval_stats es ON es.application_id = a.id
  WHERE es.evaluation_type IN ('objective', 'interview')
    AND ABS(
      COALESCE(
        CASE es.evaluation_type
          WHEN 'objective' THEN a.objective_score_avg
          WHEN 'interview' THEN a.interview_score
        END, -999999
      ) - ROUND((2*es.mn + 4*es.av + 2*es.mx)/8, 2)
    ) > 0.01
  ORDER BY drift DESC;
$$;

COMMENT ON FUNCTION public.check_application_score_consistency() IS
  'p129 S1 Item #7 — Invariant 12 (M_application_score_consistency). Returns rows where selection_applications.objective_score_avg or interview_score diverges from PERT-computed value. Empty result = healthy. Driven by ARM_PILLARS_AUDIT_P107 R2.';

GRANT EXECUTE ON FUNCTION public.check_application_score_consistency() TO authenticated;

NOTIFY pgrst, 'reload schema';
