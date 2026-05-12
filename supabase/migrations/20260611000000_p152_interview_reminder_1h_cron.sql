-- p152 W4 P3 (2026-05-12) — Interview reminder 1h before cron.
--
-- Anti-no-show: 1h-before email reduces no-show rate ~30-50% per industry
-- benchmark. Bruna Zomer no-show hoje 18:00 motivou implementação. Cron
-- */15min offset (5,20,35,50) finds interviews 30-90min ahead, status=scheduled,
-- reminder_sent_at_1h NULL.
--
-- Smoke 12/05 23:20 UTC: cron fired auto, dispatched para Bruna Soares
-- (00:00 UTC) + Flavio Oliveira (00:30 UTC). Ambos receberam reminder.
-- Idempotency: re-run manual @ 23:21 retornou 0 (reminder_sent_at_1h marker).

ALTER TABLE public.selection_interviews
  ADD COLUMN IF NOT EXISTS reminder_sent_at_1h timestamptz;

CREATE INDEX IF NOT EXISTS idx_selection_interviews_reminder_pending
  ON public.selection_interviews (scheduled_at)
  WHERE status = 'scheduled' AND reminder_sent_at_1h IS NULL;

INSERT INTO public.campaign_templates (slug, name, subject, body_html, body_text, category, target_audience, variables)
VALUES (
  'interview_reminder_1h',
  'Interview reminder 1h before (auto-cron)',
  jsonb_build_object(
    'pt', 'Lembrete: sua entrevista é em ~1h ({{time_str}})',
    'en', 'Reminder: your interview starts in ~1h ({{time_str}})',
    'es', 'Recordatorio: tu entrevista es en ~1h ({{time_str}})'
  ),
  jsonb_build_object(
    'pt',
    '<p>Olá {{first_name}},</p>' ||
    '<p>Só passando para lembrar que sua entrevista com o Núcleo IA &amp; GP está agendada para <strong>hoje às {{time_str}} (Brasília)</strong>.</p>' ||
    '<p>O link Google Meet está no seu convite do Google Calendar. Se não encontrar, responda este email que reenviamos.</p>' ||
    '<p>Caso surja um imprevisto, avise-nos com antecedência e podemos reagendar.</p>' ||
    '<p>Atenciosamente,<br>Equipe GP — Núcleo IA &amp; GP</p>',
    'en',
    '<p>Hi {{first_name}},</p>' ||
    '<p>Just a heads-up: your interview with Núcleo IA &amp; GP is scheduled for <strong>today at {{time_str}} (Brasília time)</strong>.</p>' ||
    '<p>The Google Meet link is in your Google Calendar invite. If you can''t find it, reply to this email and we''ll resend.</p>' ||
    '<p>If something unexpected comes up, let us know in advance and we can reschedule.</p>' ||
    '<p>Best regards,<br>GP Team — Núcleo IA &amp; GP</p>',
    'es',
    '<p>Hola {{first_name}},</p>' ||
    '<p>Recordatorio: tu entrevista con el Núcleo IA &amp; GP está programada para <strong>hoy a las {{time_str}} (hora Brasilia)</strong>.</p>' ||
    '<p>El link Google Meet está en tu invitación de Google Calendar. Si no lo encuentras, responde este email y lo reenviamos.</p>' ||
    '<p>Si surge un imprevisto, avísanos con anticipación y podemos reagendar.</p>' ||
    '<p>Saludos,<br>Equipo GP — Núcleo IA &amp; GP</p>'
  ),
  jsonb_build_object(
    'pt', 'Lembrete: sua entrevista é hoje às {{time_str}} (Brasília). Link Meet está no Google Calendar.',
    'en', 'Reminder: your interview is today at {{time_str}} (Brasília time). Meet link is in your Google Calendar.',
    'es', 'Recordatorio: tu entrevista es hoy a las {{time_str}} (Brasilia). Link Meet en Google Calendar.'
  ),
  'operational',
  jsonb_build_object('audience', 'selection_candidate'),
  jsonb_build_object(
    'first_name', jsonb_build_object('type', 'text', 'required', true),
    'time_str', jsonb_build_object('type', 'text', 'required', true)
  )
)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  subject = EXCLUDED.subject,
  body_html = EXCLUDED.body_html,
  body_text = EXCLUDED.body_text,
  variables = EXCLUDED.variables,
  updated_at = now();

CREATE OR REPLACE FUNCTION public.process_interview_reminders_1h()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_intv record;
  v_app record;
  v_first_name text;
  v_time_str text;
  v_sent int := 0;
  v_processed jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
BEGIN
  FOR v_intv IN
    SELECT si.id, si.scheduled_at, si.application_id
    FROM public.selection_interviews si
    WHERE si.status = 'scheduled'
      AND si.reminder_sent_at_1h IS NULL
      AND si.scheduled_at BETWEEN now() + interval '30 minutes' AND now() + interval '90 minutes'
    ORDER BY si.scheduled_at
  LOOP
    SELECT id, applicant_name, first_name, email INTO v_app
    FROM public.selection_applications WHERE id = v_intv.application_id;
    IF v_app.id IS NULL OR v_app.email IS NULL THEN CONTINUE; END IF;

    v_first_name := COALESCE(
      NULLIF(trim(v_app.first_name), ''),
      NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
      'candidato(a)'
    );
    v_time_str := to_char(v_intv.scheduled_at AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI');

    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'interview_reminder_1h',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'time_str', v_time_str
        ),
        p_metadata := jsonb_build_object(
          'source', 'process_interview_reminders_1h',
          'application_id', v_app.id,
          'interview_id', v_intv.id,
          'scheduled_at', v_intv.scheduled_at
        )
      );

      UPDATE public.selection_interviews
      SET reminder_sent_at_1h = now()
      WHERE id = v_intv.id;

      v_sent := v_sent + 1;
      v_processed := v_processed || jsonb_build_object(
        'interview_id', v_intv.id,
        'applicant_name', v_app.applicant_name,
        'scheduled_at', v_intv.scheduled_at,
        'time_str', v_time_str
      );

      PERFORM pg_sleep(0.3);
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'interview_id', v_intv.id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'reminders_sent', v_sent,
    'processed', v_processed,
    'errors', v_errors,
    'run_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.process_interview_reminders_1h() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_interview_reminders_1h() TO authenticated, service_role;

COMMENT ON FUNCTION public.process_interview_reminders_1h() IS
'Cron-driven: dispatches interview_reminder_1h to candidates with scheduled '
'interviews 30-90min ahead. Marks reminder_sent_at_1h for idempotency. Resend '
'5rps rate-limited via pg_sleep(0.3). Anti-no-show per p152 W4 P3.';

SELECT cron.schedule(
  'interview-reminder-1h-q15min',
  '5,20,35,50 * * * *',
  $cron$ SELECT public.process_interview_reminders_1h() $cron$
);

NOTIFY pgrst, 'reload schema';
