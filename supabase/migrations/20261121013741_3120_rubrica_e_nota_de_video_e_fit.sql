-- #3120 (ADR-0134 §3): rubrica por vaga e parte, e a nota de vídeo e de fit do piloto da linha.
--
-- Decisões do GP (20/11/2026): escala de 3 níveis (fraco 1, médio 2, forte 3) com âncora escrita em cada nível; no
-- fit, mínimo opcional por critério, escrito pelo líder, e nota abaixo dele exige justificativa naquele critério sem
-- bloquear a decisão; o fit só abre depois de enviada ao menos 1 nota de vídeo da candidatura. Decisões técnicas
-- aprovadas: rubrica versionada por vaga e parte, travada depois da 1ª nota enviada daquela parte, escrita pela mesma
-- função para a gestão e para o líder ativo da vaga.
--
-- 1. Tabela selection_opening_rubrics (RLS, só por função; grants dos 3 papéis declarados, #2854).
-- 2. selection_evaluations: CHECK de evaluation_type aceita 'video' e 'fit' (só alarga); coluna nova rubric_id
--    (nula, sem default: nenhuma linha existente é reescrita).
-- 3. Auxiliares: _rubrica_vigente_id, _criterios_da_rubrica, _fit_aberto, _rubrica_travada.
-- 4. save_selection_rubric (gestão ou líder ativo da vaga; valida; recusa versão nova com a parte travada; histórico).
-- 5. get_evaluation_form, submit_evaluation e get_my_pending_evaluations passam a tratar vídeo e fit pela rubrica.
-- 6. get_selection_evaluators_admin devolve as rubricas e o histórico delas.
-- Fora isso, cada função é a captura vigente (get_evaluation_form e get_my_pending_evaluations de 20261114173210,
-- submit_evaluation de 20261104205503, get_selection_evaluators_admin da #3119).

CREATE TABLE IF NOT EXISTS public.selection_opening_rubrics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  opportunity_id text NOT NULL REFERENCES public.vep_opportunities(opportunity_id),
  part text NOT NULL CHECK (part IN ('video', 'fit')),
  version int NOT NULL CHECK (version >= 1),
  items jsonb NOT NULL CHECK (jsonb_typeof(items) = 'array'),
  created_by uuid REFERENCES public.members(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (opportunity_id, part, version)
);
ALTER TABLE public.selection_opening_rubrics ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.selection_opening_rubrics FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.selection_opening_rubrics TO service_role;
COMMENT ON TABLE public.selection_opening_rubrics IS
  '#3120 (ADR-0134 §3): a rubrica da vaga por parte (vídeo: perguntas; fit: critérios), cada item com âncora em 3 níveis. Versionada; a versão vigente é a maior. Só por função.';

ALTER TABLE public.selection_evaluations DROP CONSTRAINT selection_evaluations_evaluation_type_check;
ALTER TABLE public.selection_evaluations ADD CONSTRAINT selection_evaluations_evaluation_type_check
  CHECK (evaluation_type IN ('objective', 'interview', 'leader_extra', 'video', 'fit'));
ALTER TABLE public.selection_evaluations ADD COLUMN IF NOT EXISTS rubric_id uuid REFERENCES public.selection_opening_rubrics(id);
COMMENT ON COLUMN public.selection_evaluations.rubric_id IS
  '#3120: a versão da rubrica da vaga com que a nota de vídeo ou de fit foi dada. Nula nas outras partes.';

CREATE OR REPLACE FUNCTION public._rubrica_vigente_id(p_application_id uuid, p_part text)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT r.id
    FROM public.selection_applications sa
    JOIN public.vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id AND vo.evaluation_track = 'line_pilot'
    JOIN public.selection_opening_rubrics r ON r.opportunity_id = vo.opportunity_id AND r.part = p_part
   WHERE sa.id = p_application_id
   ORDER BY r.version DESC
   LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public._criterios_da_rubrica(p_application_id uuid, p_part text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  -- Cada item vira um critério na forma dos critérios do ciclo (key, label, guide, weight, max), mais a escala de 3
  -- níveis, as âncoras e o mínimo. Sem rubrica vigente, a lista vazia.
  SELECT COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'key', i->>'key', 'label', i->>'label', 'guide', i->>'question', 'weight', 1, 'max', 3, 'scale_min', 1,
             'anchors', i->'anchors', 'min_level', i->'min_level') ORDER BY o.n)
      FROM public.selection_opening_rubrics r, jsonb_array_elements(r.items) WITH ORDINALITY AS o(i, n)
     WHERE r.id = public._rubrica_vigente_id(p_application_id, p_part)), '[]'::jsonb);
