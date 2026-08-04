-- #1594 + #1595 — o mesmo arco, sobre o core que o #1584 acabou de escrever.
--
-- ============================================================================
-- #1594 — a auditoria de RECUSA de gate é decorativa
-- ----------------------------------------------------------------------------
-- Medido ao vivo em 2026-08-05, antes desta DDL: `gate_attempts` tem 31 linhas, TODAS com
-- `gate_passed = true`. Zero recusas em toda a vida da tabela. Não é falta de código: os dois
-- únicos chamadores de `_log_gate_attempt` (`schedule_interview` e
-- `_issue_interview_booking_token_core`) têm ramificação de recusa e chamam o log nela.
--
-- O mecanismo é o rollback: o `INSERT` do log e o `RAISE EXCEPTION` que vem logo depois estão na
-- MESMA transação, então a linha morre com a exceção que ela deveria explicar. O
-- `EXCEPTION WHEN OTHERS` de `_log_gate_attempt` protege a regra de negócio contra uma falha do
-- log — não faz o log sobreviver ao rollback do chamador.
--
-- Decisão do PM (05/08, opção 2): **recusa vira retorno estruturado**
-- (`{success:false, gate_failed_code}`) em vez de exceção, para que a transação commite. Recusadas:
-- transação autônoma (dependência de extensão + uma conexão por recusa) e "log de tentativa
-- iniciada" (morre no mesmo rollback — não existe meio-termo barato).
--
-- ⚠️ O cuidado que define se o fix presta: `notify_selection_cutoff_approved` DEPENDIA da exceção
-- para abortar o e-mail. Ela passa a checar o retorno e abortar explicitamente, e
-- `_selection_cutoff_pending_cron` passa a contar recusa separado de despacho — senão o cron
-- reportaria `dispatched_count` inflado, porque hoje ele conta uma volta bem-sucedida do laço.
--
-- ============================================================================
-- #1595 — a porta do REAGENDAMENTO ficou inteira
-- ----------------------------------------------------------------------------
-- O #1584 fechou a porta da primeira convocação. Medido no corpo VIVO (`pg_proc`), o link
-- institucional cru seguia entregue por três RPCs — `mark_interview_status`,
-- `request_interview_reschedule`, `process_pending_reschedule_nudges` — e pelo
-- `PMIOnboardingPortal.tsx`. O caminho do no-show é justamente o que mais reagenda.
--
-- Decisão do PM (05/08): **o reagendamento NÃO reaplica os três gates, reusa a decisão original.**
-- Reaplicar barraria exatamente as 3 pessoas para quem a porta existe. Condição inegociável: pular
-- tem de ser AUDITADO (`GATE_REUSED_PRIOR`), senão o reagendamento volta a ser caminho não auditado.
--
-- ⚠️ AJUSTE DE FORMA, medido neste turno e registrado aqui de propósito. A decisão pedia, no modo
-- de reuso, "prova de que o gate foi passado uma vez: linha em `selection_dispatch_url_log`, ou
-- token anterior". Medido:
--
--   quem                          | interviews | dispatch_rows | prior_tokens | gate_attempts pass
--   Nestor Collato (noshow)       |     2      |       0       |      0       |        0
--   Anastasia Kukova (scheduled)  |     1      |       0       |      0       |        0
--   Marcelo Figueiredo (scheduled)|     1      |       0       |      0       |        0
--
-- Nenhum dos três tem a prova — eles entraram pela porta paralela, que é a razão de a issue
-- existir. Exigir a prova produziria o MESMO resultado que reaplicar os gates (recusar os 3), que é
-- o resultado que a decisão foi tomada para evitar. Portanto vale o gatilho que a decisão nomeia
-- (candidatura com linha em `selection_interviews`), e a prova vira **nível registrado** no payload
-- da auditoria — `prior_evidence` ∈ {dispatch_log, prior_token, interview_row_only} — para que o
-- caso fraco fique visível em vez de silencioso.
--
-- ============================================================================
-- Ordem das partes
--   1. _issue_interview_booking_token_core — recusa estruturada + modo reuse_prior
--   2. _dispatch_interview_booking_link    — resolve + emite + grava despacho (fonte ÚNICA)
--   3. schedule_interview                  — as 4 recusas viram retorno estruturado
--   4. notify_selection_cutoff_approved    — usa o helper e aborta o e-mail explicitamente
--   5. _selection_cutoff_pending_cron      — conta recusa separado de despacho
--   6. mark_interview_status               — link de token no e-mail de no-show
--   7. request_interview_reschedule        — link de token, e recusa não escreve nada
--   8. process_pending_reschedule_nudges   — link de token no cutucão
--   9. request_interview_booking_link_via_token — porta do portal do candidato
--  10. get_application_gate_attempts       — expõe o modo do gate na leitura
-- ============================================================================

