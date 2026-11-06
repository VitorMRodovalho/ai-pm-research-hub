-- #2393 M2b (ADR-0134 §4, emenda de 06/11/2026): na objetiva do piloto, o líder da vaga avalia com 1 pessoa de fora.
--
-- Antes, quem tinha vínculo ativo ou suspenso na iniciativa da vaga ficava fora das duas partes. Agora:
-- - objetiva: entra no máximo 1 avaliador de dentro da linha por candidatura, e ele tem de ter vínculo de líder
--   (role 'leader') ativo na iniciativa. O outro é de fora. Qualquer outro vínculo na linha continua impedido;
-- - vídeo: nada muda, todo vínculo na linha impede.
-- A regra mora em _impedimento_na_linha, que a regra única (_avaliador_do_piloto) e a atribuição chamam. Na
-- execução ela conta quem é de dentro AGORA: se a pessoa de fora entrar na linha depois da atribuição, as duas
-- atribuições param, e a gestão refaz.
-- As outras condições das duas funções ficam como estavam, byte a byte (gerado de 20261104205503_avaliador_do_piloto.sql e 20261104210514_motivos_da_recusa_do_avaliador.sql).

-- ── 1. A regra do vínculo na linha ──
CREATE OR REPLACE FUNCTION public._impedimento_na_linha(p_member_id uuid, p_application_id uuid, p_part text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_pessoa uuid;
  v_iniciativa uuid;
BEGIN
  SELECT m.person_id, vo.initiative_id INTO v_pessoa, v_iniciativa
    FROM public.selection_applications sa
    JOIN public.vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id AND vo.evaluation_track = 'line_pilot'
    JOIN public.members m ON m.id = p_member_id
   WHERE sa.id = p_application_id;
  -- Falha fechada: sem candidatura piloto ou sem membro, há impedimento.
  IF NOT FOUND THEN
    RETURN 'candidatura de vaga piloto ou membro inexistente';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.engagements e
                  WHERE e.person_id = v_pessoa AND e.initiative_id = v_iniciativa AND e.status IN ('active', 'suspended')) THEN
    RETURN NULL;
  END IF;
  IF p_part IS DISTINCT FROM 'objective' THEN
    RETURN 'tem vínculo na iniciativa da vaga (ADR-0134 §4: o vídeo é avaliado de fora da linha)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.engagements e
                  WHERE e.person_id = v_pessoa AND e.initiative_id = v_iniciativa AND e.role = 'leader' AND e.status = 'active') THEN
    RETURN 'tem vínculo na iniciativa da vaga e não é o líder dela (ADR-0134 §4: na objetiva, só o líder entra de dentro)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.selection_evaluation_assignments a
               JOIN public.members m2 ON m2.id = a.evaluator_member_id
              WHERE a.application_id = p_application_id AND a.part = 'objective' AND a.withdrawn_at IS NULL
                AND a.evaluator_member_id <> p_member_id
                AND EXISTS (SELECT 1 FROM public.engagements e
                             WHERE e.person_id = m2.person_id AND e.initiative_id = v_iniciativa AND e.status IN ('active', 'suspended'))) THEN
    RETURN 'a objetiva desta candidatura já tem um avaliador de dentro da linha (ADR-0134 §4: o outro é de fora)';
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public._impedimento_na_linha(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public._impedimento_na_linha(uuid, uuid, text) IS
  '#2393 M2b (ADR-0134 §4, emenda de 06/11/2026): NULL quando o vínculo na iniciativa da vaga não impede; senão, o motivo. Sem vínculo na linha, não impede. No vídeo, todo vínculo impede. Na objetiva, entra só o líder ativo, e só se nenhum outro avaliador ativo da candidatura for de dentro. Falha fechada.';

-- ── 2. A regra única de quem avalia ──
CREATE OR REPLACE FUNCTION public._avaliador_do_piloto(p_member_id uuid, p_application_id uuid, p_part text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.selection_evaluation_assignments a
    JOIN public.selection_applications sa ON sa.id = a.application_id
    JOIN public.vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id AND vo.evaluation_track = 'line_pilot'
    JOIN public.members m ON m.id = a.evaluator_member_id AND m.is_active
    WHERE a.application_id = p_application_id
      AND a.part = p_part
      AND a.evaluator_member_id = p_member_id
      AND a.withdrawn_at IS NULL
      AND public.can_by_member(p_member_id, 'evaluate_assigned_application')
      AND EXISTS (SELECT 1 FROM public.selection_evaluator_calibrations c
                   WHERE c.member_id = p_member_id AND c.opportunity_id = vo.opportunity_id AND c.part = p_part)
      AND NOT public.selection_coi_recused(p_member_id, sa.cycle_id)
      AND public._impedimento_na_linha(p_member_id, p_application_id, p_part) IS NULL
  );
$function$;
COMMENT ON FUNCTION public._avaliador_do_piloto(uuid, uuid, text) IS
  '#2393 M2 e M2b (ADR-0134 §4): atribuição ativa daquela parte, ação evaluate_assigned_application, calibragem da vaga e parte, sem conflito de interesse e sem impedimento na linha (_impedimento_na_linha: na objetiva, o líder da vaga com 1 de fora; no vídeo, só de fora). Fila, formulário e envio usam esta regra.';

-- ── 3. A atribuição recusa pela mesma regra, por candidatura ──
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
  v_impedimento text;
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
  FOR v_app IN
    SELECT u.id AS pedido, sa.id, sa.cycle_id, sa.status, sa.vep_opportunity_id
      FROM unnest(p_application_ids) AS u(id) LEFT JOIN public.selection_applications sa ON sa.id = u.id
  LOOP
    -- ADR-0134 §4, emenda de 06/11/2026: o vínculo na linha é julgado por candidatura, pela mesma regra da fila e do envio.
    v_impedimento := public._impedimento_na_linha(p_member_id, v_app.id, p_part);
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
    ELSIF v_impedimento IS NOT NULL THEN
      v_motivos := v_motivos || (left(v_app.id::text, 8) || ': ' || v_impedimento);
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
