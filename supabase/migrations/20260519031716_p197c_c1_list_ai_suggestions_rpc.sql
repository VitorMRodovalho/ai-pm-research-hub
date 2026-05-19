-- p197c C1 (2026-05-19): consumer surface for ai_suggestion_id. Generator
-- (analyze_application/selection_evaluation_ai_suggestions) exists with schema in place
-- but table is currently empty (0 rows) — when content lands, evaluators/committee will be
-- able to discover suggestions via this RPC and reference them via ai_suggestion_id in
-- submit_evaluation. Pre-positioning the consumer so the producer→consumer loop is closed.

CREATE OR REPLACE FUNCTION public.list_ai_suggestions(
  p_application_id uuid,
  p_evaluation_type text DEFAULT NULL,
  p_only_pending boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_app record;
  v_is_committee boolean;
  v_can_admin boolean;
  v_results jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id, cycle_id INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  v_is_committee := EXISTS (
    SELECT 1 FROM public.selection_committee
    WHERE cycle_id = v_app.cycle_id AND member_id = v_caller_id
  );
  v_can_admin := public.can_by_member(v_caller_id, 'manage_member');
  IF NOT (v_is_committee OR v_can_admin) THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'committee or manage_member');
  END IF;

  PERFORM public._log_application_pii_access(
    p_application_id, v_caller_id,
    ARRAY['ai_suggestions'],
    'list_ai_suggestions:' || COALESCE(p_evaluation_type, 'all')
  );

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'evaluation_type', s.evaluation_type,
    'suggested_scores', s.suggested_scores,
    'suggested_criterion_notes', s.suggested_criterion_notes,
    'suggested_weighted_subtotal', s.suggested_weighted_subtotal,
    'suggested_overall_summary', s.suggested_overall_summary,
    'model_provider', s.model_provider,
    'model_name', s.model_name,
    'prompt_version', s.prompt_version,
    'generation_cost_usd', s.generation_cost_usd,
    'generation_latency_ms', s.generation_latency_ms,
    'used_in_evaluation_id', s.used_in_evaluation_id,
    'superseded_by', s.superseded_by,
    'generated_at', s.generated_at,
    'consumed_at', s.consumed_at,
    'is_pending', (s.used_in_evaluation_id IS NULL AND s.superseded_by IS NULL)
  ) ORDER BY s.generated_at DESC), '[]'::jsonb)
  INTO v_results
  FROM public.selection_evaluation_ai_suggestions s
  WHERE s.application_id = p_application_id
    AND (p_evaluation_type IS NULL OR s.evaluation_type = p_evaluation_type)
    AND (NOT p_only_pending OR (s.used_in_evaluation_id IS NULL AND s.superseded_by IS NULL));

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'evaluation_type_filter', p_evaluation_type,
    'only_pending', p_only_pending,
    'count', jsonb_array_length(v_results),
    'suggestions', v_results
  );
END;
$$;

COMMENT ON FUNCTION public.list_ai_suggestions(uuid, text, boolean) IS
  'p197c C1 (2026-05-19): consumer surface for selection_evaluation_ai_suggestions. Returns suggestions filtered by application_id (+ optional evaluation_type + only_pending). Closes the producer→consumer loop: analyze_application generates, submit_evaluation accepts via ai_suggestion_id. Auth: committee membership of cycle OR manage_member. Logs PII access.';

GRANT EXECUTE ON FUNCTION public.list_ai_suggestions(uuid, text, boolean) TO authenticated;
