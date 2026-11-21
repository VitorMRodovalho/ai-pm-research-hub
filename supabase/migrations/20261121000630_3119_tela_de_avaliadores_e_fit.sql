-- #3119 (ADR-0134 §3 e §4): a tela de avaliadores do piloto, o encerramento do vínculo, o histórico e o fit na atribuição.
--
-- 1. CHECK de part em selection_evaluator_calibrations e selection_evaluation_assignments passa a aceitar 'fit'. Só
--    alarga a lista: toda linha existente ('objective' ou 'video') continua válida, e o ADD CONSTRAINT revalida as
--    linhas na hora (tabelas pequenas, travadas só durante a validação).
-- 2. _impedimento_na_linha: no fit a regra é a inversa das outras partes, só passa o líder ativo da iniciativa da vaga.
--    Como _avaliador_do_piloto e assign_selection_evaluators já leem esta regra, fila, formulário, envio e atribuição
--    passam a tratar o fit sem outra mudança.
-- 3. assign_selection_evaluators aceita fit, com 1 avaliador por candidatura e sem prazo (como o vídeo); record_
--    selection_evaluator_calibration aceita fit.
-- 4. As funções de escrita (grant, calibração, assign, withdraw) passam a gravar em admin_audit_log, com a ação
--    selection_evaluator.<granted|extended|calibrated|assigned|assignment_withdrawn>.
-- 5. Novas: end_selection_evaluator (encerra o vínculo hoje, com motivo, e retira as atribuições ativas da pessoa) e
--    get_selection_evaluators_admin (leitura da tela). As duas só para manage_platform.
-- Fora isso, cada função é a captura vigente: _impedimento_na_linha e assign de 20261107020038, as outras de
-- 20261104205503.

ALTER TABLE public.selection_evaluator_calibrations DROP CONSTRAINT selection_evaluator_calibrations_part_check;
ALTER TABLE public.selection_evaluator_calibrations ADD CONSTRAINT selection_evaluator_calibrations_part_check
  CHECK (part IN ('objective', 'video', 'fit'));
ALTER TABLE public.selection_evaluation_assignments DROP CONSTRAINT selection_evaluation_assignments_part_check;
ALTER TABLE public.selection_evaluation_assignments ADD CONSTRAINT selection_evaluation_assignments_part_check
  CHECK (part IN ('objective', 'video', 'fit'));

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
  -- #3119 (ADR-0134 §3): o fit é do líder da linha. Aqui a regra é a inversa das outras partes: só passa quem tem
  -- vínculo de líder ativo na iniciativa da vaga.
  IF p_part = 'fit' THEN
    IF EXISTS (SELECT 1 FROM public.engagements e
                WHERE e.person_id = v_pessoa AND e.initiative_id = v_iniciativa AND e.role = 'leader' AND e.status = 'active') THEN
      RETURN NULL;
    END IF;
    RETURN 'não é o líder ativo da iniciativa da vaga (ADR-0134 §3: o fit é do líder da linha)';
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
  IF p_part NOT IN ('objective', 'video', 'fit') OR p_application_ids IS NULL OR cardinality(p_application_ids) = 0 THEN
    RETURN jsonb_build_object('error', 'Parte (objective, video ou fit) e ao menos uma candidatura são obrigatórias.');
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
    -- #3119 (ADR-0134 §3): o fit tem 1 avaliador, o líder da vaga.
    ELSIF p_part = 'fit' AND (SELECT count(*) FROM public.selection_evaluation_assignments a
            WHERE a.application_id = v_app.id AND a.part = 'fit' AND a.withdrawn_at IS NULL
              AND a.evaluator_member_id <> p_member_id) >= 1 THEN
      v_motivos := v_motivos || (left(v_app.id::text, 8) || ': o fit já tem avaliador');
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
    'Vaga ' || v_vo.opportunity_id || ', parte ' || CASE p_part WHEN 'objective' THEN 'objetiva' WHEN 'video' THEN 'do vídeo' ELSE 'de fit' END
      || CASE WHEN v_prazo IS NOT NULL THEN ', prazo ' || to_char(v_prazo AT TIME ZONE 'America/Sao_Paulo', 'DD/MM') ELSE '' END
      || '. A lista está em Minhas avaliações.',
    '/minhas-avaliacoes', 'vep_opportunity', NULL
  );
  -- #3119: o histórico da tela de avaliadores.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (v_caller, 'selection_evaluator.assigned', 'member', p_member_id,
          jsonb_build_object('opportunity_id', p_opportunity_id, 'part', p_part, 'application_ids', to_jsonb(p_application_ids),
                             'assigned', v_n, 'due_at', v_prazo));
  RETURN jsonb_build_object('success', true, 'assigned', v_n, 'due_at', v_prazo);
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
  IF p_part NOT IN ('objective', 'video', 'fit') OR coalesce(btrim(p_material_version), '') = '' THEN
    RETURN jsonb_build_object('error', 'Parte (objective, video ou fit) e versão do material são obrigatórias.');
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
  -- #3119: o histórico da tela de avaliadores.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (v_caller, 'selection_evaluator.calibrated', 'member', p_member_id,
          jsonb_build_object('opportunity_id', p_opportunity_id, 'part', p_part, 'material_version', btrim(p_material_version), 'notes', p_notes));
  RETURN jsonb_build_object('success', true);
