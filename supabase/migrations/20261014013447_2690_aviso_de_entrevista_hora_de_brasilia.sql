-- #2690: o aviso de entrevista agendada mostrava a hora em UTC, sem rotulo de fuso.
-- `to_char(p_scheduled_at, ...)` formata no fuso da sessao, que e UTC: uma entrevista as 19:30
-- de Brasilia (22:30+00) saia como "22:30". As duas mensagens (entrevistador e candidato) passam
-- a formatar em America/Sao_Paulo e a dizer o fuso, como ja fazem process_interview_reminders_1h
-- e request_interview_reschedule. O capitulo deixa de imprimir "()" quando e nulo ou vazio.
-- Corpo restante identico ao de 20260826212137 (#2012), conferido por md5 contra o vivo.

CREATE OR REPLACE FUNCTION public.schedule_interview(
  p_application_id uuid,
  p_interviewer_ids uuid[],
  p_scheduled_at timestamp with time zone,
  p_duration_minutes integer DEFAULT 30,
  p_calendar_event_id text DEFAULT NULL::text,
  p_bypass_gate boolean DEFAULT false
)
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
