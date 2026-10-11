-- O aviso da varredura de dado pessoal no tracker publico (`tracker_pii_found`) passa a ser URGENTE na regra de
-- 1 e-mail por pessoa por dia (#2580 regra 1). Decisao do GP de 10/10/2026.
--
-- POR QUE NO BANCO TAMBEM: a lista de urgentes existe nos dois lados, `public._is_urgent_email_type` e
-- `URGENT_EMAIL_TYPES` da Edge Function send-notification-email, e o guard 2580-um-email-por-pessoa-por-dia exige
-- que sejam iguais. A Edge Function decide o envio na hora; o banco decide a CONTAGEM por pessoa
-- (`email_people_sent_today` exclui os urgentes). So do lado da Edge Function, o aviso sairia, mas gastaria o unico
-- e-mail do dia de quem gere a plataforma e seguraria o resto para o dia seguinte.
--
-- O corpo foi montado sobre o CORPO VIVO: md5 normalizado do vivo igual ao da captura mais nova (20261008050613),
-- conferido em 2026-10-10 via _audit_list_public_function_bodies(). CREATE OR REPLACE preserva os grants; a
-- assinatura e os atributos (sql, IMMUTABLE, search_path) nao mudam.
-- ROLLBACK: reaplicar a captura 20261008050613.

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
    'selection_cutoff_approved',
    'affiliation_renewal_d7_urgent',
    'tracker_pii_found'
  );
$function$;

-- Pos-condicao: o tipo novo e urgente, os antigos continuam, e o instrumento sabe dizer nao.
DO $pos$
BEGIN
  IF NOT public._is_urgent_email_type('tracker_pii_found') THEN
    RAISE EXCEPTION 'tracker_pii_found nao ficou urgente';
  END IF;
  IF NOT public._is_urgent_email_type('selection_approved')
     OR NOT public._is_urgent_email_type('affiliation_renewal_d7_urgent')
     OR public._is_urgent_email_type('system_alert') THEN
    RAISE EXCEPTION 'a lista de urgentes mudou alem do tipo novo';
  END IF;
END
$pos$;
