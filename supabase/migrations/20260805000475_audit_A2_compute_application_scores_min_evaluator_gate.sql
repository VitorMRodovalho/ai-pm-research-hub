-- Audit 2026-07-21 (docs/audit/2026-07-21_scoring_merit_audit.md) — Finding A2 (ALTA)
-- compute_application_scores fugia da fórmula ratificada v1.0-cr047: gravava research_score
-- = AVG(subtotais objetivos) + AVG(subtotais entrevista) SEM trava de min_evaluators. Efeito
-- vivo no Ciclo 4: 17 aplicações receberam research_score (e rank) a partir de UM ÚNICO
-- avaliador objetivo, enquanto objective_score_avg (que exige 2) ficava NULL. 2 delas já
-- aprovadas. Isso fura a revisão dupla que dá credibilidade ao mérito.
--
-- Correção: derivar dos valores JÁ consolidados por PERT e JÁ gated por min_evaluators
-- (objective_score_avg exige >= min_evaluators; interview_score exige >= 1), mantidos por
-- _recompute_application_pert. Ordem de disparo garante frescor: trg_recompute_app_pert
-- (_recompute_application_pert) dispara ANTES de trg_recompute_application_scores (esta fn),
-- pois 'app_pert' < 'application_scores' alfabeticamente.
--   research_score = objective_pert + interview_pert  (NULL se objective_score_avg NULL)
--   leader_score   = research*0.7 + leader_extra_pert*0.3  (leader_extra PERT, min-2 gated)
--   final_score    = COALESCE(leader, research)
-- leader_extra agora é PERT (2*min+4*avg+2*max)/8 e não AVG cru (idêntico p/ n<=2, correto p/ >=3).
--
-- Validado read-only (Ciclo 4 08c1e301): nula exatamente as 17 linhas de 1-avaliador;
-- 0 divergência nas 54 já corretas (AVG==PERT p/ n<=2).
--
-- APLICAÇÃO (sessão main, deferida): após apply_migration, rodar backfill idempotente
--   SELECT public.compute_application_scores(id) FROM public.selection_applications
--   WHERE cycle_id = '08c1e301-9f7b-4d01-a13c-43ac7775c0f7';
-- (isso é MUDANÇA DE DADO — muda ranks; combinar com o recompute de ranks da migration A1).

CREATE OR REPLACE FUNCTION public.compute_application_scores(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app record;
  v_obj_pert numeric;
  v_int_pert numeric;
  v_lead_pert numeric;
  v_research numeric;
  v_leader numeric;
  v_le_subtotals numeric[];
  v_min numeric;
  v_max numeric;
  v_avg numeric;
BEGIN
  SELECT role_applied, promotion_path, objective_score_avg, interview_score
    INTO v_app
  FROM selection_applications WHERE id = p_application_id;
  IF v_app.role_applied IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  -- objective_pert / interview_pert = colunas PERT já min-gated por _recompute_application_pert.
  v_obj_pert := v_app.objective_score_avg;
  v_int_pert := v_app.interview_score;

  -- research_score = objective_pert + interview_pert (ratificado). NULL até objective passar a
  -- trava de min_evaluators (objective_score_avg NULL => sem score ranqueável).
  IF v_obj_pert IS NOT NULL AND v_int_pert IS NOT NULL THEN
    v_research := round(v_obj_pert + v_int_pert, 2);
  ELSIF v_obj_pert IS NOT NULL THEN
    v_research := round(v_obj_pert, 2);  -- parcial: objetivo apenas (pré-entrevista), já min-2 gated
  ELSE
    v_research := NULL;
  END IF;

  -- leader_score só p/ trilha líder OU triaged-to-leader; leader_extra PERT min-2 gated.
  IF v_app.role_applied = 'leader' OR v_app.promotion_path = 'triaged_to_leader' THEN
    SELECT array_agg(weighted_subtotal ORDER BY weighted_subtotal) INTO v_le_subtotals
    FROM selection_evaluations
    WHERE application_id = p_application_id
      AND evaluation_type = 'leader_extra' AND submitted_at IS NOT NULL;

    IF v_le_subtotals IS NOT NULL AND array_length(v_le_subtotals, 1) >= 2 THEN
      v_min := v_le_subtotals[1];
      v_max := v_le_subtotals[array_upper(v_le_subtotals, 1)];
      SELECT avg(u) INTO v_avg FROM unnest(v_le_subtotals) AS u;
      v_lead_pert := round((2 * v_min + 4 * v_avg + 2 * v_max) / 8, 2);
    ELSE
      v_lead_pert := NULL;
    END IF;

    IF v_research IS NOT NULL AND v_lead_pert IS NOT NULL THEN
      v_leader := round(v_research * 0.7 + v_lead_pert * 0.3, 2);
    ELSIF v_research IS NOT NULL THEN
      v_leader := v_research;  -- parcial: sem leader_extra ainda
    ELSE
      v_leader := NULL;
    END IF;
  END IF;

  UPDATE selection_applications
  SET research_score = v_research,
      leader_score = v_leader,
      final_score = COALESCE(v_leader, v_research),
      updated_at = now()
  WHERE id = p_application_id;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'research_score', v_research,
    'leader_score', v_leader,
    'objective_pert', v_obj_pert,
    'interview_pert', v_int_pert,
    'leader_extra_pert', v_lead_pert
  );
END;
$function$;
