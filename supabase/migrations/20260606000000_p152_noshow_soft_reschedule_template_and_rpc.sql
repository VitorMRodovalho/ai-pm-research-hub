-- p152 W4 P1 (2026-05-12) — No-show soft reschedule: email template + mark_interview_status extension.
--
-- Strategic: PM ask 12/05 — quando admin marca No-Show no modal Entrevista,
-- atualmente só atualiza DB + notifica GP in-platform. Candidato NÃO recebe
-- nada — quebra retomada do funil para candidatos que tiveram imprevistos
-- legítimos (engarrafamento, doença, conflito agenda).
--
-- Best practice industry: email empático + soft reschedule link com prazo
-- (não auto-reject; preserva human judgment via PM).
--
-- Implementação:
--   1. INSERT template `interview_noshow_soft_reschedule` (PT/EN/ES) — tone
--      empático, sem culpabilizar, com link cycle.interview_booking_url e
--      deadline (default 7d).
--   2. UPDATE `mark_interview_status` quando p_status='noshow':
--      - Só dispara email se status anterior ≠ 'noshow' (idempotência —
--        PM pode re-clicar sem enviar 2 emails).
--      - Usa `campaign_send_one_off` (mesmo pattern de request_interview_reschedule).
--      - Resolve booking_url via cycle.interview_booking_url; fallback hard-coded.
--      - Adiciona send_result ao retorno JSONB.

-- ─── 1) Email template ─────────────────────────────────────────────────────

INSERT INTO public.campaign_templates (slug, name, subject, body_html, body_text, category, target_audience, variables)
VALUES (
  'interview_noshow_soft_reschedule',
  'No-show Soft Reschedule (auto pós-noshow)',
  jsonb_build_object(
    'pt', 'Sentimos sua falta hoje, {{first_name}} — vamos reagendar?',
    'en', 'We missed you today, {{first_name}} — shall we reschedule?',
    'es', 'No pudimos verte hoy, {{first_name}} — ¿reagendamos?'
  ),
  jsonb_build_object(
    'pt',
    '<p>Olá {{first_name}},</p>' ||
    '<p>Notamos que você não pôde comparecer à sua entrevista hoje no Núcleo IA &amp; GP. Imprevistos acontecem — entendemos completamente.</p>' ||
    '<p>Se ainda tem interesse em participar do nosso ciclo seletivo, basta escolher um novo horário até <strong>{{deadline_date}}</strong>:</p>' ||
    '<p><a href="{{booking_url}}" style="background:#1e2a78;color:#fff;padding:10px 20px;border-radius:8px;text-decoration:none;display:inline-block;font-weight:bold">→ Reagendar entrevista</a></p>' ||
    '<p>Se preferir, responda este email e combinamos diretamente.</p>' ||
    '<p>Caso não consiga reagendar até a data limite, finalizaremos seu processo seletivo — você pode aplicar novamente em ciclos futuros.</p>' ||
    '<p>Atenciosamente,<br>Equipe GP — Núcleo IA &amp; GP</p>',
    'en',
    '<p>Hi {{first_name}},</p>' ||
    '<p>We noticed you couldn''t attend your interview today at Núcleo IA &amp; GP. Things happen — we completely understand.</p>' ||
    '<p>If you''re still interested in joining our selection cycle, please pick a new time slot by <strong>{{deadline_date}}</strong>:</p>' ||
    '<p><a href="{{booking_url}}" style="background:#1e2a78;color:#fff;padding:10px 20px;border-radius:8px;text-decoration:none;display:inline-block;font-weight:bold">→ Reschedule interview</a></p>' ||
    '<p>If you prefer, simply reply to this email and we''ll arrange it directly.</p>' ||
    '<p>If you can''t reschedule by the deadline, we''ll close your selection process — you''re always welcome to apply in future cycles.</p>' ||
    '<p>Best regards,<br>GP Team — Núcleo IA &amp; GP</p>',
    'es',
    '<p>Hola {{first_name}},</p>' ||
    '<p>Notamos que no pudiste asistir a tu entrevista hoy en el Núcleo IA &amp; GP. Imprevistos suceden — lo entendemos perfectamente.</p>' ||
    '<p>Si aún tienes interés en participar de nuestro ciclo selectivo, elige un nuevo horario hasta <strong>{{deadline_date}}</strong>:</p>' ||
    '<p><a href="{{booking_url}}" style="background:#1e2a78;color:#fff;padding:10px 20px;border-radius:8px;text-decoration:none;display:inline-block;font-weight:bold">→ Reagendar entrevista</a></p>' ||
    '<p>Si prefieres, responde este email y lo coordinamos directamente.</p>' ||
    '<p>Si no puedes reagendar hasta la fecha límite, cerraremos tu proceso selectivo — siempre puedes postular en ciclos futuros.</p>' ||
    '<p>Saludos,<br>Equipo GP — Núcleo IA &amp; GP</p>'
  ),
  jsonb_build_object(
    'pt', 'Olá {{first_name}}, notamos que você não compareceu à entrevista hoje. Reagende em: {{booking_url}} (até {{deadline_date}}).',
    'en', 'Hi {{first_name}}, you missed today''s interview. Reschedule: {{booking_url}} (by {{deadline_date}}).',
    'es', 'Hola {{first_name}}, no asististe a la entrevista de hoy. Reagenda: {{booking_url}} (hasta {{deadline_date}}).'
  ),
  'operational',
  jsonb_build_object('audience', 'selection_candidate'),
  jsonb_build_object(
    'first_name', jsonb_build_object('type', 'text', 'required', true),
    'booking_url', jsonb_build_object('type', 'text', 'required', true),
    'deadline_date', jsonb_build_object('type', 'text', 'required', true)
  )
)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  subject = EXCLUDED.subject,
  body_html = EXCLUDED.body_html,
  body_text = EXCLUDED.body_text,
  variables = EXCLUDED.variables,
  updated_at = now();

-- ─── 2) Update mark_interview_status with no-show email trigger ────────────

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

  -- p152 W4 P1: dispatch soft-reschedule email on no-show transition.
  -- Idempotent: only fires if prior status ≠ 'noshow' (PM can re-click without re-emailing).
  IF p_status = 'noshow' AND v_prior_status IS DISTINCT FROM 'noshow' THEN
    v_first_name := COALESCE(
      NULLIF(trim(v_app.first_name), ''),
      NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
      'candidato(a)'
    );
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
      -- Don't fail the no-show marking if email dispatch errors; surface as warning.
      v_send_result := jsonb_build_object('error', SQLERRM);
    END;
  END IF;

  -- In-platform notification to committee lead (preserved).
  IF p_status = 'noshow' THEN
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
    'application_status', v_new_app_status,
    'email_dispatched', v_send_result IS NOT NULL AND (v_send_result ? 'send_id'),
    'email_send_result', v_send_result
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.mark_interview_status(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
