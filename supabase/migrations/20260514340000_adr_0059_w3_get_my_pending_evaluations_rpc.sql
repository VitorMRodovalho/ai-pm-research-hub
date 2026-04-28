-- ADR-0059 W3 — get_my_pending_evaluations: fila do avaliador
-- ux-leader Pareto #1 — fecha gap de gerenciamento de fila pessoal (#87 FP-02)

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
  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.selection_committee sc
    JOIN public.selection_cycles c ON c.id = sc.cycle_id
    WHERE sc.member_id = v_caller_member_id AND c.phase = 'evaluating'
  ) AND NOT public.can_by_member(v_caller_member_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: caller is not on active evaluating committee'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE phase = 'evaluating' LIMIT 1;
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('cycle', null, 'pending', '[]'::jsonb, 'completed_count', 0, 'total_count', 0);
  END IF;

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
  'ADR-0059 W3 (#87 ux Pareto #1): committee member fila pessoal. Returns applications no current evaluating cycle onde caller ainda nao submitted. Skips applications onde caller ja submitted (status final). Includes has_my_evaluation_in_progress flag for incomplete drafts.';

NOTIFY pgrst, 'reload schema';
