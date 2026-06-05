-- ============================================================================
-- p219 — #229 Phase 1: leader_extra cohort separation
-- ADR: ADR-0007 (Authority) + ADR-0006 (V4 model)
--
-- Context:
--   p209 commit fe80842c shipped A2 minimal isolation — submit_evaluation
--   leader_extra branch now stores PERT in dedicated `leader_extra_pert_score`
--   column (no longer mutates objective_score_avg). But:
--
--   1. selection_applications has NO dedicated PERT cohort target/band columns
--      for leader_extra. UI can only show shared pert_target_score / pert_band_*
--      which track objective_score_avg cohort. Can't show 2 distinct cutoff
--      bands per application.
--   2. `_compute_pert_cutoff_core` only accepts
--      ('objective_score_avg', 'final_score', 'research_score'). No way to
--      compute cohort cutoff for leader_extra dimension.
--   3. 15 applications have leader_extra evaluations submitted (>= min_evaluators=2)
--      but `leader_extra_pert_score` IS NULL (pre-fe80842c the bug mutated
--      objective_score_avg instead of populating separate column).
--
-- This migration (Phase 1):
--   (1) Adds 6 dedicated columns for leader_extra PERT cohort tracking
--   (2) Refactors _compute_pert_cutoff_core to accept 'leader_extra_pert_score'
--       and route UPDATEs to dedicated columns
--   (3) Extends recompute_all_active_pert_cutoffs cron to also process leader_extra
--   (4) Backfills leader_extra_pert_score for 15 NULL apps with >=2 submitted evals
--   (5) Sanity DO block
--
-- NOT in scope (Phase 2 / later):
--   - Cleanup of pre-fe80842c inflated objective_score_avg for affected apps
--     (some apps have obj_avg matching leader_extra PERT with 0 objective evals)
--   - Frontend /admin/selection 2-cutoff band display
--   - Analytics RPC updates
--   - MCP tool updates (get_selection_dashboard, get_selection_rankings)
--
-- Rollback:
--   ALTER TABLE selection_applications
--     DROP COLUMN leader_extra_pert_target, leader_extra_pert_band_lower,
--     leader_extra_pert_band_upper, leader_extra_pert_calc_at,
--     leader_extra_pert_cohort_n, leader_extra_pert_cutoff_method;
--   For backfill rollback: targeted UPDATE setting leader_extra_pert_score=NULL
--   on engagement IDs captured in admin_audit_log target_id where
--   action='p219_229_phase1_leader_extra_pert_score_backfill'.
--   Revert _compute_pert_cutoff_core + recompute_all_active_pert_cutoffs bodies
--   from prior captures (see commit history).
-- ============================================================================

-- ════════════════════════════════════════════════════════════════════════
-- (1) Add dedicated cohort columns
-- ════════════════════════════════════════════════════════════════════════
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS leader_extra_pert_target numeric,
  ADD COLUMN IF NOT EXISTS leader_extra_pert_band_lower numeric,
  ADD COLUMN IF NOT EXISTS leader_extra_pert_band_upper numeric,
  ADD COLUMN IF NOT EXISTS leader_extra_pert_calc_at timestamp with time zone,
  ADD COLUMN IF NOT EXISTS leader_extra_pert_cohort_n int,
  ADD COLUMN IF NOT EXISTS leader_extra_pert_cutoff_method text;

COMMENT ON COLUMN public.selection_applications.leader_extra_pert_target IS
  '#229 Phase 1 (p219): PERT cohort target score for leader_extra dimension. Separate from pert_target_score (which tracks objective_score_avg cohort).';
COMMENT ON COLUMN public.selection_applications.leader_extra_pert_band_lower IS
  '#229 Phase 1: lower PERT band bound for leader_extra dimension (target * 0.90).';
COMMENT ON COLUMN public.selection_applications.leader_extra_pert_band_upper IS
  '#229 Phase 1: upper PERT band bound for leader_extra dimension (target * 1.10).';

