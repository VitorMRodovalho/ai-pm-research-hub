-- #2188 — o despacho passa a registrar o que a agenda mostrava, e ganha uma sonda que mede isso.
--
-- O DEFEITO (medido em 04/09 e confirmado em 08/09): `_dispatch_interview_booking_link` resolve o
-- destino pelo rodizio, emite o token, grava a linha e dispara o e-mail SEM em nenhum ponto
-- perguntar se a agenda escolhida tem horario livre. 132 despachos produziram 6 reservas; uma das
-- quatro agendas estava fechada e recebeu 39 despachos de 22 candidaturas distintas.
--
-- A limitacao que esta migration ataca primeiro e a do item 3 da issue, e ela e a que trava as
-- outras: o log guarda a URL, nao o ESTADO dela. Sem isso nenhuma investigacao consegue
-- reconstruir o que o candidato viu, que foi exatamente onde a apuracao de 04/09 parou ("a
-- disponibilidade foi medida HOJE; nao ha como saber o que cada agenda mostrava na data de cada
-- despacho"). Enquanto "despachei para porta aberta" e "despachei para porta fechada" forem
-- indistinguiveis em todas as tabelas, o funil continua contando convite entregue onde o candidato
-- viu porta fechada.
--
-- O QUE ENTRA AQUI (fase 1 de 2):
--   1. `interview_agenda_probes` — uma sondagem por agenda, com quantos DIAS tinham horario na
--      janela renderizada. A leitura e feita fora do banco (endpoint interno com o binding
--      BROWSER, mesmo caminho do cert-pdf-render), porque a disponibilidade de um Google
--      appointment schedule so existe depois que a pagina monta em JS: `fetch` devolve 200 com a
--      agenda vazia. Medido em 08/09: 3.501 bytes de casca.
--   2. duas colunas em `selection_dispatch_url_log` com o que a sonda dizia NO MOMENTO do despacho.
--   3. o despacho passa a preencher essas colunas.
--   4. um leitor (`get_interview_agenda_health`), para a sonda nao virar mais um sinal gravado sem
--      ninguem que o consulte — o padrao que a #2130 registrou em outra familia.
--
-- O QUE NAO ENTRA (fase 2, PR seguinte): o rodizio PULAR agenda comprovadamente vazia (item 1), o
-- despacho FALHAR de forma visivel quando nenhuma agenda tem horario (item 2) e o alerta
-- operacional quando um avaliador ativo zera (item 4). Os tres dependem do dado que esta migration
-- comeca a produzir, e nenhum deles deve ser escrito contra uma tabela ainda vazia.
--
-- MITIGACAO JA APLICADA, FORA DE MIGRATION (e dado, nao estrutura): em 08/09 foi registrado um
-- `selection_interviewer_blackouts` para o avaliador cuja agenda esta fechada, pela RPC canonica
-- `set_interviewer_routing_block`, com auditoria `selection.routing_block_set`. Sem ele o proximo
-- despacho de researcher iria para a porta fechada: o avaliador era a posicao 1 do LRD.
--
-- ESTE ARQUIVO E O ESTADO FINAL. A aplicacao saiu em QUATRO tracking rows, duas delas correcao de
-- erro cometido durante a propria aplicacao, e as duas viraram comentario onde o erro moraria:
--   20260908182226  esta onda (tabela, colunas, escrita, leitor)
--   20260908182253  fix: no RETURN QUERY do leitor eu troquei a ordem de can_interview e cycle_id
--                   contra o RETURNS TABLE. Postgres so casa as colunas em tempo de EXECUCAO, entao
--                   `apply_migration` devolveu sucesso e a funcao teria falhado na primeira chamada.
--                   Sucesso do executor nao e pos-condicao: quem prova e chamar.
--   20260908182528  o despacho e o cron, que eu havia cortado da primeira transcricao sem perceber
--                   (`dispatch_le_a_sonda` = false na releitura). Ao reaplicar, o CREATE OR REPLACE
--                   recusou por eu ter omitido os DEFAULTs da assinatura viva.
--   20260908182606  fix: `REVOKE ... FROM PUBLIC` nao tira o EXECUTE que o Supabase concede
--                   nominalmente a `anon` e `authenticated`. Ver a nota na secao 3.
-- Se `supabase db push` rodar nesta arvore um dia, as quatro versoes ja constam de
-- `schema_migrations` e este arquivo nao deve ser reaplicado.

-- ---------------------------------------------------------------------------
-- 1. A tabela de sondagens
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.interview_agenda_probes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- A URL e a chave de juncao com o log de despacho, porque e ela que o candidato recebe. Duas
  -- pessoas podem compartilhar um mesmo schedule, e um mesmo dono pode ter dois links curtos
  -- diferentes apontando para o mesmo schedule (medido: o GP tem exatamente isso).
  booking_url text NOT NULL,

  -- Dono e ciclo sao CONTEXTO, nao chave: uma URL de fallback do ciclo nao tem dono, e uma URL
  -- global de membro nao pertence a um ciclo. Por isso os dois sao anulaveis e nenhum entra no
  -- indice de leitura.
  member_id uuid REFERENCES public.members(id) ON DELETE SET NULL,
  cycle_id uuid REFERENCES public.selection_cycles(id) ON DELETE SET NULL,

  probed_at timestamptz NOT NULL DEFAULT now(),

  -- A janela que a pagina renderizou. Sem ela, `days_open = 0` e ambiguo entre "a agenda esta
  -- fechada" e "a sonda olhou para um periodo curto".
  window_start date,
  window_end date,

  -- days_open = dias com horario na janela. E o sinal estavel: a grade do mes marca cada dia com
  -- "no available times" ou nao, numa unica renderizacao e sem clicar em nada.
  days_open integer,
  -- slots_visible = horarios clicaveis na faixa de dias visivel. Mais fino e mais volatil; serve
  -- para diagnostico, nao para decidir.
  slots_visible integer,

  -- `ok` separa "a agenda esta vazia" de "a sonda nao conseguiu ler". Sem essa coluna, uma falha de
  -- rede vira agenda fechada e o rodizio da fase 2 excluiria um avaliador por engano.
  ok boolean NOT NULL DEFAULT false,
  error text,

  organization_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- A leitura quente e sempre "a sondagem mais recente desta URL".
CREATE INDEX IF NOT EXISTS interview_agenda_probes_url_recente_idx
  ON public.interview_agenda_probes (booking_url, probed_at DESC);

ALTER TABLE public.interview_agenda_probes ENABLE ROW LEVEL SECURITY;

-- Mesmo desenho de `selection_interviewer_blackouts` (#1590 onda B): a tabela nao tem caminho
-- direto, nem de leitura nem de escrita. Quem le e a RPC SECDEF abaixo; quem escreve e o endpoint
-- interno, com service_role.
DROP POLICY IF EXISTS rpc_only_deny_all ON public.interview_agenda_probes;
CREATE POLICY rpc_only_deny_all ON public.interview_agenda_probes FOR ALL USING (false);

COMMENT ON TABLE public.interview_agenda_probes IS
  '#2188 fase 1: uma linha por sondagem de agenda de agendamento de entrevista. Preenchida pelo endpoint interno /api/internal/agenda-availability-probe, que renderiza o link com o binding BROWSER porque a disponibilidade de um Google appointment schedule so existe depois do JS montar. days_open=0 com ok=true e agenda fechada; ok=false e sonda cega, e as duas NAO podem ser lidas como a mesma coisa.';

COMMENT ON COLUMN public.interview_agenda_probes.ok IS
  'false = a sonda nao conseguiu ler a pagina. Distingue agenda fechada de sonda cega: sem isso uma falha de rede excluiria um avaliador do rodizio na fase 2.';

-- ---------------------------------------------------------------------------
-- 2. O log de despacho passa a guardar o estado da agenda
-- ---------------------------------------------------------------------------

ALTER TABLE public.selection_dispatch_url_log
  ADD COLUMN IF NOT EXISTS agenda_days_open integer,
  ADD COLUMN IF NOT EXISTS agenda_probed_at timestamptz;

COMMENT ON COLUMN public.selection_dispatch_url_log.agenda_days_open IS
  '#2188: quantos dias com horario a sonda via nesta agenda no momento do despacho. NULL = nao havia sondagem (toda linha anterior a 08/09/2026, e qualquer despacho cuja agenda nunca foi sondada). 0 = despachamos para porta fechada. Nao confundir NULL com 0.';

COMMENT ON COLUMN public.selection_dispatch_url_log.agenda_probed_at IS
  '#2188: quando aquela sondagem foi feita. Uma sondagem velha e um dado velho: quem ler precisa poder medir a distancia entre a sonda e o despacho.';

-- ---------------------------------------------------------------------------
-- 3. A escrita da sonda (chamada pelo endpoint interno, com service_role)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_interview_agenda_probe(
  p_booking_url text,
  p_days_open integer DEFAULT NULL,
  p_slots_visible integer DEFAULT NULL,
  p_window_start date DEFAULT NULL,
  p_window_end date DEFAULT NULL,
  p_ok boolean DEFAULT false,
  p_error text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url text := nullif(trim(COALESCE(p_booking_url, '')), '');
  v_member uuid;
  v_cycle uuid;
  v_org uuid;
  v_id uuid;
BEGIN
  IF v_url IS NULL THEN
    RETURN jsonb_build_object('error', 'booking_url is required');
  END IF;

  -- Uma sondagem ok NAO pode chegar sem numero: seria uma linha que afirma ter medido e nao diz o
  -- que mediu, e o leitor da fase 2 a trataria como agenda fechada.
  IF p_ok AND p_days_open IS NULL THEN
    RETURN jsonb_build_object('error', 'ok=true requires days_open');
  END IF;

  -- Dono e ciclo sao resolvidos AQUI, a partir da configuracao vigente, e nao vem do chamador: o
  -- endpoint sabe a URL que renderizou, nao a quem ela pertence, e deixar isso do lado de fora
  -- abriria caminho para atribuir uma sondagem ao avaliador errado.
  SELECT sc.member_id, sc.cycle_id, c.organization_id
  INTO v_member, v_cycle, v_org
  FROM public.selection_committee sc
  JOIN public.selection_cycles c ON c.id = sc.cycle_id
  WHERE sc.interview_booking_url = v_url
  ORDER BY (c.status = 'open') DESC
  LIMIT 1;

  IF v_member IS NULL THEN
    SELECT m.id INTO v_member FROM public.members m WHERE m.interview_booking_url = v_url LIMIT 1;
  END IF;

  IF v_cycle IS NULL THEN
    SELECT c.id, c.organization_id INTO v_cycle, v_org
    FROM public.selection_cycles c
    WHERE c.interview_booking_url = v_url
    ORDER BY (c.status = 'open') DESC
    LIMIT 1;
  END IF;

  INSERT INTO public.interview_agenda_probes (
    booking_url, member_id, cycle_id,
    window_start, window_end, days_open, slots_visible, ok, error, organization_id
  ) VALUES (
    v_url, v_member, v_cycle,
    p_window_start, p_window_end, p_days_open, p_slots_visible, COALESCE(p_ok, false), p_error, v_org
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'success', true,
    'probe_id', v_id,
    'booking_url', v_url,
    'member_id', v_member,
    'cycle_id', v_cycle,
    'days_open', p_days_open,
    'ok', COALESCE(p_ok, false)
  );
END;
$$;

-- `CREATE FUNCTION` nasce com EXECUTE para PUBLIC. Nenhuma funcao desta migration pode ficar assim.
-- `FROM PUBLIC` NAO basta: o Supabase concede EXECUTE nominalmente a `anon` e `authenticated` em
-- funcao nova do schema public. Medido em 08/09 depois de aplicar: as duas apareceram com anon.
-- Na escrita isso era exploravel (uma sondagem `ok=true, days_open=0` forjada e o que a fase 2 le
-- para tirar um avaliador do rodizio). O REVOKE tem de NOMEAR os papeis.
REVOKE ALL ON FUNCTION public.record_interview_agenda_probe(text, integer, integer, date, date, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_interview_agenda_probe(text, integer, integer, date, date, boolean, text) TO service_role;

COMMENT ON FUNCTION public.record_interview_agenda_probe(text, integer, integer, date, date, boolean, text) IS
  '#2188: grava uma sondagem de agenda. Chamada pelo endpoint interno /api/internal/agenda-availability-probe com service_role. Resolve dono e ciclo pela configuracao vigente em vez de aceita-los do chamador.';

-- ---------------------------------------------------------------------------
-- 4. O leitor
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_interview_agenda_health()
RETURNS TABLE (
  booking_url text,
  member_id uuid,
  member_name text,
  cycle_id uuid,
  can_interview boolean,
  routing_blocked boolean,
  probed_at timestamptz,
  days_open integer,
  slots_visible integer,
  probe_ok boolean,
  probe_error text,
  dispatches_total bigint,
  bookings_total bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid;
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  WITH agendas AS (
    SELECT DISTINCT ON (url)
      url, m_id AS member_id, c_id AS cycle_id, pode
    FROM (
      SELECT sc.interview_booking_url AS url, sc.member_id AS m_id, sc.cycle_id AS c_id,
             sc.can_interview AS pode, 1 AS prio
      FROM public.selection_committee sc
      JOIN public.selection_cycles c ON c.id = sc.cycle_id
      WHERE sc.interview_booking_url IS NOT NULL AND c.status = 'open'
      UNION ALL
      SELECT m.interview_booking_url, m.id, NULL::uuid, NULL::boolean, 2
      FROM public.members m WHERE m.interview_booking_url IS NOT NULL
      UNION ALL
      SELECT c.interview_booking_url, NULL::uuid, c.id, NULL::boolean, 3
      FROM public.selection_cycles c
      WHERE c.interview_booking_url IS NOT NULL AND c.status = 'open'
    ) t
    ORDER BY url, prio
  )
  SELECT
    a.url,
    a.member_id,
    m.name,
    a.cycle_id,
    a.pode,
    EXISTS (
      SELECT 1 FROM public.selection_interviewer_blackouts b
      WHERE b.member_id = a.member_id AND b.cycle_id = a.cycle_id
        AND v_hoje >= b.starts_on AND (b.ends_on IS NULL OR v_hoje <= b.ends_on)
    ),
    p.probed_at, p.days_open, p.slots_visible, p.ok, p.error,
    (SELECT count(*) FROM public.selection_dispatch_url_log l WHERE l.resolved_url = a.url),
    (SELECT count(*) FROM public.selection_dispatch_url_log l
      WHERE l.resolved_url = a.url AND l.booked_at IS NOT NULL)
  FROM agendas a
  LEFT JOIN public.members m ON m.id = a.member_id
  LEFT JOIN LATERAL (
    SELECT pr.probed_at, pr.days_open, pr.slots_visible, pr.ok, pr.error
    FROM public.interview_agenda_probes pr
    WHERE pr.booking_url = a.url
    ORDER BY pr.probed_at DESC
    LIMIT 1
  ) p ON true
  ORDER BY a.url;
END;
$$;

REVOKE ALL ON FUNCTION public.get_interview_agenda_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_interview_agenda_health() TO authenticated, service_role;

COMMENT ON FUNCTION public.get_interview_agenda_health() IS
  '#2188: uma linha por agenda de agendamento configurada, com a sondagem mais recente e o par despachos/reservas. E o leitor que impede a sonda de virar sinal gravado sem consulta. Exige manage_member.';

-- ---------------------------------------------------------------------------
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
