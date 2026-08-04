-- #1584 — Opção A: tornar o token a única porta de agendamento de entrevista.
--
-- Contexto medido em 2026-08-05 (re-ancorado ao vivo antes desta DDL):
--   • tokens de escopo 'interview_booking' emitidos até hoje: 0 (de 99 linhas em onboarding_tokens).
--   • ACHADO NOVO desta sessão: validate_interview_booking_token NUNCA funcionou. O corpo compara
--     `WHERE id::text = v_token_row.source_id`, e `onboarding_tokens.source_id` é `uuid` DESDE A
--     CRIAÇÃO (mig 20260516200000, linha 249). Não existe `operator text = uuid`, então a função
--     levanta 42883 em runtime. Provado por sonda transacional (INSERT + chamada + RAISE de aborto,
--     zero resíduo): `RAISED 42883 -> operator does not exist: text = uuid`. O defeito passou 3 meses
--     invisível porque a porta nunca foi exercida — mesmo padrão de "gêmea morta" do #1584/#1589.
--   • o cron de cutoff pegaria 0 candidaturas hoje, então os 3 gates do candidato passam a valer
--     para o despacho com raio de explosão zero.
--
-- Raiz única dos três defeitos: não existe fonte compartilhada de resolução da URL. Ela vive inline
-- dentro de notify_selection_cutoff_approved (mig 20260805000030), e por isso a página fixou um
-- literal e o token nunca soube para onde apontar.
--
-- A1 resolve_interview_booking_url  — resolvedor PURO (sem escrita), reusável.
-- A2 _issue_interview_booking_token_core — gates do candidato sem gate de chamador (o cron não tem JWT).
-- A3 validate_interview_booking_token — corrige o 42883 e devolve booking_url.
-- A4 v_booking_url_base — nucleoia.vitormr.dev → nucleoia.pmigo.org.br.
-- A6 notify_selection_cutoff_approved — emite token e manda o link do token, não o link cru do Google.

