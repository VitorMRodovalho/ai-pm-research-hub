-- p152 W4 (2026-05-12) — 2-strike no-show auto-close.
--
-- Completa ciclo anti-no-show: reminder 1h-before (P3) → soft reschedule
-- (P1) → 2nd no-show = auto-close com email respectful + notif PM.
-- PM override path: manual status select in modal info.

INSERT INTO public.campaign_templates (slug, name, subject, body_html, body_text, category, target_audience, variables)
VALUES (
  'interview_two_strike_close',
  'Two-strike no-show close (auto pós-2-noshows)',
  jsonb_build_object(
    'pt', 'Encerrando seu processo seletivo, {{first_name}}',
    'en', 'Closing your selection process, {{first_name}}',
    'es', 'Cerrando tu proceso selectivo, {{first_name}}'
  ),
  jsonb_build_object(
    'pt',
    '<p>Olá {{first_name}},</p>' ||
    '<p>Tentamos remarcar sua entrevista mais de uma vez sem sucesso. Entendemos que imprevistos acontecem, e tudo bem — vamos encerrar seu processo seletivo no Núcleo IA &amp; GP por enquanto.</p>' ||
    '<p>Você é muito bem-vinda(o) a se candidatar novamente em ciclos futuros quando tiver disponibilidade. Acompanhe nossas redes para saber quando abrirmos a próxima janela.</p>' ||
    '<p>Boa sorte na sua jornada profissional.</p>' ||
    '<p>Atenciosamente,<br>Equipe GP — Núcleo IA &amp; GP</p>',
    'en',
    '<p>Hi {{first_name}},</p>' ||
    '<p>We''ve tried to reschedule your interview more than once without success. Things happen, and that''s OK — we''ll close your selection process at Núcleo IA &amp; GP for now.</p>' ||
    '<p>You''re very welcome to apply again in future cycles when your availability allows. Follow our channels to know when the next window opens.</p>' ||
    '<p>Best of luck on your professional journey.</p>' ||
    '<p>Best regards,<br>GP Team — Núcleo IA &amp; GP</p>',
    'es',
    '<p>Hola {{first_name}},</p>' ||
    '<p>Intentamos reagendar tu entrevista más de una vez sin éxito. Imprevistos suceden, está bien — cerraremos tu proceso selectivo en Núcleo IA &amp; GP por ahora.</p>' ||
    '<p>Eres muy bienvenida(o) a postular nuevamente en ciclos futuros cuando tengas disponibilidad. Sigue nuestros canales para conocer la próxima ventana.</p>' ||
    '<p>Mucho éxito en tu carrera.</p>' ||
    '<p>Saludos,<br>Equipo GP — Núcleo IA &amp; GP</p>'
  ),
  jsonb_build_object(
    'pt', 'Olá {{first_name}}, encerrando seu processo após mais de uma tentativa sem sucesso. Bem-vinda(o) em ciclos futuros.',
    'en', 'Hi {{first_name}}, closing your process after more than one missed attempt. Welcome to apply in future cycles.',
    'es', 'Hola {{first_name}}, cerrando tu proceso después de más de un intento fallido. Bienvenido(a) en ciclos futuros.'
  ),
  'operational',
  jsonb_build_object('audience', 'selection_candidate'),
  jsonb_build_object(
    'first_name', jsonb_build_object('type', 'text', 'required', true)
  )
)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  subject = EXCLUDED.subject,
  body_html = EXCLUDED.body_html,
  body_text = EXCLUDED.body_text,
  variables = EXCLUDED.variables,
  updated_at = now();

