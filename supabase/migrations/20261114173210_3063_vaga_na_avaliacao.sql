-- #3063: a fila e o formulário de avaliação passam a dizer a VAGA do VEP da candidatura.
--
-- role_applied não diz a vaga: Onboarding, Comunicação, Curadoria e Publicações chegam como 'researcher'.
-- Decisão do GP em 14/11/2026: cada candidatura é avaliada pela régua da própria vaga, inclusive quando a
-- mesma pessoa se candidata a duas. Sem a vaga na tela, o avaliador não sabe qual régua aplicar.
--
-- Só aditivo: as chaves existentes não mudam. O formulário ganha 'vaga' (com as perguntas do essay_mapping)
-- e 'pert_cutoff.cohort_scope', que diz que o corte de hoje é de ciclo + função, não da vaga.

CREATE OR REPLACE FUNCTION public._vaga_da_candidatura(p_application_id uuid, p_com_perguntas boolean)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
  SELECT CASE WHEN vo.opportunity_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'opportunity_id', vo.opportunity_id,
      'title', vo.title,
      'evaluation_track', vo.evaluation_track
    ) || CASE WHEN p_com_perguntas THEN jsonb_build_object(
      'vep_url', vo.vep_url,
      'time_commitment', vo.time_commitment,
      'essay_mapping', vo.essay_mapping
    ) ELSE '{}'::jsonb END
  END
  FROM public.selection_applications sa
  LEFT JOIN public.vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
  WHERE sa.id = p_application_id
$function$;

REVOKE ALL ON FUNCTION public._vaga_da_candidatura(uuid, boolean) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._vaga_da_candidatura(uuid, boolean) IS
  '#3063: a vaga do VEP de uma candidatura (id, título, trilha; com p_com_perguntas, também URL, horas e essay_mapping). NULL quando a candidatura não tem vaga conhecida. Só para funções SECURITY DEFINER que já checaram a autoridade de quem chama.';

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
    AND a.part = 'objective'
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
    IF v_piloto IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: caller is not on this cycle committee'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
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
$function$
;