-- ============================================================================
-- A1 — resolvedor compartilhado, PURO
-- ----------------------------------------------------------------------------
-- Extraído byte-a-byte da lógica viva de notify_selection_cutoff_approved (SPEC #348 v1 / #355),
-- com uma diferença deliberada: NÃO escreve em selection_dispatch_url_log. A escrita do log é ato do
-- DESPACHO, e quem despacha é o chamador. Manter a escrita aqui faria toda leitura de página
-- (validate_interview_booking_token) gravar uma linha de despacho e envenenar o round-robin LRD.
--
-- Precedência preservada: researcher → LRD sobre evaluator/lead com URL resolvível
-- (committee_override > member_global); qualquer outro role_applied → cycle_fallback.
-- `role IN ('evaluator','lead')` exclui observer por decisão do PM ratificada em 2026-05-24 (p251):
-- os 4 observer do ciclo vivo têm can_interview=true e URL NULL, e continuam FORA do rodízio.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.resolve_interview_booking_url(p_application_id uuid)
 RETURNS TABLE(url text, resolution_path text, evaluator_id uuid)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
  v_cycle record;
  v_url text;
  v_path text;
  v_evaluator uuid;
BEGIN
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  IF v_app.role_applied = 'researcher' THEN
    -- LRD: avaliador com o despacho mais antigo primeiro (NULLS FIRST = nunca usado fura a fila).
    -- Desempate por member_id para ordem estável.
    SELECT
      sc.member_id,
      COALESCE(sc.interview_booking_url, m.interview_booking_url),
      CASE
        WHEN sc.interview_booking_url IS NOT NULL THEN 'committee_override'
        ELSE 'member_global'
      END
    INTO v_evaluator, v_url, v_path
    FROM public.selection_committee sc
    JOIN public.members m ON m.id = sc.member_id
    LEFT JOIN LATERAL (
      SELECT MAX(l.dispatched_at) AS last_dispatched
      FROM public.selection_dispatch_url_log l
      WHERE l.cycle_id = v_cycle.id
        AND l.track = 'researcher'
        AND l.resolved_evaluator_id = sc.member_id
    ) lrd ON true
    WHERE sc.cycle_id = v_cycle.id
      AND sc.role IN ('evaluator', 'lead')
      AND sc.can_interview = true
      AND COALESCE(sc.interview_booking_url, m.interview_booking_url) IS NOT NULL
    ORDER BY lrd.last_dispatched NULLS FIRST, sc.member_id
    LIMIT 1;
  END IF;

  -- Fallback único: leader, role desconhecido, ou researcher sem avaliador resolvível.
  IF v_url IS NULL OR length(trim(v_url)) = 0 THEN
    v_url := v_cycle.interview_booking_url;
    v_path := 'cycle_fallback';
    v_evaluator := NULL;
  END IF;

  -- Sem URL em lugar nenhum devolve NULL, não exceção: quem despacha decide se isso é erro
  -- (notify levanta P0020) ou estado de erro de tela (a página do token).
  IF v_url IS NULL OR length(trim(v_url)) = 0 THEN
    v_url := NULL;
    v_path := NULL;
    v_evaluator := NULL;
  END IF;

  RETURN QUERY SELECT v_url, v_path, v_evaluator;
END;
$function$;

COMMENT ON FUNCTION public.resolve_interview_booking_url(uuid) IS
  '#1584 A1 — resolução compartilhada e PURA da URL de agendamento (researcher: LRD sobre '
  'evaluator/lead; demais: cycle_fallback). Não escreve em selection_dispatch_url_log: a escrita '
  'do log é ato do despacho, e fica no chamador.';

-- Função interna: nenhum chamador de fora do banco.
--
-- ⚠️ `FROM PUBLIC` sozinho NÃO fecha nada aqui. Este projeto tem
-- `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role`,
-- então função nova nasce com grant NOMINAL a anon e authenticated, e revogar de PUBLIC remove um
-- privilégio que PUBLIC nunca teve. Medido ao vivo nesta sessão: depois de `REVOKE ... FROM PUBLIC`
-- o ACL seguia `{postgres=X,anon=X,authenticated=X,service_role=X}`. Os papéis têm de ser nomeados.
REVOKE ALL ON FUNCTION public.resolve_interview_booking_url(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_interview_booking_url(uuid) TO service_role;

-- ============================================================================
-- A2 — core da emissão de token, sem gate de chamador
-- ----------------------------------------------------------------------------
-- A RPC pública exige auth.uid() + comitê lead/manage_platform. A notificação de cutoff roda por
-- pg_cron, SEM JWT, e por isso nunca conseguiu emitir token. O core carrega os TRÊS gates do
-- CANDIDATO (que é o que protege o candidato) e não decide autoridade — quem decide é o chamador.
-- p_bypass_granted já chega decidido; o core nunca chama can_by_member.
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
  -- A4: link para candidato usa o alias institucional, não o domínio pessoal.
  v_booking_url_base text := 'https://nucleoia.pmigo.org.br/interview-booking/';
  v_gate_payload jsonb;
BEGIN
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT COUNT(*) INTO v_eval_count
  FROM public.selection_evaluations WHERE application_id = p_application_id;

  v_gate_payload := jsonb_build_object(
    'has_consent', (v_app.consent_ai_analysis_at IS NOT NULL),
    'has_ai_analysis', (v_app.ai_analysis IS NOT NULL),
    'eval_count', v_eval_count,
    'objective_score_avg', v_app.objective_score_avg
  );

  IF NOT p_bypass_granted THEN
    IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, '_issue_interview_booking_token_core', p_caller_id, false,
        'P0001', 'GATE_NO_AI', p_bypass_requested, p_bypass_granted,
        v_gate_payload, v_app.organization_id
      );
      RAISE EXCEPTION 'GATE_NO_AI: candidate has no AI analysis.' USING ERRCODE = 'P0001';
    END IF;

    IF v_eval_count < 2 THEN
      PERFORM public._log_gate_attempt(
        p_application_id, '_issue_interview_booking_token_core', p_caller_id, false,
        'P0002', 'GATE_NO_PEER_REVIEW', p_bypass_requested, p_bypass_granted,
        v_gate_payload, v_app.organization_id
      );
      RAISE EXCEPTION 'GATE_NO_PEER_REVIEW: candidate has % peer evaluations.', v_eval_count USING ERRCODE = 'P0002';
    END IF;

    IF v_app.objective_score_avg IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, '_issue_interview_booking_token_core', p_caller_id, false,
        'P0003', 'GATE_NO_SCORE', p_bypass_requested, p_bypass_granted,
        v_gate_payload, v_app.organization_id
      );
      RAISE EXCEPTION 'GATE_NO_SCORE: objective_score_avg not computed.' USING ERRCODE = 'P0003';
    END IF;
  END IF;

  -- ACHADO NOVO 2: a emissão também estava morta. O corpo original chamava `gen_random_bytes(32)`
  -- sem qualificar, sob `SET search_path TO 'public'`, e pgcrypto vive no schema `extensions` —
  -- 42883 em toda chamada. Todas as RPCs de token que de fato produziram as 99 linhas vivas
  -- (dispatch_consent_nudge, dispatch_pending_welcomes, request_account_claim,
  -- request_secondary_email_verification) qualificam como `extensions.gen_random_bytes`.
  -- Ou seja: a porta governada tinha DOIS defeitos fatais independentes, um na emissão e um na
  -- validação, e ambos ficaram invisíveis porque ninguém nunca atravessou a porta.
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
    'gate_bypassed', p_bypass_granted
  );
