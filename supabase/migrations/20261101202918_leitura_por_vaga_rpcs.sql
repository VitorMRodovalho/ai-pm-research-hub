-- #2393, ADR-0134 §6, fatia 2: leitura por vaga. Parte 2 de 2: as duas leituras.
--
-- `list_opening_applications(p_opportunity_id)` lista as candidaturas das vagas de linha em que o
-- caller tem `view_opening_applications`, ou de uma vaga só. `get_opening_application(p_application_id)`
-- devolve o detalhe de uma.
--
-- O portão, nesta ordem:
--   1. o caller é membro ativo, e vaga e candidatura são da organização dele (auth_org(), §10);
--   2. a vaga geral (sem iniciativa) não tem leitor por vaga e é recusada antes da autoridade: segue
--      com o comitê do ciclo e o GP, pelas telas de hoje;
--   3. can_by_member(caller, 'view_opening_applications', 'initiative', <iniciativa da vaga>), sempre
--      com a iniciativa;
--   4. rls_can_see_initiative(<iniciativa>) (ADR-0105). Hoje o passo 3 já exige vínculo autoritativo
--      na própria iniciativa; o passo 4 segura uma semente futura de escopo mais largo;
--   5. selection_coi_recused(caller, ciclo) (ADR-0109): quem é candidato no ciclo fica impedido;
--   6. registro OBRIGATÓRIO em pii_access_log por candidatura devolvida, antes do retorno, por
--      _log_opening_application_access: se não gravar, a leitura falha e nada é devolvido.
-- Até a autoridade, toda recusa é 'Unauthorized': a resposta não diz se a vaga ou a candidatura
-- existem, nem se a vaga é geral.
--
-- O que volta (decisão do GP, D2 (a), 01/11/2026): dados do candidato, respostas, status e etapa.
-- As respostas são as colunas que o essay_mapping das vagas preenche, e o detalhe traz, de cada
-- pergunta da vaga, só o campo e o texto. Nenhuma nota de avaliador e nenhuma análise
-- ou triagem por IA: a §4 tira o líder da avaliação objetiva e do vídeo da própria vaga, a revisão
-- cega (ADR-0059) segue valendo, e a §5 e a ADR-0067 tiram a IA da nota. Também ficam fora
-- telefone, gênero, faixa etária, perfil PMI e o texto extraído do currículo (minimização). O
-- detalhe lê só as colunas que devolve, nunca a linha inteira.
--
-- Só a candidatura do mesmo ciclo da vaga entra, e a anonimizada não entra.
-- VOLATILE porque grava o registro. O GP não tem a ação e lê pelas telas de hoje.
-- Limite conhecido: o conflito de interesse reconhece o candidato pelo e-mail (o principal e os de
-- member_emails), como em toda superfície da ADR-0109.

