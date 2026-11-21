-- #3130: get_my_pending_evaluations, fora do comitê do ciclo, devolve a fila vazia a quem tem atribuição ativa no
-- piloto da linha (ADR-0134) e nenhum item aberto agora, em vez de recusar. Sem atribuição ativa, a recusa continua.
-- Mesma assinatura; o resto do corpo é byte a byte o da 20261121013741 (#3120).

CREATE OR REPLACE FUNCTION public.get_my_pending_evaluations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_cycle record;
  v_pending jsonb;
  v_completed_count int;
  v_total_count int;
  -- #705 Bug 1/3 — terminais NÃO são avaliáveis: excluídos da fila, do numerador
  -- (completed) E do denominador (total) para o indicador fechar (pending +
  -- completed = total; progress_pct <= 100).
  v_terminal constant text[] := ARRAY['rejected','withdrawn','cancelled','approved','converted','waitlist','interview_noshow'];
  v_piloto jsonb;  -- #2393 M2
BEGIN
  -- Authenticate caller
  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- #2393 M2: as candidaturas piloto atribuídas a quem chama, válidas pela mesma regra do formulário e do envio,
  -- sem nome (D23), com o prazo da parte (D22). A parte do vídeo entra na fila com o vídeo da linha (M3).
  SELECT jsonb_agg(jsonb_build_object(
    'application_id', sa.id,
    'applicant_name', 'Candidatura ' || left(sa.id::text, 8),
    'role_applied', sa.role_applied,
    'promotion_path', sa.promotion_path,
    'created_at', sa.created_at,
    'evaluation_track', 'line_pilot',
    'vaga', public._vaga_da_candidatura(sa.id, false),  -- #3063
    'part', a.part,
    'due_at', a.due_at,
    'has_my_evaluation_in_progress',
      EXISTS (SELECT 1 FROM public.selection_evaluations se
              WHERE se.application_id = sa.id AND se.evaluator_id = v_caller_member_id
                AND se.evaluation_type = a.part AND se.submitted_at IS NULL)
  ) ORDER BY a.due_at NULLS LAST, sa.created_at)
  INTO v_piloto
  FROM public.selection_evaluation_assignments a
  JOIN public.selection_applications sa ON sa.id = a.application_id
  WHERE a.evaluator_member_id = v_caller_member_id
    AND a.withdrawn_at IS NULL
    -- #3120: vídeo e fit entram quando a vaga tem rubrica da parte; o fit, só depois da 1ª nota de vídeo enviada.
    AND (a.part = 'objective'
         OR (a.part IN ('video', 'fit') AND public._rubrica_vigente_id(sa.id, a.part) IS NOT NULL
             AND (a.part <> 'fit' OR public._fit_aberto(sa.id))))
    AND sa.status <> ALL (v_terminal)
    AND public._avaliador_do_piloto(v_caller_member_id, sa.id, a.part)
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations se
      WHERE se.application_id = sa.id AND se.evaluator_id = v_caller_member_id
        AND se.evaluation_type = a.part AND se.submitted_at IS NOT NULL
    );

  -- Pick the evaluating cycle deterministically (fix #298 A+ part 1), por ESTADO (#1801):
  -- `created_at` é a data de escrita da linha e só entra como último desempate.
  SELECT * INTO v_cycle FROM public.selection_cycles
  WHERE phase = 'evaluating'
    AND status <> 'closed'
  ORDER BY (status = 'open') DESC,
           open_date DESC NULLS LAST,
           created_at DESC
  LIMIT 1;

  -- No evaluating cycle -> return empty consistently (no info leak)
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('cycle', null, 'pending', COALESCE(v_piloto, '[]'::jsonb), 'completed_count', 0, 'total_count', 0);
  END IF;

  -- Gate scoped to picked cycle's committee OR admin manage_member bypass (fix #298 A+ part 2)
  IF NOT EXISTS (
    SELECT 1 FROM public.selection_committee sc
    WHERE sc.member_id = v_caller_member_id AND sc.cycle_id = v_cycle.id
  ) AND NOT public.can_by_member(v_caller_member_id, 'manage_member') THEN
    -- #2393 M2: fora do comitê, quem tem atribuição no piloto vê só ela; quem não tem, segue recusado.
    -- #3130: atribuição ATIVA sem item aberto agora (o fit espera a 1ª nota de vídeo; o vídeo, a rubrica) é fila
    -- vazia, não recusa. A recusa fica para quem não tem atribuição ativa nenhuma.
    IF v_piloto IS NULL AND NOT EXISTS (
         SELECT 1 FROM public.selection_evaluation_assignments a
          WHERE a.evaluator_member_id = v_caller_member_id AND a.withdrawn_at IS NULL) THEN
      RAISE EXCEPTION 'Unauthorized: caller is not on this cycle committee'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    v_piloto := COALESCE(v_piloto, '[]'::jsonb);
    RETURN jsonb_build_object(
      'cycle_code', v_cycle.cycle_code, 'cycle_phase', v_cycle.phase,
      'pending', v_piloto, 'pending_count', jsonb_array_length(v_piloto),
      'completed_count', 0, 'total_count', jsonb_array_length(v_piloto), 'progress_pct', 0);
  END IF;

  -- Pending = EVALUÁVEIS (não-terminais) do ciclo onde o avaliador ainda não submeteu.
  -- #705 Bug 1: faltava o filtro de status -> terminais poluíam a fila.
  SELECT jsonb_agg(jsonb_build_object(
    'application_id', sa.id,
    'applicant_name', sa.applicant_name,
    'role_applied', sa.role_applied,
    'promotion_path', sa.promotion_path,
    'created_at', sa.created_at,
    'vaga', public._vaga_da_candidatura(sa.id, false),  -- #3063: a régua é a da vaga, e role_applied não a diz
    'has_my_evaluation_in_progress',
      EXISTS (SELECT 1 FROM public.selection_evaluations se
              WHERE se.application_id = sa.id AND se.evaluator_id = v_caller_member_id
                AND se.submitted_at IS NULL)
  ) ORDER BY sa.created_at)
  INTO v_pending
  FROM public.selection_applications sa
  WHERE sa.cycle_id = v_cycle.id
    AND public._na_avaliacao_geral(sa.id)  -- #2393 fatia 3: piloto da linha fora da fila geral
    AND sa.status <> ALL (v_terminal)
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations se
      WHERE se.application_id = sa.id
        AND se.evaluator_id = v_caller_member_id
        AND se.submitted_at IS NOT NULL
    );

  -- Completed = apps avaliáveis DISTINTOS que o avaliador já submeteu.
  -- #705 Bug 3: era count(*) sobre o JOIN de evals -> fan-out fazia completed > total.
  SELECT count(DISTINCT sa.id)
  INTO v_completed_count
  FROM public.selection_applications sa
  JOIN public.selection_evaluations se ON se.application_id = sa.id
  WHERE sa.cycle_id = v_cycle.id
    AND public._na_avaliacao_geral(sa.id)  -- #2393 fatia 3
    AND sa.status <> ALL (v_terminal)
    AND se.evaluator_id = v_caller_member_id
    AND se.submitted_at IS NOT NULL;

  -- Total = apps avaliáveis do ciclo (denominador alinhado com a fila).
  SELECT count(*) INTO v_total_count
  FROM public.selection_applications
  WHERE cycle_id = v_cycle.id
    AND public._na_avaliacao_geral(id)  -- #2393 fatia 3
    AND status <> ALL (v_terminal);

  RETURN jsonb_build_object(
    'cycle_code', v_cycle.cycle_code,
    'cycle_phase', v_cycle.phase,
    'pending', COALESCE(v_pending, '[]'::jsonb) || COALESCE(v_piloto, '[]'::jsonb),  -- #2393 M2
    'pending_count', COALESCE(jsonb_array_length(v_pending), 0) + COALESCE(jsonb_array_length(v_piloto), 0),
    'completed_count', v_completed_count,
    'total_count', v_total_count,
    'progress_pct', CASE WHEN v_total_count > 0 THEN round((v_completed_count::numeric / v_total_count) * 100, 1) ELSE 0 END
  );
END;
$function$;
