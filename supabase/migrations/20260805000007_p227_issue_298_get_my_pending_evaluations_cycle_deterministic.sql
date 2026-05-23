-- p227 — Issue #298 (Cycle 4 selection trust audit p226 finding A)
-- Fix get_my_pending_evaluations() cycle non-determinism + gate misalignment.
--
-- Problem (audit p226 / PR #297 / docs/audit/CYCLE4_TRUST_AUDIT_P226.md):
--   1. SELECT * INTO v_cycle FROM selection_cycles WHERE phase='evaluating' LIMIT 1
--      had no ORDER BY -> non-deterministic picker when 2+ cycles in 'evaluating'.
--   2. Authorization gate checked membership against ANY evaluating committee
--      (JOIN selection_cycles ON phase='evaluating'), but picker could select a
--      different cycle -> caller scoped to wrong cycle, possibly seeing pending
--      list of a cycle they are not on. Latent privilege misalignment.
--
-- Fix (Option A+ per PM ABCD decision 2026-05-23):
--   1. Pick newest evaluating cycle deterministically: ORDER BY created_at DESC LIMIT 1.
--   2. Re-order flow: pick cycle FIRST, then gate scoped to picked cycle (sc.cycle_id = v_cycle.id).
--   3. Empty-cycle short-circuit returns consistent empty payload regardless of caller
--      (no information leak; no pending data is returned in either branch).
--
-- Post-fix behavior:
--   - Fabricio (cycle3-2026-b2 evaluator only, NOT on cycle4-2026 committee):
--     receives Unauthorized when cycle4-2026 is newest evaluating cycle.
--     Resolves once PM seeds cycle4-2026 committee (audit Item 6, separate PM decision).
--   - Vitor (manage_member via can_by_member): sees pending list for cycle4-2026.
--   - Any cycle4-2026 committee member (post-seed): sees pending list for cycle4-2026.
--   - Anonymous/unauthenticated: existing 'Not authenticated' branch unchanged.
--
-- Rollback: restore prior body from
-- supabase/migrations/20260684000000_p178_phase_b_drift_capture_1_touch_a_g_69fns.sql
-- (drift capture of ADR-0059 W3 original) by re-running CREATE OR REPLACE with that body.
-- Note: rolling back re-exposes the non-determinism + gate misalignment; not recommended.

CREATE OR REPLACE FUNCTION public.get_my_pending_evaluations()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_cycle record;
  v_pending jsonb;
  v_completed_count int;
  v_total_count int;
BEGIN
  -- Authenticate caller
  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Pick newest evaluating cycle deterministically (fix #298 A+ part 1)
  SELECT * INTO v_cycle FROM public.selection_cycles
  WHERE phase = 'evaluating'
  ORDER BY created_at DESC
  LIMIT 1;

  -- No evaluating cycle -> return empty consistently (no info leak)
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('cycle', null, 'pending', '[]'::jsonb, 'completed_count', 0, 'total_count', 0);
  END IF;

  -- Gate scoped to picked cycle's committee OR admin manage_member bypass (fix #298 A+ part 2)
  IF NOT EXISTS (
    SELECT 1 FROM public.selection_committee sc
    WHERE sc.member_id = v_caller_member_id AND sc.cycle_id = v_cycle.id
  ) AND NOT public.can_by_member(v_caller_member_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: caller is not on this cycle committee'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Pending = applications in cycle where caller hasn't submitted yet
  SELECT jsonb_agg(jsonb_build_object(
    'application_id', sa.id,
    'applicant_name', sa.applicant_name,
    'role_applied', sa.role_applied,
    'promotion_path', sa.promotion_path,
    'created_at', sa.created_at,
    'has_my_evaluation_in_progress',
      EXISTS (SELECT 1 FROM public.selection_evaluations se
              WHERE se.application_id = sa.id AND se.evaluator_id = v_caller_member_id
                AND se.submitted_at IS NULL)
  ) ORDER BY sa.created_at)
  INTO v_pending
  FROM public.selection_applications sa
  WHERE sa.cycle_id = v_cycle.id
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations se
      WHERE se.application_id = sa.id
        AND se.evaluator_id = v_caller_member_id
        AND se.submitted_at IS NOT NULL
    );

  -- Counts for fila health
  SELECT count(*)
  INTO v_completed_count
  FROM public.selection_applications sa
  JOIN public.selection_evaluations se ON se.application_id = sa.id
  WHERE sa.cycle_id = v_cycle.id
    AND se.evaluator_id = v_caller_member_id
    AND se.submitted_at IS NOT NULL;

  SELECT count(*) INTO v_total_count FROM public.selection_applications WHERE cycle_id = v_cycle.id;

  RETURN jsonb_build_object(
    'cycle_code', v_cycle.cycle_code,
    'cycle_phase', v_cycle.phase,
    'pending', COALESCE(v_pending, '[]'::jsonb),
    'pending_count', COALESCE(jsonb_array_length(v_pending), 0),
    'completed_count', v_completed_count,
    'total_count', v_total_count,
    'progress_pct', CASE WHEN v_total_count > 0 THEN round((v_completed_count::numeric / v_total_count) * 100, 1) ELSE 0 END
  );
END;
$$;

COMMENT ON FUNCTION public.get_my_pending_evaluations() IS
  'ADR-0059 W3 (#87 ux Pareto #1, fix #298 p227 A+): committee member fila pessoal. Returns applications no newest evaluating cycle (ORDER BY created_at DESC LIMIT 1) onde caller ainda nao submitted. Gate scoped to picked cycle (caller must be on that cycle committee OR have manage_member). Empty-cycle returns consistent empty payload regardless of caller. Includes has_my_evaluation_in_progress flag for incomplete drafts.';

NOTIFY pgrst, 'reload schema';