-- ============================================================================
-- 1 — _issue_interview_booking_token_core
-- ----------------------------------------------------------------------------
-- Assinatura inalterada (uuid, boolean, uuid, boolean) → jsonb, logo CREATE OR REPLACE preserva o
-- ACL fechado do #1584. Duas mudanças de comportamento:
--   (a) #1594 — cada recusa RETORNA em vez de levantar. É o que faz a linha de `gate_attempts`
--       commitar. Quem chama TEM de checar `success`; os 4 chamadores desta migration checam.
--   (b) #1595 — quando a candidatura já tem linha em `selection_interviews`, o modo passa a
--       `reuse_prior`: os 3 gates não são reavaliados e a linha de auditoria carrega
--       `gate_reuse_reason = 'GATE_REUSED_PRIOR'` + o nível da prova anterior.
-- O bypass explícito (`p_bypass_granted`, decidido pelo chamador com manage_member) continua acima
-- dos dois: bypass > reuse_prior > full.
-- ============================================================================
CREATE OR REPLACE FUNCTION public._issue_interview_booking_token_core(
  p_application_id uuid,
  p_bypass_granted boolean DEFAULT false,
  p_caller_id uuid DEFAULT NULL,
  p_bypass_requested boolean DEFAULT false
)
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
    IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, '_issue_interview_booking_token_core', p_caller_id, false,
        'P0001', 'GATE_NO_AI', p_bypass_requested, p_bypass_granted,
        v_gate_payload, v_app.organization_id
      );
      -- #1594: RETURN, não RAISE. Um RAISE aqui desfaria o INSERT de auditoria acima.
      RETURN jsonb_build_object(
        'success', false,
        'application_id', p_application_id,
        'gate_mode', v_gate_mode,
        'gate_failed_code', 'P0001',
        'gate_failed_reason', 'GATE_NO_AI',
        'message', 'GATE_NO_AI: candidate has no AI analysis.'
      );
    END IF;

    IF v_eval_count < 2 THEN
      PERFORM public._log_gate_attempt(
        p_application_id, '_issue_interview_booking_token_core', p_caller_id, false,
        'P0002', 'GATE_NO_PEER_REVIEW', p_bypass_requested, p_bypass_granted,
        v_gate_payload, v_app.organization_id
      );
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

COMMENT ON FUNCTION public._issue_interview_booking_token_core(uuid, boolean, uuid, boolean) IS
  'Core de emissão do token de agendamento. Gates do CANDIDATO (P0001/P0002/P0003) sem gate de '
  'chamador — quem decide autoridade é o chamador. #1594: recusa RETORNA {success:false, '
  'gate_failed_code} em vez de levantar, para que a linha de gate_attempts commite. #1595: '
  'candidatura com linha em selection_interviews entra em modo reuse_prior (GATE_REUSED_PRIOR) e '
  'não reavalia os 3 gates. Interna: sem EXECUTE para anon/authenticated.';

