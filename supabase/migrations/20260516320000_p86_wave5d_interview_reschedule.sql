-- p86 Wave 5d: Interview Reschedule Flow
--
-- Use case: PM declines candidate-booked Calendar slot (e.g., Thayanne 2026-04-30) →
-- admin marks application interview_status='needs_reschedule' + emails candidate with
-- new booking link. Independent of Wave 5b. Risk-low: additive columns + new RPC + new
-- campaign_template + new index. Email dispatch reuses campaign_send_one_off (Pattern
-- adopted by ADR-0066 PMI Journey path) — no new EF, no new cron.
--
-- V4 authority: caller must be selection_committee.role='lead' for the cycle, OR have
-- can_by_member(caller, 'manage_member')=true. SECURITY DEFINER + search_path pinned.
--
-- Rollback:
--   DROP FUNCTION public.request_interview_reschedule(uuid, text);
--   DELETE FROM public.campaign_templates WHERE slug='interview_reschedule_request';
--   DROP INDEX IF EXISTS public.ix_selection_applications_interview_status_active;
--   ALTER TABLE public.selection_applications
--     DROP COLUMN IF EXISTS interview_reschedule_requested_by,
--     DROP COLUMN IF EXISTS interview_reschedule_requested_at,
--     DROP COLUMN IF EXISTS interview_reschedule_reason,
--     DROP COLUMN IF EXISTS interview_status;

-- 1. Schema additions on selection_applications
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS interview_status text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS interview_reschedule_reason text,
  ADD COLUMN IF NOT EXISTS interview_reschedule_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS interview_reschedule_requested_by uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.selection_applications'::regclass
      AND conname = 'selection_applications_interview_status_check'
  ) THEN
    ALTER TABLE public.selection_applications
      ADD CONSTRAINT selection_applications_interview_status_check
      CHECK (interview_status IN ('none','scheduled','needs_reschedule','completed','rescheduled'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.selection_applications'::regclass
      AND conname = 'selection_applications_interview_reschedule_requested_by_fkey'
  ) THEN
    ALTER TABLE public.selection_applications
      ADD CONSTRAINT selection_applications_interview_reschedule_requested_by_fkey
      FOREIGN KEY (interview_reschedule_requested_by) REFERENCES public.members(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_selection_applications_interview_status_active
  ON public.selection_applications (interview_status)
  WHERE interview_status <> 'none';

-- 2. Email template seed (reuses campaign_send_one_off plumbing — same path as PMI welcome)
INSERT INTO public.campaign_templates (slug, name, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'interview_reschedule_request',
  'Reagendar Entrevista — Núcleo IA & GP',
  jsonb_build_object(
    'pt', 'Vamos remarcar sua entrevista, {{first_name}}?',
    'en', 'Let''s reschedule your interview, {{first_name}}',
    'es', '¿Reagendamos tu entrevista, {{first_name}}?'
  ),
  jsonb_build_object(
    'pt', '<p>Olá {{first_name}},</p><p>Precisamos remarcar sua entrevista no Núcleo IA &amp; GP.</p><p><strong>Motivo:</strong> {{reason}}</p><p>Por favor, escolha um novo horário pelo link abaixo:</p><p><a href="{{booking_url}}">{{booking_url}}</a></p><p>Se preferir, responda este email para combinarmos diretamente.</p><p>—<br>Equipe GP — Núcleo IA</p>',
    'en', '<p>Hi {{first_name}},</p><p>We need to reschedule your interview at Núcleo IA &amp; GP.</p><p><strong>Reason:</strong> {{reason}}</p><p>Please pick a new time slot here:</p><p><a href="{{booking_url}}">{{booking_url}}</a></p><p>Or simply reply to this email and we''ll arrange it directly.</p><p>—<br>GP Team — Núcleo IA</p>',
    'es', '<p>Hola {{first_name}},</p><p>Necesitamos reagendar tu entrevista en el Núcleo IA &amp; GP.</p><p><strong>Motivo:</strong> {{reason}}</p><p>Por favor, elige un nuevo horario aquí:</p><p><a href="{{booking_url}}">{{booking_url}}</a></p><p>O responde a este email y lo organizamos directamente.</p><p>—<br>Equipo GP — Núcleo IA</p>'
  ),
  jsonb_build_object(
    'pt', E'Olá {{first_name}},\n\nPrecisamos remarcar sua entrevista no Núcleo IA & GP.\n\nMotivo: {{reason}}\n\nEscolha um novo horário: {{booking_url}}\n\nSe preferir, responda este email para combinarmos.\n\n—\nEquipe GP — Núcleo IA',
    'en', E'Hi {{first_name}},\n\nWe need to reschedule your interview at Núcleo IA & GP.\n\nReason: {{reason}}\n\nPick a new time slot: {{booking_url}}\n\nOr reply to this email.\n\n—\nGP Team — Núcleo IA',
    'es', E'Hola {{first_name}},\n\nNecesitamos reagendar tu entrevista en el Núcleo IA & GP.\n\nMotivo: {{reason}}\n\nElige un nuevo horario: {{booking_url}}\n\nO responde a este email.\n\n—\nEquipo GP — Núcleo IA'
  ),
  '{}'::jsonb,
  'onboarding',
  jsonb_build_object(
    'first_name', jsonb_build_object('type', 'text', 'required', true),
    'reason', jsonb_build_object('type', 'text', 'required', true),
    'booking_url', jsonb_build_object('type', 'text', 'required', true)
  )
)
ON CONFLICT (slug) DO NOTHING;

-- 3. RPC: request_interview_reschedule
DROP FUNCTION IF EXISTS public.request_interview_reschedule(uuid, text);
CREATE FUNCTION public.request_interview_reschedule(
  p_application_id uuid,
  p_reason text
) RETURNS jsonb
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

  IF v_app.status NOT IN ('interview_pending', 'interview_scheduled') THEN
    RAISE EXCEPTION 'Application status % does not allow reschedule request', v_app.status;
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'Reschedule reason is required';
  END IF;

  UPDATE public.selection_applications
  SET interview_status = 'needs_reschedule',
      interview_reschedule_reason = p_reason,
      interview_reschedule_requested_at = now(),
      interview_reschedule_requested_by = v_caller.id,
      updated_at = now()
  WHERE id = p_application_id;

  UPDATE public.selection_interviews
  SET status = 'rescheduled',
      notes = COALESCE(notes || E'\n', '')
            || '[' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') || ' BRT] '
            || 'Marked for reschedule by ' || COALESCE(v_caller.name, 'admin') || ': ' || p_reason
  WHERE application_id = p_application_id
    AND status = 'scheduled';

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
    'requested_by', v_caller.id,
    'requested_at', now()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.request_interview_reschedule(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.request_interview_reschedule(uuid, text) IS
  'p86 Wave 5d: Marks selection_application interview_status=needs_reschedule + emails candidate via campaign_send_one_off. V4 manage_member or committee lead. Use case: PM-declined Calendar slot.';

NOTIFY pgrst, 'reload schema';
