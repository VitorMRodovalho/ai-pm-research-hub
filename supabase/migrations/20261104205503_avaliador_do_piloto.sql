-- #2393 M2 (ADR-0134): o avaliador mínimo do piloto da linha e o lembrete único do portal.
--
-- 1. O vínculo de avaliador (D7): kind selection_evaluator, sem iniciativa, com data de fim obrigatória, e a ação
--    evaluate_assigned_application em escopo de organização (procedimento V4, etapa 0: o kind não é atado a espécie).
-- 2. Calibragem (D8) e atribuição (P1), em tabelas próprias, só por função: calibra antes, atribui depois.
-- 3. _avaliador_do_piloto: a regra única de quem avalia uma candidatura piloto. Fila, formulário e envio a usam.
-- 4. As funções da avaliação abrem a exceção do piloto só para o avaliador atribuído; o piloto não entra no corte
--    do ciclo; as notas do piloto só a gestão lê.
-- 5. O aviso de atribuição ao avaliador (catálogo da ADR-0022) e o lembrete único do portal ao candidato (C9).

-- ── 1. O vínculo de avaliador ──
DO $$
DECLARE
  v_org uuid;
BEGIN
  SELECT organization_id INTO v_org FROM public.engagement_kind_permissions
   WHERE kind = 'volunteer' AND role = 'leader' AND action = 'view_pii';
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'âncora ausente: volunteer x leader x view_pii não existe; não dá para derivar organization_id';
  END IF;

  INSERT INTO public.engagement_kinds (
    slug, display_name, description,
    legal_basis, requires_agreement, agreement_template,
    default_duration_days, retention_days_after_end, is_initiative_scoped,
    requires_vep, requires_selection, max_duration_days,
    anonymization_policy, renewable, auto_expire_behavior, notify_before_expiry_days,
    created_by_role, revocable_by_role, initiative_kinds_allowed,
    metadata_schema, display_i18n, organization_id
  ) VALUES (
    'selection_evaluator', 'Avaliador de seleção',
    'Avaliador de fora da linha no piloto da vaga por linha (ADR-0134 §4): avalia só as candidaturas atribuídas a ele, depois da calibragem. Sem iniciativa: a autoridade é a ação evaluate_assigned_application e a atribuição.',
    'legitimate_interest', false, NULL,
    120, 730, false,
    false, false, 180,
    'anonymize', true, 'notify_only', 14,
    ARRAY['manager','deputy_manager'], ARRAY['manager','deputy_manager'], ARRAY[]::text[],
    NULL, '{"en":"Selection evaluator","es":"Evaluador de selección"}'::jsonb, v_org
  ) ON CONFLICT (slug) DO NOTHING;

  INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description, organization_id)
  VALUES ('selection_evaluator', 'evaluator', 'evaluate_assigned_application', 'organization',
          'Avaliador de fora da linha avalia as candidaturas atribuídas a ele no piloto (ADR-0134 §4).', v_org)
  ON CONFLICT (kind, role, action) DO NOTHING;
END $$;

ALTER TABLE public.engagements DROP CONSTRAINT IF EXISTS engagements_selection_evaluator_end_date_check;
ALTER TABLE public.engagements ADD CONSTRAINT engagements_selection_evaluator_end_date_check
  CHECK (kind <> 'selection_evaluator' OR end_date IS NOT NULL);

-- ── 2. Calibragem e atribuição ──
CREATE TABLE IF NOT EXISTS public.selection_evaluator_calibrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  member_id uuid NOT NULL REFERENCES public.members(id),
  opportunity_id text NOT NULL,
  part text NOT NULL CHECK (part IN ('objective', 'video')),
  material_version text NOT NULL,
  calibrated_at timestamptz NOT NULL DEFAULT now(),
  calibrated_by uuid REFERENCES public.members(id),
  notes text,
  UNIQUE (member_id, opportunity_id, part)
);
ALTER TABLE public.selection_evaluator_calibrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.selection_evaluator_calibrations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.selection_evaluator_calibrations TO service_role;
COMMENT ON TABLE public.selection_evaluator_calibrations IS
  '#2393 M2 (ADR-0134 §4, D8): a calibragem do avaliador por vaga e parte. Sem ela, a atribuição é recusada. Só por função.';

