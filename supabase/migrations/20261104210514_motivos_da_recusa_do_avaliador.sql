-- #2393 M2, correção: a recusa da atribuição devolve os motivos em vez de estourar.
--
-- Em PL/pgSQL, text[] || 'literal' resolve o literal como text[], e um texto comum vira 22P02 (malformed array
-- literal). As 4 recusas com motivo literal de assign_selection_evaluators estouravam, e a gestão recebia um
-- erro em vez da lista de motivos. Com ::text, o operador vira array || elemento.
-- A função é a mesma da 20261104205503, com ::text nos 4 literais e nada mais: assinatura, SECURITY DEFINER,
-- search_path e grants ficam como estão (CREATE OR REPLACE preserva os privilégios).

CREATE OR REPLACE FUNCTION public.assign_selection_evaluators(
  p_opportunity_id text, p_part text, p_member_id uuid, p_application_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller uuid;
  v_vo record;
  v_member record;
  v_app record;
  v_motivos text[] := ARRAY[]::text[];
  v_prazo timestamptz;
  v_n int := 0;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active;
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF p_part NOT IN ('objective', 'video') OR p_application_ids IS NULL OR cardinality(p_application_ids) = 0 THEN
    RETURN jsonb_build_object('error', 'Parte (objective ou video) e ao menos uma candidatura são obrigatórias.');
  END IF;
  SELECT vo.opportunity_id, vo.title, vo.initiative_id, vo.organization_id INTO v_vo FROM public.vep_opportunities vo
   WHERE vo.opportunity_id = p_opportunity_id AND vo.evaluation_track = 'line_pilot';
  IF v_vo.opportunity_id IS NULL THEN
    RETURN jsonb_build_object('error', 'A vaga não existe ou não é piloto da linha.');
  END IF;
  SELECT m.id, m.person_id, m.is_active INTO v_member FROM public.members m WHERE m.id = p_member_id;

  -- Tudo ou nada: a gestão vê todos os motivos de uma vez e nenhuma atribuição pela metade fica.
  IF v_member.id IS NULL OR NOT v_member.is_active THEN v_motivos := v_motivos || 'membro inexistente ou inativo'::text; END IF;
  IF NOT public.can_by_member(p_member_id, 'evaluate_assigned_application') THEN
    v_motivos := v_motivos || 'sem o vínculo de avaliador'::text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.selection_evaluator_calibrations c
                  WHERE c.member_id = p_member_id AND c.opportunity_id = p_opportunity_id AND c.part = p_part) THEN
    v_motivos := v_motivos || 'sem calibragem desta vaga e parte'::text;
  END IF;
  IF EXISTS (SELECT 1 FROM public.engagements e
              WHERE e.person_id = v_member.person_id AND e.initiative_id = v_vo.initiative_id AND e.status IN ('active', 'suspended')) THEN
    v_motivos := v_motivos || 'tem vínculo na iniciativa da vaga (ADR-0134 §4: avaliador de fora da linha)'::text;
  END IF;
  FOR v_app IN
    SELECT u.id AS pedido, sa.id, sa.cycle_id, sa.status, sa.vep_opportunity_id
      FROM unnest(p_application_ids) AS u(id) LEFT JOIN public.selection_applications sa ON sa.id = u.id
  LOOP
    IF v_app.id IS NULL OR v_app.vep_opportunity_id IS DISTINCT FROM p_opportunity_id THEN
      v_motivos := v_motivos || (left(v_app.pedido::text, 8) || ': não é candidatura desta vaga');
    ELSIF v_app.status IN ('rejected', 'withdrawn', 'cancelled', 'approved', 'converted') THEN
      v_motivos := v_motivos || (left(v_app.id::text, 8) || ': candidatura encerrada');
    ELSIF public.selection_coi_recused(p_member_id, v_app.cycle_id) THEN
      v_motivos := v_motivos || (left(v_app.id::text, 8) || ': conflito de interesse');
    ELSIF (SELECT count(*) FROM public.selection_evaluation_assignments a
            WHERE a.application_id = v_app.id AND a.part = p_part AND a.withdrawn_at IS NULL
              AND a.evaluator_member_id <> p_member_id) >= 2 THEN
      v_motivos := v_motivos || (left(v_app.id::text, 8) || ': já tem 2 avaliadores nesta parte');
    END IF;
  END LOOP;
  IF cardinality(v_motivos) > 0 THEN
    RETURN jsonb_build_object('error', 'Atribuição recusada: ' || array_to_string(v_motivos, '; ') || '.', 'reasons', to_jsonb(v_motivos));
  END IF;

  -- D22: 7 dias para a objetiva, contados da atribuição. O prazo do vídeo conta do envio do vídeo (M3).
  v_prazo := CASE WHEN p_part = 'objective' THEN now() + interval '7 days' END;
  INSERT INTO public.selection_evaluation_assignments (organization_id, application_id, part, evaluator_member_id, assigned_by, due_at)
  SELECT v_vo.organization_id, u.id, p_part, p_member_id, v_caller, v_prazo FROM unnest(p_application_ids) AS u(id)
  ON CONFLICT (application_id, part, evaluator_member_id) DO UPDATE
    SET withdrawn_at = NULL, withdrawn_reason = NULL, assigned_by = EXCLUDED.assigned_by, assigned_at = now(), due_at = EXCLUDED.due_at;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- Um aviso por lote, sem nome de candidato (ADR-0022, emendas B e C).
  PERFORM public.create_notification(
    p_member_id, 'selection_evaluator_assigned',
    v_n || CASE WHEN v_n = 1 THEN ' candidatura atribuída a você' ELSE ' candidaturas atribuídas a você' END,
    'Vaga ' || v_vo.opportunity_id || ', parte ' || CASE p_part WHEN 'objective' THEN 'objetiva' ELSE 'do vídeo' END
      || CASE WHEN v_prazo IS NOT NULL THEN ', prazo ' || to_char(v_prazo AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') ELSE '' END
      || '. A lista está em Minhas avaliações.',
    '/minhas-avaliacoes', 'vep_opportunity', NULL
  );
  RETURN jsonb_build_object('success', true, 'assigned', v_n, 'due_at', v_prazo);
END;
$function$;