CREATE OR REPLACE FUNCTION public.mark_interview_status(p_interview_id uuid, p_status text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_interview record;
  v_app record;
  v_cycle record;
  v_new_app_status text;
  v_prior_status text;
  v_first_name text;
  v_booking_url text;
  v_deadline_date text;
  v_send_result jsonb := NULL;
  v_noshow_count int;
  v_two_strike_applied boolean := false;
  v_two_strike_send jsonb := NULL;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF p_status NOT IN ('noshow', 'cancelled', 'rescheduled', 'completed') THEN
    RAISE EXCEPTION 'Invalid interview status: %', p_status;
  END IF;

  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF v_interview IS NULL THEN
    RAISE EXCEPTION 'Interview not found';
  END IF;

  v_prior_status := v_interview.status;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  IF NOT (
    v_caller.id = ANY(v_interview.interviewer_ids)
    OR public.can_by_member(v_caller.id, 'manage_platform'::text)
    OR EXISTS (
      SELECT 1 FROM public.selection_committee
      WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
    )
  ) THEN
    RAISE EXCEPTION 'Unauthorized: must be interviewer, committee lead, or platform admin';
  END IF;

  UPDATE public.selection_interviews
  SET status = p_status,
      notes = COALESCE(p_notes, notes),
      conducted_at = CASE WHEN p_status = 'completed' THEN now() ELSE conducted_at END
  WHERE id = p_interview_id;

  v_new_app_status := CASE p_status
    WHEN 'noshow' THEN 'interview_noshow'
    WHEN 'cancelled' THEN 'interview_pending'
    WHEN 'rescheduled' THEN 'interview_pending'
    WHEN 'completed' THEN 'interview_done'
    ELSE v_app.status
  END;

  UPDATE public.selection_applications
  SET status = v_new_app_status, updated_at = now()
  WHERE id = v_interview.application_id
    AND status IN ('interview_scheduled', 'interview_done');

  IF p_status = 'noshow' AND v_prior_status IS DISTINCT FROM 'noshow' THEN
    v_first_name := COALESCE(
      NULLIF(trim(v_app.first_name), ''),
      NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
      'candidato(a)'
    );

    SELECT count(*) INTO v_noshow_count
    FROM public.selection_interviews
    WHERE application_id = v_interview.application_id
      AND status = 'noshow';

    IF v_noshow_count >= 2 THEN
      UPDATE public.selection_applications
      SET status = 'rejected',
          feedback = COALESCE(feedback, '') || E'\n[p152 auto-close ' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') || ' BRT] Encerrado automaticamente após ' || v_noshow_count || ' no-shows na entrevista.',
          updated_at = now()
      WHERE id = v_interview.application_id;

      BEGIN
        v_two_strike_send := public.campaign_send_one_off(
          'interview_two_strike_close',
          v_app.email,
          jsonb_build_object('first_name', v_first_name),
          jsonb_build_object(
            'language', 'pt',
            'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
            'source', 'mark_interview_status:two_strike_close',
            'noshow_count', v_noshow_count
          )
        );
      EXCEPTION WHEN OTHERS THEN
        v_two_strike_send := jsonb_build_object('error', SQLERRM);
      END;

      v_two_strike_applied := true;

      PERFORM public.create_notification(
        sc.member_id,
        'selection_application_two_strike_closed',
        '2-strike encerrado: ' || v_app.applicant_name,
        v_app.applicant_name || ' teve ' || v_noshow_count || ' no-shows. Processo encerrado automaticamente + email enviado. Override manual via Status select.',
        '/admin/selection',
        'selection_application',
        v_interview.application_id
      )
      FROM public.selection_committee sc
      WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
    ELSE
      v_booking_url := COALESCE(
        NULLIF(trim(v_cycle.interview_booking_url), ''),
        'https://calendar.app.google/gh9WjefjcmisVLoh7'
      );
      v_deadline_date := to_char((now() + interval '7 days') AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY');

      BEGIN
        v_send_result := public.campaign_send_one_off(
          'interview_noshow_soft_reschedule',
          v_app.email,
          jsonb_build_object(
            'first_name', v_first_name,
            'booking_url', v_booking_url,
            'deadline_date', v_deadline_date
          ),
          jsonb_build_object(
            'language', 'pt',
            'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
            'source', 'mark_interview_status:noshow'
          )
        );
      EXCEPTION WHEN OTHERS THEN
        v_send_result := jsonb_build_object('error', SQLERRM);
      END;
    END IF;
  END IF;

  IF p_status = 'noshow' AND NOT v_two_strike_applied THEN
    PERFORM public.create_notification(
      sc.member_id,
      'selection_interview_noshow',
      'No-show: ' || v_app.applicant_name,
      v_app.applicant_name || ' (' || COALESCE(v_app.chapter, '') || ') não compareceu à entrevista agendada.',
      '/admin/selection',
      'selection_interview',
      p_interview_id
    )
    FROM public.selection_committee sc
    WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'interview_status', p_status,
    'application_status', CASE WHEN v_two_strike_applied THEN 'rejected' ELSE v_new_app_status END,
    'email_dispatched', v_send_result IS NOT NULL AND (v_send_result ? 'send_id'),
    'email_send_result', v_send_result,
    'two_strike_applied', v_two_strike_applied,
    'noshow_count', v_noshow_count,
    'two_strike_email', v_two_strike_send
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.mark_interview_status(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