-- ⚠️ `FROM PUBLIC` sozinho NÃO fecha nada aqui: o projeto tem
-- `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role`.
-- CREATE OR REPLACE preserva o ACL, mas o REVOKE é repetido de propósito — é idempotente e mantém
-- a asserção do teste de classe verdadeira sobre ESTA migration também.
REVOKE ALL ON FUNCTION public._issue_interview_booking_token_core(uuid, boolean, uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._issue_interview_booking_token_core(uuid, boolean, uuid, boolean) TO service_role;

-- ============================================================================
-- 2 — _dispatch_interview_booking_link: a fonte ÚNICA de "mandar link de agendamento"
-- ----------------------------------------------------------------------------
-- O #1584 deixou resolve + emite + grava despacho inline dentro de
-- `notify_selection_cutoff_approved`. Com o #1595 esse mesmo trio passa a ser necessário em mais
-- QUATRO lugares. Duplicar seria plantar a quinta porta paralela — que é exatamente a classe de
-- defeito que este arco inteiro persegue. Um helper, cinco chamadores, e um teste de classe
-- afirmando que nenhuma função viva de `public` volta a carregar o literal do Google.
--
-- Ordem interna importa: a resolução vem ANTES da emissão. Sem destino resolvível não há despacho,
-- e como nada foi gravado ainda, quem chama pode levantar exceção nesse caso sem perder auditoria.
-- Depois da emissão, NINGUÉM pode levantar — a linha de gate_attempts morreria junto (#1594).
-- ============================================================================
CREATE OR REPLACE FUNCTION public._dispatch_interview_booking_link(
  p_application_id uuid,
  p_caller_id uuid DEFAULT NULL,
  p_source text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
  v_url text;
  v_path text;
  v_evaluator uuid;
  v_token_result jsonb;
BEGIN
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT r.url, r.resolution_path, r.evaluator_id
  INTO v_url, v_path, v_evaluator
  FROM public.resolve_interview_booking_url(p_application_id) r;

  IF v_url IS NULL OR length(trim(v_url)) = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'failure_code', 'NO_BOOKING_URL',
      'application_id', p_application_id,
      'dispatch_source', p_source,
      'message', 'no resolvable booking URL for this application'
    );
  END IF;

  v_token_result := public._issue_interview_booking_token_core(
    p_application_id, false, p_caller_id, false
  );

  IF COALESCE((v_token_result->>'success')::boolean, false) IS NOT TRUE THEN
    -- Recusa de gate: devolver como está, SEM levantar. A linha de auditoria já foi gravada pelo
    -- core e só sobrevive se ninguém abortar a transação daqui para cima.
    RETURN v_token_result || jsonb_build_object(
      'failure_code', 'GATE_REFUSED',
      'dispatch_source', p_source
    );
  END IF;

  -- Linha de despacho: é ela que `validate_interview_booking_token` lê para montar a página, e é
  -- ela que alimenta o lookback do LRD. Sem esta linha o reagendamento continuaria fora do rodízio
  -- e fora do log, que é metade do achado da #1595.
  INSERT INTO public.selection_dispatch_url_log (
    application_id, cycle_id, track,
    resolved_url, resolution_path, resolved_evaluator_id, organization_id
  ) VALUES (
    p_application_id, v_app.cycle_id, v_app.role_applied,
    v_url, v_path, v_evaluator, v_app.organization_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'booking_url', v_token_result->>'booking_url',
    'token', v_token_result->>'token',
    'expires_at', v_token_result->>'expires_at',
    'resolved_url', v_url,
    'resolution_path', v_path,
    'resolved_evaluator_id', v_evaluator,
    'gate_mode', v_token_result->>'gate_mode',
    'prior_evidence', v_token_result->>'prior_evidence',
    'dispatch_source', p_source
  );
END;
$function$;

COMMENT ON FUNCTION public._dispatch_interview_booking_link(uuid, uuid, text) IS
  '#1595 — fonte única de despacho de link de agendamento: resolve a URL (LRD/precedência), emite o '
  'token pelo core (herda gates + modo reuse_prior) e grava selection_dispatch_url_log. Devolve '
  '{success:false, failure_code} em NO_BOOKING_URL e GATE_REFUSED; nunca levanta depois de emitir, '
  'para não desfazer a auditoria de recusa (#1594). Interna: sem EXECUTE para anon/authenticated.';

REVOKE ALL ON FUNCTION public._dispatch_interview_booking_link(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._dispatch_interview_booking_link(uuid, uuid, text) TO service_role;

-- ============================================================================
-- 3 — schedule_interview: as 4 recusas viram retorno estruturado
-- ----------------------------------------------------------------------------
-- É AQUI que estão as 31 linhas de `gate_attempts`, todas de sucesso. As quatro ramificações de
-- recusa (P0001/P0002/P0003 dentro do `IF NOT v_can_bypass`, e P0004 fora dele) chamam
-- `_log_gate_attempt` e em seguida levantam — logo nunca produziram linha.
--
-- Preservado sem alteração: gate de autoridade (comitê lead OU manage_platform), a autoridade do
-- bypass (`p_bypass_gate AND manage_member`), a allow-list P0004 do #472 corr.3, o INSERT da
-- entrevista, o UPDATE de status e as notificações.
--
-- ⚠️ Mudança de CONTRATO para quem chama de fora do banco: recusa deixa de chegar como erro
-- PostgREST e passa a chegar como HTTP 200 com `success:false`. `admin/selection.astro` e o
-- `nucleo-mcp` foram atualizados no mesmo PR — um consumidor que só olhasse `error` leria recusa
-- como sucesso, que é falha pior do que a que se está corrigindo.
-- ============================================================================
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
    IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'schedule_interview', v_caller.id, false,
        'P0001', 'GATE_NO_AI', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RETURN jsonb_build_object(
        'success', false,
        'application_id', p_application_id,
        'gate_failed_code', 'P0001',
        'gate_failed_reason', 'GATE_NO_AI',
        'message', 'GATE_NO_AI: candidate has no AI analysis. Use p_bypass_gate=true with manage_member to override.'
      );
    END IF;

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

  UPDATE public.selection_applications
  SET status = 'interview_scheduled', updated_at = now()
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
    v_gate_payload, v_app.organization_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'interview_id', v_interview_id,
    'scheduled_at', p_scheduled_at,
    'application_status', 'interview_scheduled',
    'gate_bypassed', v_can_bypass
  );
END;
$function$;

COMMENT ON FUNCTION public.schedule_interview(uuid, uuid[], timestamptz, integer, text, boolean) IS
  'Agenda entrevista. Autoridade: comitê lead OU manage_platform; bypass dos gates só com '
  'manage_member + p_bypass_gate. #1594: as recusas P0001/P0002/P0003/P0004 devolvem '
  '{success:false, gate_failed_code} em vez de levantar, para que a linha de gate_attempts commite.';

-- ============================================================================
-- 4 — notify_selection_cutoff_approved
-- ----------------------------------------------------------------------------
-- Base: corpo VIVO (versão p1584_a1_a6). Duas mudanças:
--   (a) #1595 — resolve + emite + grava despacho passam a vir do helper, fonte única.
--   (b) #1594 — o e-mail era abortado PELA EXCEÇÃO do core. O core não levanta mais, então o abort
--       vira explícito: checa `success`, e em recusa RETORNA sem gravar despacho, sem carimbar a
--       idempotência e sem mandar e-mail. Se este RETURN virasse RAISE, a linha de auditoria que a
--       #1594 existe para produzir morreria de novo.
-- Preservado: bypass de cron do ADR-0028, idempotência de disparo único, o gate #1450
-- (objective_score_avg) e a linha de admin_audit_log.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_selection_cutoff_approved(p_application_id uuid)
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
  v_first_name text;
  v_objective_done int;
  -- roteamento v1 (#355) — vindo do helper compartilhado (#1595)
  v_resolved_url text;
  v_resolution_path text;
  v_resolved_evaluator_id uuid;
  -- p282 #411 W2a: cron/service context flag (ADR-0028)
  v_is_cron boolean := false;
  -- #1584 A6: o link que vai para o candidato é o do token, não o do Google
  v_dispatch jsonb;
  v_token_url text;
BEGIN
  -- Authority gate — mesmo de dispatch_peer_review_invitations (committee lead OU manage_member).
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    -- ADR-0028 cron/service bypass: sessão sem JWT (pg_cron) ou service_role é o caminho
    -- automatizado. Um ghost autenticado tem auth.uid() não-nulo + claims presentes, então cai no
    -- ELSE e levanta.
    IF current_setting('request.jwt.claims', true) IS NULL OR auth.role() = 'service_role' THEN
      v_is_cron := true;  -- v_caller segue NULL → actor_id NULL (linha de sistema)
    ELSE
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  IF NOT v_is_cron THEN
    SELECT * INTO v_committee
    FROM public.selection_committee
    WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

    IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
      RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
    END IF;
  END IF;

  -- Idempotência: disparo único por candidatura
  IF v_app.cutoff_approved_email_sent_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'application_id', p_application_id,
      'email_sent', false,
      'reason', 'already_sent',
      'previously_sent_at', v_app.cutoff_approved_email_sent_at
    );
  END IF;

  IF v_app.email IS NULL THEN
    RAISE EXCEPTION 'Application has no email — cannot dispatch';
  END IF;

  -- #1450 — gate de fase objetiva. NUNCA despachar o convite de agendamento antes de o candidato
  -- ter fechado a fase objetiva. Mantido explícito aqui (além do P0003 do core) porque a mensagem
  -- nomeia o #1450 e é o que o teste de contrato daquele arco afirma. Segue levantando: acontece
  -- ANTES de qualquer emissão, então não há linha de auditoria para perder.
  IF v_app.objective_score_avg IS NULL THEN
    RAISE EXCEPTION 'GATE_NO_SCORE: objective_score_avg not computed for application % — the interview-scheduling invite must not be sent before the objective phase completes (#1450).', p_application_id
      USING ERRCODE = 'P0003';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- ============================================================
  -- #1595 — resolve + emite token + grava a linha de despacho, tudo pela fonte única.
  -- ============================================================
  v_dispatch := public._dispatch_interview_booking_link(
    p_application_id, v_caller.id, CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END
  );

  IF COALESCE((v_dispatch->>'success')::boolean, false) IS NOT TRUE THEN
    IF v_dispatch->>'failure_code' = 'NO_BOOKING_URL' THEN
      -- Nada foi emitido nem gravado ainda: levantar aqui é seguro e preserva o contrato P0020.
      RAISE EXCEPTION 'CUTOFF_NO_BOOKING_URL: no resolvable booking URL for application % (cycle %, role %); set selection_cycles.interview_booking_url or seed selection_committee with per-evaluator URLs',
        p_application_id, v_app.cycle_id, v_app.role_applied USING ERRCODE = 'P0020';
    END IF;

    -- #1594 — recusa de gate: abortar o e-mail EXPLICITAMENTE, sem exceção. A linha de
    -- gate_attempts que o core acabou de gravar só sobrevive se esta transação commitar.
    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'email_sent', false,
      'reason', 'gate_refused',
      'gate_failed_code', v_dispatch->>'gate_failed_code',
      'gate_failed_reason', v_dispatch->>'gate_failed_reason',
      'message', v_dispatch->>'message'
    );
  END IF;

  v_token_url            := v_dispatch->>'booking_url';
  v_resolved_url         := v_dispatch->>'resolved_url';
  v_resolution_path      := v_dispatch->>'resolution_path';
  v_resolved_evaluator_id := NULLIF(v_dispatch->>'resolved_evaluator_id', '')::uuid;

  -- Sanidade de threshold (informativa).
  SELECT count(*)::int INTO v_objective_done
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'objective';

  v_first_name := COALESCE(
    NULLIF(trim(v_app.first_name), ''),
    NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
    'candidato(a)'
  );

  -- Despacho via campaign_send_one_off — #1584 A6: passa o link do TOKEN.
  PERFORM public.campaign_send_one_off(
    p_template_slug := 'selection_cutoff_approved',
    p_to_email := v_app.email,
    p_variables := jsonb_build_object(
      'first_name', v_first_name,
      'interview_booking_url', v_token_url
    ),
    p_metadata := jsonb_build_object(
      'source', 'notify_selection_cutoff_approved',
      'application_id', p_application_id,
      'cycle_id', v_app.cycle_id,
      'cycle_code', v_cycle.cycle_code,
      'objective_done', v_objective_done,
      'research_score', v_app.research_score,
      'resolution_path', v_resolution_path,
      'resolved_evaluator_id', v_resolved_evaluator_id,
      'link_kind', 'governed_token'
    )
  );

  -- Carimbo de idempotência pós-envio.
  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = now(),
      updated_at = now()
  WHERE id = p_application_id;

  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.cutoff_approved_email_dispatched',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'cutoff_approved_email_sent_at_before', NULL,
      'cutoff_approved_email_sent_at_after', now(),
      'recipient_email', v_app.email
    ),
    jsonb_build_object(
      'cycle_id', v_app.cycle_id,
      'cycle_code', v_cycle.cycle_code,
      'objective_done', v_objective_done,
      'research_score', v_app.research_score,
      'interview_booking_url', v_resolved_url,
      'resolution_path', v_resolution_path,
      'resolved_evaluator_id', v_resolved_evaluator_id,
      'role_applied', v_app.role_applied,
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
      'token_prefix', left(COALESCE(v_dispatch->>'token', ''), 8),
      'gate_mode', v_dispatch->>'gate_mode',
      'link_kind', 'governed_token',
      'rpc_version', 'p1594_p1595'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'cycle_id', v_app.cycle_id,
    'email_sent', true,
    'recipient_email_redacted', LEFT(v_app.email, 2) || '***' || RIGHT(v_app.email, 4),
    'objective_done', v_objective_done,
    'research_score', v_app.research_score,
    'resolution_path', v_resolution_path,
    'resolved_evaluator_id', v_resolved_evaluator_id,
    'link_kind', 'governed_token',
    'gate_mode', v_dispatch->>'gate_mode',
    'token_expires_at', v_dispatch->>'expires_at'
  );