CREATE OR REPLACE FUNCTION public.get_evaluation_form(p_application_id uuid, p_evaluation_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_draft record;
  v_criteria jsonb;
  v_criteria_enriched jsonb;
  v_max_weighted numeric := 0;
  v_returning_match record;
  v_app_core jsonb;
  v_app_body jsonb;
  v_app_profile jsonb;
  v_app_pmi_history jsonb;
  v_app_returning jsonb;
  v_app_ai jsonb;
  v_piloto_atribuido boolean := false;  -- #2393 M2
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found: %', p_application_id; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  -- #2393 M2: quem tem atribuição válida no piloto (a mesma regra da fila e do envio, em _avaliador_do_piloto).
  v_piloto_atribuido := NOT public._na_avaliacao_geral(p_application_id)
    AND public._avaliador_do_piloto(v_caller.id, p_application_id, p_evaluation_type);

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) AND NOT v_piloto_atribuido THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- #2393 fatia 3 (D1) e M2: piloto fora da avaliação geral, salvo o avaliador atribuído a ele.
  IF NOT public._na_avaliacao_geral(p_application_id) AND NOT v_piloto_atribuido THEN
    RAISE EXCEPTION 'Unauthorized: pilot_track application is not evaluated through the general committee (ADR-0134)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public._log_application_pii_access(
    p_application_id, v_caller.id,
    -- #2393 M2 (D23): ao avaliador do piloto não saem nome, e-mail nem LinkedIn, e o registro não os lista.
    CASE WHEN v_piloto_atribuido THEN ARRAY[]::text[] ELSE ARRAY['email','applicant_name','linkedin_url'] END || ARRAY[
      'resume_url','resume_storage_path','cv_extracted_text',
      'motivation_letter','leadership_experience','academic_background','reason_for_applying',
      'profile_about_me','profile_specialties','profile_company','profile_designation',
      'profile_industry','profile_certifications','profile_linkedin_url',
      'service_history_chapters','pmi_memberships','previous_cycles','linkedin_relevant_posts'
    ],
    'get_evaluation_form:' || p_evaluation_type
  );

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  SELECT * INTO v_draft FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluator_id = v_caller.id
    AND evaluation_type = p_evaluation_type;

  SELECT jsonb_agg(
    jsonb_build_object(
      'key', c->>'key', 'label', c->>'label', 'guide', c->>'guide',
      'weight', COALESCE((c->>'weight')::numeric, 1),
      'max', COALESCE((c->>'max')::numeric, 10),
      'max_weighted_contribution', COALESCE((c->>'weight')::numeric, 1) * COALESCE((c->>'max')::numeric, 10),
      'your_score', CASE WHEN v_draft.scores IS NOT NULL AND v_draft.scores ? (c->>'key')
                          THEN (v_draft.scores->>(c->>'key'))::numeric ELSE NULL END,
      'your_weighted_contribution', CASE WHEN v_draft.scores IS NOT NULL AND v_draft.scores ? (c->>'key')
                                          THEN COALESCE((c->>'weight')::numeric, 1) * (v_draft.scores->>(c->>'key'))::numeric ELSE NULL END,
      'your_criterion_note', CASE WHEN v_draft.criterion_notes IS NOT NULL AND v_draft.criterion_notes ? (c->>'key')
                                   THEN v_draft.criterion_notes->>(c->>'key') ELSE NULL END
    )
  ) INTO v_criteria_enriched
  FROM jsonb_array_elements(v_criteria) c;

  SELECT SUM(COALESCE((c->>'weight')::numeric, 1) * COALESCE((c->>'max')::numeric, 10))
  INTO v_max_weighted
  FROM jsonb_array_elements(v_criteria) c;

  SELECT id, name, member_status, operational_role, offboarded_at
  INTO v_returning_match
  FROM public.members WHERE lower(email) = lower(v_app.email) LIMIT 1;

  -- Build application object in chunks (PG jsonb_build_object 100-arg cap workaround)
  v_app_core := jsonb_build_object(
    'id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'email', v_app.email,
    'chapter', v_app.chapter,
    'role_applied', v_app.role_applied,
    'promotion_path', v_app.promotion_path,
    'certifications', v_app.certifications,
    'linkedin_url', v_app.linkedin_url,
    'resume_url', v_app.resume_url,
    'resume_storage_path', v_app.resume_storage_path,
    'resume_synced_at', v_app.resume_synced_at,
    'cv_extracted_text', v_app.cv_extracted_text,
    'membership_status', v_app.membership_status,
    'status', v_app.status,
    'credly_url', v_app.credly_url,
    'is_open_to_volunteer', v_app.is_open_to_volunteer
  );

  v_app_body := jsonb_build_object(
    'motivation_letter', v_app.motivation_letter,
    'reason_for_applying', v_app.reason_for_applying,
    'chapter_affiliation', v_app.chapter_affiliation,
    'non_pmi_experience', v_app.non_pmi_experience,
    'areas_of_interest', v_app.areas_of_interest,
    'availability_declared', v_app.availability_declared,
    'proposed_theme', v_app.proposed_theme,
    'leadership_experience', v_app.leadership_experience,
    'academic_background', v_app.academic_background
  );

  v_app_profile := jsonb_build_object(
    'profile_about_me', v_app.profile_about_me,
    'profile_specialties', v_app.profile_specialties,
    'profile_company', v_app.profile_company,
    'profile_designation', v_app.profile_designation,
    'profile_industry', v_app.profile_industry,
    'profile_certifications', v_app.profile_certifications,
    'profile_volunteer_interest', v_app.profile_volunteer_interest,
    'profile_location', v_app.profile_location,
    'profile_state', v_app.profile_state,
    'profile_country', v_app.profile_country,
    'profile_linkedin_url', v_app.profile_linkedin_url,
    'linkedin_relevant_posts', v_app.linkedin_relevant_posts,
    'ai_pm_focus_tags', v_app.ai_pm_focus_tags
  );

  v_app_pmi_history := jsonb_build_object(
    'service_history_count', v_app.service_history_count,
    'service_history_chapters', v_app.service_history_chapters,
    'service_first_start_date', v_app.service_first_start_date,
    'service_latest_end_date', v_app.service_latest_end_date,
    'pmi_memberships', v_app.pmi_memberships
  );

  v_app_returning := jsonb_build_object(
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

  v_app_ai := jsonb_build_object(
    'consent_ai_analysis_at', v_app.consent_ai_analysis_at,
    'ai_analysis', v_app.ai_analysis,
    'ai_triage_score', v_app.ai_triage_score,
    'ai_triage_reasoning', v_app.ai_triage_reasoning,
    'ai_triage_confidence', v_app.ai_triage_confidence,
    'ai_triage_at', v_app.ai_triage_at,
    'ai_triage_model', v_app.ai_triage_model,
    'last_briefing_jsonb', v_app.last_briefing_jsonb,
    'last_briefing_at', v_app.last_briefing_at,
    'last_briefing_model', v_app.last_briefing_model
  );

  -- #2393 M2 (D23 e D3): o avaliador de fora do piloto não recebe nome, e-mail nem LinkedIn, e não vê a triagem
  -- por IA antes da própria nota. O currículo pode trazer o nome: o que a tela não mostra é o canal de contato.
  IF v_piloto_atribuido THEN
    v_app_core := v_app_core || jsonb_build_object('applicant_name', 'Candidatura ' || left(v_app.id::text, 8),
                                                   'email', NULL, 'linkedin_url', NULL);
    v_app_profile := v_app_profile || jsonb_build_object('profile_linkedin_url', NULL);
    v_app_ai := '{}'::jsonb;  -- opção A: nem antes nem depois da nota; a gestão e o líder (depois do fit) seguem vendo
  END IF;

  RETURN jsonb_build_object(
    'application', v_app_core || v_app_body || v_app_profile || v_app_pmi_history || v_app_returning || v_app_ai,
    'criteria', v_criteria,
    'criteria_with_weights', COALESCE(v_criteria_enriched, '[]'::jsonb),
    'max_weighted_subtotal', v_max_weighted,
    'pert_cutoff', jsonb_build_object(
      'target_score', v_app.pert_target_score,
      'band_lower', v_app.pert_band_lower,
      'band_upper', v_app.pert_band_upper,
      'cohort_n', v_app.pert_cohort_n,
      'method', v_app.pert_cutoff_method,
      'calc_at', v_app.pert_calc_at,
      -- #3063: a coorte é ciclo + função, não a vaga. Dito aqui para o avaliador não ler o corte como o da vaga.
      'cohort_scope', 'ciclo_e_funcao'
    ),
    -- #3063: a vaga do VEP e as perguntas dela. role_applied não diz a vaga (Onboarding, Comunicação e Curadoria
    -- chegam como 'researcher'), e cada candidatura é avaliada pela régua da própria vaga (decisão do GP, 14/11/2026).
    'vaga', public._vaga_da_candidatura(p_application_id, true),
    'evaluation_type', p_evaluation_type,
    'committee_role', COALESCE(v_committee.role, 'platform_admin'),
    'draft', CASE WHEN v_draft IS NOT NULL THEN jsonb_build_object(
      'id', v_draft.id, 'scores', v_draft.scores, 'notes', v_draft.notes,
      'criterion_notes', COALESCE(v_draft.criterion_notes, '{}'::jsonb),
      'weighted_subtotal', v_draft.weighted_subtotal, 'submitted_at', v_draft.submitted_at
    ) ELSE NULL END,
    'is_locked', CASE WHEN v_draft.submitted_at IS NOT NULL THEN true ELSE false END
  );
END;
$function$
;