END;
$function$;

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
  -- #3119: o histórico da tela de avaliadores. Sem vínculo antes é concessão; com vínculo, extensão da data de fim.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (v_caller, CASE WHEN v_fim_antes IS NULL THEN 'selection_evaluator.granted' ELSE 'selection_evaluator.extended' END,
          'member', p_member_id,
          jsonb_build_object('engagement_id', v_eng, 'end_date', p_end_date, 'end_date_before', v_fim_antes, 'note', p_note));
  RETURN jsonb_build_object('success', true, 'engagement_id', v_eng, 'end_date', p_end_date);
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
  v_a record;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active;
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF coalesce(btrim(p_reason), '') = '' THEN
    RETURN jsonb_build_object('error', 'O motivo é obrigatório.');
  END IF;
  UPDATE public.selection_evaluation_assignments SET withdrawn_at = now(), withdrawn_reason = btrim(p_reason)
   WHERE id = p_assignment_id AND withdrawn_at IS NULL
  RETURNING evaluator_member_id, application_id, part INTO v_a;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Atribuição inexistente ou já retirada.'); END IF;
  -- #3119: o histórico da tela de avaliadores.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (v_caller, 'selection_evaluator.assignment_withdrawn', 'selection_evaluation_assignment', p_assignment_id,
          jsonb_build_object('member_id', v_a.evaluator_member_id, 'application_id', v_a.application_id, 'part', v_a.part,
                             'reason', btrim(p_reason)));
  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.end_selection_evaluator(p_member_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller uuid;
  v_caller_person uuid;
  v_person uuid;
  v_eng uuid;
  v_retiradas int := 0;
BEGIN
  SELECT m.id, m.person_id INTO v_caller, v_caller_person FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active;
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF coalesce(btrim(p_reason), '') = '' THEN
    RETURN jsonb_build_object('error', 'O motivo é obrigatório.');
  END IF;
  SELECT m.person_id INTO v_person FROM public.members m WHERE m.id = p_member_id;
  SELECT e.id INTO v_eng FROM public.engagements e
   WHERE e.person_id = v_person AND e.kind = 'selection_evaluator' AND e.status = 'active'
   ORDER BY e.start_date DESC LIMIT 1;
  IF v_person IS NULL OR v_eng IS NULL THEN
    RETURN jsonb_build_object('error', 'A pessoa não tem vínculo de avaliador ativo.');
  END IF;

  -- Encerra hoje: status offboarded tira a autoridade na hora (auth_engagements só conta status active).
  UPDATE public.engagements
     SET status = 'offboarded', end_date = CURRENT_DATE, revoked_at = now(), revoked_by = v_caller_person,
         revoke_reason = btrim(p_reason), updated_at = now()
   WHERE id = v_eng;

  -- As atribuições ativas param junto, com o motivo, para a tela não mostrar trabalho que ninguém pode fazer.
  UPDATE public.selection_evaluation_assignments
     SET withdrawn_at = now(), withdrawn_reason = 'vínculo de avaliador encerrado: ' || btrim(p_reason)
   WHERE evaluator_member_id = p_member_id AND withdrawn_at IS NULL;
  GET DIAGNOSTICS v_retiradas = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (v_caller, 'selection_evaluator.ended', 'member', p_member_id,
          jsonb_build_object('engagement_id', v_eng, 'reason', btrim(p_reason), 'assignments_withdrawn', v_retiradas));
  RETURN jsonb_build_object('success', true, 'engagement_id', v_eng, 'assignments_withdrawn', v_retiradas);
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
    -- O histórico: as escritas das funções de avaliador, da mais nova para a mais antiga.
    'history', COALESCE((
      SELECT jsonb_agg(h ORDER BY h.created_at DESC) FROM (
        SELECT l.created_at, l.action, l.target_type, l.target_id, l.metadata, act.name AS actor_name, tgt.name AS target_name
          FROM public.admin_audit_log l
          LEFT JOIN public.members act ON act.id = l.actor_id
          LEFT JOIN public.members tgt ON l.target_type = 'member' AND tgt.id::text = l.target_id::text
         WHERE l.action LIKE 'selection\_evaluator.%'
         ORDER BY l.created_at DESC
         LIMIT 300) h), '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public._impedimento_na_linha(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.end_selection_evaluator(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_selection_evaluators_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_selection_evaluator(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_selection_evaluators_admin() TO authenticated;
COMMENT ON FUNCTION public.end_selection_evaluator(uuid, text) IS
  '#3119 (ADR-0134 §4): a gestão encerra o vínculo de avaliador hoje, com motivo; as atribuições ativas da pessoa são retiradas e tudo vai ao admin_audit_log.';
COMMENT ON FUNCTION public.get_selection_evaluators_admin() IS
  '#3119: leitura da aba Avaliadores de /admin/selection (vínculos, calibragens, atribuições com estado e histórico). Só manage_platform.';