CREATE OR REPLACE FUNCTION public.list_opening_applications(p_opportunity_id text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_org uuid;
  v_opp record;
  v_app record;
  v_rows jsonb := '[]'::jsonb;
  v_omitidas_coi int := 0;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  v_org := public.auth_org();
  IF v_caller_id IS NULL OR v_org IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF p_opportunity_id IS NOT NULL THEN
    SELECT vo.opportunity_id, vo.initiative_id, vo.cycle_id, vo.organization_id
      INTO v_opp
    FROM public.vep_opportunities vo
    WHERE vo.opportunity_id = p_opportunity_id;

    IF v_opp.opportunity_id IS NULL OR v_opp.organization_id IS DISTINCT FROM v_org THEN
      RETURN jsonb_build_object('error', 'Unauthorized');
    END IF;
    IF v_opp.initiative_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Unauthorized');
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'view_opening_applications', 'initiative', v_opp.initiative_id)
       OR NOT public.rls_can_see_initiative(v_opp.initiative_id) THEN
      RETURN jsonb_build_object('error', 'Unauthorized');
    END IF;
    IF public.selection_coi_recused(v_caller_id, v_opp.cycle_id) THEN
      RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
        'detail', 'Você é candidato(a) neste ciclo: a leitura das candidaturas está impedida por conflito de interesse (ADR-0109).');
    END IF;
  END IF;

  FOR v_app IN
    SELECT sa.id, sa.cycle_id, sa.applicant_name, sa.chapter, sa.role_applied, sa.status,
           sa.interview_status, sa.application_date,
           vo.opportunity_id, vo.title AS opening_title, vo.initiative_id
    FROM public.vep_opportunities vo
    JOIN public.selection_applications sa
      ON sa.vep_opportunity_id = vo.opportunity_id
     AND sa.cycle_id = vo.cycle_id
    WHERE vo.initiative_id IS NOT NULL
      AND vo.organization_id = v_org
      AND sa.organization_id = v_org
      AND sa.anonymized_at IS NULL
      AND (p_opportunity_id IS NULL OR vo.opportunity_id = p_opportunity_id)
      AND public.can_by_member(v_caller_id, 'view_opening_applications', 'initiative', vo.initiative_id)
      AND public.rls_can_see_initiative(vo.initiative_id)
    ORDER BY vo.opportunity_id, sa.application_date NULLS LAST, sa.id
  LOOP
    IF public.selection_coi_recused(v_caller_id, v_app.cycle_id) THEN
      v_omitidas_coi := v_omitidas_coi + 1;
      CONTINUE;
    END IF;

    PERFORM public._log_opening_application_access(
      v_app.id, v_caller_id,
      ARRAY['applicant_name', 'chapter', 'role_applied', 'status', 'interview_status'],
      'list_opening_applications'
    );

    v_rows := v_rows || jsonb_build_array(jsonb_build_object(
      'application_id', v_app.id,
      'opportunity_id', v_app.opportunity_id,
      'opening_title', v_app.opening_title,
      'initiative_id', v_app.initiative_id,
      'applicant_name', v_app.applicant_name,
      'chapter', v_app.chapter,
      'role_applied', v_app.role_applied,
      'status', v_app.status,
      'interview_status', v_app.interview_status,
      'application_date', v_app.application_date
    ));
  END LOOP;

  RETURN jsonb_build_object(
    'applications', v_rows,
    'count', jsonb_array_length(v_rows),
    'omitted_conflict_of_interest', v_omitidas_coi
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_opening_application(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_org uuid;
  v_app record;
  v_perguntas jsonb;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  v_org := public.auth_org();
  IF v_caller_id IS NULL OR v_org IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT sa.id, sa.cycle_id, sa.organization_id,
         sa.applicant_name, sa.email, sa.chapter, sa.chapter_affiliation,
         sa.applicant_city, sa.state, sa.country, sa.linkedin_url, sa.credly_url,
         sa.role_applied, sa.status, sa.interview_status, sa.application_date,
         sa.certifications, sa.academic_background, sa.motivation_letter, sa.reason_for_applying,
         sa.proposed_theme, sa.areas_of_interest, sa.availability_declared,
         sa.leadership_experience, sa.non_pmi_experience,
         vo.opportunity_id AS vo_opportunity_id, vo.title AS opening_title,
         vo.initiative_id AS vo_initiative_id, vo.organization_id AS vo_organization_id,
         vo.essay_mapping AS vo_essay_mapping,
         sc.cycle_code
    INTO v_app
  FROM public.selection_applications sa
  LEFT JOIN public.vep_opportunities vo
    ON vo.opportunity_id = sa.vep_opportunity_id
   AND vo.cycle_id = sa.cycle_id
  LEFT JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
  WHERE sa.id = p_application_id
    AND sa.anonymized_at IS NULL;

  IF v_app.id IS NULL OR v_app.organization_id IS DISTINCT FROM v_org THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF v_app.vo_opportunity_id IS NULL OR v_app.vo_organization_id IS DISTINCT FROM v_org THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF v_app.vo_initiative_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_opening_applications', 'initiative', v_app.vo_initiative_id)
     OR NOT public.rls_can_see_initiative(v_app.vo_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF public.selection_coi_recused(v_caller_id, v_app.cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo: a leitura das candidaturas está impedida por conflito de interesse (ADR-0109).');
  END IF;

  PERFORM public._log_opening_application_access(
    v_app.id, v_caller_id,
    ARRAY['applicant_name', 'email', 'chapter', 'chapter_affiliation', 'applicant_city', 'state',
          'country', 'linkedin_url', 'credly_url', 'certifications', 'academic_background',
          'motivation_letter', 'reason_for_applying', 'proposed_theme', 'areas_of_interest',
          'availability_declared', 'leadership_experience', 'non_pmi_experience'],
    'get_opening_application'
  );

  -- Das perguntas da vaga saem só o campo e o texto. O essay_mapping é jsonb livre e vai crescer
  -- com as camadas de perguntas (ADR-0134 §2); o que entrar nele além disso não chega ao leitor.
  v_perguntas := (
    SELECT jsonb_object_agg(q.key, jsonb_build_object('field', q.value->>'field', 'question', q.value->>'question'))
    FROM jsonb_each(CASE WHEN jsonb_typeof(v_app.vo_essay_mapping) = 'object'
                         THEN v_app.vo_essay_mapping ELSE '{}'::jsonb END) q
  );

  RETURN jsonb_build_object(
    'application_id', v_app.id,
    'opportunity_id', v_app.vo_opportunity_id,
    'opening_title', v_app.opening_title,
    'initiative_id', v_app.vo_initiative_id,
    'cycle_code', v_app.cycle_code,
    'essay_questions', v_perguntas,
    'applicant_name', v_app.applicant_name,
    'email', v_app.email,
    'chapter', v_app.chapter,
    'chapter_affiliation', v_app.chapter_affiliation,
    'applicant_city', v_app.applicant_city,
    'state', v_app.state,
    'country', v_app.country,
    'linkedin_url', v_app.linkedin_url,
    'credly_url', v_app.credly_url,
    'role_applied', v_app.role_applied,
    'status', v_app.status,
    'interview_status', v_app.interview_status,
    'application_date', v_app.application_date,
    'certifications', v_app.certifications,
    'academic_background', v_app.academic_background,
    'motivation_letter', v_app.motivation_letter,
    'reason_for_applying', v_app.reason_for_applying,
    'proposed_theme', v_app.proposed_theme,
    'areas_of_interest', v_app.areas_of_interest,
    'availability_declared', v_app.availability_declared,
    'leadership_experience', v_app.leadership_experience,
    'non_pmi_experience', v_app.non_pmi_experience
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.list_opening_applications(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_opening_applications(text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_opening_application(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_opening_application(uuid) TO authenticated;

COMMENT ON FUNCTION public.list_opening_applications(text) IS
  '#2393 (ADR-0134 §6): candidaturas das vagas de linha em que o caller tem view_opening_applications. Sem nota e sem IA (D2). Registro obrigatório em pii_access_log por candidatura devolvida. Limite conhecido: o conflito de interesse reconhece o candidato pelo e-mail.';
COMMENT ON FUNCTION public.get_opening_application(uuid) IS
  '#2393 (ADR-0134 §6): detalhe de uma candidatura de vaga de linha, para quem tem view_opening_applications na iniciativa da vaga. Sem nota e sem IA (D2). Registro obrigatório em pii_access_log. Limite conhecido: o conflito de interesse reconhece o candidato pelo e-mail.';

NOTIFY pgrst, 'reload schema';
