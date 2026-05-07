-- p113 — Onda 5 Fase 3: drill-down validações por validador.
-- Returns detailed list of validations for a single validator with applicant info + cycle code + comment.
-- V4 auth: view_internal_analytics (same as dashboard).
-- Rollback: DROP FUNCTION public.list_validations_by_validator(uuid, int, uuid);

CREATE OR REPLACE FUNCTION public.list_validations_by_validator(
  p_validator_id uuid,
  p_limit int DEFAULT 50,
  p_cycle_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_validations jsonb;
  v_validator_name text;
  v_effective_limit int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  SELECT name INTO v_validator_name FROM public.members WHERE id = p_validator_id;

  v_effective_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', v.id,
    'application_id', v.application_id,
    'applicant_name', COALESCE(NULLIF(a.applicant_name, ''), 'Anônimo'),
    'cycle_code', c.cycle_code,
    'application_status', a.status,
    'ai_purpose', v.ai_purpose,
    'ai_model', v.ai_model,
    'ai_score', v.ai_score,
    'ai_verdict', v.ai_verdict,
    'validation_action', v.validation_action,
    'override_score', v.override_score,
    'comment', v.comment,
    'validated_at', v.validated_at
  ) ORDER BY v.validated_at DESC), '[]'::jsonb) INTO v_validations
  FROM (
    SELECT *
    FROM public.ai_score_validations
    WHERE validator_id = p_validator_id
    ORDER BY validated_at DESC
    LIMIT v_effective_limit
  ) v
  LEFT JOIN public.selection_applications a ON a.id = v.application_id
  LEFT JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE p_cycle_id IS NULL OR a.cycle_id = p_cycle_id;

  RETURN jsonb_build_object(
    'validator_id', p_validator_id,
    'validator_name', v_validator_name,
    'validations', v_validations,
    'count', jsonb_array_length(v_validations),
    'cycle_filter', p_cycle_id,
    'limit', v_effective_limit
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_validations_by_validator(uuid, int, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_validations_by_validator(uuid, int, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
