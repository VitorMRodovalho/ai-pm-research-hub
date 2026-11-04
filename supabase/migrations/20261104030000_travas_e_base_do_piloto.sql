-- #2393 M1 (ADR-0134): travas e base do piloto da linha (fatias A1 a A4).
--
-- Partes 1 a 4, A1: travas do piloto (abaixo).
-- Partes 5 e 6, A2: a vaga no payload do portal e a data prometida do convite do vídeo.
-- Partes 7 e 8, A3: o link do portal do piloto vale o processo inteiro, e os e-mails de candidatura recebida.
-- Parte 9, A4: o líder da vaga não recebe o e-mail da candidatura piloto.
--
-- A1 (ADR-0134): travas do piloto da linha.
--
-- A candidatura de vaga line_pilot não entra no fluxo geral por nenhum caminho:
--   1. um trigger suprime e registra a mudança de status para aprovação, conversão, corte, entrevista ou lista
--      de espera (padrão da #1613, sem exceção, por causa dos escritores em laço);
--   2. admin_update_application recusa, com mensagem, toda mudança de status que não seja desistência ou
--      cancelamento, antes do UPDATE e antes da aprovação canônica;
--   3. schedule_interview e _issue_interview_booking_token_core recusam, com mensagem e registro em
--      gate_attempts (P0030, LINE_PILOT_NOT_GENERAL_FLOW), antes de criar entrevista, token ou aviso.
-- A candidatura da avaliação geral não muda em nada: toda trava começa por _na_avaliacao_geral ou pela trilha.

-- ── 1. Trava de status da candidatura de vaga piloto da linha ──
-- Padrão da #1613: BEFORE UPDATE que SUPRIME a transição (NEW.status := OLD.status) e registra, sem levantar
-- exceção, porque há escritores em laço (crons) e uma exceção abortaria a rodada inteira. Fora da lista
-- permitida, o status da candidatura piloto não muda por nenhum caminho: RPC, MCP, cron ou trigger de entrevista.
-- A lista permitida: o que não depende de nota (desistência, cancelamento, recusa vinda do VEP) e as fases antes
-- da avaliação. Aprovação, conversão, corte, entrevista e lista de espera ficam para a decisão do piloto.
CREATE OR REPLACE FUNCTION public._trg_piloto_trava_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_tentado text;
  v_actor uuid;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status IN ('submitted', 'screening', 'objective_eval', 'rejected', 'withdrawn', 'cancelled')
     OR NOT EXISTS (
       SELECT 1 FROM public.vep_opportunities vo
       WHERE vo.opportunity_id = NEW.vep_opportunity_id
         AND vo.evaluation_track = 'line_pilot'
     ) THEN
    RETURN NEW;
  END IF;

  v_tentado := NEW.status;
  NEW.status := OLD.status;

  BEGIN
    SELECT m.id INTO v_actor FROM public.members m WHERE m.auth_id = auth.uid();
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_actor,
      'selection.pilot_status_blocked',
      'selection_application',
      NEW.id,
      jsonb_build_object('status', jsonb_build_object('attempted', v_tentado, 'kept', OLD.status)),
      jsonb_build_object('issue', 2393, 'reason', 'line_pilot', 'has_auth_uid', (auth.uid() IS NOT NULL),
                         'source', '_trg_piloto_trava_status')
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '_trg_piloto_trava_status: registro falhou: %', SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._trg_piloto_trava_status() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._trg_piloto_trava_status() IS
  '#2393 A1 (ADR-0134): suprime e registra (selection.pilot_status_blocked) a mudança de status da candidatura de vaga line_pilot para fora da lista permitida. Padrão da #1613: não levanta exceção.';

DROP TRIGGER IF EXISTS trg_zy_piloto_trava_status ON public.selection_applications;
CREATE TRIGGER trg_zy_piloto_trava_status
  BEFORE UPDATE OF status ON public.selection_applications
  FOR EACH ROW EXECUTE FUNCTION public._trg_piloto_trava_status();

-- ── 2. admin_update_application ──
CREATE OR REPLACE FUNCTION public.admin_update_application(p_application_id uuid, p_data jsonb)
 RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_app              record;
  v_old_status       text;
  v_new_status       text;
  v_requested_status text;
  v_gate_suppressed  boolean := false;
  v_canonical_result jsonb := NULL;
  v_member_id        uuid := NULL;
  v_seeded_count     int := 0;
  v_promoted         boolean := false;
  v_target_role      text;
  v_objective_evaluators int := NULL;
  v_min_evaluators       int := NULL;
  v_early_reason     text := NULL;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  v_old_status       := v_app.status;
  v_requested_status := coalesce(p_data->>'status', v_old_status);
  v_new_status       := v_requested_status;

  -- #2393 A1: na candidatura de vaga piloto da linha, o status só muda pela avaliação do piloto. Daqui só saem
  -- desistência e cancelamento, que não dependem de nota. O resto do p_data (feedback, tags) segue valendo.
  IF NOT public._na_avaliacao_geral(p_application_id)
     AND v_requested_status IS DISTINCT FROM v_old_status
     AND v_requested_status NOT IN ('withdrawn', 'cancelled') THEN
    RETURN json_build_object(
      'error', 'Candidatura do piloto da linha: a decisão sai da avaliação do piloto (objetiva, vídeo da linha e conversa de fit), não do fluxo geral. Aqui só valem desistência e cancelamento.',
      'code',  'line_pilot_status_locked'
    );
  END IF;

  -- #2392 — aprovar abaixo do mínimo de avaliadores objetivos do ciclo (somando a candidatura ligada)
  -- continua permitido, como Aceite Antecipado, mas exige justificativa. Antes a régua era "zero
  -- avaliações de qualquer tipo", e uma candidatura com UMA objetiva passava calada. Mínimo vazio
  -- conta como não atingido: a trava não abre por falta de dado.
  -- #1572 — a recusa acontece ANTES do UPDATE: uma aprovação sem lastro que gravasse status e só
  -- depois falhasse deixaria a candidatura aprovada sem o carimbo que a explica.
  IF v_requested_status = 'approved' AND v_old_status <> 'approved' THEN
    v_objective_evaluators := public._selection_objective_evaluators(p_application_id);

    SELECT c.min_evaluators INTO v_min_evaluators
    FROM public.selection_cycles c
    WHERE c.id = v_app.cycle_id;

    IF v_min_evaluators IS NULL OR v_objective_evaluators < v_min_evaluators THEN
      v_early_reason := btrim(coalesce(p_data->>'early_acceptance_reason', ''));
      IF length(v_early_reason) < 20 THEN
        RETURN json_build_object(
          'error',   format('Aprovação com %s avaliador(es) objetivo(s), abaixo do mínimo do ciclo (%s), exige justificativa de pelo menos 20 caracteres em early_acceptance_reason (Aceite Antecipado). A contagem soma a candidatura ligada.',
                            v_objective_evaluators, coalesce(v_min_evaluators::text, 'não definido')),
          'code',    'early_acceptance_reason_required',
          'objective_evaluators', v_objective_evaluators,
          'min_evaluators',       v_min_evaluators
        );
      END IF;
    END IF;
  END IF;

  UPDATE public.selection_applications SET
    status            = v_requested_status,
    feedback          = coalesce(p_data->>'feedback', feedback),
    tags              = CASE WHEN p_data ? 'tags'              THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'tags')) ELSE tags END,
    role_applied      = coalesce(p_data->>'role_applied', role_applied),
    converted_from    = CASE WHEN p_data ? 'converted_from'    THEN p_data->>'converted_from'    ELSE converted_from END,
    converted_to      = CASE WHEN p_data ? 'converted_to'      THEN p_data->>'converted_to'      ELSE converted_to END,
    conversion_reason = CASE WHEN p_data ? 'conversion_reason' THEN p_data->>'conversion_reason' ELSE conversion_reason END,
    updated_at        = now()
  WHERE id = p_application_id
  RETURNING status INTO v_new_status;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Application not found');
  END IF;

  -- #1613 — o gate de entrada pode suprimir `* → interview_scheduled` quando não há nota
  -- objetiva e não há override do R1.4. Devolver o status PEDIDO como se tivesse sido
  -- gravado era a forma exata de recusa-lida-como-sucesso. Este RPC é o caminho de exceção
  -- de FATO do GP, mas a exceção passa a exigir `grant_interview_stage_override` — com
  -- motivo — em vez de acontecer por acidente aqui.
  v_gate_suppressed := (v_new_status IS DISTINCT FROM v_requested_status);

  IF v_new_status = 'approved' AND v_old_status <> 'approved' THEN
    -- #1572 — o carimbo entra DEPOIS do UPDATE, e só quando o `approved` realmente pegou: se o gate
    -- do #1613 suprimir o status, não houve aceite antecipado para registrar.
    IF v_early_reason IS NOT NULL THEN
      UPDATE public.selection_applications SET
        early_acceptance_at     = now(),
        early_acceptance_by     = v_caller_id,
        early_acceptance_reason = v_early_reason
      WHERE id = p_application_id;
    END IF;

    -- #1175 D2: partner-chapter tag semantics centralized (no_partner_chapter /
    -- partner_chapter_at_risk) — see apply_partner_chapter_tags.
    PERFORM public.apply_partner_chapter_tags(p_application_id);

    v_canonical_result := public.approve_selection_application(p_application_id, p_data);

    -- Council fix: RAISE so the entire transaction rolls back if canonical fails
    -- (otherwise the UPDATE status='approved' above commits without member/person/
    -- engagement, creating an invariant-R violation).
    IF (v_canonical_result->>'success') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Canonical approval failed: %', coalesce(v_canonical_result->>'error', 'unknown')
        USING ERRCODE = 'P0001',
              DETAIL = v_canonical_result::text;
    END IF;

    v_member_id      := (v_canonical_result->>'member_id')::uuid;
    v_seeded_count   := coalesce((v_canonical_result->>'onboarding_seeded')::int, 0);
    v_promoted       := coalesce((v_canonical_result->>'role_promoted')::boolean, false);
    v_target_role    := v_canonical_result->>'promoted_to';
  END IF;

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_status_change',
    'info',
    'Application ' || v_app.applicant_name || ': ' || v_old_status || ' → ' || v_new_status
      || CASE WHEN v_gate_suppressed THEN ' (pedido: ' || v_requested_status || ' — suprimido pelo gate #1613)' ELSE '' END,
    jsonb_build_object(
      'application_id',    p_application_id,
      'old_status',        v_old_status,
      'new_status',        v_new_status,
      'requested_status',  v_requested_status,
      'gate_suppressed',   v_gate_suppressed,
      'actor',             v_caller_name,
      'actor_id',          v_caller_id,
      'member_id',         v_member_id,
      'onboarding_seeded', v_seeded_count,
      'role_promoted',     v_promoted,
      'promoted_to',       CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
      'canonical_invoked', v_canonical_result IS NOT NULL,
      'objective_evaluators',  v_objective_evaluators,
      'min_evaluators',        v_min_evaluators,
      'early_acceptance',      v_early_reason IS NOT NULL
    )
  );

  RETURN json_build_object(
    'success',           true,
    'old_status',        v_old_status,
    'new_status',        v_new_status,
    'requested_status',  v_requested_status,
    'gate_suppressed',   v_gate_suppressed,
    'onboarding_seeded', v_seeded_count,
    'role_promoted',     v_promoted,
    'promoted_to',       CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
    'objective_evaluators',  v_objective_evaluators,
    'min_evaluators',        v_min_evaluators,
    'early_acceptance',      v_early_reason IS NOT NULL,
    'canonical',         v_canonical_result
  );
