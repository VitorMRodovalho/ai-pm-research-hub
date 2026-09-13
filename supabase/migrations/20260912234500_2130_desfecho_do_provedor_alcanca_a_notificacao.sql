-- #2130 — o sinal de parada alcanca a NOTIFICACAO, nao so a campanha.
--
-- SINTOMA (01-12/09/2026): um lider de tribo ativo ficou 94 dias sem receber e-mail e um guest
-- nunca recebeu nenhum e-mail de onboarding. Os dois por supressao do provedor apos reclamacao de
-- spam. Ninguem na plataforma tinha como saber: 15 sinais de parada registrados, nenhum leitor.
--
-- A CAUSA, em duas metades:
--   (a) o Resend responde 200 para endereco suprimido. Ele ACEITA, devolve id, e suprime depois por
--       webhook. Entao "a API aceitou" e "a pessoa recebeu" sao dois fatos com tempos diferentes, e
--       `notifications.email_sent_at` so sabe o primeiro;
--   (b) `notifications` NAO guardava o `resend_id` devolvido no aceite, entao o webhook de desfecho
--       nao tinha onde pousar. Por isso 12 dos 15 sinais ficaram orfaos.
--
-- O QUE ESTA MIGRATION FAZ: guarda o id da mensagem e o desfecho AO LADO de `email_sent_at`, sem
-- mudar o significado nem o valor dele. `email_sent_at` passa a querer dizer explicitamente "a API
-- aceitou", que e o que sempre quis dizer.
--
-- SEM BACKFILL, de proposito: para as linhas antigas o id foi perdido de verdade, e inventar um
-- desfecho para elas seria fabricar o fato que a issue existe para medir. `resend_id` nulo diz
-- "nao sabemos", nunca "nao foi entregue".
--
-- Cross-ref: #2130 (spec no comentario 5641960282), #2129 (mesma familia: envia e nao confere o
-- outro lado), #1424 (o EF de envio).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. As quatro colunas, todas anulaveis e aditivas
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS resend_id            text,
  ADD COLUMN IF NOT EXISTS email_delivery_status text,
  ADD COLUMN IF NOT EXISTS email_delivery_at     timestamptz,
  ADD COLUMN IF NOT EXISTS email_delivery_reason text;

COMMENT ON COLUMN public.notifications.resend_id IS
  '#2130 — id da mensagem devolvido pelo POST /emails do Resend. Era DESCARTADO; e a chave que liga o aceite ao desfecho do webhook. NULL em linha anterior a 2026-09-12 significa "id perdido", nao "nao enviado".';
COMMENT ON COLUMN public.notifications.email_delivery_status IS
  '#2130 — desfecho conhecido do provedor. accepted (a API aceitou) | deduplicated (digest rico duplicado, carimbado sem enviar) | delivered | suppressed | bounced | complained | delayed. NULL = sem informacao.';
COMMENT ON COLUMN public.notifications.email_delivery_at IS
  '#2130 — carimbo do ultimo desfecho conhecido. Distinto de email_sent_at, que marca o ACEITE.';
COMMENT ON COLUMN public.notifications.email_delivery_reason IS
  '#2130 — detalhe do desfecho (hoje: bounce_type). Anulavel.';

