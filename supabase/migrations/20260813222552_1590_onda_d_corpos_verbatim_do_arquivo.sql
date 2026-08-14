-- ============================================================================
-- #1590 onda D — os quatro corpos, VERBATIM do arquivo da onda
-- ============================================================================
--
-- Esta migration não muda comportamento nenhum. Ela existe porque a primeira aplicação da onda D
-- (`20260813220605`) foi feita com os comentários INTERNOS das funções removidos, e comentário
-- dentro de `$function$...$function$` faz parte de `prosrc` — portanto entra no hash de corpo do
-- Phase C. As quatro funções passaram a divergir da própria captura, e o guard
-- `1590-onda-d-a-tentativa-que-falha-deixa-linha` acusou, corretamente, deriva.
--
-- O conserto é reaplicar os corpos exatamente como estão no arquivo, para que o registro e o corpo
-- vivo voltem a ser a mesma coisa. Confirmado depois: os 4 md5 vivos batem com a captura.
--
-- A lição, para quem aplicar DDL por MCP: o payload do `apply_migration` tem de ser o arquivo, e
-- não uma versão "limpa" dele. Enxugar comentário na hora de aplicar é o mesmo que editar a
-- migration depois de aplicada.
--
-- Os blocos abaixo são extraídos do arquivo da onda sem uma letra de diferença.

CREATE OR REPLACE FUNCTION public._dispatch_interview_booking_link(p_application_id uuid, p_caller_id uuid DEFAULT NULL::uuid, p_source text DEFAULT NULL::text)
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
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_capazes int;
  v_bloqueados int;
  v_token text;
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

  v_token := v_token_result->>'token';

  -- #1590 onda D — aposentar a oferta anterior ANTES de inserir a nova.
  -- Um reenvio (remarcação, cutucão, resgate) não é o mesmo candidato falhando duas vezes: é a
  -- mesma pergunta feita de novo. Sem este bloco, cada reenvio deixaria para trás uma linha
  -- eternamente "ofertada e nunca reservada", e o funil contaria a mesma pessoa N vezes no
  -- numerador do fracasso. A ordem importa — superseder DEPOIS do INSERT apagaria a linha nova.
  UPDATE public.selection_dispatch_url_log
  SET superseded_at = now()
  WHERE application_id = p_application_id
    AND instrumented
    AND booked_at IS NULL
    AND superseded_at IS NULL;

  -- Linha de despacho: é ela que `validate_interview_booking_token` lê para montar a página, e é
  -- ela que alimenta o lookback do LRD. Sem esta linha o reagendamento continuaria fora do rodízio
  -- e fora do log, que é metade do achado da #1595.
  INSERT INTO public.selection_dispatch_url_log (
    application_id, cycle_id, track,
    resolved_url, resolution_path, resolved_evaluator_id, organization_id,
    booking_token_md5
  ) VALUES (
    p_application_id, v_app.cycle_id, v_app.role_applied,
    v_url, v_path, v_evaluator, v_app.organization_id,
    -- #1590 onda D: hash, nunca o token. Ver cabeçalho.
    CASE WHEN v_token IS NOT NULL THEN md5(v_token) ELSE NULL END
  );

  -- #1590 onda B: o desvio para a agenda institucional é EVENTO, não estado normal, na trilha
  -- researcher. Roda depois do log de despacho para registrar só o que de fato foi enviado.
  IF v_app.role_applied = 'researcher' AND v_path = 'cycle_fallback' THEN
    WITH capaz AS (
      SELECT sc.member_id
      FROM public.selection_committee sc
      JOIN public.members m ON m.id = sc.member_id
      WHERE sc.cycle_id = v_app.cycle_id
        AND sc.role IN ('evaluator', 'lead')
        AND sc.can_interview = true
        AND COALESCE(sc.interview_booking_url, m.interview_booking_url) IS NOT NULL
    )
    SELECT
      count(*),
      count(*) FILTER (WHERE EXISTS (
        SELECT 1
        FROM public.selection_interviewer_blackouts b
        WHERE b.cycle_id = v_app.cycle_id
          AND b.member_id = capaz.member_id
          AND v_hoje >= b.starts_on
          AND (b.ends_on IS NULL OR v_hoje <= b.ends_on)
      ))
    INTO v_capazes, v_bloqueados
    FROM capaz;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (
      p_caller_id,
      'selection.routing_fell_back_to_cycle',
      'selection_application',
      p_application_id,
      jsonb_build_object(
        'cycle_id', v_app.cycle_id,
        'dispatch_source', p_source,
        'committee_routable', v_capazes,
        'blocked_by_window', v_bloqueados,
        'local_date', v_hoje
      )
    );
  END IF;

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
  v_stamped_id uuid;
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

  -- #1590 onda D — o carimbo de ABERTURA na linha de despacho.
  -- Preferência pela linha de onde ESTE token saiu; recuo para a mais recente instrumentada.
  -- Se não houver linha instrumentada nenhuma, não carimba: um token anterior à instrumentação
  -- não deve inventar medição numa linha que não foi medida.
  SELECT l.id INTO v_stamped_id
  FROM public.selection_dispatch_url_log l
  WHERE l.application_id = v_app.id
    AND l.instrumented
    AND l.booking_token_md5 = md5(p_token)
  ORDER BY l.dispatched_at DESC
  LIMIT 1;

  IF v_stamped_id IS NULL THEN
    SELECT l.id INTO v_stamped_id
    FROM public.selection_dispatch_url_log l
    WHERE l.application_id = v_app.id AND l.instrumented
    ORDER BY l.dispatched_at DESC
    LIMIT 1;
  END IF;

  IF v_stamped_id IS NOT NULL THEN
    UPDATE public.selection_dispatch_url_log
    SET open_count      = COALESCE(open_count, 0) + 1,
        first_opened_at = COALESCE(first_opened_at, now()),
        last_opened_at  = now()
    WHERE id = v_stamped_id;
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