END;
$function$;

-- ── 3. schedule_interview ──
CREATE OR REPLACE FUNCTION public.schedule_interview(p_application_id uuid,
  p_interviewer_ids uuid[],
  p_scheduled_at timestamp with time zone,
  p_duration_minutes integer DEFAULT 30,
  p_calendar_event_id text DEFAULT NULL::text,
  p_bypass_gate boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_interview_id uuid;
  v_interviewer_id uuid;
  v_eval_count int;
  v_can_bypass boolean;
  v_gate_payload jsonb;
  v_stamp_override boolean;
  -- #2012
  v_is_platform_admin boolean;
  v_self_only boolean;
  v_conducts_own boolean;
  v_authority_path text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  v_is_platform_admin := public.can_by_member(v_caller.id, 'manage_platform'::text);

  -- #2012 — o caminho novo: registrar a entrevista que o proprio chamador conduziu.
  -- Lista de UM, e esse um e ele. Comite DO CICLO, com `can_interview` e papel que decide
  -- (o dominio e evaluator | lead | observer; observador e leitura).
  v_self_only := cardinality(coalesce(p_interviewer_ids, ARRAY[]::uuid[])) = 1
                 AND p_interviewer_ids[1] = v_caller.id;

  v_conducts_own := v_self_only AND EXISTS (
    SELECT 1 FROM public.selection_committee sc
    WHERE sc.member_id = v_caller.id
      AND sc.cycle_id = v_app.cycle_id
      AND sc.can_interview
      AND sc.role <> 'observer'
  );

  -- Precedencia: lead > manage_platform > self. Quem ja passava passa pelo MESMO caminho de
  -- antes, e so o caminho novo perde o bypass.
  v_authority_path := CASE
    WHEN v_committee IS NOT NULL THEN 'committee_lead'
    WHEN v_is_platform_admin     THEN 'manage_platform'
    WHEN v_conducts_own          THEN 'self_interviewer'
    ELSE NULL
  END;

  v_can_bypass := p_bypass_gate
                  AND public.can_by_member(v_caller.id, 'manage_member'::text)
                  AND v_authority_path IS DISTINCT FROM 'self_interviewer';

  SELECT COUNT(*) INTO v_eval_count FROM public.selection_evaluations WHERE application_id = p_application_id;
  v_gate_payload := jsonb_build_object(
    'has_consent', (v_app.consent_ai_analysis_at IS NOT NULL),
    'has_ai_analysis', (v_app.ai_analysis IS NOT NULL),
    'eval_count', v_eval_count,
    'objective_score_avg', v_app.objective_score_avg,
    'app_status', v_app.status,
    'gate_mode', CASE WHEN v_can_bypass THEN 'bypass' ELSE 'full' END,
    'authority_path', v_authority_path,
    'self_only_interviewer', v_self_only
  );

  -- #2012 — a recusa por AUTORIDADE passa a registrar. Antes era `RAISE EXCEPTION` antes do
  -- primeiro log, e a tentativa barrada nao existia para quem investigasse.
  IF v_authority_path IS NULL THEN
    PERFORM public._log_gate_attempt(
      p_application_id, 'schedule_interview', v_caller.id, false,
      'P0005', 'UNAUTHORIZED_NOT_INTERVIEW_AUTHORITY', p_bypass_gate, v_can_bypass,
      v_gate_payload, v_app.organization_id
    );
    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'gate_failed_code', 'P0005',
      'gate_failed_reason', 'UNAUTHORIZED_NOT_INTERVIEW_AUTHORITY',
      'message', 'Unauthorized: agendar em nome de terceiro exige lead do comite ou manage_platform; registrar a entrevista que voce conduziu exige estar no comite do ciclo com can_interview (papel evaluator ou lead) e informar apenas a si proprio como entrevistador.'
    );
  END IF;

  -- #2393 A1: candidatura de vaga piloto da linha não tem entrevista do fluxo geral, nem com bypass.
  IF NOT public._na_avaliacao_geral(p_application_id) THEN
    PERFORM public._log_gate_attempt(
      p_application_id, 'schedule_interview', v_caller.id, false,
      'P0030', 'LINE_PILOT_NOT_GENERAL_FLOW', p_bypass_gate, v_can_bypass,
      v_gate_payload, v_app.organization_id
    );
    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'gate_failed_code', 'P0030',
      'gate_failed_reason', 'LINE_PILOT_NOT_GENERAL_FLOW',
      'message', 'Candidatura do piloto da linha: não há entrevista do fluxo geral. A conversa de fit com o líder da linha abre depois do vídeo da linha.'
    );
  END IF;

  -- Workflow gate
  IF NOT v_can_bypass THEN
    -- #1640: o gate de análise por IA saiu daqui também. Ele nunca recusou ninguém em produção
    -- porque o comitê o contornava com `p_bypass_gate` — que desliga junto os dois gates abaixo.
    IF v_eval_count < 2 THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'schedule_interview', v_caller.id, false,
        'P0002', 'GATE_NO_PEER_REVIEW', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RETURN jsonb_build_object(
        'success', false,
        'application_id', p_application_id,
        'gate_failed_code', 'P0002',
        'gate_failed_reason', 'GATE_NO_PEER_REVIEW',
        'message', format('GATE_NO_PEER_REVIEW: candidate has %s peer evaluations (minimum 2 required).', v_eval_count)
      );
    END IF;

    IF v_app.objective_score_avg IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'schedule_interview', v_caller.id, false,
        'P0003', 'GATE_NO_SCORE', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RETURN jsonb_build_object(
        'success', false,
        'application_id', p_application_id,
        'gate_failed_code', 'P0003',
        'gate_failed_reason', 'GATE_NO_SCORE',
        'message', 'GATE_NO_SCORE: objective_score_avg not computed.'
      );
    END IF;
  END IF;

  -- #472 corr.3 — P0004 status gate. O bypass do admin (v_can_bypass = p_bypass_gate AND
  -- manage_member) vale APENAS a partir de um status pré-entrevista que genuinamente ainda não tem
  -- entrevista — ALLOW-LIST, não block-list, para que um status de fase posterior
  -- (interview_done / final_eval) ou terminal NUNCA seja regredido a interview_scheduled pelo
  -- UPDATE incondicional abaixo.
  IF NOT (
       v_app.status IN ('interview_pending', 'interview_scheduled')
       OR ( v_can_bypass AND v_app.status IN ('screening', 'submitted', 'objective_eval', 'objective_cutoff') )
     ) THEN
    PERFORM public._log_gate_attempt(
      p_application_id, 'schedule_interview', v_caller.id, false,
      'P0004', 'INVALID_APP_STATUS:' || v_app.status, p_bypass_gate, v_can_bypass,
      v_gate_payload, v_app.organization_id
    );
    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'gate_failed_code', 'P0004',
      'gate_failed_reason', 'INVALID_APP_STATUS:' || v_app.status,
      'message', format('Application status %s does not allow scheduling interview', v_app.status)
    );
  END IF;

  -- All gates passed → create interview
  INSERT INTO public.selection_interviews (
    application_id, interviewer_ids, scheduled_at,
    duration_minutes, status, calendar_event_id
  ) VALUES (
    p_application_id, p_interviewer_ids, p_scheduled_at,
    p_duration_minutes, 'scheduled', p_calendar_event_id
  )
  RETURNING id INTO v_interview_id;

  -- #1613 R1.4 — quando o admin usa o bypass numa candidatura SEM nota objetiva, esse ato É
  -- a exceção declarada: carimba o override no MESMO UPDATE que promove o status, para que
  -- trg_zz_gate_interview_stage_entry (que lê NEW) deixe passar. Sem isto, um caminho vivo
  -- (26 usos, 3 sem nota) passaria a suprimir a promoção em silêncio.
  v_stamp_override := v_can_bypass AND v_app.objective_score_avg IS NULL;

  UPDATE public.selection_applications
  SET status = 'interview_scheduled',
      updated_at = now(),
      interview_stage_override_at =
        CASE WHEN v_stamp_override THEN now() ELSE interview_stage_override_at END,
      interview_stage_override_by =
        CASE WHEN v_stamp_override THEN v_caller.id ELSE interview_stage_override_by END,
      interview_stage_override_reason =
        CASE WHEN v_stamp_override
             THEN 'schedule_interview: p_bypass_gate=true (manage_member) — excecao do R1.4 pelo caminho de emergencia do admin'
             ELSE interview_stage_override_reason END
  WHERE id = p_application_id;

  FOREACH v_interviewer_id IN ARRAY p_interviewer_ids
  LOOP
    PERFORM public.create_notification(
      v_interviewer_id,
      'selection_interview_scheduled',
      'Entrevista agendada: ' || v_app.applicant_name,
      'Entrevista com ' || v_app.applicant_name
        || COALESCE(' (' || NULLIF(btrim(v_app.chapter), '') || ')', '')
        || ' agendada para ' || to_char(p_scheduled_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
        || ' (horário de Brasília)',
      '/admin/selection',
      'selection_interview',
      v_interview_id
    );
  END LOOP;

  PERFORM public.create_notification(
    m.id,
    'selection_interview_scheduled',
    'Sua entrevista foi agendada',
    'Entrevista agendada para ' || to_char(p_scheduled_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
      || ' (horário de Brasília). Prepare-se!',
    NULL,
    'selection_interview',
    v_interview_id
  )
  FROM public.members m
  WHERE m.email = v_app.email;

  PERFORM public._log_gate_attempt(
    p_application_id, 'schedule_interview', v_caller.id, true,
    NULL, NULL, p_bypass_gate, v_can_bypass,
    v_gate_payload || jsonb_build_object('stage_override_stamped', v_stamp_override),
    v_app.organization_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'interview_id', v_interview_id,
    'scheduled_at', p_scheduled_at,
    'application_status', 'interview_scheduled',
    'gate_bypassed', v_can_bypass,
    'stage_override_stamped', v_stamp_override,
    'authority_path', v_authority_path
  );
END;
$function$;

-- ── 4. _issue_interview_booking_token_core ──
CREATE OR REPLACE FUNCTION public._issue_interview_booking_token_core(p_application_id uuid, p_bypass_granted boolean DEFAULT false, p_caller_id uuid DEFAULT NULL::uuid, p_bypass_requested boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
  v_eval_count int;
  v_token text;
  v_expires_at timestamptz;
  -- A4 (#1584): link para candidato usa o alias institucional, não o domínio pessoal.
  v_booking_url_base text := 'https://nucleoia.pmigo.org.br/interview-booking/';
  v_gate_payload jsonb;
  v_has_interview boolean;
  v_has_dispatch boolean;
  v_has_prior_token boolean;
  v_prior_evidence text;
  v_gate_mode text;
BEGIN
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- #2393 A1: candidatura de vaga piloto da linha não recebe link de entrevista do fluxo geral, nem com bypass.
  IF NOT public._na_avaliacao_geral(p_application_id) THEN
    PERFORM public._log_gate_attempt(
      p_application_id, '_issue_interview_booking_token_core', p_caller_id, false,
      'P0030', 'LINE_PILOT_NOT_GENERAL_FLOW', p_bypass_requested, p_bypass_granted,
      jsonb_build_object('app_status', v_app.status, 'evaluation_track', 'line_pilot'), v_app.organization_id
    );
    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'gate_failed_code', 'P0030',
      'gate_failed_reason', 'LINE_PILOT_NOT_GENERAL_FLOW',
      'message', 'Candidatura do piloto da linha: não há entrevista do fluxo geral. A conversa de fit com o líder da linha abre depois do vídeo da linha.'
    );
  END IF;

  SELECT COUNT(*) INTO v_eval_count
  FROM public.selection_evaluations WHERE application_id = p_application_id;

  -- #1595 — gatilho do modo de reuso e o nível da prova anterior.
  SELECT EXISTS (SELECT 1 FROM public.selection_interviews WHERE application_id = p_application_id)
    INTO v_has_interview;
  SELECT EXISTS (SELECT 1 FROM public.selection_dispatch_url_log WHERE application_id = p_application_id)
    INTO v_has_dispatch;
  SELECT EXISTS (
    SELECT 1 FROM public.onboarding_tokens
    WHERE source_id = p_application_id AND 'interview_booking' = ANY(scopes)
  ) INTO v_has_prior_token;

  v_prior_evidence := CASE
    WHEN v_has_dispatch     THEN 'dispatch_log'
    WHEN v_has_prior_token  THEN 'prior_token'
    WHEN v_has_interview    THEN 'interview_row_only'
    ELSE NULL
  END;

  v_gate_mode := CASE
    WHEN p_bypass_granted THEN 'bypass'
    WHEN v_has_interview  THEN 'reuse_prior'
    ELSE 'full'
  END;

  v_gate_payload := jsonb_build_object(
    'has_consent', (v_app.consent_ai_analysis_at IS NOT NULL),
    'has_ai_analysis', (v_app.ai_analysis IS NOT NULL),
    'eval_count', v_eval_count,
    'objective_score_avg', v_app.objective_score_avg,
    'app_status', v_app.status,
    'gate_mode', v_gate_mode,
    'prior_evidence', v_prior_evidence
  );

  IF v_gate_mode = 'reuse_prior' THEN
    -- O motivo próprio que a decisão do PM exige. Fica no payload (e não em `gate_failed_reason`,
    -- que é coluna de RECUSA) para não fabricar uma falha onde houve reuso deliberado.
    v_gate_payload := v_gate_payload || jsonb_build_object('gate_reuse_reason', 'GATE_REUSED_PRIOR');
  END IF;

  IF v_gate_mode = 'full' THEN
    -- #1640: aqui havia o primeiro gate, que recusava por ausência de análise por IA. Ele saiu.
    -- Os dois que sobraram são requisitos de conclusão do processo OBJETIVO — o candidato não os
    -- controla por consentimento, e nenhum deles pertence a uma finalidade secundária.
    IF v_eval_count < 2 THEN
      PERFORM public._log_gate_attempt(
        p_application_id, '_issue_interview_booking_token_core', p_caller_id, false,
        'P0002', 'GATE_NO_PEER_REVIEW', p_bypass_requested, p_bypass_granted,
        v_gate_payload, v_app.organization_id
      );
      -- #1594: RETURN, não RAISE. Um RAISE aqui desfaria o INSERT de auditoria acima.
      RETURN jsonb_build_object(
        'success', false,
        'application_id', p_application_id,
        'gate_mode', v_gate_mode,
        'gate_failed_code', 'P0002',
        'gate_failed_reason', 'GATE_NO_PEER_REVIEW',
        'message', format('GATE_NO_PEER_REVIEW: candidate has %s peer evaluations.', v_eval_count)
      );
    END IF;

    IF v_app.objective_score_avg IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, '_issue_interview_booking_token_core', p_caller_id, false,
        'P0003', 'GATE_NO_SCORE', p_bypass_requested, p_bypass_granted,
        v_gate_payload, v_app.organization_id
      );
      RETURN jsonb_build_object(
        'success', false,
        'application_id', p_application_id,
        'gate_mode', v_gate_mode,
        'gate_failed_code', 'P0003',
        'gate_failed_reason', 'GATE_NO_SCORE',
        'message', 'GATE_NO_SCORE: objective_score_avg not computed.'
      );
    END IF;
  END IF;

  -- #1584 achado 2: `gen_random_bytes` sob `search_path=public` levanta 42883 — pgcrypto vive em
  -- `extensions`. A qualificação é obrigatória e é afirmada por teste contra o corpo VIVO.
  v_token := encode(extensions.gen_random_bytes(32), 'base64');
  v_token := translate(v_token, '+/=', '-_');
  v_expires_at := now() + interval '14 days';

  INSERT INTO public.onboarding_tokens (
    token, source_type, source_id, scopes,
    issued_at, expires_at, issued_by, organization_id
  ) VALUES (
    v_token, 'pmi_application', p_application_id,
    ARRAY['interview_booking']::text[],
    now(), v_expires_at, p_caller_id, v_app.organization_id
  );

  PERFORM public._log_gate_attempt(
    p_application_id, '_issue_interview_booking_token_core', p_caller_id, true,
    NULL, NULL, p_bypass_requested, p_bypass_granted,
    v_gate_payload || jsonb_build_object('token_prefix', left(v_token, 8)),
    v_app.organization_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'token', v_token,
    'booking_url', v_booking_url_base || v_token,
    'expires_at', v_expires_at::text,
    'gate_bypassed', p_bypass_granted,
    'gate_mode', v_gate_mode,
    'prior_evidence', v_prior_evidence
  );
END;
$function$;

-- ── 5. A2: data prometida do convite do vídeo, como configuração da vaga ──
ALTER TABLE public.vep_opportunities ADD COLUMN IF NOT EXISTS video_invite_by date;
COMMENT ON COLUMN public.vep_opportunities.video_invite_by IS
  '#2393 (ADR-0134, N1 do GP em 03/11/2026): data até a qual a vaga piloto da linha promete o convite do vídeo. Lida pelo portal e pelo e-mail de candidatura recebida. NULL fora do piloto.';
UPDATE public.vep_opportunities SET video_invite_by = DATE '2026-11-20'
 WHERE opportunity_id = '76080' AND evaluation_track = 'line_pilot' AND video_invite_by IS NULL;

-- ── 6. A2: consume_onboarding_token devolve a vaga ──
CREATE OR REPLACE FUNCTION public.consume_onboarding_token(p_token text)
 RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_app selection_applications%ROWTYPE;
  v_cycle selection_cycles%ROWTYPE;
  v_progress jsonb;
  v_video_screenings jsonb;
  v_step_catalog jsonb;
  v_member_id uuid;
  v_member_auth_id uuid;
  v_primary_email text;
  v_result jsonb;
BEGIN
  UPDATE onboarding_tokens
     SET consumed_at = COALESCE(consumed_at, now()),
         last_accessed_at = now(),
         access_count = access_count + 1
   WHERE token = p_token
     AND expires_at > now()
  RETURNING * INTO v_token_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired token'
      USING ERRCODE = 'invalid_authorization_specification';
  END IF;

  IF v_token_row.source_type = 'pmi_application' THEN
    SELECT * INTO v_app
    FROM selection_applications
    WHERE id = v_token_row.source_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Token references missing application';
    END IF;

    SELECT * INTO v_cycle
    FROM selection_cycles
    WHERE id = v_app.cycle_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'step_key', op.step_key,
      'status', op.status,
      'completed_at', op.completed_at,
      'evidence_url', op.evidence_url,
      'notes', op.notes,
      'sla_deadline', op.sla_deadline
    ) ORDER BY op.created_at), '[]'::jsonb)
    INTO v_progress
    FROM onboarding_progress op
    WHERE op.application_id = v_app.id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'pillar', vs.pillar,
      'question_index', vs.question_index,
      'status', vs.status,
      'uploaded_at', vs.uploaded_at
    ) ORDER BY vs.question_index, vs.created_at), '[]'::jsonb)
    INTO v_video_screenings
    FROM pmi_video_screenings vs
    WHERE vs.application_id = v_app.id;

    -- #2273 defeito A — o CATALOGO, que e onde os rotulos sempre estiveram.
    -- Vai inteiro, sem filtrar por papel: quem decide quais passos a pessoa tem e
    -- `onboarding_progress`, ja semeado. Filtrar aqui duplicaria a regra de elegibilidade em
    -- dois lugares, e a copia e que envelhece.
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'key', os.id,
      'step_order', os.step_order,
      'icon', os.icon,
      'is_required', os.is_required,
      'applies_to_role', os.applies_to_role,
      'label', jsonb_build_object(
        'pt-BR', os.label_pt, 'en-US', os.label_en, 'es-LATAM', os.label_es
      ),
      'description', jsonb_build_object(
        'pt-BR', os.description_pt, 'en-US', os.description_en, 'es-LATAM', os.description_es
      )
    ) ORDER BY os.step_order), '[]'::jsonb)
    INTO v_step_catalog
    FROM onboarding_steps os;

    -- #2273 defeito B — o estado de conta, para o portal poder dizer COM QUAL e-mail entrar.
    v_member_id := public._portal_member_for_application(v_app.id);
    IF v_member_id IS NOT NULL THEN
      SELECT m.auth_id,
             COALESCE(
               (SELECT me.email::text FROM public.member_emails me
                 WHERE me.member_id = m.id AND me.is_primary IS TRUE LIMIT 1),
               m.email
             )
        INTO v_member_auth_id, v_primary_email
      FROM public.members m WHERE m.id = v_member_id;
    END IF;

    v_result := jsonb_build_object(
      'source_type', 'pmi_application',
      'scopes', v_token_row.scopes,
      'application', jsonb_build_object(
        'id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'phone', v_app.phone,
        'linkedin_url', v_app.linkedin_url,
        'credly_url', v_app.credly_url,
        'role_applied', v_app.role_applied,
        'cycle_id', v_app.cycle_id,
        'has_consent', v_app.consent_ai_analysis_at IS NOT NULL
                       AND v_app.consent_ai_analysis_revoked_at IS NULL,
        'has_revoked', v_app.consent_ai_analysis_revoked_at IS NOT NULL,
        'has_voice_biometric_consent', v_app.consent_voice_biometric_at IS NOT NULL
                       AND v_app.consent_voice_biometric_revoked_at IS NULL,
        'has_voice_biometric_revoked', v_app.consent_voice_biometric_revoked_at IS NOT NULL,
        'status', v_app.status
      ),
      'cycle', jsonb_build_object(
        'id', v_cycle.id,
        'cycle_code', v_cycle.cycle_code,
        'title', v_cycle.title,
        'phase', v_cycle.phase,
        'onboarding_steps', v_cycle.onboarding_steps
      ),
      'step_catalog', v_step_catalog,
      -- #2393 A2: a vaga da candidatura, para o portal mostrar o período e os passos da trilha no lugar do ciclo.
      'opening', (SELECT jsonb_build_object(
                    'opportunity_id', vo.opportunity_id, 'title', vo.title,
                    'start_date', vo.start_date, 'end_date', vo.end_date,
                    'evaluation_track', vo.evaluation_track, 'video_invite_by', vo.video_invite_by)
                  FROM public.vep_opportunities vo WHERE vo.opportunity_id = v_app.vep_opportunity_id),
      'account_state', jsonb_build_object(
        'member_exists',     v_member_id IS NOT NULL,
        'has_account',       v_member_auth_id IS NOT NULL,
        'masked_email',      public._mask_email(v_primary_email),
        'can_request_setup', v_member_id IS NOT NULL
                             AND v_member_auth_id IS NULL
                             AND v_app.status = 'approved'
      ),
      'onboarding_progress', v_progress,
      'video_screenings', v_video_screenings,
      'token_metadata', jsonb_build_object(
        'access_count', v_token_row.access_count,
        'expires_at', v_token_row.expires_at,
        'first_access', v_token_row.consumed_at = v_token_row.last_accessed_at
      )
    );

  ELSIF v_token_row.source_type IN ('initiative_invitation', 'direct_assignment') THEN
    v_result := jsonb_build_object(
      'source_type', v_token_row.source_type,
      'scopes', v_token_row.scopes,
      'pending_implementation', true,
      'message', 'Esse fluxo ainda não está ativo. Aguarde comunicação.'
    );

  ELSE
    RAISE EXCEPTION 'Unknown source_type: %', v_token_row.source_type;
  END IF;

  RETURN v_result;
