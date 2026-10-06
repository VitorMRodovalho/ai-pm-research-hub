-- #2580, frente 1: teto diário de e-mails do hub num lugar só, contando só o que o hub envia, com alerta.
--
-- A conta da Resend passou para o plano Pro: sem cota diária, cota mensal dividida com os outros projetos
-- da mesma conta. O teto do hub deixa de ser a cota do plano gratuito e vira rede de segurança contra
-- disparo descontrolado, dimensionada pela necessidade medida. Ele mora em site_config ('email_daily_cap')
-- e a fila de campanhas e as duas Edge Functions de e-mail leem dali. O que conta é o que o próprio hub
-- enviou no dia de Brasília (notificações e campanhas), e não os eventos de envio da conta inteira, que
-- incluem os outros projetos. Ao bater no teto, a gestão recebe um alerta no sininho, uma vez por dia.

-- 1. O valor, ajustável sem migration pela set_site_config.
INSERT INTO public.site_config (key, value) VALUES ('email_daily_cap', '250'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 2. Leitura do teto. Sem a chave, ou com valor que não seja número, volta ao teto antigo (100).
CREATE OR REPLACE FUNCTION public.email_daily_cap()
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(
    (SELECT CASE WHEN jsonb_typeof(c.value) = 'number' THEN (c.value #>> '{}')::int END
       FROM public.site_config c WHERE c.key = 'email_daily_cap'),
    100);
$function$;

COMMENT ON FUNCTION public.email_daily_cap() IS
  '#2580: teto diário de e-mails do hub, lido de site_config (email_daily_cap). Sem a chave ou com valor não numérico, 100.';
REVOKE ALL ON FUNCTION public.email_daily_cap() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.email_daily_cap() TO service_role;

-- 3. O que o hub enviou hoje, no dia de Brasília: um e-mail por envio da Resend nas notificações, mais as
--    campanhas entregues.
CREATE OR REPLACE FUNCTION public.email_sends_today()
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH d AS (
    SELECT date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo' AS inicio
  )
  SELECT (
    (SELECT count(DISTINCT coalesce(n.resend_id, n.id::text))
       FROM public.notifications n, d WHERE n.email_sent_at >= d.inicio)
    + (SELECT count(*) FROM public.campaign_recipients cr, d
        WHERE cr.delivered IS TRUE AND cr.delivered_at >= d.inicio)
  )::int;
$function$;

COMMENT ON FUNCTION public.email_sends_today() IS
  '#2580: e-mails que o hub enviou hoje (dia de Brasília): notificações, um por envio da Resend, e campanhas entregues.';
REVOKE ALL ON FUNCTION public.email_sends_today() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.email_sends_today() TO service_role;

-- 4. Alerta de teto atingido: notificação no sininho de quem gere a plataforma, uma vez por dia.
--    Aparece na hora; o e-mail dela sai quando houver espaço no teto.
CREATE OR REPLACE FUNCTION public.email_cap_reached(p_lane text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_inicio timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo';
  v_teto int := public.email_daily_cap();
  v_hoje int := public.email_sends_today();
  v_novos int;
BEGIN
  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, is_read, delivery_mode)
  SELECT m.id,
         'system_alert',
         'Teto diário de e-mails do hub atingido',
         format('O hub enviou %s e-mails hoje e chegou ao teto de %s (caminho: %s). O que faltou sai no próximo dia. '
                'O teto mora em site_config, chave email_daily_cap.', v_hoje, v_teto, coalesce(p_lane, '?')),
         '/admin',
         'email_daily_cap',
         false,
         'transactional_immediate'
  FROM public.members m
  WHERE m.is_active IS TRUE
    AND public.can_by_member(m.id, 'manage_platform')
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = m.id AND n.source_type = 'email_daily_cap' AND n.created_at >= v_inicio
    );
  GET DIAGNOSTICS v_novos = ROW_COUNT;
  RETURN v_novos;
END;
$function$;

COMMENT ON FUNCTION public.email_cap_reached(text) IS
  '#2580: avisa quem gere a plataforma, no sininho e uma vez por dia, que o teto diário de e-mails do hub foi atingido.';
REVOKE ALL ON FUNCTION public.email_cap_reached(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.email_cap_reached(text) TO service_role;

-- 5. A fila de campanhas lê o teto e a contagem do hub, e avisa ao bater no teto.
CREATE OR REPLACE FUNCTION public.process_pending_email_queue()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today_count int;
  v_daily_limit int := public.email_daily_cap();
  v_slots int;
  v_pending record;
  v_dispatched int := 0;
  v_skipped int := 0;
  v_service_role_key text;
  v_today_start timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo';
BEGIN
  -- #2580: conta o que o hub enviou hoje (notificações e campanhas), não só as campanhas.
  v_today_count := public.email_sends_today();

  v_slots := GREATEST(0, v_daily_limit - v_today_count);

  IF v_slots = 0 THEN
    PERFORM public.email_cap_reached('fila de campanhas');
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
      -- A conta da Resend tem 10 chamadas por segundo, divididas entre os projetos; o hub fica em 4.
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