CREATE OR REPLACE FUNCTION public.trg_close_dispatch_on_interview()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_target uuid;
BEGIN
  SELECT l.id INTO v_target
  FROM public.selection_dispatch_url_log l
  WHERE l.application_id = NEW.application_id
    AND l.instrumented
    AND l.booked_at IS NULL
    AND l.superseded_at IS NULL
  ORDER BY l.dispatched_at DESC
  LIMIT 1;

  -- Nenhuma oferta aberta: entrevista criada sem despacho instrumentado (agendamento manual, ou
  -- despacho anterior à instrumentação). Não inventar vínculo — o silêncio aqui é a resposta certa.
  IF v_target IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.selection_dispatch_url_log
  SET booked_at = now(), booked_interview_id = NEW.id
  WHERE id = v_target;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_interview_booking_funnel(p_cycle_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_cycle record;
  v_can_manage boolean;
  v_is_committee boolean;
  v_rows json;
BEGIN
  SELECT m.id, m.designations, m.is_superadmin INTO v_caller
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  SELECT c.id, c.cycle_code, c.status INTO v_cycle
  FROM public.selection_cycles c WHERE c.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN json_build_object('error', 'Cycle not found');
  END IF;

  v_is_committee := EXISTS (
    SELECT 1 FROM public.selection_committee sc
    WHERE sc.cycle_id = p_cycle_id AND sc.member_id = v_caller.id
  );
  v_can_manage := public.can_by_member(v_caller.id, 'manage_member');

  IF NOT (
    v_is_committee
    OR v_can_manage
    OR COALESCE(v_caller.is_superadmin, false)
    OR ('sponsor' = ANY(COALESCE(v_caller.designations, '{}'::text[])))
  ) THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT COALESCE(json_agg(t.obj ORDER BY t.dispatched_at DESC), '[]'::json) INTO v_rows
  FROM (
    SELECT
      l.dispatched_at,
      json_build_object(
        'dispatch_id', l.id,
        'application_id', l.application_id,
        'applicant_name', a.applicant_name,
        'track', l.track,
        'resolution_path', l.resolution_path,
        'resolved_evaluator_id', l.resolved_evaluator_id,
        'dispatched_at', l.dispatched_at,
        'first_opened_at', l.first_opened_at,
        'last_opened_at', l.last_opened_at,
        'open_count', COALESCE(l.open_count, 0),
        'booked_at', l.booked_at,
        'superseded_at', l.superseded_at,
        'window_ends_at', w.window_ends_at,
        'outcome', CASE
          WHEN NOT l.instrumented              THEN 'pre_instrumentation'
          WHEN l.booked_at IS NOT NULL         THEN 'booked'
          WHEN l.superseded_at IS NOT NULL     THEN 'superseded'
          WHEN COALESCE(l.open_count, 0) > 0
               AND now() > w.window_ends_at    THEN 'opened_never_booked'
          WHEN COALESCE(l.open_count, 0) > 0   THEN 'opened_waiting'
          WHEN now() > w.window_ends_at        THEN 'never_opened_expired'
          ELSE                                      'never_opened_waiting'
        END
      ) AS obj
    FROM public.selection_dispatch_url_log l
    JOIN public.selection_applications a ON a.id = l.application_id
    CROSS JOIN LATERAL (
      -- A janela é a validade do PRÓPRIO token desta oferta. Sem o hash não há como saber qual
      -- token era, e recair sobre "o token mais recente da candidatura" daria a esta oferta a
      -- validade de outra — por isso o recuo é o prazo nominal, não o token do vizinho.
      SELECT COALESCE(
        CASE WHEN l.booking_token_md5 IS NOT NULL THEN (
          SELECT max(ot.expires_at) FROM public.onboarding_tokens ot
           WHERE ot.source_id = l.application_id
             AND ot.scopes @> ARRAY['interview_booking']::text[]
             AND md5(ot.token) = l.booking_token_md5
        ) END,
        l.dispatched_at + interval '14 days'
      ) AS window_ends_at
    ) w
    WHERE l.cycle_id = p_cycle_id
  ) t;

  RETURN json_build_object(
    'success', true,
    'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code,
    'dispatches', v_rows,
    -- Os totais saem do JSON JÁ MONTADO, não de um segundo predicado: duas implementações da
    -- mesma pergunta divergem, e foi assim que a taxa de presença passou meses dizendo 100%.
    'totals', COALESCE((
      SELECT json_object_agg(o, n) FROM (
        SELECT e->>'outcome' AS o, count(*) AS n
        FROM json_array_elements(v_rows) e GROUP BY 1
      ) z
    ), '{}'::json),
    'measured_at', now()
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_interview_booking_funnel(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.trg_close_dispatch_on_interview() FROM PUBLIC, anon;
