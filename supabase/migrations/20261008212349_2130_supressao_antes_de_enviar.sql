-- #2130 E-b: every send path asks ONE function which addresses must not receive email, before sending.
--
-- Decisions of the GP (2026-10-08):
--   E1. a complaint, a provider suppression or a permanent bounce stops every email to the address, except a link the
--       person asked for (email verification, account claim, competition registration: those senders do not call this
--       function); a transient bounce stops nothing; an unsubscribe stops campaigns and broadcasts only.
--   E2. a later delivery releases the address (the provider is the truth: it delivered, so the address works again).
--
-- Today the webhook records the signals (email_webhook_events) and only send-campaign looked at anything.

-- 1. The rule. Returns the subset of p_emails (lowercased) that is suppressed. Signals come from email_webhook_events,
--    whatever the sender, because a provider suppression or a dead mailbox holds for the whole account.
CREATE OR REPLACE FUNCTION public.email_suppressed_among(p_emails text[], p_include_unsubscribed boolean DEFAULT false)
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH addr AS (
    SELECT DISTINCT lower(btrim(e)) AS email
    FROM unnest(p_emails) AS e
    WHERE e IS NOT NULL AND btrim(e) <> ''
  ),
  sig AS (
    SELECT a.email,
      max(w.created_at) FILTER (
        WHERE w.event_type IN ('email.complained', 'email.suppressed')
           OR (w.event_type = 'email.bounced' AND w.payload #>> '{data,bounce,type}' = 'Permanent')
      ) AS last_stop,
      max(w.created_at) FILTER (WHERE w.event_type = 'email.delivered') AS last_ok
    FROM addr a
    JOIN public.email_webhook_events w ON lower(btrim(w.recipient_email)) = a.email
    GROUP BY a.email
  )
  SELECT COALESCE(array_agg(a.email ORDER BY a.email), '{}'::text[])
  FROM addr a
  LEFT JOIN sig s ON s.email = a.email
  WHERE (s.last_stop IS NOT NULL AND (s.last_ok IS NULL OR s.last_stop > s.last_ok))
     OR (p_include_unsubscribed AND public._campaign_email_unsubscribed(a.email));
$function$;
REVOKE ALL ON FUNCTION public.email_suppressed_among(text[], boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.email_suppressed_among(text[], boolean) TO service_role;

CREATE INDEX IF NOT EXISTS idx_email_webhook_events_recipient_lower
  ON public.email_webhook_events (lower(btrim(recipient_email)));

-- 2. A campaign row that was suppressed at send time is marked, so the queue does not pick it again every run.
ALTER TABLE public.campaign_recipients ADD COLUMN IF NOT EXISTS suppressed_at timestamptz;
COMMENT ON COLUMN public.campaign_recipients.suppressed_at IS
  '#2130: set by send-campaign when email_suppressed_among() returned the address; the row is never sent.';

-- 3. process_pending_email_queue: a suppressed row is not pending.
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
  -- #2130: destinatário suprimido no envio não é pendente.
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
        AND cr.suppressed_at IS NULL
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

-- 4. A notification row marked 'suppressed' gets email_sent_at (that is what takes it out of the queue) but nothing was
--    sent, exactly like 'deduplicated'. Neither counts as an email sent today: not in the hub cap, not in the per-person
--    limit. email_people_sent_today already skipped 'deduplicated'; email_sends_today skipped neither.
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
       FROM public.notifications n, d WHERE n.email_sent_at >= d.inicio
         AND n.email_delivery_status IS DISTINCT FROM 'deduplicated'
         AND n.email_delivery_status IS DISTINCT FROM 'suppressed')
    + (SELECT count(*) FROM public.campaign_recipients cr, d
        WHERE cr.delivered IS TRUE AND cr.delivered_at >= d.inicio)
  )::int;
$function$;

CREATE OR REPLACE FUNCTION public.email_people_sent_today(p_member_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH inicio AS (
    SELECT date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo' AS t
  ), envios AS (
    SELECT n.recipient_id AS member_id
    FROM public.notifications n, inicio
    WHERE n.recipient_id = ANY(p_member_ids)
      AND n.email_sent_at >= inicio.t
      AND n.email_delivery_status IS DISTINCT FROM 'deduplicated'
      AND NOT public._is_urgent_email_type(n.type)
      AND n.email_delivery_status IS DISTINCT FROM 'suppressed'
    UNION ALL
    SELECT r.member_id
    FROM public.campaign_recipients r
    JOIN public.campaign_sends s ON s.id = r.send_id, inicio
    WHERE r.member_id = ANY(p_member_ids)
      AND r.delivered
      AND COALESCE(r.delivered_at, s.sent_at) >= inicio.t
  )
  SELECT COALESCE(jsonb_object_agg(member_id, n), '{}'::jsonb)
  FROM (SELECT member_id, count(*) AS n FROM envios GROUP BY member_id) x;
$function$;
