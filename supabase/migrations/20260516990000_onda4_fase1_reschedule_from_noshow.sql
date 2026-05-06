-- ARM Onda 4 Fase 1.3 (p109): permitir reschedule a partir de interview_noshow.
-- Bug discovered live (2026-05-06): Cristiano não compareceu, foi marcado no-show,
-- e PM não conseguia reagendar (RPC só aceitava interview_pending|interview_scheduled).
-- Segunda chance é o caso mais comum de reschedule — não pode bloquear.
--
-- Mudança:
--   1. Adiciona 'interview_noshow' aos status aceitos
--   2. Quando origem é noshow → reseta status para 'interview_pending' (limpa o stuck state)
--   3. UPDATE em selection_interviews também aceita status='noshow' (não só 'scheduled')
--
-- Rollback: reverter para versão pré-existente (only allows interview_pending|interview_scheduled).

CREATE OR REPLACE FUNCTION public.request_interview_reschedule(p_application_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_send_result jsonb;
  v_first_name text;
  v_was_noshow boolean := false;
  v_booking_url text := 'https://calendar.app.google/gh9WjefjcmisVLoh7';
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id
    AND member_id = v_caller.id
    AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
  END IF;

  IF v_app.status NOT IN ('interview_pending', 'interview_scheduled', 'interview_noshow') THEN
    RAISE EXCEPTION 'Application status % does not allow reschedule request', v_app.status;
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'Reschedule reason is required';
  END IF;

  v_was_noshow := v_app.status = 'interview_noshow';

  UPDATE public.selection_applications
  SET interview_status = 'needs_reschedule',
      interview_reschedule_reason = p_reason,
      interview_reschedule_requested_at = now(),
      interview_reschedule_requested_by = v_caller.id,
      status = CASE WHEN v_was_noshow THEN 'interview_pending' ELSE status END,
      updated_at = now()
  WHERE id = p_application_id;

  UPDATE public.selection_interviews
  SET status = 'rescheduled',
      notes = COALESCE(notes || E'\n', '')
            || '[' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') || ' BRT] '
            || 'Marked for reschedule by ' || COALESCE(v_caller.name, 'admin')
            || CASE WHEN v_was_noshow THEN ' (from no-show)' ELSE '' END
            || ': ' || p_reason
  WHERE application_id = p_application_id
    AND status IN ('scheduled', 'noshow');

  v_first_name := COALESCE(
    NULLIF(trim(v_app.first_name), ''),
    NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
    'candidato(a)'
  );

  v_send_result := public.campaign_send_one_off(
    'interview_reschedule_request',
    v_app.email,
    jsonb_build_object(
      'first_name', v_first_name,
      'reason', p_reason,
      'booking_url', v_booking_url
    ),
    jsonb_build_object(
      'language', 'pt',
      'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
      'source', 'request_interview_reschedule'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'send_id', v_send_result->>'send_id',
    'booking_url', v_booking_url,
    'interview_status', 'needs_reschedule',
    'was_noshow', v_was_noshow,
    'requested_by', v_caller.id,
    'requested_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.request_interview_reschedule(uuid, text) IS
  'p109 ARM Onda 4 Fase 1.3: permite reschedule a partir de interview_noshow (segunda chance). Reseta status para interview_pending quando origem é noshow.';

NOTIFY pgrst, 'reload schema';
