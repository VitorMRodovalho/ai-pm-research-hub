-- #2188 — o despacho grava o estado da agenda, e o cron da sonda.
--
-- POR QUE ESTE ARQUIVO EXISTE SEPARADO. Eu cortei estas duas secoes da primeira transcricao para
-- `apply_migration` sem perceber, e so descobri relendo o estado: `prosrc LIKE '%interview_agenda_probes%'`
-- vinha `false` e `cron.job` vinha vazio. Confirmacao do executor nao prova a pos-condicao.
--
-- Ao reaplicar, o `CREATE OR REPLACE` RECUSOU com "cannot remove parameter defaults from existing
-- function": a assinatura viva tem `p_caller_id uuid DEFAULT NULL` e `p_source text DEFAULT NULL`
-- (`pg_get_function_arguments`), e omitir um default nao o preserva, faz o Postgres barrar. Quem
-- chama com um argumento so depende deles.

-- 5. O despacho grava o estado da agenda
-- ---------------------------------------------------------------------------
-- Corpo transcrito do vivo (pg_proc) em 08/09/2026, com a leitura da sonda e as duas colunas novas
-- no INSERT como unica diferenca. Atributos preservados: SECURITY DEFINER, VOLATILE,
-- search_path=public. O ACL sobrevive ao CREATE OR REPLACE (postgres + service_role, sem PUBLIC).

-- Os DEFAULTs sao parte da assinatura viva (`pg_get_function_arguments`, medido em 08/09): omiti-los
-- num CREATE OR REPLACE nao os mantem, faz o Postgres RECUSAR com "cannot remove parameter defaults
-- from existing function". Quem chama com um argumento so depende deles.
CREATE OR REPLACE FUNCTION public._dispatch_interview_booking_link(
  p_application_id uuid,
  p_caller_id uuid DEFAULT NULL::uuid,
  p_source text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  -- #2188: o que a sonda dizia sobre a agenda escolhida, no momento deste despacho.
  v_agenda_days_open int;
  v_agenda_probed_at timestamptz;
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

  -- #2188: so a sondagem que CONSEGUIU ler entra aqui. Uma sonda cega (ok=false) deixa as duas
  -- colunas nulas, que e a leitura honesta: nao sabemos o que o candidato viu.
  SELECT pr.days_open, pr.probed_at
  INTO v_agenda_days_open, v_agenda_probed_at
  FROM public.interview_agenda_probes pr
  WHERE pr.booking_url = v_url AND pr.ok
  ORDER BY pr.probed_at DESC
  LIMIT 1;

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
    booking_token_md5,
    agenda_days_open, agenda_probed_at
  ) VALUES (
    p_application_id, v_app.cycle_id, v_app.role_applied,
    v_url, v_path, v_evaluator, v_app.organization_id,
    -- #1590 onda D: hash, nunca o token. Ver cabeçalho.
    CASE WHEN v_token IS NOT NULL THEN md5(v_token) ELSE NULL END,
    v_agenda_days_open, v_agenda_probed_at
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
    'dispatch_source', p_source,
    -- #2188: o retorno tambem carrega o estado, para quem chama poder decidir sem reconsultar.
    'agenda_days_open', v_agenda_days_open,
    'agenda_probed_at', v_agenda_probed_at
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. O agendamento da sonda
-- ---------------------------------------------------------------------------
-- 4 vezes ao dia. O denominador e pequeno (4 agendas configuradas, medido em 08/09), e a janela
-- que importa e "a agenda estava aberta quando despachamos", nao "esta aberta agora": sondar de
-- hora em hora nao compraria precisao, so custo de renderizacao.
--
-- O segredo compartilhado e o mesmo mecanismo do cert-pdf-render: GUC de banco
-- `app.agenda_probe_internal_secret`, casado com o wrangler secret AGENDA_PROBE_INTERNAL_SECRET.
-- Sem o GUC configurado o cron nao chama nada e avisa, em vez de bater num 401 quatro vezes ao dia.

SELECT cron.unschedule('interview-agenda-probe')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'interview-agenda-probe');

SELECT cron.schedule(
  'interview-agenda-probe',
  '17 */6 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://nucleoia.vitormr.dev/api/internal/agenda-availability-probe',
    body := '{"source":"pg_cron"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || COALESCE(current_setting('app.agenda_probe_internal_secret', true), '')
    ),
    timeout_milliseconds := 120000
  )
  WHERE COALESCE(current_setting('app.agenda_probe_internal_secret', true), '') <> '';
  $cron$
);
