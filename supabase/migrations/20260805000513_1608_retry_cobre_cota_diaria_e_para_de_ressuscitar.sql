-- ============================================================================
-- #1608 — o retry da fila de e-mail passa a cobrir a SEGUNDA forma de cota,
--         e para de ressuscitar envio antigo
-- ----------------------------------------------------------------------------
-- O defeito relatado: `process_pending_email_queue()` (cron 30,
-- `dispatch-pending-emails`, */30) só reprocessava `campaign_sends` com
-- `status='failed'` quando o `error_log` casava `%rate_limit_exceeded%`. A Resend
-- tem DUAS formas de cota e devolve `daily_quota_exceeded` quando o limite é o
-- diário — que não casa aquele predicado.
--
-- O defeito que a investigação achou, e que é o mais perigoso dos dois:
-- **não havia limite de idade**. Corrigir só o predicado teria feito o cron
-- despachar, no tick seguinte, dois envios de 2026-07-04 cujo assunto é
-- "agende sua entrevista NESTE FIM DE SEMANA". Medido em 2026-08-05, os dois
-- destinatários são candidaturas JÁ DECIDIDAS (uma `approved` com entrevista
-- marcada, outra `rejected`, ambas atualizadas em 03/08). Ou seja: a issue
-- descrevia "2 pessoas encalhadas há 32 dias", e a medição mostrou que ninguém
-- estava esperando esse e-mail — o processo delas seguiu por outro caminho.
-- Entregar agora seria absurdo para a primeira e ativamente ruim para a segunda.
--
-- Então a correção tem duas metades, e a segunda é o que impede o dano:
--   1. o vocabulário de erro retentável vira DADO (array), não literal no meio
--      de um predicado — para que um terceiro código de cota entre por lista e
--      não por edição de WHERE;
--   2. só se retenta o que falhou nas últimas 24h. A cota diária da Resend zera
--      todo dia, então uma falha legítima de cota é recuperada no mesmo dia;
--      o que passou disso perdeu o contexto e não deve reviver.
--
-- Efeito hoje: ZERO. Todos os 11 `failed` em produção têm mais de 24h, então o
-- predicado novo seleciona as mesmas zero linhas que o antigo. Esta migration é
-- prevenção da próxima ocorrência, não reparo de dano em repouso — e é por isso
-- que o aceite depende do TESTE, não de um antes/depois de contagem.
--
-- NOTA (registrada, não corrigida): o ramo `cs.status IN ('pending_delivery',
-- 'throttled')` cita `throttled`, que VIOLA o próprio CHECK de
-- `campaign_sends.status` (draft, pending_delivery, scheduled, sending, sent,
-- failed). É vocabulário morto e inofensivo; removê-lo é faxina fora do escopo
-- de uma correção de bug. Fica o registro para quem for mexer ali depois.
--
-- Por que a função-predicado separada: sem ela, provar o comportamento exigiria
-- INSERIR um `campaign_sends` recente com destinatário não entregue em
-- PRODUÇÃO — e o cron roda a cada 30 min, então o teste dispararia um e-mail
-- real. `email_send_retry_eligible` deixa o teste exercitar a lógica DE VERDADE
-- com valores sintéticos, sem escrever uma linha. Duplicar o predicado dentro do
-- teste seria a alternativa, e produziria um teste que passa enquanto a função
-- diverge (ver `reference-mutation-test-reveals-decorative-defenses`).
--
-- ROLLBACK:
--   DROP FUNCTION public.email_send_retry_eligible(text, text, timestamptz);
--   + re-aplicar o corpo anterior de process_pending_email_queue (o predicado
--     inline com um único ILIKE e sem limite de idade). Nenhum dado é tocado.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.email_send_retry_eligible(
  p_status     text,
  p_error_log  text,
  p_created_at timestamptz
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Vocabulário de erro RETENTÁVEL. É uma allow-list de propósito: a Resend
  -- também devolve falhas permanentes (endereço inválido, bounce duro) e um
  -- predicado largo — `%429%`, ou qualquer coisa que case "quota" — as
  -- transformaria em laço infinito. Medido em 2026-08-05: das 11 falhas em
  -- produção, 9 são de um 401 de Edge Function de março, já corrigido por
  -- deploy, e NÃO podem voltar para a fila.
  SELECT p_status = 'failed'
     AND p_created_at >= now() - interval '24 hours'
     AND EXISTS (
       SELECT 1
       FROM unnest(ARRAY['rate_limit_exceeded', 'daily_quota_exceeded']) AS n(name)
       WHERE p_error_log ILIKE '%' || n.name || '%'
     );
$function$;

COMMENT ON FUNCTION public.email_send_retry_eligible(text, text, timestamptz) IS
  '#1608: um envio falho volta para a fila apenas se o erro estiver na allow-list de cota '
  'E a falha tiver menos de 24h. O limite de idade é a metade que impede o dano: sem ele, '
  'corrigir o vocabulário faria o cron despachar um lembrete de 32 dias ("agende neste fim '
  'de semana") para candidaturas já decididas.';

REVOKE ALL ON FUNCTION public.email_send_retry_eligible(text, text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.email_send_retry_eligible(text, text, timestamptz) TO authenticated, service_role;

-- ── a fila passa a consultar o predicado nomeado ────────────────────────────
CREATE OR REPLACE FUNCTION public.process_pending_email_queue()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today_count int;
  v_daily_limit int := 100;
  v_slots int;
  v_pending record;
  v_dispatched int := 0;
  v_skipped int := 0;
  v_service_role_key text;
  v_today_start timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo';
BEGIN
  SELECT count(*) INTO v_today_count
  FROM campaign_recipients
  WHERE delivered = true
    AND created_at >= v_today_start;

  v_slots := GREATEST(0, v_daily_limit - v_today_count);

  IF v_slots = 0 THEN
    RETURN jsonb_build_object('today_count', v_today_count, 'slots', 0, 'dispatched', 0, 'message', 'daily_limit_reached');
  END IF;

  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  IF v_service_role_key IS NULL THEN
    RAISE NOTICE 'process_pending_email_queue: no service_role_key in vault';
    RETURN jsonb_build_object('error', 'no_service_role_key');
  END IF;

  -- Pick: pending_delivery OR throttled OR failed-que-ainda-vale-retentar.
  -- #1608: o que decide a terceira parcela é `email_send_retry_eligible`, que
  -- exige DOIS fatos — erro na allow-list de cota (rate_limit_exceeded OU
  -- daily_quota_exceeded) E menos de 24h de idade. Antes, o predicado estava
  -- inline, citava só a primeira forma de cota e não olhava idade nenhuma.
  FOR v_pending IN
    SELECT cs.id AS send_id
    FROM campaign_sends cs
    WHERE (
      cs.status IN ('pending_delivery', 'throttled')
      OR public.email_send_retry_eligible(cs.status, cs.error_log, cs.created_at)
    )
    AND EXISTS (
      SELECT 1 FROM campaign_recipients cr
      WHERE cr.send_id = cs.id AND cr.delivered = false AND cr.unsubscribed = false
    )
    ORDER BY cs.created_at ASC
    LIMIT v_slots
  LOOP
    BEGIN
      PERFORM net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-campaign',
        body := jsonb_build_object('send_id', v_pending.send_id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        )
      );
      v_dispatched := v_dispatched + 1;
      -- Serialize dispatches: Resend rate limit is 5 req/s, we sustain 4/s.
      PERFORM pg_sleep(0.25);
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      RAISE NOTICE 'process_pending_email_queue dispatch failed send_id=%: %', v_pending.send_id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'today_count_before', v_today_count,
    'daily_limit', v_daily_limit,
    'slots_available', v_slots,
    'dispatched', v_dispatched,
    'skipped', v_skipped,
    'today_start', v_today_start,
    'rate_limit_protection', '4_per_second'
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