END;
$function$;

-- ============================================================================
-- 5 — _selection_cutoff_pending_cron: recusa não é despacho
-- ----------------------------------------------------------------------------
-- Antes, `PERFORM notify_...` + `v_dispatched + 1`: como a recusa chegava por exceção, ela caía no
-- `EXCEPTION WHEN OTHERS` e virava `error_count`. Com o retorno estruturado do #1594 a chamada
-- volta NORMAL, e um `PERFORM` cego contaria a recusa como despacho — o cron reportaria e-mail
-- enviado onde não houve nenhum. Passa a ler o envelope.
-- Mantido `SET search_path TO ''` (tudo qualificado) e a subtransação por linha.
-- ============================================================================
CREATE OR REPLACE FUNCTION public._selection_cutoff_pending_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_app record;
  v_result jsonb;
  v_dispatched int := 0;
  v_refused int := 0;
  v_errors int := 0;
  v_cycles text[] := '{}';
  v_run_at timestamptz := now();
BEGIN
  FOR v_app IN
    SELECT a.id AS app_id, c.cycle_code
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status IN ('screening', 'interview_pending')
      AND a.role_applied = 'researcher'                   -- Audit A3: objective cutoff is researcher-only
      AND a.objective_score_avg IS NOT NULL
      AND a.pert_target_score IS NOT NULL
      AND a.objective_score_avg >= a.pert_target_score   -- STRICT above-target only (NOT in_band)
      AND a.cutoff_approved_email_sent_at IS NULL          -- pre-flight idempotency
      AND c.status = 'open'
    ORDER BY a.objective_score_avg DESC
    LIMIT 50                                               -- runaway cap
  LOOP
    -- Subtransação por linha: uma candidatura ruim (ex.: CUTOFF_NO_BOOKING_URL) nunca aborta a volta.
    BEGIN
      v_result := public.notify_selection_cutoff_approved(v_app.app_id);

      IF COALESCE((v_result->>'email_sent')::boolean, false) THEN
        v_dispatched := v_dispatched + 1;
        IF NOT (v_app.cycle_code = ANY (v_cycles)) THEN
          v_cycles := array_append(v_cycles, v_app.cycle_code);
        END IF;
      ELSIF COALESCE((v_result->>'success')::boolean, true) IS NOT TRUE THEN
        -- #1594: recusa de gate chega por retorno, não por exceção. Contá-la como despacho seria
        -- reportar e-mail que não saiu.
        v_refused := v_refused + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.cutoff_pending_cron_run', 'system', NULL,
    jsonb_build_object('dispatched_count', v_dispatched, 'refused_count', v_refused, 'error_count', v_errors),
    jsonb_build_object(
      'dispatched_count', v_dispatched,
      'refused_count', v_refused,
      'error_count', v_errors,
      'cycle_codes_touched', to_jsonb(v_cycles),
      'run_at', v_run_at,
      'limit', 50,
      'policy', 'strict_above_target'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'dispatched_count', v_dispatched,
    'refused_count', v_refused,
    'error_count', v_errors,
    'cycle_codes_touched', to_jsonb(v_cycles),
    'run_at', v_run_at
  );
