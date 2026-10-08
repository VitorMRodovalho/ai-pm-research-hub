-- #2580 (decisao do GP de 08/10/2026): selection_cutoff_approved entra na lista de urgentes. E o convite ao candidato
-- para marcar a entrevista depois do corte, e tem prazo; nao pode ficar retido pelo limite de 1 e-mail por dia.

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
    'affiliation_renewal_d7_urgent'
  );
$function$;

NOTIFY pgrst, 'reload schema';