$function$;

CREATE OR REPLACE FUNCTION public._fit_aberto(p_application_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.selection_evaluations e
                  WHERE e.application_id = p_application_id AND e.evaluation_type = 'video' AND e.submitted_at IS NOT NULL);
$function$;

CREATE OR REPLACE FUNCTION public._rubrica_travada(p_opportunity_id text, p_part text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  -- Travada desde a 1ª nota enviada daquela parte em qualquer candidatura da vaga.
  SELECT EXISTS (SELECT 1 FROM public.selection_evaluations e
                   JOIN public.selection_applications sa ON sa.id = e.application_id
                  WHERE sa.vep_opportunity_id = p_opportunity_id AND e.evaluation_type = p_part
                    AND e.submitted_at IS NOT NULL);
$function$;

CREATE OR REPLACE FUNCTION public.save_selection_rubric(p_opportunity_id text, p_part text, p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller uuid;
  v_caller_person uuid;
  v_vo record;
  v_motivos text[] := ARRAY[]::text[];
  v_item jsonb;
  v_n int;
  v_chaves text[] := ARRAY[]::text[];
  v_k text;
  v_limpos jsonb := '[]'::jsonb;
  v_versao int;
  v_id uuid;
BEGIN
  SELECT m.id, m.person_id INTO v_caller, v_caller_person FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active;
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  SELECT vo.opportunity_id, vo.initiative_id, vo.organization_id INTO v_vo FROM public.vep_opportunities vo
   WHERE vo.opportunity_id = p_opportunity_id AND vo.evaluation_track = 'line_pilot';
  IF v_vo.opportunity_id IS NULL THEN
    RETURN jsonb_build_object('error', 'A vaga não existe ou não é piloto da linha.');
  END IF;
  -- A gestão, ou o líder ativo da iniciativa da vaga (a mesma função serve às duas telas).
  IF NOT public.can_by_member(v_caller, 'manage_platform')
     AND NOT EXISTS (SELECT 1 FROM public.engagements e
                      WHERE e.person_id = v_caller_person AND e.initiative_id = v_vo.initiative_id
                        AND e.role = 'leader' AND e.status = 'active') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF p_part NOT IN ('video', 'fit') THEN
    RETURN jsonb_build_object('error', 'A parte é video ou fit.');
  END IF;
  IF public._rubrica_travada(p_opportunity_id, p_part) THEN
    RETURN jsonb_build_object('error', 'A rubrica desta parte está travada: já há nota enviada com ela.');
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN jsonb_build_object('error', 'Os itens vêm numa lista.');
  END IF;
  v_n := jsonb_array_length(p_items);
  -- ADR-0134 §3: de 3 a 5 perguntas no vídeo; no fit, os critérios escritos antes (até 8).
  IF p_part = 'video' AND (v_n < 3 OR v_n > 5) THEN
    v_motivos := v_motivos || ('o vídeo tem de 3 a 5 perguntas; vieram ' || v_n);
  ELSIF p_part = 'fit' AND (v_n < 1 OR v_n > 8) THEN
    v_motivos := v_motivos || ('o fit tem de 1 a 8 critérios; vieram ' || v_n);
  END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_k := coalesce(btrim(v_item ->> 'key'), '');
    IF v_k !~ '^[a-z][a-z0-9_]{0,39}$' THEN
      v_motivos := v_motivos || ('chave inválida: "' || v_k || '" (minúsculas, dígitos e _, começando por letra)');
    ELSIF v_k = ANY (v_chaves) THEN
      v_motivos := v_motivos || ('chave repetida: ' || v_k);
    END IF;
    v_chaves := v_chaves || v_k;
    IF coalesce(btrim(v_item ->> 'label'), '') = '' THEN
      v_motivos := v_motivos || (v_k || ': sem rótulo');
    END IF;
    IF p_part = 'video' AND coalesce(btrim(v_item ->> 'question'), '') = '' THEN
      v_motivos := v_motivos || (v_k || ': sem a pergunta');
    END IF;
    IF coalesce(btrim(v_item #>> '{anchors,weak}'), '') = '' OR coalesce(btrim(v_item #>> '{anchors,medium}'), '') = ''
       OR coalesce(btrim(v_item #>> '{anchors,strong}'), '') = '' THEN
      v_motivos := v_motivos || (v_k || ': falta âncora em algum nível (fraco, médio, forte)');
    END IF;
    IF v_item ? 'min_level' AND jsonb_typeof(v_item -> 'min_level') <> 'null' THEN
      IF p_part <> 'fit' THEN
        v_motivos := v_motivos || (v_k || ': mínimo só existe no fit');
      ELSIF jsonb_typeof(v_item -> 'min_level') <> 'number' OR (v_item ->> 'min_level') NOT IN ('1', '2', '3') THEN
        v_motivos := v_motivos || (v_k || ': o mínimo é 1, 2 ou 3');
      END IF;
    END IF;
    v_limpos := v_limpos || jsonb_build_array(jsonb_build_object(
      'key', v_k, 'label', btrim(v_item ->> 'label'), 'question', NULLIF(btrim(coalesce(v_item ->> 'question', '')), ''),
      'anchors', jsonb_build_object('weak', btrim(v_item #>> '{anchors,weak}'), 'medium', btrim(v_item #>> '{anchors,medium}'),
                                    'strong', btrim(v_item #>> '{anchors,strong}')),
      'min_level', CASE WHEN p_part = 'fit' AND jsonb_typeof(v_item -> 'min_level') = 'number' THEN v_item -> 'min_level' END));
  END LOOP;
  IF cardinality(v_motivos) > 0 THEN
    RETURN jsonb_build_object('error', 'Rubrica recusada: ' || array_to_string(v_motivos, '; ') || '.', 'reasons', to_jsonb(v_motivos));
  END IF;

  SELECT coalesce(max(r.version), 0) + 1 INTO v_versao FROM public.selection_opening_rubrics r
   WHERE r.opportunity_id = p_opportunity_id AND r.part = p_part;
  INSERT INTO public.selection_opening_rubrics (organization_id, opportunity_id, part, version, items, created_by)
  VALUES (v_vo.organization_id, p_opportunity_id, p_part, v_versao, v_limpos, v_caller)
  RETURNING id INTO v_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (v_caller, 'selection_rubric.saved', 'selection_opening_rubric', v_id,
          jsonb_build_object('opportunity_id', p_opportunity_id, 'part', p_part, 'version', v_versao, 'items', v_n));
  RETURN jsonb_build_object('success', true, 'id', v_id, 'version', v_versao);
END;
$function$;

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

  -- #3120 (ADR-0134 §3): vídeo e fit são do piloto e leem a rubrica da vaga. Sem rubrica, não há o que avaliar; o
  -- fit só abre depois da 1ª nota de vídeo enviada (decisão do GP, 20/11/2026). Antes do registro de acesso: a
  -- recusa não lê a candidatura.
  IF p_evaluation_type IN ('video', 'fit') THEN
    IF public._rubrica_vigente_id(p_application_id, p_evaluation_type) IS NULL THEN
      RAISE EXCEPTION 'A vaga desta candidatura ainda não tem rubrica de %', p_evaluation_type
        USING ERRCODE = 'check_violation';
    END IF;
    IF p_evaluation_type = 'fit' AND NOT public._fit_aberto(p_application_id) THEN
      RAISE EXCEPTION 'O fit abre depois da primeira nota de vídeo enviada desta candidatura (ADR-0134 §3)'
        USING ERRCODE = 'check_violation';
    END IF;
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
    WHEN 'video' THEN public._criterios_da_rubrica(p_application_id, 'video')  -- #3120
    WHEN 'fit' THEN public._criterios_da_rubrica(p_application_id, 'fit')      -- #3120
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
    -- #3120: na rubrica da vaga, a escala de 3 níveis com a âncora de cada um e, no fit, o mínimo do critério.
    -- Nos critérios do ciclo as três chaves não existem e saem nulas.
    || jsonb_build_object('scale_min', c->'scale_min', 'anchors', c->'anchors', 'min_level', c->'min_level')
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
    'rubric_version', CASE WHEN p_evaluation_type IN ('video', 'fit') THEN (SELECT r.version FROM public.selection_opening_rubrics r
                        WHERE r.id = public._rubrica_vigente_id(p_application_id, p_evaluation_type)) END,  -- #3120
    'committee_role', COALESCE(v_committee.role, 'platform_admin'),
    'draft', CASE WHEN v_draft IS NOT NULL THEN jsonb_build_object(
      'id', v_draft.id, 'scores', v_draft.scores, 'notes', v_draft.notes,
      'criterion_notes', COALESCE(v_draft.criterion_notes, '{}'::jsonb),
      'weighted_subtotal', v_draft.weighted_subtotal, 'submitted_at', v_draft.submitted_at
    ) ELSE NULL END,
    'is_locked', CASE WHEN v_draft.submitted_at IS NOT NULL THEN true ELSE false END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_evaluation(p_application_id uuid, p_evaluation_type text, p_scores jsonb, p_notes text DEFAULT NULL::text, p_criterion_notes jsonb DEFAULT NULL::jsonb, p_ai_suggestion_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_score numeric;
  v_weight numeric;
  v_max numeric;
  v_weighted_sum numeric := 0;
  v_eval_id uuid;
  v_total_evaluators int;
  v_submitted_count int;
  v_all_subtotals numeric[];
  v_pert_score numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
  v_cutoff numeric;
  v_median numeric;
  v_new_status text;
  v_piloto_atribuido boolean := false;  -- #2393 M2
  v_rubrica uuid;                        -- #3120
  v_minimo numeric;                      -- #3120
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found'; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  -- #2393 M2: quem tem atribuição válida no piloto (a mesma regra da fila e do envio, em _avaliador_do_piloto).
  v_piloto_atribuido := NOT public._na_avaliacao_geral(p_application_id)
    AND public._avaliador_do_piloto(v_caller.id, p_application_id, p_evaluation_type);

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) AND NOT v_piloto_atribuido THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- #1591 — OBSERVADOR OBSERVA, nao avalia.
  -- Ate aqui estar no comite bastava: nem esta funcao nem `get_my_pending_evaluations` olhavam o
  -- `role`. Na pratica os 4 observadores do ciclo vivo nunca submeteram (455 avaliacoes, TODAS de
  -- `evaluator`), entao o comportamento estava certo por HABITO das pessoas, nao por trava. Uma
  -- capacidade que so nao e exercida por costume nao e uma regra.
  -- Decisao do PM (07/08/2026): peer review aberto a todo o comite, EXCETO observadores.
  -- O escape de `manage_platform` continua, para nao mudar a autoridade de quem administra.
  IF v_committee.role = 'observer'
     AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text)
     AND NOT v_piloto_atribuido THEN
    RAISE EXCEPTION 'Unauthorized: observer role does not evaluate'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- #2393 fatia 3 (D1) e M2: piloto fora da avaliação geral, salvo o avaliador atribuído a ele.
  IF NOT public._na_avaliacao_geral(p_application_id) AND NOT v_piloto_atribuido THEN
    RAISE EXCEPTION 'Unauthorized: pilot_track application is not evaluated through the general committee (ADR-0134)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- #3120 (ADR-0134 §3): vídeo e fit leem a rubrica vigente da vaga; o fit só depois da 1ª nota de vídeo enviada.
  IF p_evaluation_type IN ('video', 'fit') THEN
    v_rubrica := public._rubrica_vigente_id(p_application_id, p_evaluation_type);
    IF v_rubrica IS NULL THEN
      RAISE EXCEPTION 'A vaga desta candidatura ainda não tem rubrica de %', p_evaluation_type
        USING ERRCODE = 'check_violation';
    END IF;
    IF p_evaluation_type = 'fit' AND NOT public._fit_aberto(p_application_id) THEN
      RAISE EXCEPTION 'O fit abre depois da primeira nota de vídeo enviada desta candidatura (ADR-0134 §3)'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluator_id = v_caller.id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Evaluation already submitted and locked';
  END IF;

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    WHEN 'video' THEN public._criterios_da_rubrica(p_application_id, 'video')  -- #3120
    WHEN 'fit' THEN public._criterios_da_rubrica(p_application_id, 'fit')      -- #3120
    ELSE '[]'::jsonb
  END;

  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);
    v_max := COALESCE((v_criterion ->> 'max')::numeric, 10);
    IF NOT (p_scores ? v_key) THEN RAISE EXCEPTION 'Missing score for criterion: %', v_key; END IF;
    v_score := (p_scores ->> v_key)::numeric;
    IF v_score IS NULL THEN RAISE EXCEPTION 'Score for % must be numeric', v_key; END IF;
    IF v_score < 0 OR v_score > v_max THEN
      RAISE EXCEPTION 'Score % for criterion "%" must be between 0 and % (schema max)', v_score, v_key, v_max;
    END IF;
    -- #3120: na rubrica, só os 3 níveis (fraco 1, médio 2, forte 3). No fit, nota abaixo do mínimo do critério
    -- exige justificativa escrita NAQUELE critério; não bloqueia a decisão, só a nota sem motivo (decisão do GP).
    IF v_rubrica IS NOT NULL THEN
      IF v_score NOT IN (1, 2, 3) THEN
        RAISE EXCEPTION 'A nota de "%" é 1 (fraco), 2 (médio) ou 3 (forte)', v_key USING ERRCODE = 'check_violation';
      END IF;
      v_minimo := (v_criterion ->> 'min_level')::numeric;
      IF p_evaluation_type = 'fit' AND v_minimo IS NOT NULL AND v_score < v_minimo
         AND coalesce(btrim(p_criterion_notes ->> v_key), '') = '' THEN
        RAISE EXCEPTION 'A nota de "%" está abaixo do mínimo do critério: escreva a justificativa nele', v_key
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at, rubric_id
  ) VALUES (
    p_application_id, v_caller.id, p_evaluation_type,
    p_scores, ROUND(v_weighted_sum, 2), p_notes,
    COALESCE(p_criterion_notes, '{}'::jsonb), now(), v_rubrica
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    rubric_id = EXCLUDED.rubric_id,  -- #3120: a versão da rubrica com que a nota foi dada
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    criterion_notes = EXCLUDED.criterion_notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  SELECT COUNT(*) INTO v_total_evaluators FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND role IN ('evaluator', 'lead');

  SELECT COUNT(*) INTO v_submitted_count FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

  IF v_submitted_count >= v_cycle.min_evaluators THEN
    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal) INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);
    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    IF p_evaluation_type = 'objective' THEN
      UPDATE public.selection_applications SET objective_score_avg = v_pert_score, updated_at = now() WHERE id = p_application_id;
      -- #2393 M2: a candidatura piloto guarda a média (a parte objetiva da nota do piloto) e fica fora do corte do
      -- ciclo, nem como candidata nem na mediana. A decisão dela sai da avaliação do piloto.
      IF public._na_avaliacao_geral(p_application_id) THEN
        SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY objective_score_avg) INTO v_median
        FROM public.selection_applications WHERE cycle_id = v_app.cycle_id AND objective_score_avg IS NOT NULL
          AND public._na_avaliacao_geral(id);
        v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);
        IF v_pert_score < v_cutoff AND v_cutoff > 0 THEN v_new_status := 'objective_cutoff'; ELSE v_new_status := 'interview_pending'; END IF;
        UPDATE public.selection_applications SET status = v_new_status, updated_at = now()
        WHERE id = p_application_id AND status IN ('submitted', 'screening', 'objective_eval');
      END IF;
    ELSIF p_evaluation_type = 'interview' THEN
      UPDATE public.selection_applications
        SET interview_score = v_pert_score,
            status = 'final_eval',
            updated_at = now()
      WHERE id = p_application_id;
      PERFORM public.compute_application_scores(p_application_id);
    ELSIF p_evaluation_type = 'leader_extra' THEN
      UPDATE public.selection_applications
        SET leader_extra_pert_score = v_pert_score,
            updated_at = now()
      WHERE id = p_application_id;
      PERFORM public.compute_application_scores(p_application_id);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'evaluation_id', v_eval_id, 'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score, 'new_status', v_new_status
  );
END;
$function$;

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
$function$;

CREATE OR REPLACE FUNCTION public.get_selection_evaluators_admin()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller uuid;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active;
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  RETURN jsonb_build_object(
    -- As vagas piloto, para os seletores da tela.
    'openings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('opportunity_id', vo.opportunity_id, 'title', vo.title, 'is_active', vo.is_active,
                                          'initiative_id', vo.initiative_id, 'initiative_title', i.title)
                       ORDER BY vo.opportunity_id)
        FROM public.vep_opportunities vo LEFT JOIN public.initiatives i ON i.id = vo.initiative_id
       WHERE vo.evaluation_track = 'line_pilot'), '[]'::jsonb),
    -- As candidaturas dessas vagas, para atribuir.
    'applications', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', sa.id, 'applicant_name', sa.applicant_name, 'status', sa.status,
                                          'opportunity_id', sa.vep_opportunity_id)
                       ORDER BY sa.vep_opportunity_id, sa.applicant_name)
        FROM public.selection_applications sa
        JOIN public.vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id AND vo.evaluation_track = 'line_pilot'), '[]'::jsonb),
    -- Membros ativos, para dar o vínculo.
    'members', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name) ORDER BY m.name)
        FROM public.members m WHERE m.is_active AND m.person_id IS NOT NULL), '[]'::jsonb),
    -- Todo vínculo de avaliador, ativo ou não. Vale (authoritative) quem está ativo e dentro da data de fim.
    'evaluators', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'engagement_id', e.id, 'member_id', m.id, 'name', m.name, 'status', e.status,
               'start_date', e.start_date, 'end_date', e.end_date, 'granted_at', e.granted_at,
               'revoked_at', e.revoked_at, 'revoke_reason', e.revoke_reason,
               'authoritative', (e.status = 'active' AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)))
             ORDER BY (e.status = 'active') DESC, m.name, e.start_date DESC)
        FROM public.engagements e JOIN public.members m ON m.person_id = e.person_id
       WHERE e.kind = 'selection_evaluator'), '[]'::jsonb),
    'calibrations', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', c.id, 'member_id', c.member_id, 'name', m.name, 'opportunity_id', c.opportunity_id, 'part', c.part,
               'material_version', c.material_version, 'calibrated_at', c.calibrated_at, 'calibrated_by_name', cb.name,
               'notes', c.notes)
             ORDER BY c.opportunity_id, c.part, m.name)
        FROM public.selection_evaluator_calibrations c
        JOIN public.members m ON m.id = c.member_id
        LEFT JOIN public.members cb ON cb.id = c.calibrated_by), '[]'::jsonb),
    -- Estado: retirada, enviada, vencida (prazo passado sem envio), em rascunho ou pendente.
    'assignments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', a.id, 'application_id', a.application_id, 'applicant_name', sa.applicant_name,
               'opportunity_id', sa.vep_opportunity_id, 'part', a.part, 'member_id', a.evaluator_member_id, 'name', m.name,
               'assigned_at', a.assigned_at, 'due_at', a.due_at, 'withdrawn_at', a.withdrawn_at,
               'withdrawn_reason', a.withdrawn_reason, 'submitted_at', se.submitted_at,
               'state', CASE WHEN a.withdrawn_at IS NOT NULL THEN 'withdrawn'
                             WHEN se.submitted_at IS NOT NULL THEN 'submitted'
                             WHEN a.due_at < now() THEN 'overdue'
                             WHEN se.id IS NOT NULL THEN 'draft'
                             ELSE 'pending' END)
             ORDER BY sa.vep_opportunity_id, sa.applicant_name, a.part, m.name)
        FROM public.selection_evaluation_assignments a
        JOIN public.selection_applications sa ON sa.id = a.application_id
        JOIN public.members m ON m.id = a.evaluator_member_id
        LEFT JOIN public.selection_evaluations se
          ON se.application_id = a.application_id AND se.evaluator_id = a.evaluator_member_id AND se.evaluation_type = a.part), '[]'::jsonb),
    -- #3120: as rubricas, toda versão, com a vigente marcada e a trava (há nota enviada daquela parte na vaga).
    'rubrics', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', r.id, 'opportunity_id', r.opportunity_id, 'part', r.part, 'version', r.version, 'items', r.items,
               'created_at', r.created_at, 'created_by_name', cb.name,
               'is_current', r.version = (SELECT max(r2.version) FROM public.selection_opening_rubrics r2
                                           WHERE r2.opportunity_id = r.opportunity_id AND r2.part = r.part),
               'locked', public._rubrica_travada(r.opportunity_id, r.part))
             ORDER BY r.opportunity_id, r.part, r.version DESC)
        FROM public.selection_opening_rubrics r LEFT JOIN public.members cb ON cb.id = r.created_by), '[]'::jsonb),
    -- O histórico: as escritas das funções de avaliador, da mais nova para a mais antiga.
    'history', COALESCE((
      SELECT jsonb_agg(h ORDER BY h.created_at DESC) FROM (
        SELECT l.created_at, l.action, l.target_type, l.target_id, l.metadata, act.name AS actor_name, tgt.name AS target_name
          FROM public.admin_audit_log l
          LEFT JOIN public.members act ON act.id = l.actor_id
          LEFT JOIN public.members tgt ON l.target_type = 'member' AND tgt.id::text = l.target_id::text
         WHERE l.action LIKE 'selection\_evaluator.%' OR l.action LIKE 'selection\_rubric.%'
         ORDER BY l.created_at DESC
         LIMIT 300) h), '[]'::jsonb)
  );