END;
$function$;

-- ============================================================================
-- 6 — mark_interview_status: o e-mail de no-show leva link de token
-- ----------------------------------------------------------------------------
-- Era `COALESCE(v_cycle.interview_booking_url, 'https://calendar.app.google/gh9WjefjcmisVLoh7')`:
-- link cru, fora do rodízio do LRD, fora do log de despacho e fora de qualquer gate por candidato.
-- É o caminho do no-show — o que MAIS reagenda.
--
-- Quem chega aqui tem, por construção, linha em `selection_interviews`, logo o core entra em modo
-- `reuse_prior` (#1595) e a decisão original é reusada em vez de reavaliada.
--
-- ⚠️ O despacho fica FORA do `BEGIN ... EXCEPTION` do envio: uma falha da Resend não pode desfazer
-- a linha de auditoria nem o token emitido.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.mark_interview_status(
  p_interview_id uuid,
  p_status text,
  p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_interview record;
  v_app record;
  v_cycle record;
  v_new_app_status text;
  v_prior_status text;
  v_first_name text;
  v_booking_url text;
  v_deadline_date text;
  v_send_result jsonb := NULL;
  v_noshow_count int;
  v_two_strike_applied boolean := false;
  v_two_strike_send jsonb := NULL;
  v_dispatch jsonb := NULL;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF p_status NOT IN ('noshow', 'cancelled', 'rescheduled', 'completed') THEN
    RAISE EXCEPTION 'Invalid interview status: %', p_status;
  END IF;

  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF v_interview IS NULL THEN
    RAISE EXCEPTION 'Interview not found';
  END IF;

  v_prior_status := v_interview.status;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  IF NOT (
    v_caller.id = ANY(v_interview.interviewer_ids)
    OR public.can_by_member(v_caller.id, 'manage_platform'::text)
    OR EXISTS (
      SELECT 1 FROM public.selection_committee
      WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
    )
  ) THEN
    RAISE EXCEPTION 'Unauthorized: must be interviewer, committee lead, or platform admin';
  END IF;

  UPDATE public.selection_interviews
  SET status = p_status,
      notes = COALESCE(p_notes, notes),
      conducted_at = CASE WHEN p_status = 'completed' THEN now() ELSE conducted_at END
  WHERE id = p_interview_id;

  v_new_app_status := CASE p_status
    WHEN 'noshow' THEN 'interview_noshow'
    WHEN 'cancelled' THEN 'interview_pending'
    WHEN 'rescheduled' THEN 'interview_pending'
    WHEN 'completed' THEN 'interview_done'
    ELSE v_app.status
  END;

  UPDATE public.selection_applications
  SET status = v_new_app_status, updated_at = now()
  WHERE id = v_interview.application_id
    AND status IN ('interview_scheduled', 'interview_done');

  IF p_status = 'noshow' AND v_prior_status IS DISTINCT FROM 'noshow' THEN
    v_first_name := COALESCE(
      NULLIF(trim(v_app.first_name), ''),
      NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
      'candidato(a)'
    );

    SELECT count(*) INTO v_noshow_count
    FROM public.selection_interviews
    WHERE application_id = v_interview.application_id
      AND status = 'noshow';

    IF v_noshow_count >= 2 THEN
      -- 2-strike auto-close: status rejected + e-mail de encerramento, sem reagendamento suave
      UPDATE public.selection_applications
      SET status = 'rejected',
          feedback = COALESCE(feedback, '') || E'\n[p152 auto-close ' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') || ' BRT] Encerrado automaticamente após ' || v_noshow_count || ' no-shows na entrevista.',
          updated_at = now()
      WHERE id = v_interview.application_id;

      BEGIN
        v_two_strike_send := public.campaign_send_one_off(
          'interview_two_strike_close',
          v_app.email,
          jsonb_build_object('first_name', v_first_name),
          jsonb_build_object(
            'language', 'pt',
            'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
            'source', 'mark_interview_status:two_strike_close',
            'noshow_count', v_noshow_count
          )
        );
      EXCEPTION WHEN OTHERS THEN
        v_two_strike_send := jsonb_build_object('error', SQLERRM);
      END;

      v_two_strike_applied := true;

      PERFORM public.create_notification(
        sc.member_id,
        'selection_application_two_strike_closed',
        '2-strike encerrado: ' || v_app.applicant_name,
        v_app.applicant_name || ' teve ' || v_noshow_count || ' no-shows. Processo encerrado automaticamente + email enviado. Override manual via Status select.',
        '/admin/selection',
        'selection_application',
        v_interview.application_id
      )
      FROM public.selection_committee sc
      WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
    ELSE
      -- 1º no-show: e-mail de reagendamento suave (caminho P1), agora com LINK DE TOKEN (#1595).
      v_dispatch := public._dispatch_interview_booking_link(
        v_interview.application_id, v_caller.id, 'mark_interview_status:noshow'
      );
      v_deadline_date := to_char((now() + interval '7 days') AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY');

      IF COALESCE((v_dispatch->>'success')::boolean, false) THEN
        v_booking_url := v_dispatch->>'booking_url';

        BEGIN
          v_send_result := public.campaign_send_one_off(
            'interview_noshow_soft_reschedule',
            v_app.email,
            jsonb_build_object(
              'first_name', v_first_name,
              'booking_url', v_booking_url,
              'deadline_date', v_deadline_date
            ),
            jsonb_build_object(
              'language', 'pt',
              'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
              'source', 'mark_interview_status:noshow',
              'link_kind', 'governed_token',
              'gate_mode', v_dispatch->>'gate_mode'
            )
          );
        EXCEPTION WHEN OTHERS THEN
          v_send_result := jsonb_build_object('error', SQLERRM);
        END;
      ELSE
        -- Sem link governado não sai e-mail: mandar o link cru era exatamente o defeito da #1595.
        v_send_result := jsonb_build_object(
          'error', 'booking_link_unavailable',
          'failure_code', v_dispatch->>'failure_code',
          'gate_failed_code', v_dispatch->>'gate_failed_code'
        );
      END IF;
    END IF;
  END IF;

  IF p_status = 'noshow' AND NOT v_two_strike_applied THEN
    PERFORM public.create_notification(
      sc.member_id,
      'selection_interview_noshow',
      'No-show: ' || v_app.applicant_name,
      v_app.applicant_name || ' (' || COALESCE(v_app.chapter, '') || ') não compareceu à entrevista agendada.',
      '/admin/selection',
      'selection_interview',
      p_interview_id
    )
    FROM public.selection_committee sc
    WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'interview_status', p_status,
    'application_status', CASE WHEN v_two_strike_applied THEN 'rejected' ELSE v_new_app_status END,
    'email_dispatched', v_send_result IS NOT NULL AND (v_send_result ? 'send_id'),
    'email_send_result', v_send_result,
    'two_strike_applied', v_two_strike_applied,
    'noshow_count', v_noshow_count,
    'two_strike_email', v_two_strike_send,
    'link_kind', CASE WHEN COALESCE((v_dispatch->>'success')::boolean, false) THEN 'governed_token' ELSE NULL END,
    'gate_mode', v_dispatch->>'gate_mode'
  );
END;
$function$;

-- ============================================================================
-- 7 — request_interview_reschedule: link de token, e recusa não escreve nada
-- ----------------------------------------------------------------------------
-- Era `v_booking_url text := 'https://calendar.app.google/gh9WjefjcmisVLoh7'` — literal, sem sequer
-- consultar o ciclo.
--
-- O despacho vai para o TOPO, antes de qualquer escrita: assim uma recusa de gate devolve envelope
-- estruturado com a candidatura intacta (nada de `needs_reschedule` sem e-mail para o candidato), e
-- a linha de auditoria da recusa commita porque ninguém levanta.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.request_interview_reschedule(p_application_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_send_result jsonb;
  v_first_name text;
  v_was_noshow boolean := false;
  v_dispatch jsonb;
  v_booking_url text;
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
  WHERE cycle_id = v_app.cycle_id
    AND member_id = v_caller.id
    AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
  END IF;

  -- p109 Onda 4 Fase 1.3: aceitar interview_noshow (segunda chance é o caso comum)
  IF v_app.status NOT IN ('interview_pending', 'interview_scheduled', 'interview_noshow') THEN
    RAISE EXCEPTION 'Application status % does not allow reschedule request', v_app.status;
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'Reschedule reason is required';
  END IF;

  -- #1595 — o link governado é pré-condição do pedido. Emitir ANTES de escrever mantém a
  -- candidatura intacta na recusa, e o RETURN (em vez de RAISE) preserva a auditoria (#1594).
  v_dispatch := public._dispatch_interview_booking_link(
    p_application_id, v_caller.id, 'request_interview_reschedule'
  );

  IF COALESCE((v_dispatch->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'reason', CASE WHEN v_dispatch->>'failure_code' = 'NO_BOOKING_URL'
                     THEN 'no_booking_url' ELSE 'gate_refused' END,
      'failure_code', v_dispatch->>'failure_code',
      'gate_failed_code', v_dispatch->>'gate_failed_code',
      'gate_failed_reason', v_dispatch->>'gate_failed_reason',
      'message', v_dispatch->>'message'
    );
  END IF;

  v_booking_url := v_dispatch->>'booking_url';
  v_was_noshow := v_app.status = 'interview_noshow';

  UPDATE public.selection_applications
  SET interview_status = 'needs_reschedule',
      interview_reschedule_reason = p_reason,
      interview_reschedule_requested_at = now(),
      interview_reschedule_requested_by = v_caller.id,
      status = CASE WHEN v_was_noshow THEN 'interview_pending' ELSE status END,
      updated_at = now()
  WHERE id = p_application_id;

  UPDATE public.selection_interviews
  SET status = 'rescheduled',
      notes = COALESCE(notes || E'\n', '')
            || '[' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') || ' BRT] '
            || 'Marked for reschedule by ' || COALESCE(v_caller.name, 'admin')
            || CASE WHEN v_was_noshow THEN ' (from no-show)' ELSE '' END
            || ': ' || p_reason
  WHERE application_id = p_application_id
    AND status IN ('scheduled', 'noshow');

  v_first_name := COALESCE(
    NULLIF(trim(v_app.first_name), ''),
    NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
    'candidato(a)'
  );

  v_send_result := public.campaign_send_one_off(
    'interview_reschedule_request',
    v_app.email,
    jsonb_build_object(
      'first_name', v_first_name,
      'reason', p_reason,
      'booking_url', v_booking_url
    ),
    jsonb_build_object(
      'language', 'pt',
      'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
      'source', 'request_interview_reschedule',
      'link_kind', 'governed_token',
      'gate_mode', v_dispatch->>'gate_mode'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'send_id', v_send_result->>'send_id',
    'booking_url', v_booking_url,
    'link_kind', 'governed_token',
    'gate_mode', v_dispatch->>'gate_mode',
    'interview_status', 'needs_reschedule',
    'was_noshow', v_was_noshow,
    'requested_by', v_caller.id,
    'requested_at', now()
  );
END;
$function$;

-- ============================================================================
-- 8 — process_pending_reschedule_nudges: o cutucão também vira link de token
-- ----------------------------------------------------------------------------
-- Duas subtransações por linha, de propósito: a do despacho e a do envio. Se fossem uma só, uma
-- falha da Resend desfaria a linha de gate_attempts e o token junto — o mesmo rollback que a #1594
-- existe para eliminar.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.process_pending_reschedule_nudges()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
  v_first_name text;
  v_booking_url text;
  v_dispatch jsonb;
  v_nudges_sent int := 0;
  v_errors jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_processed jsonb := '[]'::jsonb;
  v_nudge_initial interval;
  v_nudge_repeat interval;
BEGIN
  SELECT value_interval INTO v_nudge_initial FROM public.sla_policies WHERE policy_key = 'reschedule_nudge_initial';
  IF v_nudge_initial IS NULL THEN v_nudge_initial := interval '3 days'; END IF;
  SELECT value_interval INTO v_nudge_repeat FROM public.sla_policies WHERE policy_key = 'reschedule_nudge_repeat';
  IF v_nudge_repeat IS NULL THEN v_nudge_repeat := interval '3 days'; END IF;

  -- Cron-context auth bypass (sem JWT). Alinhado ao padrão do ADR-0028 (emenda p89).
  IF auth.role() IS NOT NULL AND auth.role() NOT IN ('service_role') AND auth.uid() IS NOT NULL THEN
    IF NOT public.can_by_member(
      (SELECT id FROM public.members WHERE auth_id = auth.uid()),
      'manage_member'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: cron RPC requires manage_member or service_role';
    END IF;
  END IF;

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.email, a.cycle_id,
           a.interview_reschedule_reason,
           a.interview_reschedule_requested_at,
           a.interview_reschedule_last_nudged_at
    FROM public.selection_applications a
    WHERE a.interview_status = 'needs_reschedule'
      AND a.interview_reschedule_requested_at IS NOT NULL
      AND a.interview_reschedule_requested_at < now() - v_nudge_initial
      AND (
        a.interview_reschedule_last_nudged_at IS NULL
        OR a.interview_reschedule_last_nudged_at < now() - v_nudge_repeat
      )
      AND a.status IN ('interview_pending', 'interview_scheduled')
  LOOP
    v_first_name := split_part(v_app.applicant_name, ' ', 1);
    v_dispatch := NULL;
    v_booking_url := NULL;

    -- Subtransação 1: o despacho governado. Commita por si — um erro de envio adiante não a desfaz.
    BEGIN
      v_dispatch := public._dispatch_interview_booking_link(v_app.id, NULL, 'process_pending_reschedule_nudges');
    EXCEPTION WHEN OTHERS THEN
      v_dispatch := jsonb_build_object('success', false, 'failure_code', 'DISPATCH_ERROR', 'message', SQLERRM);
    END;

    IF COALESCE((v_dispatch->>'success')::boolean, false) IS NOT TRUE THEN
      -- Sem link governado não sai cutucão: mandar o literal do Google era o defeito da #1595.
      v_skipped := v_skipped || jsonb_build_object(
        'application_id', v_app.id,
        'failure_code', v_dispatch->>'failure_code',
        'gate_failed_code', v_dispatch->>'gate_failed_code'
      );
      CONTINUE;
    END IF;

    v_booking_url := v_dispatch->>'booking_url';

    -- Subtransação 2: envio + carimbo.
    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'interview_reschedule_nudge',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'reason', COALESCE(v_app.interview_reschedule_reason, '—'),
          'booking_url', v_booking_url
        ),
        p_metadata := jsonb_build_object(
          'source', 'process_pending_reschedule_nudges',
          'application_id', v_app.id,
          'reschedule_requested_at', v_app.interview_reschedule_requested_at,
          'last_nudged_at_before', v_app.interview_reschedule_last_nudged_at,
          'days_pending', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0,
          'link_kind', 'governed_token',
          'gate_mode', v_dispatch->>'gate_mode'
        )
      );

      UPDATE public.selection_applications
      SET interview_reschedule_last_nudged_at = now()
      WHERE id = v_app.id;

      v_nudges_sent := v_nudges_sent + 1;
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'gate_mode', v_dispatch->>'gate_mode',
        'days_since_request', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0
      );

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'nudges_sent', v_nudges_sent,
    'processed', v_processed,
    'skipped', v_skipped,
    'errors', v_errors,
    'run_at', now()
  );
END;
$function$;

-- ============================================================================
-- 9 — request_interview_booking_link_via_token: a porta do portal do candidato
-- ----------------------------------------------------------------------------
-- `PMIOnboardingPortal.tsx` fixava `const BOOKING_URL = 'https://calendar.app.google/...'` num
-- `href`. Era o quarto caminho do link cru, e o único do lado do CANDIDATO — quem clica ali nunca
-- passou por gate, nunca entrou no rodízio e nunca deixou linha de despacho.
--
-- Gate: o próprio token de onboarding (mesma validação de `get_application_enrichment_status`),
-- mais a exigência de a candidatura estar em fase de entrevista. Alcançável por anon/authenticated
-- de propósito — a página do portal é pública sob posse do token — e por isso NÃO devolve
-- `resolved_url` nem `token` cru: o candidato recebe apenas a URL governada.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.request_interview_booking_link_via_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token public.onboarding_tokens%ROWTYPE;
  v_app public.selection_applications%ROWTYPE;
  v_dispatch jsonb;
BEGIN
  SELECT * INTO v_token
  FROM public.onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'profile_completion' = ANY(scopes);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support interview booking', v_token.source_type;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_token.source_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  IF v_app.status NOT IN ('interview_pending', 'interview_scheduled', 'interview_noshow') THEN
    RETURN jsonb_build_object(
      'success', false,
      'failure_code', 'NOT_IN_INTERVIEW_STAGE',
      'application_status', v_app.status
    );
  END IF;

  v_dispatch := public._dispatch_interview_booking_link(v_app.id, NULL, 'pmi_onboarding_portal');

  -- O candidato nunca vê o destino cru nem o token isolado: só a URL governada.
  RETURN (v_dispatch - 'resolved_url' - 'token' - 'resolved_evaluator_id');
END;
$function$;

COMMENT ON FUNCTION public.request_interview_booking_link_via_token(text) IS
  '#1595 — porta do candidato no portal PMI: valida o token de onboarding (profile_completion), '
  'exige fase de entrevista e devolve a URL governada do agendamento. Nunca devolve o link cru do '
  'Google nem o token isolado.';

REVOKE ALL ON FUNCTION public.request_interview_booking_link_via_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_interview_booking_link_via_token(text) TO anon, authenticated, service_role;

-- ============================================================================
-- 10 — get_application_gate_attempts: o modo do gate tem de aparecer na leitura
-- ----------------------------------------------------------------------------
-- A superfície de leitura é vendida como diagnóstico de violação de gate (MCP + /admin/selection).
-- Com o #1595 ela precisa distinguir "passou os 3 gates" de "reusou a decisão anterior", senão o
-- skip auditado vira invisível na única tela que o leria — que é a definição de auditoria
-- decorativa que a #1594 ataca. `gate_mode` sai do payload como coluna própria.
-- Assinatura de RETORNO muda (coluna nova) → DROP + CREATE.
-- ============================================================================
DROP FUNCTION IF EXISTS public.get_application_gate_attempts(uuid);

CREATE OR REPLACE FUNCTION public.get_application_gate_attempts(p_application_id uuid)
RETURNS TABLE(
  attempt_id uuid,
  rpc_name text,
  caller_name text,
  gate_passed boolean,
  gate_mode text,
  gate_failed_code text,
  gate_failed_reason text,
  bypass_requested boolean,
  bypass_granted boolean,
  payload jsonb,
  attempted_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
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
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL
     AND NOT public.can_by_member(v_caller.id, 'manage_member'::text)
     AND NOT public.can_by_member(v_caller.id, 'view_internal_analytics'::text)
  THEN
    RAISE EXCEPTION 'Unauthorized: must be committee member or have manage_member/view_internal_analytics';
  END IF;

  RETURN QUERY
  SELECT ga.id AS attempt_id, ga.rpc_name,
         m.name AS caller_name,
         ga.gate_passed,
         -- Tentativas anteriores ao #1595 não têm gate_mode no payload; 'full' é o que elas foram.
         COALESCE(ga.payload->>'gate_mode', 'full') AS gate_mode,
         ga.gate_failed_code, ga.gate_failed_reason,
         ga.bypass_requested, ga.bypass_granted,
         ga.payload, ga.attempted_at
  FROM public.gate_attempts ga
  LEFT JOIN public.members m ON m.id = ga.caller_id
  WHERE ga.application_id = p_application_id
  ORDER BY ga.attempted_at DESC;
END;
$function$;

COMMENT ON FUNCTION public.get_application_gate_attempts(uuid) IS
  'Timeline de tentativas de gate por candidatura (schedule_interview + emissão de token). #1594: '
  'as recusas passam a existir aqui — antes disto a tabela só sabia mostrar sucesso, porque o '
  'INSERT morria no rollback do RAISE. #1595: gate_mode distingue full / reuse_prior / bypass.';

REVOKE ALL ON FUNCTION public.get_application_gate_attempts(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_application_gate_attempts(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