-- CHECK com nome EXPLICITO: `ADD CONSTRAINT` sem nome recebe nome auto-gerado e o `DROP` seguinte
-- nao o acha, entao a segunda aplicacao falharia. DROP + ADD torna a migration reaplicavel.
--
-- ⚠️ Cada valor admitido aqui TEM um caminho de escrita vivo, e cada caminho escreve um valor daqui
-- (o teste de contrato de #2130 prova a diferenca simetrica nos dois sentidos). Ampliar a lista sem
-- criar o caminho produziria um valor que o CHECK aceita e que ninguem jamais grava.
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_email_delivery_status_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_email_delivery_status_check
  CHECK (email_delivery_status IS NULL OR email_delivery_status IN (
    'accepted', 'deduplicated', 'delivered', 'suppressed', 'bounced', 'complained', 'delayed'
  ));

-- Parcial: so as linhas com id participam do join do webhook, e hoje sao 0 de 7.975.
CREATE INDEX IF NOT EXISTS idx_notifications_resend_id
  ON public.notifications (resend_id)
  WHERE resend_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. process_email_webhook: o desfecho passa a alcancar `notifications`
-- ─────────────────────────────────────────────────────────────────────────────
--
-- O ACHADO QUE FECHOU O DIAGNOSTICO, e que nenhuma leitura anterior tinha visto: o `CASE
-- p_event_type` abaixo NAO TEM ramo `ELSE`. Em PL/pgSQL um CASE-comando sem ELSE levanta
-- `CASE_NOT_FOUND` quando nada casa. Ou seja: acrescentar `email.suppressed` ao `validEvents` do EF
-- do webhook SEM criar o ramo aqui faria a chamada lancar excecao, e `processed` ficaria falso do
-- mesmo jeito — o defeito sobreviveria a propria correcao, com a aparencia de ter sido corrigido.
-- Por isso os dois tipos novos ganham ramo EXPLICITO (mesmo sem acao no lado da campanha), e o CASE
-- continua SEM `ELSE`: um tipo futuro admitido no EF sem ramo aqui precisa falhar ALTO, no log do
-- webhook, e nao ser marcado `processed = true` em silencio.
--
-- `CREATE OR REPLACE` com a assinatura identica, e com TODOS os atributos repetidos: omitir
-- `SECURITY DEFINER` ou o `SET search_path` os reseta sem aviso, e omitir o DEFAULT do terceiro
-- parametro faz o comando ser RECUSADO.
--
-- Nada do bloco de `campaign_recipients` muda. O teste de contrato de #2130 afirma a INVERSA —
-- reprova se esse bloco sumir — justamente porque "acrescentar depois" e a forma mais facil de
-- apagar o que ja funcionava.

CREATE OR REPLACE FUNCTION public.process_email_webhook(
  p_resend_id text,
  p_event_type text,
  p_update_fields jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_send_id uuid;
  v_delivered_at timestamptz;
  v_user_agent text;
  v_is_bot boolean := false;
  v_known_bot_patterns text[] := ARRAY[
    'GoogleImageProxy', 'YahooMailProxy', 'Outlook-iOS',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'python-requests', 'Go-http-client', 'curl',
    'Barracuda', 'ZScaler', 'Mimecast', 'Proofpoint',
    'MessageLabs', 'Symantec', 'FireEye', 'Trend Micro'
  ];
  v_pattern text;
  -- #2130
  v_notif_status text;
BEGIN
  CASE p_event_type
    WHEN 'email.delivered' THEN
      UPDATE campaign_recipients SET
        delivered = true,
        delivered_at = COALESCE(delivered_at, now())
      WHERE resend_id = p_resend_id;

    WHEN 'email.opened' THEN
      v_user_agent := p_update_fields->>'user_agent';

      SELECT delivered_at INTO v_delivered_at
      FROM campaign_recipients WHERE resend_id = p_resend_id;

      -- Bot detection: timing (<30s after delivery)
      IF v_delivered_at IS NOT NULL
         AND (now() - v_delivered_at) < interval '30 seconds' THEN
        v_is_bot := true;
      END IF;

      -- Bot detection: known bot user-agent patterns
      IF v_user_agent IS NOT NULL THEN
        FOREACH v_pattern IN ARRAY v_known_bot_patterns LOOP
          IF v_user_agent ILIKE '%' || v_pattern || '%' THEN
            v_is_bot := true;
            EXIT;
          END IF;
        END LOOP;
      END IF;

      UPDATE campaign_recipients SET
        opened = true,
        opened_at = COALESCE(opened_at, now()),
        first_opened_at = COALESCE(first_opened_at, now()),
        open_count = open_count + 1,
        last_user_agent = COALESCE(v_user_agent, last_user_agent),
        bot_suspected = bot_suspected OR v_is_bot
      WHERE resend_id = p_resend_id;

    WHEN 'email.clicked' THEN
      -- Click = strong human signal — clear bot flag
      UPDATE campaign_recipients SET
        clicked_at = COALESCE(clicked_at, now()),
        click_count = click_count + 1,
        bot_suspected = false
      WHERE resend_id = p_resend_id;

    WHEN 'email.bounced' THEN
      UPDATE campaign_recipients SET
        bounced_at = COALESCE(bounced_at, now()),
        bounce_type = COALESCE(p_update_fields->>'bounce_type', 'unknown')
      WHERE resend_id = p_resend_id;

    WHEN 'email.complained' THEN
      UPDATE campaign_recipients SET
        complained_at = COALESCE(complained_at, now()),
        unsubscribed = true
      WHERE resend_id = p_resend_id;

    -- #2130 — os dois tipos que o EF do webhook descartava no `else`. Nao ha acao no lado da
    -- campanha (o spec e explicito: `campaign_recipients` ja funciona e nao se mexe), mas o ramo
    -- precisa EXISTIR, senao o CASE sem ELSE levanta CASE_NOT_FOUND. O desfecho deles mora no
    -- bloco de `notifications`, abaixo.
    WHEN 'email.suppressed' THEN
      NULL;

    WHEN 'email.delivery_delayed' THEN
      NULL;
  END CASE;

  UPDATE email_webhook_events SET processed = true
  WHERE resend_id = p_resend_id AND event_type = p_event_type
  AND processed = false;

  SELECT send_id INTO v_send_id FROM campaign_recipients WHERE resend_id = p_resend_id;
  IF v_send_id IS NOT NULL THEN
    UPDATE campaign_sends SET
      delivered_count = (SELECT count(*) FROM campaign_recipients WHERE send_id = v_send_id AND delivered = true),
      failed_count = (SELECT count(*) FROM campaign_recipients WHERE send_id = v_send_id AND bounced_at IS NOT NULL)
    WHERE id = v_send_id;
  END IF;

  -- ── #2130: o desfecho alcanca a NOTIFICACAO ────────────────────────────────
  -- Acrescentado DEPOIS de tudo acima e sem tocar em nada: a campanha ja funcionava.
  v_notif_status := CASE p_event_type
    WHEN 'email.delivered'        THEN 'delivered'
    WHEN 'email.suppressed'       THEN 'suppressed'
    WHEN 'email.bounced'          THEN 'bounced'
    WHEN 'email.complained'       THEN 'complained'
    WHEN 'email.delivery_delayed' THEN 'delayed'
    ELSE NULL
  END;

  IF v_notif_status IS NOT NULL THEN
    UPDATE notifications SET
      email_delivery_status = v_notif_status,
      email_delivery_at     = now(),
      email_delivery_reason = COALESCE(p_update_fields->>'bounce_type', email_delivery_reason)
    WHERE resend_id = p_resend_id
      -- 'delayed' e o UNICO desfecho nao-terminal, e o webhook pode chegar FORA DE ORDEM: um atraso
      -- que pousasse depois do `delivered` faria o estado REGREDIR e apagaria o fato mais novo.
      -- Entao ele so promove quem ainda esta no aceite (ou ja estava atrasado).
      AND (v_notif_status <> 'delayed'
           OR email_delivery_status IS NULL
           OR email_delivery_status IN ('accepted', 'delayed'));
  END IF;
END;
$function$;

NOTIFY pgrst, 'reload schema';
