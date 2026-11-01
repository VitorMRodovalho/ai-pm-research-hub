-- #2905 (decisão do GP em 01/11/2026): a sugestão de IA de tipo `video` só sai para quem passa no portão do
-- vídeo (ADR-0134, portão provisório de get_application_video_screenings). A sugestão que já existe fica
-- MANTIDA e ESCONDIDA: nada é apagado.
--
-- O portão do vídeo: membro ativo; candidatura da organização do caller e não anonimizada; manage_platform OU
-- assento lead/evaluator do comitê do ciclo da candidatura; e sem impedimento por conflito de interesse
-- (ADR-0109). Ele passa a morar em _passa_no_portao_do_video(uuid), que as duas leituras de sugestão chamam.
-- get_application_video_screenings segue com o portão escrito no próprio corpo; o guard
-- 2905-sugestao-de-video-pelo-portao confere que os dois dizem a mesma coisa.
--
-- get_ai_suggestion(p_application_id, 'video'): quem não passa recebe a mesma recusa de quem não é do comitê.
-- list_ai_suggestions: as linhas de tipo `video` ficam fora para quem não passa. Os outros tipos seguem a
-- regra de antes, inclusive o caminho por manage_member.
-- Fora isso, os dois corpos são os das capturas vigentes (20260516200000 e 20260802000001). O md5 do corpo vivo
-- de cada uma foi conferido em 01/11/2026 14:26Z contra a captura: 9ceb0701 e daf85daa, sem divergência.

CREATE OR REPLACE FUNCTION public._passa_no_portao_do_video(p_application_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT sa.cycle_id INTO v_cycle_id
  FROM public.selection_applications sa
  WHERE sa.id = p_application_id
    AND sa.organization_id = public.auth_org()
    AND sa.anonymized_at IS NULL;
  IF v_cycle_id IS NULL THEN
    RETURN false;
  END IF;

  IF NOT (
    public.can_by_member(v_caller_id, 'manage_platform')
    OR EXISTS (
      SELECT 1
      FROM public.selection_committee sc
      WHERE sc.cycle_id = v_cycle_id
        AND sc.member_id = v_caller_id
        AND sc.role IN ('lead', 'evaluator')
    )
  ) THEN
    RETURN false;
  END IF;

  RETURN NOT public.selection_coi_recused(v_caller_id, v_cycle_id);
END;
$function$;

REVOKE ALL ON FUNCTION public._passa_no_portao_do_video(uuid) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._passa_no_portao_do_video(uuid) IS
  'ADR-0134 (#2905): o caller passa no portão do vídeo da candidatura? Membro ativo, mesma organização, candidatura não anonimizada, manage_platform ou assento lead/evaluator do ciclo, sem conflito de interesse. Só para funções SECURITY DEFINER.';

CREATE OR REPLACE FUNCTION public.get_ai_suggestion(
  p_application_id uuid,
  p_evaluation_type text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_result jsonb;
  v_authorized boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM selection_applications a
    JOIN selection_committee sc ON sc.cycle_id = a.cycle_id
    JOIN members m ON m.id = sc.member_id
    WHERE a.id = p_application_id
      AND m.auth_id = auth.uid()
  ) INTO v_authorized;

  -- #2905: a sugestão de vídeo segue o portão do vídeo
  IF v_authorized AND p_evaluation_type = 'video' THEN
    v_authorized := public._passa_no_portao_do_video(p_application_id);
  END IF;

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Not authorized to read AI suggestions for this application'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT jsonb_build_object(
    'exists', true,
    'id', s.id,
    'suggested_scores', s.suggested_scores,
    'suggested_criterion_notes', s.suggested_criterion_notes,
    'suggested_overall_summary', s.suggested_overall_summary,
    'suggested_weighted_subtotal', s.suggested_weighted_subtotal,
    'model_provider', s.model_provider,
    'model_name', s.model_name,
    'prompt_version', s.prompt_version,
    'generated_at', s.generated_at,
    'is_consumed', s.consumed_at IS NOT NULL,
    'used_in_evaluation_id', s.used_in_evaluation_id
  )
    INTO v_result
  FROM selection_evaluation_ai_suggestions s
  WHERE s.application_id = p_application_id
    AND s.evaluation_type = p_evaluation_type
    AND s.superseded_by IS NULL
  ORDER BY s.generated_at DESC
  LIMIT 1;

  RETURN COALESCE(v_result, jsonb_build_object('exists', false));
END;
$function$;

REVOKE ALL ON FUNCTION public.get_ai_suggestion(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ai_suggestion(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_ai_suggestions(p_application_id uuid, p_evaluation_type text DEFAULT NULL::text, p_only_pending boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_app record;
  v_is_committee boolean;
  v_can_admin boolean;
  v_ve_video boolean;
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

  -- #2905: a sugestão de vídeo segue o portão do vídeo
  v_ve_video := public._passa_no_portao_do_video(p_application_id);

  -- Light audit log (this surface exposes AI inputs — track access)
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
    AND (s.evaluation_type IS DISTINCT FROM 'video' OR v_ve_video)
    AND (NOT p_only_pending OR (s.used_in_evaluation_id IS NULL AND s.superseded_by IS NULL));

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'evaluation_type_filter', p_evaluation_type,
    'only_pending', p_only_pending,
    'count', jsonb_array_length(v_results),
    'suggestions', v_results
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.list_ai_suggestions(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_ai_suggestions(uuid, text, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