CREATE TABLE IF NOT EXISTS public.selection_evaluation_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  application_id uuid NOT NULL REFERENCES public.selection_applications(id) ON DELETE CASCADE,
  part text NOT NULL CHECK (part IN ('objective', 'video')),
  evaluator_member_id uuid NOT NULL REFERENCES public.members(id),
  assigned_by uuid REFERENCES public.members(id),
  assigned_at timestamptz NOT NULL DEFAULT now(),
  due_at timestamptz,
  withdrawn_at timestamptz,
  withdrawn_reason text,
  UNIQUE (application_id, part, evaluator_member_id)
);
CREATE INDEX IF NOT EXISTS selection_evaluation_assignments_evaluator_idx
  ON public.selection_evaluation_assignments (evaluator_member_id) WHERE withdrawn_at IS NULL;
ALTER TABLE public.selection_evaluation_assignments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.selection_evaluation_assignments FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.selection_evaluation_assignments TO service_role;
COMMENT ON TABLE public.selection_evaluation_assignments IS
  '#2393 M2 (ADR-0134 §4, P1): quem avalia qual parte de qual candidatura piloto. Duas pessoas por parte, só por função.';

-- ── 3. A regra única de quem avalia uma candidatura piloto ──
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
      AND NOT EXISTS (SELECT 1 FROM public.engagements e
                       WHERE e.person_id = m.person_id AND e.initiative_id = vo.initiative_id
                         AND e.status IN ('active', 'suspended'))
  );