END;
$function$;

-- ── 7. A3 (R3): o link do portal da candidatura piloto vale o processo inteiro ──
-- 45 dias (ADR-0134 §8, prazo do resultado) a partir da emissão. Só o token do portal do candidato; o de
-- agendamento do fluxo geral é recusado na trava da A1. Os tokens já emitidos ganham o mesmo prazo abaixo.
CREATE OR REPLACE FUNCTION public._token_do_piloto_vale_o_processo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.source_type = 'pmi_application'
     AND NEW.scopes && ARRAY['profile_completion', 'consent_giving']::text[]
     AND NOT public._na_avaliacao_geral(NEW.source_id) THEN
    NEW.expires_at := greatest(NEW.expires_at, now() + interval '45 days');
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._token_do_piloto_vale_o_processo() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._token_do_piloto_vale_o_processo() IS
  '#2393 A3 (ADR-0134, R3 do GP): o token do portal da candidatura de vaga line_pilot vale 45 dias da emissão, o prazo do resultado.';

DROP TRIGGER IF EXISTS trg_token_do_piloto_vale_o_processo ON public.onboarding_tokens;
CREATE TRIGGER trg_token_do_piloto_vale_o_processo
  BEFORE INSERT ON public.onboarding_tokens
  FOR EACH ROW EXECUTE FUNCTION public._token_do_piloto_vale_o_processo();

