-- p92 Phase E — Reschedule nudge loop
-- Audit context: docs/specs/p91-selection-journey-audit.md Bug #6
-- Pre-requisite: Phase B B3 (webhook clears interview_status flags) — already shipped p92.
-- Pattern: daily cron checks for candidates with interview_status='needs_reschedule'
-- where reschedule was requested >3d ago and they haven't rebooked yet → send nudge.

-- ===== 1. Track when we last nudged (avoid daily double-nudge) =====
ALTER TABLE public.selection_applications
ADD COLUMN IF NOT EXISTS interview_reschedule_last_nudged_at timestamptz;

COMMENT ON COLUMN public.selection_applications.interview_reschedule_last_nudged_at IS
'Last time process_pending_reschedule_nudges sent a reminder. NULL if never nudged. '
'Cleared by Calendar webhook on rebook (along with other reschedule fields).';

-- ===== 2. Email template: interview_reschedule_nudge =====
INSERT INTO public.campaign_templates (slug, name, subject, body_html, body_text, variables, category, target_audience, created_at, updated_at)
VALUES (
  'interview_reschedule_nudge',
  'Interview reschedule nudge (3-day reminder)',
  jsonb_build_object(
    'pt', 'Lembrete: vamos remarcar sua entrevista, {{first_name}}?',
    'en', 'Reminder: let''s reschedule your interview, {{first_name}}?',
    'es', 'Recordatorio: ¿agendamos tu entrevista, {{first_name}}?'
  ),
  jsonb_build_object(
    'pt', '<p>Olá {{first_name}},</p>' ||
          '<p>Há alguns dias enviamos um link para você remarcar sua entrevista (motivo: {{reason}}). Notamos que ainda não foi agendado um novo horário.</p>' ||
          '<p>Para concluir o processo seletivo, é importante remarcar nas próximas 48 horas:</p>' ||
          '<p><a href="{{booking_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Escolher novo horário</a></p>' ||
          '<p style="color:#666;font-size:13px;">Se a remarcação não ocorrer, sua candidatura pode ficar pausada. Caso prefira desistir, responda este email — não tem problema, apenas precisamos saber.</p>' ||
          '<p>Obrigado!<br/>Núcleo IA &amp; GP</p>',
    'en', '<p>Hello {{first_name}},</p>' ||
          '<p>A few days ago we sent you a link to reschedule your interview (reason: {{reason}}). We noticed a new slot has not yet been booked.</p>' ||
          '<p>To complete the selection process, please rebook within the next 48 hours:</p>' ||
          '<p><a href="{{booking_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Pick a new slot</a></p>' ||
          '<p style="color:#666;font-size:13px;">If the rebook does not happen, your application may be paused. If you prefer to withdraw, just reply to this email — no problem, we just need to know.</p>' ||
          '<p>Thank you!<br/>Núcleo IA &amp; GP</p>',
    'es', '<p>Hola {{first_name}},</p>' ||
          '<p>Hace algunos días te enviamos un enlace para reagendar tu entrevista (motivo: {{reason}}). Notamos que aún no se ha agendado un nuevo horario.</p>' ||
          '<p>Para completar el proceso, por favor reagenda en las próximas 48 horas:</p>' ||
          '<p><a href="{{booking_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Elegir nuevo horario</a></p>' ||
          '<p style="color:#666;font-size:13px;">Si el reagendamiento no ocurre, tu candidatura puede quedar en pausa. Si prefieres desistir, responde este correo — sin problema, solo necesitamos saber.</p>' ||
          '<p>¡Gracias!<br/>Núcleo IA &amp; GP</p>'
  ),
  jsonb_build_object(
    'pt', 'Olá {{first_name}},\n\nHá alguns dias enviamos um link para remarcar sua entrevista (motivo: {{reason}}). Por favor remarque em 48h: {{booking_url}}\n\nSe preferir desistir, responda este email.\n\nNúcleo IA & GP',
    'en', 'Hello {{first_name}},\n\nA few days ago we sent a link to reschedule your interview (reason: {{reason}}). Please rebook within 48h: {{booking_url}}\n\nIf you prefer to withdraw, reply to this email.\n\nNúcleo IA & GP',
    'es', 'Hola {{first_name}},\n\nHace algunos días te enviamos un enlace para reagendar tu entrevista (motivo: {{reason}}). Por favor reagenda en 48h: {{booking_url}}\n\nSi prefieres desistir, responde este correo.\n\nNúcleo IA & GP'
  ),
  jsonb_build_object(
    'first_name',  jsonb_build_object('type', 'text', 'required', true),
    'reason',      jsonb_build_object('type', 'text', 'required', true),
    'booking_url', jsonb_build_object('type', 'text', 'required', true)
  ),
  'operational',
  jsonb_build_object('audience', 'selection_candidate'),
  now(),
  now()
)
ON CONFLICT (slug) DO UPDATE SET
  subject = EXCLUDED.subject,
  body_html = EXCLUDED.body_html,
  body_text = EXCLUDED.body_text,
  variables = EXCLUDED.variables,
  updated_at = now();

