-- Onda 4 — backend de transparência por critério (auditoria pontuação/mérito 2026-07-21, seções C-sel + C-blind)
--
-- WHAT:
--   1. NEW `selection_peer_review_complete(uuid)` — SSOT do gatilho de desanonimização de co-avaliador.
--      "peer review terminou" := nº de avaliações objetivas submetidas >= selection_cycles.min_evaluators.
--   2. `get_evaluation_results` — (a) delega o gate cego ao helper (antes: contagem inline);
--      (b) passa a incluir `criterion_notes` (racional qualitativo por critério × avaliador) no retorno.
--   3. `get_application_score_breakdown` — troca o gate cego de FASE do ciclo (evaluating/interviews)
--      para o MESMO helper `selection_peer_review_complete`, unificando a regra nas duas superfícies.
--
-- WHY:
--   C-sel: as `criterion_notes` (78 preenchidas no Ciclo 4, ao vivo 2026-07-22) só apareciam no form
--   travado do próprio avaliador e via MCP get_application_score_breakdown (nenhuma .astro chama). Um
--   curador reconciliando um score divergente no app web não lia a justificativa. Agora get_evaluation_results
--   (única RPC que selection.astro chama) as expõe ao comitê pós-peer-review.
--   C-blind: as duas superfícies discordavam sobre QUANDO desanonimizar (min_evaluators vs fase). Owner
--   ratificou 2026-07-22: candidato NUNCA vê; comitê vê; revelar co-avaliador APÓS o peer review =
--   min_evaluators atingido. Um único predicado compartilhado torna a divergência estruturalmente impossível.
--   Ambas as RPCs permanecem gated por autoridade de comitê/admin — nenhuma superfície de candidato é criada.
--
-- ROLLBACK:
--   Restaurar os corpos anteriores de get_evaluation_results (md5 normalizado 9652cfee1b68e64ad42588fe7b9ff48f)
--   e get_application_score_breakdown (dd1efce384a2cf18a1e1e554a139cb4e) e DROP FUNCTION
--   public.selection_peer_review_complete(uuid). Sem mudança de dados (só corpos de função).

