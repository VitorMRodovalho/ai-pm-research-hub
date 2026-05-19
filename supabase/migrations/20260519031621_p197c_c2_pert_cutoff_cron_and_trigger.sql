-- p197c C2 (2026-05-19): automatic PERT cutoff refresh — refactor compute_pert_cutoff into
-- a thin auth wrapper over _compute_pert_cutoff_core, add recompute_all_active_pert_cutoffs
-- helper for cron, schedule weekly + on-phase-transition trigger.
--
-- Motivation: cycle3-2026-b2 (evaluating, 2 apps) has NEVER had pert computed; cycle4-2026
-- last calc was 9 days ago. The cohort of approved active members shifts as offboards/
-- onboards happen — comitê can decide against a stale band.
--
-- Architecture:
-- - _compute_pert_cutoff_core(cycle_id, role, filter_active_only, score_column, actor_id):
--   internal SECURITY DEFINER. Pure logic, no auth gate. Accepts actor_id NULL when
--   triggered by cron.
-- - compute_pert_cutoff(...): user-facing entrypoint. Auth via can_by_member('manage_member'),
--   then delegates to _core with caller as actor.
-- - recompute_all_active_pert_cutoffs(): iterates cycles in phases evaluating/interviews/
--   open_apps, runs _core for role='researcher'. Returns jsonb with per-cycle results.
-- - cron weekly job 'recompute-pert-cutoffs-weekly' (Monday 13:00 UTC).
-- - trigger trg_pert_cutoff_on_evaluating_phase: AFTER UPDATE ON selection_cycles WHEN
--   NEW.phase = 'evaluating' AND OLD.phase != NEW.phase — fires _core for that cycle.

-- 1) Internal core (no auth gate)
CREATE OR REPLACE FUNCTION public._compute_pert_cutoff_core(
  p_cycle_id uuid,
  p_role text DEFAULT 'researcher',
  p_filter_active_only boolean DEFAULT true,
  p_score_column text DEFAULT 'objective_score_avg',
  p_actor_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_cycle record;
  v_cohort record;
  v_target numeric;
  v_band_lower numeric;
  v_band_upper numeric;
  v_method text;
  v_n int;
  v_updated_rows int;
  v_fallback_target numeric;
BEGIN
  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score') THEN
    RETURN jsonb_build_object('error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg', 'final_score', 'research_score'),
      'received', p_score_column);
  END IF;

  SELECT sc.id, sc.cycle_code INTO v_cycle FROM public.selection_cycles sc WHERE sc.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('error', 'cycle_not_found', 'cycle_id', p_cycle_id);
  END IF;

  WITH prior_cycles AS (
    SELECT id FROM public.selection_cycles
    WHERE id != p_cycle_id
      AND created_at < (SELECT created_at FROM public.selection_cycles WHERE id = p_cycle_id)
  ),
  cohort_apps AS (
    SELECT CASE p_score_column
        WHEN 'objective_score_avg' THEN sa.objective_score_avg
        WHEN 'final_score' THEN sa.final_score
        WHEN 'research_score' THEN sa.research_score
      END AS s
    FROM public.selection_applications sa
    WHERE sa.cycle_id IN (SELECT id FROM prior_cycles)
      AND sa.role_applied = p_role
      AND sa.status = 'approved'
      AND CASE p_score_column
            WHEN 'objective_score_avg' THEN sa.objective_score_avg IS NOT NULL
            WHEN 'final_score' THEN sa.final_score IS NOT NULL
            WHEN 'research_score' THEN sa.research_score IS NOT NULL
          END
      AND (NOT p_filter_active_only OR EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.persons pp ON pp.id = e.person_id
          WHERE pp.legacy_member_id IS NOT NULL AND e.kind = 'volunteer'
            AND e.role = p_role AND e.status = 'active'
            AND lower(coalesce(sa.email,'')) IN (
              SELECT lower(m.email) FROM public.members m
              WHERE m.id = pp.legacy_member_id AND m.email IS NOT NULL)))
  )
  SELECT COUNT(*)::int AS n, MIN(s) AS s_min, MAX(s) AS s_max, AVG(s) AS s_avg
  INTO v_cohort FROM cohort_apps;

  v_n := COALESCE(v_cohort.n, 0);

  IF v_n >= 10 THEN
    v_target := (2 * v_cohort.s_min + 4 * v_cohort.s_avg + 2 * v_cohort.s_max) / 8;
    v_method := 'dynamic';
  ELSE
    SELECT MAX(pert_target_score) INTO v_fallback_target
    FROM public.selection_applications
    WHERE pert_target_score IS NOT NULL AND cycle_id != p_cycle_id;
    IF v_fallback_target IS NULL THEN
      v_target := NULL; v_method := 'disabled';
    ELSE
      v_target := v_fallback_target; v_method := 'historical_fallback';
    END IF;
  END IF;

  IF v_target IS NOT NULL THEN
    v_band_lower := v_target * 0.90;
    v_band_upper := v_target * 1.10;
  END IF;

  UPDATE public.selection_applications
  SET pert_target_score = v_target, pert_band_lower = v_band_lower,
      pert_band_upper = v_band_upper, pert_cutoff_method = v_method,
      pert_cohort_n = v_n, pert_calc_at = now()
  WHERE cycle_id = p_cycle_id;
  GET DIAGNOSTICS v_updated_rows = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (p_actor_id, 'pert_cutoff_computed', 'selection_cycle', p_cycle_id,
    jsonb_build_object('cycle_code', v_cycle.cycle_code, 'role', p_role,
      'score_column_used', p_score_column, 'filter_active_only', p_filter_active_only,
      'cohort_n', v_n, 'cohort_min', v_cohort.s_min, 'cohort_max', v_cohort.s_max,
      'cohort_avg', v_cohort.s_avg, 'target_score', v_target, 'band_lower', v_band_lower,
      'band_upper', v_band_upper, 'method', v_method, 'rows_updated', v_updated_rows),
    jsonb_build_object('source', '_compute_pert_cutoff_core',
      'actor_kind', CASE WHEN p_actor_id IS NULL THEN 'system' ELSE 'human' END));

  RETURN jsonb_build_object('success', true, 'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code, 'role', p_role, 'score_column_used', p_score_column,
    'cohort_n', v_n,
    'cohort_stats', jsonb_build_object('min', v_cohort.s_min, 'max', v_cohort.s_max, 'avg', v_cohort.s_avg),
    'target_score', v_target, 'band_lower', v_band_lower, 'band_upper', v_band_upper,
    'method', v_method, 'rows_updated', v_updated_rows, 'computed_at', now());