END;
$function$;

-- #3120 (achado da orquestradora na aplicação da 3119): concessão × extensão no histórico.
CREATE OR REPLACE FUNCTION public.grant_selection_evaluator(p_member_id uuid, p_end_date date, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller uuid;
  v_caller_person uuid;
  v_member record;
  v_eng uuid;
  v_fim_antes date;
  v_existia boolean;
BEGIN
  SELECT m.id, m.person_id INTO v_caller, v_caller_person FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active;
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  SELECT m.id, m.person_id, m.organization_id, m.is_active INTO v_member FROM public.members m WHERE m.id = p_member_id;
  IF v_member.id IS NULL OR NOT v_member.is_active OR v_member.person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Membro inexistente, inativo ou sem pessoa: o avaliador do piloto precisa ser membro ativo (D21).');
  END IF;
  IF p_end_date IS NULL OR p_end_date < CURRENT_DATE OR p_end_date > CURRENT_DATE + 180 THEN
    RETURN jsonb_build_object('error', 'A data de fim é obrigatória, a partir de hoje e em até 180 dias.');
  END IF;

  SELECT e.id, e.end_date INTO v_eng, v_fim_antes FROM public.engagements e
   WHERE e.person_id = v_member.person_id AND e.kind = 'selection_evaluator' AND e.status = 'active'
   ORDER BY e.start_date DESC LIMIT 1;
  v_existia := v_eng IS NOT NULL;
  IF v_existia THEN
    UPDATE public.engagements SET end_date = p_end_date, updated_at = now() WHERE id = v_eng;
  ELSE
    INSERT INTO public.engagements (person_id, organization_id, kind, role, status, start_date, end_date,
                                    legal_basis, granted_by, granted_at, metadata)
    VALUES (v_member.person_id, v_member.organization_id, 'selection_evaluator', 'evaluator', 'active', CURRENT_DATE, p_end_date,
            'legitimate_interest', v_caller_person, now(),
            jsonb_build_object('source', 'grant_selection_evaluator', 'note', p_note))
    RETURNING id INTO v_eng;
  END IF;
  -- #3119/#3120: o histórico da tela de avaliadores. Sem vínculo ativo antes é concessão; com vínculo, extensão da data
  -- de fim. Decide pela EXISTÊNCIA do vínculo, não pela data de fim dele, que pode ser nula num vínculo antigo.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (v_caller, CASE WHEN NOT v_existia THEN 'selection_evaluator.granted' ELSE 'selection_evaluator.extended' END,
          'member', p_member_id,
          jsonb_build_object('engagement_id', v_eng, 'end_date', p_end_date, 'end_date_before', v_fim_antes, 'note', p_note));
  RETURN jsonb_build_object('success', true, 'engagement_id', v_eng, 'end_date', p_end_date);
END;
$function$;

REVOKE ALL ON FUNCTION public._rubrica_vigente_id(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._criterios_da_rubrica(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._fit_aberto(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._rubrica_travada(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.save_selection_rubric(text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_selection_rubric(text, text, jsonb) TO authenticated;
COMMENT ON FUNCTION public.save_selection_rubric(text, text, jsonb) IS
  '#3120 (ADR-0134 §3): grava uma versão nova da rubrica da vaga (vídeo ou fit), pela gestão ou pelo líder ativo da vaga; recusa com a parte travada; registra em admin_audit_log.';