-- ===== 3. RPC: process_pending_reschedule_nudges =====
CREATE OR REPLACE FUNCTION public.process_pending_reschedule_nudges()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $func$
DECLARE
  v_app record;
  v_cycle record;
  v_first_name text;
  v_booking_url text;
  v_nudges_sent int := 0;
  v_errors jsonb := '[]'::jsonb;
  v_processed jsonb := '[]'::jsonb;
BEGIN
  -- Cron-context auth bypass (no JWT). Aligns with ADR-0028 amendment p89 pattern.
  -- This RPC is only invoked by pg_cron (no human callers) so explicit role gate
  -- would never pass; we trust the scheduler context.
  IF auth.role() IS NOT NULL AND auth.role() NOT IN ('service_role') AND auth.uid() IS NOT NULL THEN
    -- A real user is calling — they must have manage_member
    IF NOT public.can_by_member(
      (SELECT id FROM public.members WHERE auth_id = auth.uid()),
      'manage_member'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: cron RPC requires manage_member or service_role';
    END IF;
  END IF;

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.email, a.cycle_id,
           a.interview_reschedule_reason,
           a.interview_reschedule_requested_at,
           a.interview_reschedule_last_nudged_at
    FROM public.selection_applications a
    WHERE a.interview_status = 'needs_reschedule'
      AND a.interview_reschedule_requested_at IS NOT NULL
      AND a.interview_reschedule_requested_at < now() - interval '3 days'
      AND (
        a.interview_reschedule_last_nudged_at IS NULL
        OR a.interview_reschedule_last_nudged_at < now() - interval '3 days'
      )
      AND a.status IN ('interview_pending', 'interview_scheduled')
  LOOP
    v_first_name := split_part(v_app.applicant_name, ' ', 1);

    SELECT interview_booking_url INTO v_cycle
    FROM public.selection_cycles
    WHERE id = v_app.cycle_id;

    v_booking_url := COALESCE(
      v_cycle.interview_booking_url,
      'https://calendar.app.google/gh9WjefjcmisVLoh7'  -- PM 2026-05-05 fallback
    );

    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'interview_reschedule_nudge',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'reason', COALESCE(v_app.interview_reschedule_reason, '—'),
          'booking_url', v_booking_url
        ),
        p_metadata := jsonb_build_object(
          'source', 'process_pending_reschedule_nudges',
          'application_id', v_app.id,
          'reschedule_requested_at', v_app.interview_reschedule_requested_at,
          'last_nudged_at_before', v_app.interview_reschedule_last_nudged_at,
          'days_pending', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0
        )
      );

      UPDATE public.selection_applications
      SET interview_reschedule_last_nudged_at = now()
      WHERE id = v_app.id;

      v_nudges_sent := v_nudges_sent + 1;
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'days_since_request', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0
      );

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'nudges_sent', v_nudges_sent,
    'processed', v_processed,
    'errors', v_errors,
    'run_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.process_pending_reschedule_nudges() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_pending_reschedule_nudges() TO authenticated, service_role;

COMMENT ON FUNCTION public.process_pending_reschedule_nudges() IS
'Cron-driven RPC: nudge candidatos com interview_status=needs_reschedule e '
'reschedule_requested_at >3d sem rebook. Cooldown de 3d entre nudges (last_nudged_at). '
'Pré-condição: status IN (interview_pending, interview_scheduled). Auth: bypass para '
'cron context (sem JWT) per ADR-0028 amendment p89.';

-- ===== 4. Pg_cron job: daily 11:00 BRT (14:00 UTC) =====
-- Slot avoid: 03:00 UTC cluster, hourly :00 cluster, Saturday 12:00 UTC, Sunday 04-05.
-- 14:00 UTC = 11:00 BRT (business hours start in São Paulo). Daily.
SELECT cron.schedule(
  'nudge-reschedule-pending-daily',
  '0 14 * * *',
  $cron$ SELECT public.process_pending_reschedule_nudges() $cron$
);

NOTIFY pgrst, 'reload schema';