END;
$function$;

COMMENT ON FUNCTION public._issue_interview_booking_token_core(uuid, boolean, uuid, boolean) IS
  '#1584 A2 — emissão de token com os 3 gates do CANDIDATO e sem gate de chamador. Permite que a '
  'notificação de cutoff (pg_cron, sem JWT) emita token. Autoridade é decidida pelo chamador; '
  'p_bypass_granted já chega decidido.';

-- Mesma armadilha de ACL da A1, e aqui o custo de errar é maior: esta função é SECDEF e não tem
-- gate de chamador por construção (é o que permite ao cron sem JWT emitir token). Alcançável por
-- anon, ela seria uma cunhadora de token de agendamento sem sessão — classe da #1592.
REVOKE ALL ON FUNCTION public._issue_interview_booking_token_core(uuid, boolean, uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._issue_interview_booking_token_core(uuid, boolean, uuid, boolean) TO service_role;

-- ============================================================================
-- A2 (cont.) — a RPC pública mantém o gate de chamador e delega ao core
-- Assinatura inalterada (uuid, boolean) → jsonb, logo CREATE OR REPLACE basta.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.issue_interview_booking_token(p_application_id uuid, p_bypass_gate boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_can_bypass boolean;
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

  -- Gates do candidato + emissão vivem no core, fonte única com o caminho do cron.
  RETURN public._issue_interview_booking_token_core(
    p_application_id, v_can_bypass, v_caller.id, p_bypass_gate
  );
END;
$function$;

-- ============================================================================
-- A3 — validate_interview_booking_token: corrige o 42883 e devolve booking_url
-- ----------------------------------------------------------------------------
-- (1) `id::text = v_token_row.source_id` → `id = v_token_row.source_id`. source_id é uuid; a
--     comparação text = uuid não tem operador e derrubava TODA chamada com 42883.
-- (2) booking_url passa a vir da MESMA fonte que alimenta selection_dispatch_url_log.
--     Lê a última linha de despacho da candidatura em vez de re-resolver ao vivo: re-resolver faria
--     o LRD escolher outro avaliador entre dois acessos da MESMA página, e o candidato veria destinos
--     diferentes a cada refresh. O resolvedor puro fica como fallback para token emitido fora do
--     fluxo de despacho.
-- Assinatura inalterada (text) → jsonb.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.validate_interview_booking_token(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_token_row record;
  v_app record;
  v_booking_url text;
  v_resolution_path text;
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 THEN
    RAISE EXCEPTION 'Invalid token format';
  END IF;

  SELECT * INTO v_token_row FROM public.onboarding_tokens WHERE token = p_token;
  IF v_token_row IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF v_token_row.expires_at < now() THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF NOT (v_token_row.scopes @> ARRAY['interview_booking']::text[]) THEN
    RAISE EXCEPTION 'Token does not have interview_booking scope';
  END IF;

  -- Increment access tracking
  UPDATE public.onboarding_tokens
  SET access_count = COALESCE(access_count, 0) + 1,
      last_accessed_at = now()
  WHERE token = p_token;

  -- Lookup application (read-only fields safe for anon)
  SELECT id, applicant_name, first_name, email, status
  INTO v_app FROM public.selection_applications
  WHERE id = v_token_row.source_id;

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- Destino do agendamento: o que foi efetivamente despachado para ESTA candidatura.
  SELECT l.resolved_url, l.resolution_path
  INTO v_booking_url, v_resolution_path
  FROM public.selection_dispatch_url_log l
  WHERE l.application_id = v_app.id
  ORDER BY l.dispatched_at DESC
  LIMIT 1;

  -- Fallback: token emitido fora do fluxo de despacho (sem linha de log).
  IF v_booking_url IS NULL THEN
    SELECT r.url, r.resolution_path
    INTO v_booking_url, v_resolution_path
    FROM public.resolve_interview_booking_url(v_app.id) r;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'first_name', COALESCE(NULLIF(trim(v_app.first_name), ''), split_part(v_app.applicant_name, ' ', 1)),
    'application_status', v_app.status,
    'expires_at', v_token_row.expires_at,
    'access_count', COALESCE(v_token_row.access_count, 0) + 1,
    'booking_url', v_booking_url,
    'resolution_path', v_resolution_path
  );
END;
$function$;

-- ============================================================================
-- A1 (cont.) + A6 — notify_selection_cutoff_approved passa a usar o resolvedor
-- compartilhado e a mandar o LINK DO TOKEN, não o link cru do Google.
-- ----------------------------------------------------------------------------
-- Base: corpo VIVO (pg_get_functiondef, versão p282_411), preservando o bypass de cron do ADR-0028,
-- a idempotência de disparo único, o gate #1450 e a linha de auditoria.
--
-- Mudança de comportamento deliberada: o despacho agora atravessa os TRÊS gates do candidato do
-- core, não só o de nota objetiva. Raio de explosão medido antes de aplicar: o predicado do cron
-- (_selection_cutoff_pending_cron) devolve 0 candidaturas hoje, e nenhuma delas falharia P0001/2/3.
-- O cron processa em subtransação por linha, então um gate recusado conta erro e não aborta a volta.
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
  -- v1 routing locals (#355) — agora vindos do resolvedor compartilhado (#1584 A1)
  v_resolved_url text;
  v_resolution_path text;
  v_resolved_evaluator_id uuid;
  -- p282 #411 W2a: cron/service context flag (ADR-0028)
  v_is_cron boolean := false;
  -- #1584 A6: o link que vai para o candidato é o do token, não o do Google
  v_token_result jsonb;
  v_token_url text;
BEGIN
  -- Authority gate — same as dispatch_peer_review_invitations (committee lead OR
  -- manage_member). PM may use this manually; the Wave 2a/2b crons use the ADR-0028
  -- cron bypass below.
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    -- ADR-0028 cron/service bypass: a no-JWT (pg_cron) or service_role session is the
    -- automated dispatch path. An authenticated ghost (JWT present, no members row) has a
    -- non-null auth.uid() + present claims, so it skips this branch and RAISEs below.
    IF current_setting('request.jwt.claims', true) IS NULL OR auth.role() = 'service_role' THEN
      v_is_cron := true;  -- v_caller stays NULL → actor_id NULL (system row)
    ELSE
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- Per-caller authority gate — skipped in cron/service context (the service_role-only
  -- cron wrapper is itself the gate).
  IF NOT v_is_cron THEN
    SELECT * INTO v_committee
    FROM public.selection_committee
    WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

    IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
      RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
    END IF;
  END IF;

  -- Idempotency: single-fire per application
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

  -- #1450 — objective-phase gate. NEVER dispatch the interview-scheduling invite before the
  -- candidate has cleared the objective phase. Mantido explícito aqui (além do P0003 do core)
  -- porque a mensagem nomeia o #1450 e é o que o teste de contrato daquele arco afirma.
  IF v_app.objective_score_avg IS NULL THEN
    RAISE EXCEPTION 'GATE_NO_SCORE: objective_score_avg not computed for application % — the interview-scheduling invite must not be sent before the objective phase completes (#1450).', p_application_id
      USING ERRCODE = 'P0003';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- ============================================================
  -- #1584 A1: resolução via fonte compartilhada (SPEC #348 v1 / #355 preservada).
  -- Era inline aqui; agora é resolve_interview_booking_url, que a página do token
  -- também enxerga. Sem fonte compartilhada, o literal volta a nascer na tela.
  -- ============================================================
  SELECT r.url, r.resolution_path, r.evaluator_id
  INTO v_resolved_url, v_resolution_path, v_resolved_evaluator_id
  FROM public.resolve_interview_booking_url(p_application_id) r;

  -- Single gate: raise only if BOTH per-evaluator and cycle URLs are absent.
  IF v_resolved_url IS NULL OR length(trim(v_resolved_url)) = 0 THEN
    RAISE EXCEPTION 'CUTOFF_NO_BOOKING_URL: no resolvable booking URL for application % (cycle %, role %); set selection_cycles.interview_booking_url or seed selection_committee with per-evaluator URLs',
      p_application_id, v_app.cycle_id, v_app.role_applied USING ERRCODE = 'P0020';
  END IF;

  -- #1584 A6 — emitir o token ANTES de gravar o log de despacho e de mandar o e-mail.
  -- Se um dos três gates do candidato recusar, a exceção desfaz tudo desta transação e nenhum
  -- e-mail sai: o despacho passa a herdar os gates da porta governada em vez de contorná-los.
  -- Contexto de cron não tem auth.uid(); o core não exige chamador (v_caller pode ser NULL).
  v_token_result := public._issue_interview_booking_token_core(
    p_application_id, false, v_caller.id, false
  );
  v_token_url := v_token_result->>'booking_url';

  -- Dispatch audit row — captures which URL + which precedence path produced it.
  -- Becomes the LRD lookback source for subsequent researcher-track dispatches in the
  -- same cycle, E a fonte que validate_interview_booking_token lê para montar a página.
  INSERT INTO public.selection_dispatch_url_log (
    application_id,
    cycle_id,
    track,
    resolved_url,
    resolution_path,
    resolved_evaluator_id,
    organization_id
  ) VALUES (
    p_application_id,
    v_app.cycle_id,
    v_app.role_applied,
    v_resolved_url,
    v_resolution_path,
    v_resolved_evaluator_id,
    v_app.organization_id
  );

  -- Threshold sanity (advisory).
  SELECT count(*)::int INTO v_objective_done
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'objective';

  v_first_name := COALESCE(
    NULLIF(trim(v_app.first_name), ''),
    NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
    'candidato(a)'
  );

  -- Dispatch via campaign_send_one_off — #1584 A6: passa o link do TOKEN.
  -- O template 'selection_cutoff_approved' já usa {{interview_booking_url}} e não tem link cru
  -- embutido (conferido ao vivo), então só o VALOR muda.
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

  -- Mark idempotency post-send.
  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = now(),
      updated_at = now()
  WHERE id = p_application_id;

  -- Audit log — canonical action preserved; metadata gains dispatch_source (p282 W2a).
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
      'token_prefix', left(COALESCE(v_token_result->>'token', ''), 8),
      'link_kind', 'governed_token',
      'rpc_version', 'p1584_a1_a6'
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
    'token_expires_at', v_token_result->>'expires_at'
  );
END;
$function$;