-- ── 1. SSOT: peer-review-complete predicate ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.selection_peer_review_complete(p_application_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- Onda 4: gatilho ÚNICO de desanonimização de co-avaliador, compartilhado por
  -- get_evaluation_results e get_application_score_breakdown (owner ratificou 2026-07-22).
  -- "peer review terminou" = nº de avaliações objetivas SUBMETIDAS >= min_evaluators do ciclo.
  -- COALESCE(...,false): min_evaluators NULL => trata como NÃO-completo (fail-closed / permanece cego).
  SELECT COALESCE(
    (
      SELECT count(*)
      FROM public.selection_evaluations e
      WHERE e.application_id = p_application_id
        AND e.evaluation_type = 'objective'
        AND e.submitted_at IS NOT NULL
    ) >= (
      SELECT c.min_evaluators
      FROM public.selection_applications a
      JOIN public.selection_cycles c ON c.id = a.cycle_id
      WHERE a.id = p_application_id
    ),
    false
  );
$function$;

-- Predicado interno: só chamado de dentro das RPCs SECDEF (rodam como owner). Não expor à API.
REVOKE ALL ON FUNCTION public.selection_peer_review_complete(uuid) FROM PUBLIC, anon, authenticated;

-- ── 2. get_evaluation_results: criterion_notes + gate cego via helper ─────────
CREATE OR REPLACE FUNCTION public.get_evaluation_results(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_evaluations jsonb;
  v_calibration_alerts jsonb := '[]'::jsonb;
  v_criterion jsonb;
  v_key text;
  v_scores_for_key numeric[];
  v_divergence numeric;
  v_pert_objective numeric;
  v_pert_interview numeric;
  v_pert_leader numeric;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get application + cycle
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- 3. V4 authorization: committee member (resource) or platform admin
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- 4. Blind enforcement (Onda 4): delega o gatilho de desanonimização ao predicado SSOT
  -- selection_peer_review_complete() para que esta superfície e get_application_score_breakdown
  -- NUNCA divirjam. Regra do owner (ratificada 2026-07-22): o comitê enxerga os co-avaliadores
  -- só APÓS o peer review (= min_evaluators atingido para a application). O helper referencia
  -- selection_cycles.min_evaluators internamente.
  IF NOT public.selection_peer_review_complete(p_application_id) THEN
    RAISE EXCEPTION 'Blind review: not all evaluators have submitted yet';
  END IF;

  -- 5. Gather all evaluations with evaluator names + criterion_notes (racional por critério)
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'evaluator_id', e.evaluator_id,
      'evaluator_name', m.name,
      'evaluation_type', e.evaluation_type,
      'scores', e.scores,
      'weighted_subtotal', e.weighted_subtotal,
      'notes', e.notes,
      'criterion_notes', e.criterion_notes,
      'submitted_at', e.submitted_at
    ) ORDER BY m.name, e.evaluation_type
  ), '[]'::jsonb)
  INTO v_evaluations
  FROM public.selection_evaluations e
  JOIN public.members m ON m.id = e.evaluator_id
  WHERE e.application_id = p_application_id
    AND e.submitted_at IS NOT NULL;

  -- 6. Calibration alerts: check divergence > 3 points per criterion
  -- Check objective criteria
  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_cycle.objective_criteria)
  LOOP
    v_key := v_criterion ->> 'key';

    SELECT ARRAY_AGG((e.scores ->> v_key)::numeric)
    INTO v_scores_for_key
    FROM public.selection_evaluations e
    WHERE e.application_id = p_application_id
      AND e.evaluation_type = 'objective'
      AND e.submitted_at IS NOT NULL
      AND e.scores ? v_key
      AND (e.scores ->> v_key) IS NOT NULL;

    IF v_scores_for_key IS NOT NULL AND array_length(v_scores_for_key, 1) >= 2 THEN
      v_divergence := (SELECT MAX(v) - MIN(v) FROM unnest(v_scores_for_key) v);
      IF v_divergence > 3 THEN
        v_calibration_alerts := v_calibration_alerts || jsonb_build_object(
          'criterion', v_key,
          'type', 'objective',
          'divergence', ROUND(v_divergence, 2),
          'scores', to_jsonb(v_scores_for_key)
        );
      END IF;
    END IF;
  END LOOP;

  -- Check interview criteria
  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_cycle.interview_criteria)
  LOOP
    v_key := v_criterion ->> 'key';

    SELECT ARRAY_AGG((e.scores ->> v_key)::numeric)
    INTO v_scores_for_key
    FROM public.selection_evaluations e
    WHERE e.application_id = p_application_id
      AND e.evaluation_type = 'interview'
      AND e.submitted_at IS NOT NULL
      AND e.scores ? v_key
      AND (e.scores ->> v_key) IS NOT NULL;

    IF v_scores_for_key IS NOT NULL AND array_length(v_scores_for_key, 1) >= 2 THEN
      v_divergence := (SELECT MAX(v) - MIN(v) FROM unnest(v_scores_for_key) v);
      IF v_divergence > 3 THEN
        v_calibration_alerts := v_calibration_alerts || jsonb_build_object(
          'criterion', v_key,
          'type', 'interview',
          'divergence', ROUND(v_divergence, 2),
          'scores', to_jsonb(v_scores_for_key)
        );
      END IF;
    END IF;
  END LOOP;

  -- Check leader extra criteria
  IF v_cycle.leader_extra_criteria IS NOT NULL AND jsonb_array_length(v_cycle.leader_extra_criteria) > 0 THEN
    FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_cycle.leader_extra_criteria)
    LOOP
      v_key := v_criterion ->> 'key';

      SELECT ARRAY_AGG((e.scores ->> v_key)::numeric)
      INTO v_scores_for_key
      FROM public.selection_evaluations e
      WHERE e.application_id = p_application_id
        AND e.evaluation_type = 'leader_extra'
        AND e.submitted_at IS NOT NULL
        AND e.scores ? v_key
        AND (e.scores ->> v_key) IS NOT NULL;

      IF v_scores_for_key IS NOT NULL AND array_length(v_scores_for_key, 1) >= 2 THEN
        v_divergence := (SELECT MAX(v) - MIN(v) FROM unnest(v_scores_for_key) v);
        IF v_divergence > 3 THEN
          v_calibration_alerts := v_calibration_alerts || jsonb_build_object(
            'criterion', v_key,
            'type', 'leader_extra',
            'divergence', ROUND(v_divergence, 2),
            'scores', to_jsonb(v_scores_for_key)
          );
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- 7. Compute PERT per type from subtotals
  SELECT ROUND((2 * MIN(weighted_subtotal) + 4 * AVG(weighted_subtotal) + 2 * MAX(weighted_subtotal)) / 8, 2)
  INTO v_pert_objective
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'objective'
    AND submitted_at IS NOT NULL;

  SELECT ROUND((2 * MIN(weighted_subtotal) + 4 * AVG(weighted_subtotal) + 2 * MAX(weighted_subtotal)) / 8, 2)
  INTO v_pert_interview
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'interview'
    AND submitted_at IS NOT NULL
    AND weighted_subtotal IS NOT NULL;

  SELECT ROUND((2 * MIN(weighted_subtotal) + 4 * AVG(weighted_subtotal) + 2 * MAX(weighted_subtotal)) / 8, 2)
  INTO v_pert_leader
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'leader_extra'
    AND submitted_at IS NOT NULL
    AND weighted_subtotal IS NOT NULL;

  -- 8. Return results
  RETURN jsonb_build_object(
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'chapter', v_app.chapter,
    'role_applied', v_app.role_applied,
    'status', v_app.status,
    'evaluations', v_evaluations,
    'consolidated', jsonb_build_object(
      'objective_pert', v_pert_objective,
      'interview_pert', v_pert_interview,
      'leader_extra_pert', v_pert_leader,
      'objective_score_avg', v_app.objective_score_avg,
      'interview_score', v_app.interview_score,
      'final_score', v_app.final_score,
      'rank_chapter', v_app.rank_chapter,
      'rank_overall', v_app.rank_overall
    ),
    'calibration_alerts', v_calibration_alerts,
    'has_calibration_issues', jsonb_array_length(v_calibration_alerts) > 0
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_evaluation_results(uuid) TO authenticated;

-- ── 3. get_application_score_breakdown: gate cego unificado (fase -> helper) ───
CREATE OR REPLACE FUNCTION public.get_application_score_breakdown(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_evals jsonb;
  v_blind boolean;
  v_hidden text[];
  v_returning_match record;
  v_ai_triage jsonb;
  v_briefing jsonb;
  v_pert jsonb;
  v_leader_extra_cutoff jsonb;
  v_returning jsonb;
  v_profile jsonb;
  v_pmi_history jsonb;
  v_core jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF NOT FOUND OR NOT (
    v_caller.is_superadmin = true
    OR public.can_by_member(v_caller.id, 'manage_member')
    OR public.can_by_member(v_caller.id, 'curate_content')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  -- ADR-0109 PR-2 COI recusal: an active candidate in this application cycle is recused.
  IF public.selection_coi_recused(v_caller.id, v_app.cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  -- p197c B3: expanded PII access log
  PERFORM public._log_application_pii_access(
    p_application_id,
    v_caller.id,
    ARRAY['email','applicant_name','evaluations','evaluator_notes','criterion_notes',
          'ai_analysis','ai_triage_reasoning','last_briefing_jsonb',
          'profile_about_me','profile_specialties','service_history_chapters','pmi_memberships',
          'previous_cycles'],
    'get_application_score_breakdown'
  );

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- Onda 4 (C-blind unify): a desanonimização passa a usar o MESMO predicado SSOT que
  -- get_evaluation_results — revelar co-avaliadores só APÓS o peer review (min_evaluators
  -- atingido), NÃO por fase do ciclo. Owner ratificou 2026-07-22. Superadmin sempre enxerga;
  -- candidato nunca alcança esta RPC (gated por manage_member/curate_content/superadmin).
  v_blind := NOT public.selection_peer_review_complete(p_application_id)
             AND v_caller.is_superadmin IS NOT TRUE;

  IF v_blind THEN
    SELECT jsonb_agg(jsonb_build_object(
      'evaluation_type', e.evaluation_type,
      'evaluator_name', m.name,
      'evaluator_id', m.id,
      'weighted_subtotal', e.weighted_subtotal,
      'submitted_at', e.submitted_at,
      'scores', e.scores,
      'notes', e.notes,
      'criterion_notes', e.criterion_notes,
      'is_own', true
    ) ORDER BY e.evaluation_type)
    INTO v_evals
    FROM public.selection_evaluations e
    JOIN public.members m ON m.id = e.evaluator_id
    WHERE e.application_id = p_application_id
      AND e.submitted_at IS NOT NULL
      AND e.evaluator_id = v_caller.id;

    v_hidden := ARRAY['other_evaluators_names', 'other_evaluators_scores',
                      'other_evaluators_subtotals', 'other_evaluators_notes'];
  ELSE
    SELECT jsonb_agg(jsonb_build_object(
      'evaluation_type', e.evaluation_type,
      'evaluator_name', m.name,
      'evaluator_id', m.id,
      'weighted_subtotal', e.weighted_subtotal,
      'submitted_at', e.submitted_at,
      'scores', e.scores,
      'notes', e.notes,
      'criterion_notes', e.criterion_notes,
      'is_own', e.evaluator_id = v_caller.id
    ) ORDER BY e.evaluation_type, m.name)
    INTO v_evals
    FROM public.selection_evaluations e
    JOIN public.members m ON m.id = e.evaluator_id
    WHERE e.application_id = p_application_id AND e.submitted_at IS NOT NULL;

    v_hidden := ARRAY[]::text[];
  END IF;

  SELECT id, name, member_status, operational_role, offboarded_at
  INTO v_returning_match
  FROM public.members WHERE lower(email) = lower(v_app.email) LIMIT 1;

  v_core := jsonb_build_object(
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'email', v_app.email,
    'role_applied', v_app.role_applied,
    'promotion_path', v_app.promotion_path,
    'status', v_app.status,
    'chapter', v_app.chapter,
    'research_score', v_app.research_score,
    'leader_score', v_app.leader_score,
    'final_score', v_app.final_score,
    'objective_score_avg', v_app.objective_score_avg,
    'interview_score', v_app.interview_score,
    -- p232 #229 Phase 2: expose leader_extra_pert_score in core (was only in evaluations[])
    'leader_extra_pert_score', v_app.leader_extra_pert_score,
    'rank_researcher', v_app.rank_researcher,
    'rank_leader', v_app.rank_leader,
    'linked_application_id', v_app.linked_application_id
  );

  v_ai_triage := jsonb_build_object(
    'score', v_app.ai_triage_score,
    'reasoning', v_app.ai_triage_reasoning,
    'confidence', v_app.ai_triage_confidence,
    'model', v_app.ai_triage_model,
    'at', v_app.ai_triage_at,
    'consent_at', v_app.consent_ai_analysis_at
  );

  v_briefing := jsonb_build_object(
    'ai_analysis', v_app.ai_analysis,
    'last_briefing_jsonb', v_app.last_briefing_jsonb,
    'last_briefing_at', v_app.last_briefing_at,
    'last_briefing_model', v_app.last_briefing_model
  );

  v_pert := jsonb_build_object(
    'target_score', v_app.pert_target_score,
    'band_lower', v_app.pert_band_lower,
    'band_upper', v_app.pert_band_upper,
    'cohort_n', v_app.pert_cohort_n,
    'method', v_app.pert_cutoff_method,
    'calc_at', v_app.pert_calc_at,
    'final_score_position', CASE
      WHEN v_app.final_score IS NULL OR v_app.pert_band_lower IS NULL OR v_app.pert_band_upper IS NULL THEN NULL
      WHEN v_app.final_score < v_app.pert_band_lower THEN 'below'
      WHEN v_app.final_score > v_app.pert_band_upper THEN 'above'
      ELSE 'within'
    END,
    'research_score_position', CASE
      WHEN v_app.research_score IS NULL OR v_app.pert_band_lower IS NULL OR v_app.pert_band_upper IS NULL THEN NULL
      WHEN v_app.research_score < v_app.pert_band_lower THEN 'below'
      WHEN v_app.research_score > v_app.pert_band_upper THEN 'above'
      ELSE 'within'
    END
  );

  -- p232 #229 Phase 2: separate leader_extra cutoff block + position
  v_leader_extra_cutoff := jsonb_build_object(
    'target_score', v_app.leader_extra_pert_target,
    'band_lower', v_app.leader_extra_pert_band_lower,
    'band_upper', v_app.leader_extra_pert_band_upper,
    'cohort_n', v_app.leader_extra_pert_cohort_n,
    'method', v_app.leader_extra_pert_cutoff_method,
    'calc_at', v_app.leader_extra_pert_calc_at,
    'leader_extra_score_position', CASE
      WHEN v_app.leader_extra_pert_score IS NULL OR v_app.leader_extra_pert_band_lower IS NULL OR v_app.leader_extra_pert_band_upper IS NULL THEN NULL
      WHEN v_app.leader_extra_pert_score < v_app.leader_extra_pert_band_lower THEN 'below'
      WHEN v_app.leader_extra_pert_score > v_app.leader_extra_pert_band_upper THEN 'above'
      ELSE 'within'
    END
  );

  v_returning := jsonb_build_object(
    'is_returning_member', v_app.is_returning_member,
    'previous_cycles', v_app.previous_cycles,
    'application_count', v_app.application_count,
    'returning_member_match', CASE WHEN v_returning_match.id IS NOT NULL THEN jsonb_build_object(
      'member_id', v_returning_match.id,
      'name', v_returning_match.name,
      'member_status', v_returning_match.member_status,
      'operational_role', v_returning_match.operational_role,
      'offboarded_at', v_returning_match.offboarded_at
    ) ELSE NULL END
  );

  v_profile := jsonb_build_object(
    'profile_about_me', v_app.profile_about_me,
    'profile_specialties', v_app.profile_specialties,
    'profile_company', v_app.profile_company,
    'profile_designation', v_app.profile_designation,
    'profile_industry', v_app.profile_industry,
    'profile_certifications', v_app.profile_certifications,
    'profile_location', v_app.profile_location,
    'credly_url', v_app.credly_url,
    'linkedin_url', v_app.linkedin_url
  );

  v_pmi_history := jsonb_build_object(
    'service_history_count', v_app.service_history_count,
    'service_history_chapters', v_app.service_history_chapters,
    'service_first_start_date', v_app.service_first_start_date,
    'service_latest_end_date', v_app.service_latest_end_date,
    'pmi_memberships', v_app.pmi_memberships
  );

  RETURN v_core
    || jsonb_build_object(
      'evaluations', COALESCE(v_evals, '[]'::jsonb),
      'blind_review_active', v_blind,
      'cycle_phase', COALESCE(v_cycle.phase, 'unknown'),
      'hidden_fields', v_hidden,
      'ai_triage', v_ai_triage,
      'briefing', v_briefing,
      'pert_cutoff', v_pert,
      'leader_extra_cutoff', v_leader_extra_cutoff,
      'returning_context', v_returning,
      'profile_lite', v_profile,
      'pmi_history', v_pmi_history
    );
END;
$function$;

NOTIFY pgrst, 'reload schema';
