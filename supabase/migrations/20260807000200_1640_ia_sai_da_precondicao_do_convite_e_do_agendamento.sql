-- #1640 — GATE_NO_AI sai da pré-condição do convite de entrevista E do agendamento.
--
-- O DEFEITO
-- `_issue_interview_booking_token_core` (modo `full`) e `schedule_interview` (fora do bypass)
-- recusavam antes de qualquer outro gate quando `consent_ai_analysis_at IS NULL` OU
-- `ai_analysis IS NULL`. Ou seja: a ausência de um consentimento de terceira finalidade
-- (art. 7º, I) negava efeito ao procedimento seletivo, que corre por base autônoma
-- (art. 7º, V). Soma-se art. 20 (efeito adverso automatizado sem revisão humana no ponto da
-- recusa) e art. 6º, III (necessidade).
--
-- POR QUE NÃO É DECISÃO DE MÉRITO (medido em 07/08/2026, ciclo `cycle4-2026`)
-- 50 candidaturas aprovadas, 18 delas SEM `ai_analysis`, e 17 dessas com entrevista registrada.
-- Avaliar, entrevistar e aprovar sem o dado é rotina comprovada. Só o convite tratava a
-- ausência como impedimento.
--
-- POPULAÇÃO
-- 6 candidaturas em `interview_pending` sem consentimento — TODAS com 2 avaliações e nota
-- objetiva calculada, isto é, o gate de IA era o único obstáculo. Dessas, 4 nunca receberam
-- convite algum.
--
-- POR QUE AS DUAS RPCs, E NÃO SÓ O EMISSOR DO TOKEN
-- `schedule_interview` nunca registrou UMA recusa `GATE_NO_AI` em 31 tentativas — e isso não é
-- imunidade: 14 agendamentos passaram com `bypass_granted` sobre candidaturas sem consentimento,
-- e 13 desses 14 já tinham as 2 avaliações e a nota. O comitê contornava o gate com um bypass de
-- admin que desliga JUNTO o peer-review e a nota. Corrigir só o emissor deixaria o mesmo defeito
-- um passo adiante, com o agravante de continuar exigindo a via que enfraquece os outros gates.
--
-- O QUE FICA DE PÉ (nas duas)
-- `GATE_NO_PEER_REVIEW` (P0002) e `GATE_NO_SCORE` (P0003) são requisitos de conclusão do processo
-- objetivo, não dados opcionais de terceira finalidade. `INVALID_APP_STATUS` (P0004) fica.
-- `has_consent` e `has_ai_analysis` seguem no payload de `gate_attempts`: deixam de ser gate,
-- continuam sendo observabilidade.
--
-- ROLLBACK: reaplicar o corpo anterior (migration 20260805000509 + 20260805000512/14 para o core;
-- 20260805000509 para schedule_interview) — mas note que isso REINTRODUZ o defeito de LGPD.
--
-- Refs #1640, #1632, #1586

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. O emissor do token de agendamento (a porta do convite)
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. O agendamento pelo comitê (a porta que o bypass vinha contornando)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.schedule_interview(p_application_id uuid, p_interviewer_ids uuid[], p_scheduled_at timestamp with time zone, p_duration_minutes integer DEFAULT 30, p_calendar_event_id text DEFAULT NULL::text, p_bypass_gate boolean DEFAULT false)
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

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or platform admin';
  END IF;

  v_can_bypass := p_bypass_gate AND public.can_by_member(v_caller.id, 'manage_member'::text);

  SELECT COUNT(*) INTO v_eval_count FROM public.selection_evaluations WHERE application_id = p_application_id;
  v_gate_payload := jsonb_build_object(
    'has_consent', (v_app.consent_ai_analysis_at IS NOT NULL),
    'has_ai_analysis', (v_app.ai_analysis IS NOT NULL),
    'eval_count', v_eval_count,
    'objective_score_avg', v_app.objective_score_avg,
    'app_status', v_app.status,
    'gate_mode', CASE WHEN v_can_bypass THEN 'bypass' ELSE 'full' END
  );

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
      'Entrevista com ' || v_app.applicant_name || ' (' || COALESCE(v_app.chapter, '') || ') agendada para ' || to_char(p_scheduled_at, 'DD/MM/YYYY HH24:MI'),
      '/admin/selection',
      'selection_interview',
      v_interview_id
    );
  END LOOP;

  PERFORM public.create_notification(
    m.id,
    'selection_interview_scheduled',
    'Sua entrevista foi agendada',
    'Entrevista agendada para ' || to_char(p_scheduled_at, 'DD/MM/YYYY HH24:MI') || '. Prepare-se!',
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
    'stage_override_stamped', v_stamp_override
  );
END;
$function$;