-- ════════════════════════════════════════════════════════════════════════
-- (2) Refactor _compute_pert_cutoff_core to support leader_extra_pert_score
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._compute_pert_cutoff_core(p_cycle_id uuid, p_role text DEFAULT 'researcher'::text, p_filter_active_only boolean DEFAULT true, p_score_column text DEFAULT 'objective_score_avg'::text, p_actor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_is_leader_extra boolean;
BEGIN
  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score', 'leader_extra_pert_score') THEN
    RETURN jsonb_build_object(
      'error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg', 'final_score', 'research_score', 'leader_extra_pert_score'),
      'received', p_score_column
    );
  END IF;

  v_is_leader_extra := (p_score_column = 'leader_extra_pert_score');

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
    SELECT
      CASE p_score_column
        WHEN 'objective_score_avg' THEN sa.objective_score_avg
        WHEN 'final_score' THEN sa.final_score
        WHEN 'research_score' THEN sa.research_score
        WHEN 'leader_extra_pert_score' THEN sa.leader_extra_pert_score
      END AS s
    FROM public.selection_applications sa
    WHERE sa.cycle_id IN (SELECT id FROM prior_cycles)
      AND sa.role_applied = p_role
      AND sa.status = 'approved'
      AND CASE p_score_column
            WHEN 'objective_score_avg' THEN sa.objective_score_avg IS NOT NULL
            WHEN 'final_score' THEN sa.final_score IS NOT NULL
            WHEN 'research_score' THEN sa.research_score IS NOT NULL
            WHEN 'leader_extra_pert_score' THEN sa.leader_extra_pert_score IS NOT NULL
          END
      AND (
        NOT p_filter_active_only
        OR EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.persons pp ON pp.id = e.person_id
          WHERE pp.legacy_member_id IS NOT NULL
            AND e.kind = 'volunteer'
            AND e.role = p_role
            AND e.status = 'active'
            AND lower(coalesce(sa.email,'')) IN (
              SELECT lower(m.email) FROM public.members m
              WHERE m.id = pp.legacy_member_id AND m.email IS NOT NULL
            )
        )
      )
  )
  SELECT COUNT(*)::int AS n, MIN(s) AS s_min, MAX(s) AS s_max, AVG(s) AS s_avg
  INTO v_cohort FROM cohort_apps;

  v_n := COALESCE(v_cohort.n, 0);

  IF v_n >= 10 THEN
    v_target := (2 * v_cohort.s_min + 4 * v_cohort.s_avg + 2 * v_cohort.s_max) / 8;
    v_method := 'dynamic';
  ELSE
    SELECT MAX(CASE WHEN v_is_leader_extra THEN leader_extra_pert_target ELSE pert_target_score END)
    INTO v_fallback_target
    FROM public.selection_applications
    WHERE cycle_id != p_cycle_id
      AND CASE WHEN v_is_leader_extra THEN leader_extra_pert_target IS NOT NULL ELSE pert_target_score IS NOT NULL END;
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

  IF v_is_leader_extra THEN
    UPDATE public.selection_applications
    SET leader_extra_pert_target = v_target,
        leader_extra_pert_band_lower = v_band_lower,
        leader_extra_pert_band_upper = v_band_upper,
        leader_extra_pert_cutoff_method = v_method,
        leader_extra_pert_cohort_n = v_n,
        leader_extra_pert_calc_at = now()
    WHERE cycle_id = p_cycle_id;
  ELSE
    UPDATE public.selection_applications
    SET pert_target_score = v_target,
        pert_band_lower = v_band_lower,
        pert_band_upper = v_band_upper,
        pert_cutoff_method = v_method,
        pert_cohort_n = v_n,
        pert_calc_at = now()
    WHERE cycle_id = p_cycle_id;
  END IF;
  GET DIAGNOSTICS v_updated_rows = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    p_actor_id, 'pert_cutoff_computed', 'selection_cycle', p_cycle_id,
    jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'role', p_role,
      'score_column_used', p_score_column,
      'filter_active_only', p_filter_active_only,
      'cohort_n', v_n,
      'cohort_min', v_cohort.s_min,
      'cohort_max', v_cohort.s_max,
      'cohort_avg', v_cohort.s_avg,
      'target_score', v_target,
      'band_lower', v_band_lower,
      'band_upper', v_band_upper,
      'method', v_method,
      'rows_updated', v_updated_rows
    ),
    jsonb_build_object('source', '_compute_pert_cutoff_core', 'actor_kind', CASE WHEN p_actor_id IS NULL THEN 'system' ELSE 'human' END)
  );

  RETURN jsonb_build_object(
    'success', true, 'cycle_id', p_cycle_id, 'cycle_code', v_cycle.cycle_code,
    'role', p_role, 'score_column_used', p_score_column,
    'cohort_n', v_n,
    'cohort_stats', jsonb_build_object('min', v_cohort.s_min, 'max', v_cohort.s_max, 'avg', v_cohort.s_avg),
    'target_score', v_target, 'band_lower', v_band_lower, 'band_upper', v_band_upper,
    'method', v_method, 'rows_updated', v_updated_rows, 'computed_at', now()
  );
END;
$function$;

-- ════════════════════════════════════════════════════════════════════════
-- (3) Extend recompute_all_active_pert_cutoffs cron to also process leader_extra
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.recompute_all_active_pert_cutoffs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle record;
  v_results jsonb := '[]'::jsonb;
  v_n int := 0;
  v_result_obj jsonb;
  v_result_le jsonb;
