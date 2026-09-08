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
-- O QUE A ONDA ENTREGA (fase 1 de 2; os itens 3 e 4 saem nos arquivos irmaos listados no fim):
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
-- A ONDA SAIU EM QUATRO ARQUIVOS, um por tracking row, porque saiu em quatro `apply_migration` e
-- DUAS delas foram correcao de erro que eu cometi durante a propria aplicacao. Manter os quatro e
-- deliberado: o guard ADR-0097 exige um .sql por versao rastreada, e consolidar tudo aqui deixaria
-- tres orfas. O erro de cada uma vira comentario no arquivo dela, onde o erro moraria.
--   20260908182226  ESTE: a tabela, as duas colunas do log, e a escrita da sonda
--   20260908182253  o leitor (aqui ele saiu com a ordem das colunas trocada; corrigido la)
--   20260908182528  o despacho e o cron (cortados desta transcricao por engano meu)
--   20260908182606  o REVOKE que NOMEIA `anon`, porque `FROM PUBLIC` nao o alcanca
-- Se `supabase db push` rodar nesta arvore um dia, as quatro versoes ja constam de
-- `schema_migrations` e nenhuma deve ser reaplicada.

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
-- O que veio depois, e por que nao esta neste arquivo
-- ---------------------------------------------------------------------------
-- O leitor (`get_interview_agenda_health`), o despacho, o cron e o REVOKE nominal saem nas tres
-- tracking rows seguintes, cada uma com seu .sql e seu motivo no cabecalho:
--   20260908182253  o leitor (aplicado aqui com a ordem das colunas trocada, e corrigido la)
--   20260908182528  o despacho e o cron (cortados desta transcricao por engano meu)
--   20260908182606  o REVOKE que NOMEIA anon, porque FROM PUBLIC nao o alcanca