END;
$$;

-- 2) Public entrypoint becomes thin wrapper around _core
DROP FUNCTION IF EXISTS public.compute_pert_cutoff(uuid, text, boolean, text);
CREATE OR REPLACE FUNCTION public.compute_pert_cutoff(
  p_cycle_id uuid, p_role text DEFAULT 'researcher',
  p_filter_active_only boolean DEFAULT true,
  p_score_column text DEFAULT 'objective_score_avg')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_caller record;
BEGIN
  SELECT m.id, m.name INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_member');
  END IF;
  RETURN public._compute_pert_cutoff_core(p_cycle_id, p_role, p_filter_active_only, p_score_column, v_caller.id);
END;
$$;

-- 3) Helper: recompute all active cycles (called by cron + trigger)
CREATE OR REPLACE FUNCTION public.recompute_all_active_pert_cutoffs()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_cycle record;
  v_results jsonb := '[]'::jsonb;
  v_n int := 0;
  v_result jsonb;
BEGIN
  FOR v_cycle IN SELECT id, cycle_code, phase FROM public.selection_cycles
    WHERE phase IN ('evaluating', 'interviews', 'open_apps') ORDER BY created_at DESC LOOP
    v_result := public._compute_pert_cutoff_core(v_cycle.id, 'researcher', true, 'objective_score_avg', NULL);
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'cycle_code', v_cycle.cycle_code, 'phase', v_cycle.phase, 'result', v_result));
    v_n := v_n + 1;
  END LOOP;
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (NULL, 'pert_cutoff_recompute_batch', 'selection_cycles', NULL,
    jsonb_build_object('cycles_processed', v_n, 'per_cycle', v_results),
    jsonb_build_object('source', 'recompute_all_active_pert_cutoffs'));
  RETURN jsonb_build_object('success', true, 'cycles_processed', v_n, 'per_cycle', v_results);
END;
$$;

GRANT EXECUTE ON FUNCTION public.recompute_all_active_pert_cutoffs() TO postgres;

-- 4) Trigger on phase transition into 'evaluating'
CREATE OR REPLACE FUNCTION public._trg_pert_on_phase_evaluating()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.phase = 'evaluating' AND (OLD.phase IS DISTINCT FROM NEW.phase) THEN
    PERFORM public._compute_pert_cutoff_core(NEW.id, 'researcher', true, 'objective_score_avg', NULL);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pert_cutoff_on_evaluating_phase ON public.selection_cycles;
CREATE TRIGGER trg_pert_cutoff_on_evaluating_phase
  AFTER UPDATE OF phase ON public.selection_cycles
  FOR EACH ROW EXECUTE FUNCTION public._trg_pert_on_phase_evaluating();

-- 5) Schedule weekly cron job (Monday 13:00 UTC = 10:00 SP-tz)
DO $body$
DECLARE v_existing int; BEGIN
  SELECT count(*) INTO v_existing FROM cron.job WHERE jobname = 'recompute-pert-cutoffs-weekly';
  IF v_existing > 0 THEN PERFORM cron.unschedule('recompute-pert-cutoffs-weekly'); END IF;
  PERFORM cron.schedule('recompute-pert-cutoffs-weekly', '0 13 * * 1',
    $cron$ SELECT public.recompute_all_active_pert_cutoffs() $cron$);
END $body$;

COMMENT ON FUNCTION public._compute_pert_cutoff_core(uuid, text, boolean, text, uuid) IS
  'p197c C2 (2026-05-19): internal PERT cutoff computation core. No auth gate — callers (compute_pert_cutoff for users, recompute_all_active_pert_cutoffs for cron, _trg_pert_on_phase_evaluating for phase trigger) handle authorization. actor_id NULL = system/cron run.';

COMMENT ON FUNCTION public.recompute_all_active_pert_cutoffs() IS
  'p197c C2: iterates all cycles in phase evaluating/interviews/open_apps and refreshes pert_target/band via _compute_pert_cutoff_core for role=researcher. Scheduled weekly via pg_cron job recompute-pert-cutoffs-weekly (Monday 13:00 UTC). Returns jsonb with per-cycle results + audit_log entry.';