$function$;
REVOKE ALL ON FUNCTION public._avaliador_do_piloto(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public._avaliador_do_piloto(uuid, uuid, text) IS
  '#2393 M2 (ADR-0134 §4): atribuição ativa daquela parte, ação evaluate_assigned_application, calibragem da vaga e parte, sem conflito de interesse e SEM vínculo na iniciativa da vaga. Fila, formulário e envio usam esta regra.';

-- ── 3b. As funções da gestão: vínculo, calibragem, atribuição e retirada ──
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

  SELECT e.id INTO v_eng FROM public.engagements e
   WHERE e.person_id = v_member.person_id AND e.kind = 'selection_evaluator' AND e.status = 'active'
   ORDER BY e.start_date DESC LIMIT 1;
  IF v_eng IS NOT NULL THEN
    UPDATE public.engagements SET end_date = p_end_date, updated_at = now() WHERE id = v_eng;
  ELSE
    INSERT INTO public.engagements (person_id, organization_id, kind, role, status, start_date, end_date,
                                    legal_basis, granted_by, granted_at, metadata)
    VALUES (v_member.person_id, v_member.organization_id, 'selection_evaluator', 'evaluator', 'active', CURRENT_DATE, p_end_date,
            'legitimate_interest', v_caller_person, now(),
            jsonb_build_object('source', 'grant_selection_evaluator', 'note', p_note))
    RETURNING id INTO v_eng;
  END IF;
  RETURN jsonb_build_object('success', true, 'engagement_id', v_eng, 'end_date', p_end_date);
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_selection_evaluator_calibration(
  p_member_id uuid, p_opportunity_id text, p_part text, p_material_version text, p_notes text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller uuid;
  v_org uuid;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active;
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF p_part NOT IN ('objective', 'video') OR coalesce(btrim(p_material_version), '') = '' THEN
    RETURN jsonb_build_object('error', 'Parte (objective ou video) e versão do material são obrigatórias.');
  END IF;
  SELECT vo.organization_id INTO v_org FROM public.vep_opportunities vo
   WHERE vo.opportunity_id = p_opportunity_id AND vo.evaluation_track = 'line_pilot';
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('error', 'A vaga não existe ou não é piloto da linha.');
  END IF;
  IF NOT public.can_by_member(p_member_id, 'evaluate_assigned_application') THEN
    RETURN jsonb_build_object('error', 'A pessoa ainda não tem o vínculo de avaliador (grant_selection_evaluator).');
  END IF;
  INSERT INTO public.selection_evaluator_calibrations (organization_id, member_id, opportunity_id, part, material_version, calibrated_by, notes)
  VALUES (v_org, p_member_id, p_opportunity_id, p_part, btrim(p_material_version), v_caller, p_notes)
  ON CONFLICT (member_id, opportunity_id, part) DO UPDATE
    SET material_version = EXCLUDED.material_version, calibrated_at = now(), calibrated_by = EXCLUDED.calibrated_by, notes = EXCLUDED.notes;
  RETURN jsonb_build_object('success', true);
END;
$function$;

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
  IF v_member.id IS NULL OR NOT v_member.is_active THEN v_motivos := v_motivos || 'membro inexistente ou inativo'; END IF;
  IF NOT public.can_by_member(p_member_id, 'evaluate_assigned_application') THEN
    v_motivos := v_motivos || 'sem o vínculo de avaliador';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.selection_evaluator_calibrations c
                  WHERE c.member_id = p_member_id AND c.opportunity_id = p_opportunity_id AND c.part = p_part) THEN
    v_motivos := v_motivos || 'sem calibragem desta vaga e parte';
  END IF;
  IF EXISTS (SELECT 1 FROM public.engagements e
              WHERE e.person_id = v_member.person_id AND e.initiative_id = v_vo.initiative_id AND e.status IN ('active', 'suspended')) THEN
    v_motivos := v_motivos || 'tem vínculo na iniciativa da vaga (ADR-0134 §4: avaliador de fora da linha)';
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

CREATE OR REPLACE FUNCTION public.withdraw_selection_evaluator_assignment(p_assignment_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
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
  IF coalesce(btrim(p_reason), '') = '' THEN
    RETURN jsonb_build_object('error', 'O motivo é obrigatório.');
  END IF;
  UPDATE public.selection_evaluation_assignments SET withdrawn_at = now(), withdrawn_reason = btrim(p_reason)
   WHERE id = p_assignment_id AND withdrawn_at IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Atribuição inexistente ou já retirada.'); END IF;
  RETURN jsonb_build_object('success', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.grant_selection_evaluator(uuid, date, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_selection_evaluator_calibration(uuid, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_selection_evaluators(text, text, uuid, uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.withdraw_selection_evaluator_assignment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.grant_selection_evaluator(uuid, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_selection_evaluator_calibration(uuid, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_selection_evaluators(text, text, uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_selection_evaluator_assignment(uuid, text) TO authenticated;

-- ── 4. As funções da avaliação ──
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
      'calc_at', v_app.pert_calc_at
    ),
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
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at
  ) VALUES (
    p_application_id, v_caller.id, p_evaluation_type,
    p_scores, ROUND(v_weighted_sum, 2), p_notes,
    COALESCE(p_criterion_notes, '{}'::jsonb), now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
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

  -- #2393 M2: as notas do piloto só a gestão lê (D18). Nem o comitê do ciclo nem quem avaliou: o avaliador do
  -- piloto que também tem assento leria a nota do outro (revisão cega, ADR-0059).
  IF NOT public._na_avaliacao_geral(p_application_id) AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: pilot_track results are read by management only (ADR-0134)'
      USING ERRCODE = 'insufficient_privilege';
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

-- ── 5. Avisos: atribuição ao avaliador e lembrete único do portal ──
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE p_type
    -- PR-2 (email audit): the per-signing leadership alert is now in-app only; the daily
    -- digest (volunteer_term_signed_digest) carries the single aggregated email.
    WHEN 'volunteer_agreement_signed'    THEN 'suppress'
    WHEN 'volunteer_term_signed_digest'  THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    -- #1169: ready is redundant with issued at the email layer (issued carries the single email);
    -- kept in-app only. Every ready-cert already fired an issued email (0 ready-without-issued/60d).
    WHEN 'certificate_ready'             THEN 'suppress'
    WHEN 'certificate_issued'            THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'governance_manual_proposed'    THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'
    -- p153 OPP-153.1: project_charter (TAP) notifications
    WHEN 'project_charter_invite'        THEN 'transactional_immediate'
    WHEN 'project_charter_approved'      THEN 'transactional_immediate'
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- #2325 (2026-09-16): o LEMBRETE de que o termo segue aberto. Tipo proprio, separado de
    -- `selection_termo_due` (que anuncia a ABERTURA, no aceite do VEP, e e alvo de replay).
    -- Nasceu porque a cobranca saia como `system`, que o catalogo manda suprimir: 26 avisos a
    -- 16 pessoas que nunca deixaram a plataforma. Catalogado de proposito em vez de cair no
    -- ELSE: o ELSE e `digest_weekly`, que carimba como entregue o que nao renderiza (#2286).
    WHEN 'volunteer_term_pending'        THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): Selection funnel Policy Matrix
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 2 (2026-05-23): admin reminder for overdue interviews
    WHEN 'selection_interview_overdue'   THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 4 (2026-05-23): candidate invite to book interview after
    -- objective evaluations cleared + research_score >= cycle cutoff.
    WHEN 'selection_cutoff_approved'     THEN 'transactional_immediate'
    -- (end p228)
    -- #2013 (2026-08-26): o teto de lembretes de reagendamento foi atingido e o caso vira
    -- trabalho de gente. Imediato de proposito: e o unico aviso, e o digest semanal so
    -- entrega a quem tem OUTRO conteudo na semana (#2010).
    WHEN 'selection_reschedule_escalated' THEN 'transactional_immediate'
    -- #186 (2026-06-05): curation committee broadcast when an item enters curation_pending
    WHEN 'curation_item_submitted'       THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    -- #625 F3 (2026-06-11): radar de renovação de filiação
    WHEN 'affiliation_renewal_d7_urgent'  THEN 'transactional_immediate'
    WHEN 'affiliation_renewal_d30'        THEN 'digest_weekly'
    WHEN 'affiliation_verification_stale' THEN 'digest_weekly'
    -- #1855 (2026-08-18): faixa de filiacao ja VENCIDA. Catalogado de proposito, e nao deixado
    -- cair no ELSE, pelo mesmo motivo registrado no bloco 5b da #625: o ELSE e um default de
    -- conveniencia e um dia muda. digest_weekly porque o PM decidiu 'so lembrete, mesmo tom'.
    WHEN 'affiliation_renewal_expired'    THEN 'digest_weekly'
    -- #2152 (2026-09-03): a verificacao ficou atras do VEP. Vai para a diretoria, nao para o
    -- membro, e no mesmo modo da faixa irma de verificacao obsoleta: e trabalho de fila, nao
    -- urgencia. Catalogado em vez de cair no ELSE, pelo motivo registrado acima.
    WHEN 'affiliation_vep_divergence'     THEN 'digest_weekly'
    -- #1224 PR2 (2026-07-09): one-time onboarding nudge when the PMI enrichment cannot resolve
    -- an entry chapter (profile_private / no_fetch / not_affiliated / ambiguous-no-choice).
    WHEN 'entry_chapter_action_needed'    THEN 'transactional_immediate'
    -- #740 Wave 3c-i (B8): agreement rejected / reissued: member must re-sign, deliver immediately
    WHEN 'volunteer_agreement_rejected'  THEN 'transactional_immediate'
    WHEN 'volunteer_agreement_reissued'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    -- #2285 (2026-09-14): o detector de contas nao ligadas passou a ter cron. Catalogado de
    -- proposito, e nao deixado cair no ELSE, pelo mesmo motivo registrado acima para #625,
    -- #1855 e #2152. Aqui o ELSE e pior que um default inconveniente: digest_weekly monta as
    -- secoes por lista branca de tipos e carimba como entregue o que nao renderizou (#2286).
    -- #2580 C1 (2026-10-08): no sino na hora; o e-mail sai no resumo diario da gestao. `suppress` e nao
    -- digest_weekly: o resumo semanal so le digest_weekly, entao nao ha carimbo sem renderizar (#2286).
    WHEN 'unlinked_accounts_detected'     THEN 'suppress'
    -- #2580 C: o resumo diario da gestao e um e-mail proprio.
    WHEN 'management_daily_digest'        THEN 'transactional_immediate'
    -- #2444 (2026-09-24): rodizio de pareceristas da curadoria. Imediato de proposito: a
    -- designacao e o lembrete sao o que da dono ao parecer; o digest semanal chegaria depois do
    -- prazo de 7 dias. O vencido vai para quem gere a plataforma, tambem imediato: e decisao.
    WHEN 'curation_review_assigned'       THEN 'transactional_immediate'
    WHEN 'curation_review_overdue'        THEN 'transactional_immediate'
    -- #2496 (2026-09-27): aviso a tribo (participantes do card e lideranca da iniciativa) de que o
    -- item entrou em curadoria. Imediato de proposito: caia em card_moved (digest_weekly), com o
    -- codigo cru do status e link generico, e nenhuma das 3 pessoas da tribo recebeu e-mail.
    WHEN 'curation_submitted_to_tribe'    THEN 'transactional_immediate'
    -- #2621 (2026-10-09): a DECISAO da curadoria volta para a mesma audiencia do aviso de entrada
    -- (participantes do card e lideranca ativa da iniciativa). Imediatos de proposito: devolucao e
    -- rejeicao nao avisavam ninguem, e o primeiro parecer real da plataforma passou mudo; no ELSE
    -- (digest_weekly) o pedido de ajuste chegaria dias depois, com o prazo do autor correndo.
    WHEN 'curation_decision_returned'     THEN 'transactional_immediate'
    WHEN 'curation_decision_rejected'     THEN 'transactional_immediate'
    WHEN 'curation_decision_approved'     THEN 'transactional_immediate'
    -- #2495 (2026-09-27): piloto do wiki vivo (ADR-0129, emenda 2). Imediatos de proposito: a
    -- lideranca publica na hora e o comite audita em 14 dias; um aviso que chegasse no digest
    -- semanal comeria metade do prazo. O vencido vai para quem gere a plataforma.
    WHEN 'wiki_review_requested'          THEN 'transactional_immediate'
    WHEN 'wiki_page_decision'             THEN 'transactional_immediate'
    WHEN 'wiki_audit_requested'           THEN 'transactional_immediate'
    WHEN 'wiki_audit_overdue'             THEN 'transactional_immediate'
    -- #2495 fase B2 (2026-09-29): "Sugerir melhoria". Imediatos pelo mesmo motivo dos avisos do wiki
    -- acima: a sugestao vai a quem decide sobre a pagina, e a resposta volta a quem sugeriu; um aviso
    -- no digest semanal chegaria depois de a pessoa ter esquecido o que sugeriu.
    WHEN 'wiki_suggestion_received'       THEN 'transactional_immediate'
    WHEN 'wiki_suggestion_decision'       THEN 'transactional_immediate'
    -- #2444 (2026-09-24): a revisao do lider e a devolucao ao autor. Imediatos de proposito: caiam no
    -- ELSE (digest_weekly) e, medido, leader_review_requested nunca gerou uma linha sequer; sem aviso,
    -- 16 cards ficaram parados em leader_review desde maio.
    WHEN 'leader_review_requested'        THEN 'transactional_immediate'
    WHEN 'leader_review_returned'         THEN 'transactional_immediate'
    -- #2454 (2026-09-24): falha de acesso ao Drive. Imediatos: a pessoa esta sem acesso a pasta da
    -- iniciativa agora (e nao sabia: 3 casos medidos), e a falha da conta de servico e acao do
    -- administrador do Workspace.
    WHEN 'drive_access_action_needed'     THEN 'transactional_immediate'
    WHEN 'drive_access_admin_needed'      THEN 'transactional_immediate'
    -- Varredura de dado pessoal no tracker publico (10/10/2026). Imediato de proposito: o dado segue publico
    -- enquanto ninguem age, e no ELSE (digest_weekly) o e-mail chegaria em ate sete dias.
    WHEN 'tracker_pii_found'              THEN 'transactional_immediate'
    -- #2593 (C2, decisão do GP 11/10/2026): o dono do bloco da Agenda Viva sabe pelo sino, não por e-mail, quando
    -- a coordenação confirma ou cancela o bloco dele. Catalogados para não cair no ELSE (digest_weekly), que
    -- mandaria um resumo semanal de algo que só serve na hora.
    WHEN 'agenda_block_confirmed'         THEN 'suppress'
    WHEN 'agenda_block_cancelled'         THEN 'suppress'
    -- #2593 (C3b, 16/10/2026): convidado externo de reunião próxima que ainda não recebeu o convite (sem e-mail,
    -- bloco reservado ou convite não entregue). No sino do dono e da coordenação; o cron repete a cada 2 dias
    -- enquanto durar. Catalogado para não cair no ELSE (digest_weekly), que chegaria depois da reunião.
    WHEN 'agenda_guest_attention'         THEN 'suppress'
    -- #2701 (16/10/2026): certificado revogado; o membro sabe pelo sino, com o motivo. Decisão do GP: sem e-mail.
    WHEN 'certificate_revoked'            THEN 'suppress'
    -- #2782 (24/10/2026): pedido de capítulo ou de organização pelo formulário da home, para quem gere a plataforma
    -- (manage_platform). Imediato de propósito: a home promete resposta em até 5 dias úteis, e no ELSE (digest_weekly)
    -- o aviso chegaria no sábado. O aviso não leva nome, e-mail, telefone nem a mensagem de quem pediu.
    WHEN 'partner_lead_received'          THEN 'transactional_immediate'
    -- #2393 fatia 3 (02/11/2026): candidaturas novas na vaga do líder. No sino na hora e no resumo de sábado,
    -- sem e-mail imediato: o líder age em dias (ADR-0134 §8), e o 1º lote de uma vaga não vira rajada.
    -- Explícito, e não deixado no ELSE, para o modo não mudar se o ELSE mudar. Sem nome de candidato.
    WHEN 'selection_opening_new_applications' THEN 'digest_weekly'
    WHEN 'selection_evaluator_assigned'       THEN 'transactional_immediate'  -- #2393 M2
    -- Onboarding, onda 0, PR-2 (#2891, 03/11/2026): os avisos do pedido de tribo e o de boas-vindas ao vinculo
    -- gravavam 'transactional_immediate' literal no proprio INSERT e caiam no ELSE (digest_weekly) para quem perguntasse
    -- ao catalogo. Catalogados com o modo que ja usam. tribe_request_expired e novo (#2888): quem pediu sabe na hora que
    -- o pedido passou do prazo e que isso nao e uma recusa.
    WHEN 'tribe_request'                  THEN 'transactional_immediate'
    WHEN 'tribe_request_reviewed'         THEN 'transactional_immediate'
    WHEN 'tribe_request_nudge'            THEN 'transactional_immediate'
    WHEN 'tribe_request_expired_gp'       THEN 'transactional_immediate'
    WHEN 'tribe_request_expired'          THEN 'transactional_immediate'
    WHEN 'engagement_welcome'             THEN 'transactional_immediate'
    -- Onda 0 PR-5 (#2890, 03/11/2026): a resposta ao convite de retorno, para quem gere a plataforma. O INSERT nao
    -- declarava o modo e caia no default da coluna (digest_weekly), que o resumo semanal renderiza no balde
    -- other_notifications (#2286). Catalogados com o mesmo modo, para nao depender do default nem do ELSE.
    WHEN 're_engagement_accepted'         THEN 'digest_weekly'
    WHEN 're_engagement_declined'         THEN 'digest_weekly'
    ELSE 'digest_weekly'
  END;
$function$;

ALTER TABLE public.selection_applications ADD COLUMN IF NOT EXISTS pilot_portal_reminder_at timestamptz;
COMMENT ON COLUMN public.selection_applications.pilot_portal_reminder_at IS
  '#2393 M2 (C9): quando saiu o lembrete único do portal à candidatura piloto que não abriu o link. NULL = não saiu.';

INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, theme, variables)
SELECT 'Lembrete do cadastro, vaga piloto da linha', 'pmi_pilot_portal_reminder',
       jsonb_build_object('pt', 'Sua candidatura à vaga {{role_label}}: falta completar o cadastro', 'en', 'Your application for {{role_label}}: your registration is not complete yet', 'es', 'Su candidatura a la vacante {{role_label}}: falta completar el registro'),
       jsonb_build_object('pt', '<p>Olá, <b>{{first_name}}</b>!</p><p>Sua candidatura à vaga <b>{{role_label}}</b>, do Núcleo IA & GP, está registrada. Falta só completar seu cadastro no link abaixo.</p><p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Completar cadastro</a></p><p>O próximo passo desta vaga é o convite para um vídeo curto, por e-mail, até {{video_invite_by}}.</p><p>Precisa de ajuda ou quer desistir? Escreva para nucleoia@pmigo.org.br.</p><p>Equipe do Núcleo IA & GP</p>', 'en', '<p>Hi, <b>{{first_name}}</b>!</p><p>Your application for <b>{{role_label}}</b> at Núcleo IA & GP is recorded. You only need to complete your registration using the link below.</p><p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Complete registration</a></p><p>The next step for this opening is the invitation to a short video, by email, by {{video_invite_by}}.</p><p>Need help or want to withdraw? Write to nucleoia@pmigo.org.br.</p><p>Núcleo IA & GP team</p>', 'es', '<p>¡Hola, <b>{{first_name}}</b>!</p><p>Su candidatura a la vacante <b>{{role_label}}</b>, del Núcleo IA & GP, está registrada. Solo falta completar su registro en el enlace de abajo.</p><p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Completar registro</a></p><p>El próximo paso de esta vacante es la invitación a un video corto, por correo electrónico, hasta el {{video_invite_by}}.</p><p>¿Necesita ayuda o quiere desistir? Escriba a nucleoia@pmigo.org.br.</p><p>Equipo del Núcleo IA & GP</p>'),
       jsonb_build_object('pt', 'Olá, {{first_name}}!

Sua candidatura à vaga {{role_label}}, do Núcleo IA & GP, está registrada. Falta só completar seu cadastro em {{onboarding_url}}

O próximo passo desta vaga é o convite para um vídeo curto, por e-mail, até {{video_invite_by}}.

Precisa de ajuda ou quer desistir? Escreva para nucleoia@pmigo.org.br.

Equipe do Núcleo IA & GP', 'en', 'Hi, {{first_name}}!

Your application for {{role_label}} at Núcleo IA & GP is recorded. You only need to complete your registration at {{onboarding_url}}

The next step for this opening is the invitation to a short video, by email, by {{video_invite_by}}.

Need help or want to withdraw? Write to nucleoia@pmigo.org.br.

Núcleo IA & GP team', 'es', '¡Hola, {{first_name}}!

Su candidatura a la vacante {{role_label}}, del Núcleo IA & GP, está registrada. Solo falta completar su registro en {{onboarding_url}}

El próximo paso de esta vacante es la invitación a un video corto, por correo electrónico, hasta el {{video_invite_by}}.

¿Necesita ayuda o quiere desistir? Escriba a nucleoia@pmigo.org.br.

Equipo del Núcleo IA & GP'),
       '{"type":"external"}'::jsonb, 'onboarding', 'onboarding',
       '{"first_name":{"type":"text","required":true},"role_label":{"type":"text","required":true},"onboarding_url":{"type":"text","required":true},"video_invite_by":{"type":"text","required":true}}'::jsonb
 WHERE NOT EXISTS (SELECT 1 FROM public.campaign_templates WHERE slug = 'pmi_pilot_portal_reminder');

CREATE OR REPLACE FUNCTION public._lembrete_do_portal_do_piloto_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  r record;
  v_enviados int := 0;
  v_falhas int := 0;
BEGIN
  -- Uma vez por candidatura: o token do portal tem de 4 a 6 dias, nenhum token da candidatura foi aberto, ela segue
  -- inscrita e o lembrete ainda não saiu. A janela curta deixa de fora quem já recebeu aviso manual.
  FOR r IN
    SELECT DISTINCT ON (sa.id) sa.id AS application_id, sa.email, sa.applicant_name, t.token, vo.title, vo.video_invite_by
      FROM public.selection_applications sa
      JOIN public.vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
       AND vo.evaluation_track = 'line_pilot' AND vo.video_invite_by IS NOT NULL
      JOIN public.onboarding_tokens t ON t.source_type = 'pmi_application' AND t.source_id = sa.id
       AND t.scopes && ARRAY['profile_completion', 'consent_giving']::text[] AND t.expires_at > now()
     WHERE sa.status = 'submitted'
       AND sa.pilot_portal_reminder_at IS NULL
       AND sa.email IS NOT NULL
       AND t.issued_at <= now() - interval '4 days'
       AND t.issued_at > now() - interval '6 days'
       AND NOT EXISTS (SELECT 1 FROM public.onboarding_tokens t2
                        WHERE t2.source_type = 'pmi_application' AND t2.source_id = sa.id AND t2.access_count > 0)
     ORDER BY sa.id, t.issued_at DESC
  LOOP
    BEGIN
      PERFORM public.campaign_send_one_off(
        'pmi_pilot_portal_reminder', r.email,
        jsonb_build_object(
          'first_name', split_part(btrim(r.applicant_name), ' ', 1),
          'role_label', btrim(regexp_replace(r.title, '\s+-\s+Núcleo\y.*$', '')),
          'onboarding_url', 'https://nucleoia.pmigo.org.br/pmi-onboarding/' || r.token,
          'video_invite_by', to_char(r.video_invite_by, 'DD/MM/YYYY')),
        jsonb_build_object('source', 'pilot_portal_reminder', 'application_id', r.application_id));
      UPDATE public.selection_applications SET pilot_portal_reminder_at = now() WHERE id = r.application_id;
      v_enviados := v_enviados + 1;
    EXCEPTION WHEN OTHERS THEN
      v_falhas := v_falhas + 1;
      RAISE WARNING '_lembrete_do_portal_do_piloto_cron: % falhou: %', left(r.application_id::text, 8), SQLERRM;
    END;
  END LOOP;
  RETURN jsonb_build_object('sent', v_enviados, 'failed', v_falhas);
END;
$function$;
REVOKE ALL ON FUNCTION public._lembrete_do_portal_do_piloto_cron() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'selection-pilot-portal-reminder-daily') THEN
    PERFORM cron.unschedule('selection-pilot-portal-reminder-daily');
  END IF;
END $$;

SELECT cron.schedule(
  'selection-pilot-portal-reminder-daily',
  '11 13 * * *',  -- minuto livre: às 13:00 já rodam três crons diários e um semanal
  $cron$ SELECT public._lembrete_do_portal_do_piloto_cron() $cron$
);
