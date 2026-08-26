-- #2012 — quem conduz a entrevista passa a poder REGISTRA-LA, e a recusa por autoridade
-- deixa rastro.
--
-- O CASO (25/08/2026). Fernando Maquiaveli entrevistou a Anastasia Kukova as 20h e nao
-- conseguiu registrar nem pontuar. A plataforma deixava o entrevistador PONTUAR
-- (`submit_interview_scores`, apos a #1972) e nao deixava CRIAR o registro do que ele
-- proprio conduziu: `schedule_interview` exigia `selection_committee.role = 'lead'` OU
-- `manage_platform`. Medido em 26/08 no `cycle4-2026`: 2 das 7 pessoas do comite passavam
-- (Vitor, lead; Fabricio, manage_platform). O botao "Iniciar avaliacao ao vivo" chama esta
-- RPC com `p_bypass_gate = true`, mas o bypass so vale para quem tem `manage_member` e o
-- portao de ENTRADA acontecia antes dele — para o Fernando o botao nao tinha como funcionar.
--
-- O DESENHO E O DA #1972, do outro lado do mesmo fluxo: a designacao e CRIADA, o portao nao
-- e contornado. Quem registra tem de ser do comite DO CICLO, com `can_interview`, e gravar
-- A SI PROPRIO como unico entrevistador.
--
-- ⚠️ `can_interview` NAO discrimina ninguem hoje. Medido em 26/08/2026: a coluna e `true` em
-- 13 de 13 linhas de `selection_committee` (4 evaluator, 4 lead, 5 observer). Alargar so por
-- ela entregaria a criacao do registro tambem aos 5 `observer` — e observador e, por desenho
-- desta plataforma, leitura: `isObserver` ja bloqueia a pontuacao no formulario, e o eixo
-- `operate_selection` do #1838 exclui exatamente esse papel. Por isso o predicado pede as DUAS
-- coisas: `can_interview` E papel diferente de `observer`. O dominio do papel vem do catalogo
-- (`selection_committee_role_check` = evaluator | lead | observer), nao de lista de nomes.
-- Efeito no cycle4-2026: 2 pessoas -> 3 (entra o Fernando; os 4 observadores seguem fora).
--
-- A RECUSA PASSA A COMMITAR. O `RAISE EXCEPTION 'Unauthorized: must be committee lead or
-- platform admin'` acontecia ANTES do primeiro `_log_gate_attempt`, entao uma tentativa
-- barrada por autoridade nao deixava linha nenhuma: `gate_attempts` tem 37 tentativas de
-- `schedule_interview`, TODAS com `gate_passed = true` e zero recusas em toda a vida da
-- tabela. Ausencia de linha nao provava ausencia de tentativa. A saida e a mesma da #1594 —
-- e pelo mesmo motivo: `RAISE` e `INSERT` rodam na MESMA transacao, entao a linha de auditoria
-- morre com a excecao que ela deveria explicar. Recusa vira envelope `{success:false}` com
-- codigo proprio **P0005** (P0001 e do GATE_NO_AI aposentado pela #1640, e o guard dela afirma
-- que P0001 nao volta ao corpo vivo; P0002/P0003/P0004 estao em uso). As tres telas que chamam
-- esta RPC ja tratam `data.success === false` desde a #1594.
--
-- O ALARGAMENTO NAO VALE PARA AGENDAR EM NOME DE TERCEIRO nem para status fora da fase de
-- entrevista:
--   (a) `v_self_only` exige lista de UM, e esse um e o proprio chamador;
--   (b) o caminho novo NUNCA recebe o bypass — `v_can_bypass` passa a excluir
--       `self_interviewer` —, entao a allow-list P0004 do #472 corr.3 continua limitando-o a
--       `interview_pending` / `interview_scheduled`, e os gates P0002/P0003 continuam valendo
--       integralmente para ele. Quem tinha bypass antes (lead / manage_platform) segue com ele:
--       a precedencia do caminho e lead > manage_platform > self, entao nada afrouxa.
--
-- Cross-ref: #2012, #1972 (mesma classe, lado da pontuacao), #1594 (recusa que commita),
-- #1613/#472 corr.3 (allow-list de status), #1838 (papel que decide, nao participacao).

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
    'stage_override_stamped', v_stamp_override,
    'authority_path', v_authority_path
  );
END;
$function$;

COMMENT ON FUNCTION public.schedule_interview(uuid, uuid[], timestamp with time zone, integer, text, boolean) IS
  '#2012: cria o registro da entrevista. Autoridade em tres caminhos, nesta precedencia: lead do comite do ciclo; manage_platform; ou membro do comite do ciclo com can_interview e papel que decide (evaluator/lead, nunca observer) registrando a SI PROPRIO como unico entrevistador. O terceiro caminho nunca recebe p_bypass_gate. Recusa por autoridade retorna {success:false, gate_failed_code:P0005} e REGISTRA em gate_attempts (#1594: RAISE e INSERT na mesma transacao matam a linha).';
