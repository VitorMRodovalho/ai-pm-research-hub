-- #2580 frente 2, regra 1 (decisao do GP de 08/10/2026): no maximo 1 e-mail por pessoa por dia, salvo os urgentes.
--
-- D2: urgentes saem na hora e nao contam no limite: selection_approved, selection_interview_scheduled,
-- selection_reschedule_escalated, selection_termo_due e affiliation_renewal_d7_urgent. Os e-mails de acesso a conta
-- (criacao, verificacao, reivindicacao) saem por Edge Functions proprias e nao passam por este limite. Tipo novo nasce
-- nao urgente; so e urgente o que estiver nesta lista.
-- Excesso (decisao b): o que passa do 1 do dia fica retido e sai num unico e-mail a partir das 07h (Brasilia) do dia
-- seguinte. A Edge Function send-notification-email aplica a regra; estas funcoes dao a ela a lista e a contagem.

-- 1) a lista de urgentes, num lugar so (a Edge Function tem a mesma lista, travada pelo guard)
CREATE OR REPLACE FUNCTION public._is_urgent_email_type(p_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_type IN (
    'selection_approved',
    'selection_interview_scheduled',
    'selection_reschedule_escalated',
    'selection_termo_due',
    'affiliation_renewal_d7_urgent'
  );
$function$;

-- 2) quantos e-mails nao urgentes cada pessoa ja recebeu hoje (dia de Brasilia): notificacoes enviadas (o status anda
--    de accepted para delivered, bounced etc. pelo webhook; so 'deduplicated' nao e envio) e campanhas entregues a
--    membros. Devolve {member_id: n} so para quem tem n >= 1.
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

REVOKE ALL ON FUNCTION public._is_urgent_email_type(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._is_urgent_email_type(text) TO service_role;
REVOKE ALL ON FUNCTION public.email_people_sent_today(uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.email_people_sent_today(uuid[]) TO service_role;

NOTIFY pgrst, 'reload schema';