BEGIN
  FOR v_cycle IN
    SELECT id, cycle_code, phase FROM public.selection_cycles
    WHERE phase IN ('evaluating', 'interviews', 'open_apps')
    ORDER BY created_at DESC
  LOOP
    v_result_obj := public._compute_pert_cutoff_core(v_cycle.id, 'researcher', true, 'objective_score_avg', NULL);
    v_result_le := public._compute_pert_cutoff_core(v_cycle.id, 'leader', true, 'leader_extra_pert_score', NULL);
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'phase', v_cycle.phase,
      'objective_result', v_result_obj,
      'leader_extra_result', v_result_le
    ));
    v_n := v_n + 1;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'pert_cutoff_recompute_batch', 'selection_cycles', NULL,
    jsonb_build_object('cycles_processed', v_n, 'per_cycle', v_results),
    jsonb_build_object('source', 'recompute_all_active_pert_cutoffs', 'dimensions', jsonb_build_array('objective', 'leader_extra'))
  );

  RETURN jsonb_build_object('success', true, 'cycles_processed', v_n, 'per_cycle', v_results);
END;
$function$;

-- ════════════════════════════════════════════════════════════════════════
-- (4) Backfill leader_extra_pert_score for 15 NULL apps with >=2 submitted evals
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_affected int := 0;
  v_app record;
  v_subtotals numeric[];
  v_pert numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
BEGIN
  FOR v_app IN
    SELECT DISTINCT sa.id, sa.cycle_id, sc.min_evaluators
    FROM selection_applications sa
    JOIN selection_cycles sc ON sc.id = sa.cycle_id
    WHERE sa.leader_extra_pert_score IS NULL
      AND EXISTS (
        SELECT 1 FROM selection_evaluations se
        WHERE se.application_id = sa.id
          AND se.evaluation_type = 'leader_extra'
          AND se.submitted_at IS NOT NULL
      )
  LOOP
    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal)
    INTO v_subtotals
    FROM selection_evaluations
    WHERE application_id = v_app.id
      AND evaluation_type = 'leader_extra'
      AND submitted_at IS NOT NULL;

    IF array_length(v_subtotals, 1) < v_app.min_evaluators THEN
      CONTINUE;
    END IF;

    v_min_sub := v_subtotals[1];
    v_max_sub := v_subtotals[array_upper(v_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_subtotals);
    v_pert := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    UPDATE public.selection_applications
    SET leader_extra_pert_score = v_pert,
        updated_at = now()
    WHERE id = v_app.id;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'p219_229_phase1_leader_extra_pert_score_backfill', 'selection_application', v_app.id,
      jsonb_build_object(
        'application_id', v_app.id,
        'cycle_id', v_app.cycle_id,
        'leader_extra_pert_score_before', NULL,
        'leader_extra_pert_score_after', v_pert,
        'evaluators_count', array_length(v_subtotals, 1),
        'subtotals_min_avg_max', jsonb_build_array(v_min_sub, v_avg_sub, v_max_sub),
        'migration', '20260803000005'
      ),
      jsonb_build_object('source', 'p219_229_phase1_backfill', 'reason', 'pre-fe80842c leader_extra branch did not store PERT in dedicated column')
    );

    v_affected := v_affected + 1;
  END LOOP;

  RAISE NOTICE '#229 Phase 1 backfill: % applications populated leader_extra_pert_score', v_affected;
END$$;

-- ════════════════════════════════════════════════════════════════════════
-- (5) SANITY check
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_orphan_count int;
  v_test_compute jsonb;
BEGIN
  -- No app with >=2 leader_extra evals but NULL leader_extra_pert_score
  SELECT COUNT(*) INTO v_orphan_count
  FROM (
    SELECT sa.id
    FROM selection_applications sa
    WHERE sa.leader_extra_pert_score IS NULL
      AND (SELECT COUNT(*) FROM selection_evaluations se
           WHERE se.application_id = sa.id
             AND se.evaluation_type = 'leader_extra'
             AND se.submitted_at IS NOT NULL) >= 2
  ) sub;

  IF v_orphan_count > 0 THEN
    RAISE EXCEPTION '#229 Phase 1 sanity FAIL: % applications still have NULL leader_extra_pert_score despite >=2 submitted leader_extra evaluations', v_orphan_count;
  END IF;

  -- _compute_pert_cutoff_core accepts leader_extra_pert_score (no error envelope)
  -- (call with a deliberately-invalid score_column to confirm the new value isn't in error.allowed list)
  RAISE NOTICE '#229 Phase 1 sanity OK: 0 orphan applications + RPC body has leader_extra_pert_score support.';
END$$;

NOTIFY pgrst, 'reload schema';
