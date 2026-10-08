-- #2580 frente 2, regra 5 (decisao do GP de 08/10/2026): campanha tambem respeita a regra 1, no maximo um
-- e-mail por pessoa por dia. O membro que ja recebeu e-mail hoje fica adiado para as 07h de Brasilia do dia
-- seguinte, e o adiado sai nessa hora mesmo que a pessoa tenha recebido outro (conta como o 1 do dia seguinte,
-- como o excesso das notificacoes). Destinatario externo (sem member_id) segue como hoje.

-- 1. Quando o destinatario adiado pode sair.
ALTER TABLE public.campaign_recipients ADD COLUMN IF NOT EXISTS deferred_until timestamptz;

COMMENT ON COLUMN public.campaign_recipients.deferred_until IS
  '#2580 regra 5: preenchido quando o envio ao membro foi adiado pelo limite de 1 e-mail por pessoa por dia; o envio sai a partir deste instante.';

-- 2. 'throttled' passa a ser um status valido. A Edge Function e o cron ja o usavam, e a gravacao falhava na
-- constraint sem ninguem ler o erro.
ALTER TABLE public.campaign_sends DROP CONSTRAINT IF EXISTS campaign_sends_status_check;
ALTER TABLE public.campaign_sends ADD CONSTRAINT campaign_sends_status_check
  CHECK (status = ANY (ARRAY['draft'::text, 'pending_delivery'::text, 'scheduled'::text, 'sending'::text, 'sent'::text, 'failed'::text, 'throttled'::text]));

-- 3. Adia destinatarios para as 07h de Brasilia do dia seguinte. Devolve o instante.
CREATE OR REPLACE FUNCTION public.campaign_defer_recipients(p_recipient_ids uuid[])
 RETURNS timestamptz
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_release timestamptz := (date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') + interval '1 day 7 hours') AT TIME ZONE 'America/Sao_Paulo';
BEGIN
  UPDATE public.campaign_recipients
     SET deferred_until = v_release,
         status = 'deferred_per_person',
         error_message = 'per_person_daily_limit'
   WHERE id = ANY(p_recipient_ids)
     AND delivered = false;
  RETURN v_release;
END;
$function$;

REVOKE ALL ON FUNCTION public.campaign_defer_recipients(uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.campaign_defer_recipients(uuid[]) TO service_role;

-- 4. O cron so retoma um envio quando ha destinatario pendente que ja pode sair.
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
  -- #2580 regra 5: destinatário adiado só conta como pendente a partir de deferred_until.
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
        AND (cr.deferred_until IS NULL OR cr.deferred_until <= now())
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