UPDATE public.onboarding_tokens t
   SET expires_at = greatest(t.expires_at, t.issued_at + interval '45 days')
 WHERE t.source_type = 'pmi_application'
   AND t.scopes && ARRAY['profile_completion', 'consent_giving']::text[]
   AND NOT public._na_avaliacao_geral(t.source_id);

-- ── 8. A3 (R4, C7, C8, C16, C17): e-mails de candidatura recebida ──
UPDATE public.campaign_templates
   SET subject   = jsonb_build_object('pt', 'Recebemos sua candidatura à vaga {{role_label}}', 'en', 'We received your application for {{role_label}}', 'es', 'Recibimos su candidatura a la vacante {{role_label}}'),
       body_html = jsonb_build_object('pt', '<p>Olá, <b>{{first_name}}</b>!</p><p>Recebemos sua candidatura à vaga <b>{{role_label}}</b>, do Núcleo IA & GP.</p><p>Próximo passo: complete seu cadastro no link abaixo. Os passos seguintes chegam por e-mail.</p><p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Continuar cadastro</a></p><p><small>O link expira em {{expires_in_days}} dias.</small></p><p>Equipe do Núcleo IA & GP</p>', 'en', '<p>Hi, <b>{{first_name}}</b>!</p><p>We received your application for <b>{{role_label}}</b> at Núcleo IA & GP.</p><p>Next step: complete your registration using the link below. The following steps will reach you by email.</p><p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Continue registration</a></p><p><small>The link expires in {{expires_in_days}} days.</small></p><p>Núcleo IA & GP team</p>', 'es', '<p>¡Hola, <b>{{first_name}}</b>!</p><p>Recibimos su candidatura a la vacante <b>{{role_label}}</b>, del Núcleo IA & GP.</p><p>Próximo paso: complete su registro en el enlace de abajo. Los pasos siguientes llegan por correo electrónico.</p><p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Continuar registro</a></p><p><small>El enlace expira en {{expires_in_days}} días.</small></p><p>Equipo del Núcleo IA & GP</p>'),
       body_text = jsonb_build_object('pt', 'Olá, {{first_name}}!

Recebemos sua candidatura à vaga {{role_label}}, do Núcleo IA & GP.

Próximo passo: complete seu cadastro em {{onboarding_url}}
Os passos seguintes chegam por e-mail.

O link expira em {{expires_in_days}} dias.

Equipe do Núcleo IA & GP', 'en', 'Hi, {{first_name}}!

We received your application for {{role_label}} at Núcleo IA & GP.

Next step: complete your registration at {{onboarding_url}}
The following steps will reach you by email.

The link expires in {{expires_in_days}} days.

Núcleo IA & GP team', 'es', '¡Hola, {{first_name}}!

Recibimos su candidatura a la vacante {{role_label}}, del Núcleo IA & GP.

Próximo paso: complete su registro en {{onboarding_url}}
Los pasos siguientes llegan por correo electrónico.

El enlace expira en {{expires_in_days}} días.

Equipo del Núcleo IA & GP'),
       updated_at = now()
 WHERE slug = 'pmi_welcome_with_token';

INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, theme, variables)
SELECT 'Candidatura recebida, vaga piloto da linha', 'pmi_welcome_line_pilot',
       jsonb_build_object('pt', 'Recebemos sua candidatura à vaga {{role_label}}', 'en', 'We received your application for {{role_label}}', 'es', 'Recibimos su candidatura a la vacante {{role_label}}'),
       jsonb_build_object('pt', '<p>Olá, <b>{{first_name}}</b>!</p><p>Recebemos sua candidatura à vaga <b>{{role_label}}</b>, do Núcleo IA & GP. Nesta vaga, a seleção é feita junto com a linha de pesquisa, em quatro passos:</p><ol><li><b>Agora:</b> complete seu cadastro no link abaixo. O consentimento para a transcrição automática do vídeo é opcional e não muda sua avaliação.</li><li><b>Até {{video_invite_by}}:</b> você recebe por e-mail o convite para um vídeo curto, com perguntas da linha. Se preferir, a mesma etapa pode ser feita ao vivo.</li><li><b>Depois do vídeo:</b> uma conversa com o líder da linha.</li><li><b>Resultado:</b> em até 45 dias a partir de hoje, por e-mail.</li></ol><p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Continuar cadastro</a></p><p><small>O link vale durante todo o processo.</small></p><p>Equipe do Núcleo IA & GP</p>', 'en', '<p>Hi, <b>{{first_name}}</b>!</p><p>We received your application for <b>{{role_label}}</b> at Núcleo IA & GP. For this opening, selection is run together with the research line, in four steps:</p><ol><li><b>Now:</b> complete your registration using the link below. Consent to the automatic transcription of the video is optional and does not change your evaluation.</li><li><b>By {{video_invite_by}}:</b> you receive by email the invitation to a short video with the line''s questions. If you prefer, the same step can be done live.</li><li><b>After the video:</b> a conversation with the line leader.</li><li><b>Result:</b> within 45 days from today, by email.</li></ol><p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Continue registration</a></p><p><small>The link stays valid for the whole process.</small></p><p>Núcleo IA & GP team</p>', 'es', '<p>¡Hola, <b>{{first_name}}</b>!</p><p>Recibimos su candidatura a la vacante <b>{{role_label}}</b>, del Núcleo IA & GP. En esta vacante, la selección se hace junto con la línea de investigación, en cuatro pasos:</p><ol><li><b>Ahora:</b> complete su registro en el enlace de abajo. El consentimiento para la transcripción automática del video es opcional y no cambia su evaluación.</li><li><b>Hasta el {{video_invite_by}}:</b> recibe por correo electrónico la invitación a un video corto, con preguntas de la línea. Si lo prefiere, la misma etapa puede hacerse en vivo.</li><li><b>Después del video:</b> una conversación con quien lidera la línea.</li><li><b>Resultado:</b> en hasta 45 días a partir de hoy, por correo electrónico.</li></ol><p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Continuar registro</a></p><p><small>El enlace vale durante todo el proceso.</small></p><p>Equipo del Núcleo IA & GP</p>'),
       jsonb_build_object('pt', 'Olá, {{first_name}}!

Recebemos sua candidatura à vaga {{role_label}}, do Núcleo IA & GP. Nesta vaga, a seleção é feita junto com a linha de pesquisa, em quatro passos:

1. Agora: complete seu cadastro em {{onboarding_url}} (o consentimento para a transcrição automática do vídeo é opcional e não muda sua avaliação).
2. Até {{video_invite_by}}: você recebe por e-mail o convite para um vídeo curto, com perguntas da linha. Se preferir, a mesma etapa pode ser feita ao vivo.
3. Depois do vídeo: uma conversa com o líder da linha.
4. Resultado: em até 45 dias a partir de hoje, por e-mail.

O link vale durante todo o processo.

Equipe do Núcleo IA & GP', 'en', 'Hi, {{first_name}}!

We received your application for {{role_label}} at Núcleo IA & GP. For this opening, selection is run together with the research line, in four steps:

1. Now: complete your registration at {{onboarding_url}} (consent to the automatic transcription of the video is optional and does not change your evaluation).
2. By {{video_invite_by}}: you receive by email the invitation to a short video with the line''s questions. If you prefer, the same step can be done live.
3. After the video: a conversation with the line leader.
4. Result: within 45 days from today, by email.

The link stays valid for the whole process.

Núcleo IA & GP team', 'es', '¡Hola, {{first_name}}!

Recibimos su candidatura a la vacante {{role_label}}, del Núcleo IA & GP. En esta vacante, la selección se hace junto con la línea de investigación, en cuatro pasos:

1. Ahora: complete su registro en {{onboarding_url}} (el consentimiento para la transcripción automática del video es opcional y no cambia su evaluación).
2. Hasta el {{video_invite_by}}: recibe por correo electrónico la invitación a un video corto, con preguntas de la línea. Si lo prefiere, la misma etapa puede hacerse en vivo.
3. Después del video: una conversación con quien lidera la línea.
4. Resultado: en hasta 45 días a partir de hoy, por correo electrónico.

El enlace vale durante todo el proceso.

Equipo del Núcleo IA & GP'),
       '{"type":"external"}'::jsonb, 'onboarding', 'onboarding', '{"first_name":{"type":"text","required":true},"role_label":{"type":"text","required":true},"onboarding_url":{"type":"text","required":true},"video_invite_by":{"type":"text","required":true}}'::jsonb
 WHERE NOT EXISTS (SELECT 1 FROM public.campaign_templates WHERE slug = 'pmi_welcome_line_pilot');

-- ── 9. A4 (R2): get_opening_application sem o e-mail da candidatura piloto ──
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
    -- #2393 A4 (R2): na candidatura piloto o e-mail não sai, então também não entra no registro de acesso.
    CASE WHEN public._na_avaliacao_geral(v_app.id) THEN ARRAY['email'] ELSE ARRAY[]::text[] END ||
    ARRAY['applicant_name', 'chapter', 'chapter_affiliation', 'applicant_city', 'state',
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
    'email', CASE WHEN public._na_avaliacao_geral(v_app.id) THEN v_app.email END,  -- #2393 A4 (R2)
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

REVOKE ALL ON FUNCTION public.get_opening_application(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_opening_application(uuid) TO authenticated;
