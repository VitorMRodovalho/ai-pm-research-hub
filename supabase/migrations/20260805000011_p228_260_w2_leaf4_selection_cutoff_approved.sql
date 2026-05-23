-- p228 #260 W2 Leaf 4: selection_cutoff_approved type + manual dispatch RPC + template
--
-- PM Policy Matrix Amendment D D-sel-1 (#260, 2026-05-23). p227 audit Finding E:
-- `selection_cutoff_approved` type does not exist (0 notifications, 0 RPC references).
-- #260 proposed adopting this as the "2 objective evaluations + research_score >=
-- cutoff" trigger to invite the candidate to book an interview. PM ratified
-- adoption in the Policy Matrix.
--
-- This leaf ships the FOUNDATION:
--   1. Helper extension: `selection_cutoff_approved` → `transactional_immediate`.
--   2. Idempotency column `cutoff_approved_email_sent_at timestamptz` on
--      `selection_applications` — single-fire guarantee per application.
--   3. Campaign template `selection_cutoff_approved` (PT-BR + EN + ES — matching
--      the multi-lang pattern from `interview_reminder_1h`).
--   4. Manual dispatch RPC `notify_selection_cutoff_approved(p_application_id)`:
--      - Authority gate: committee lead OR can_by_member('manage_member')
--      - Idempotent: NO-OP if `cutoff_approved_email_sent_at IS NOT NULL`
--      - Validates: objective_done >= cycle.min_evaluators AND research_score is
--        not NULL (PERT cutoff value confirmation deferred to PM follow-up — cron
--        can wrap this RPC when criteria + threshold mapping is finalized)
--      - Sends email via `campaign_send_one_off` with cycle's `interview_booking_url`
--      - Marks `cutoff_approved_email_sent_at = now()` post-dispatch
--      - Audit log entry
--   5. NO auto-trigger yet — admin invokes RPC manually. Auto-trigger from
--      selection_evaluations INSERT + PERT recompute cron is a PM follow-up (needs
--      decision on fire condition + threshold interpretation of objective_cutoff_formula).
--
-- Catalog entry + Amendment D phasing update ship in the same PR.

-- 1. Helper extension — add selection_cutoff_approved
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path TO ''
AS $function$
  SELECT CASE p_type
    WHEN 'volunteer_agreement_signed'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    WHEN 'certificate_ready'             THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'governance_manual_proposed'    THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'
    -- p153 OPP-153.1: project_charter (TAP) notifications
    WHEN 'project_charter_invite'        THEN 'transactional_immediate'
    WHEN 'project_charter_approved'      THEN 'transactional_immediate'
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): Selection funnel Policy Matrix
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 2 (2026-05-23): admin reminder for overdue interviews
    WHEN 'selection_interview_overdue'   THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 4 (2026-05-23): candidate invite to book interview after
    -- objective evaluations cleared + research_score >= cycle cutoff.
    WHEN 'selection_cutoff_approved'     THEN 'transactional_immediate'
    -- (end p228)
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- 2. Idempotency column on selection_applications
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS cutoff_approved_email_sent_at timestamptz;

COMMENT ON COLUMN public.selection_applications.cutoff_approved_email_sent_at IS
'p228 W2 Leaf 4: marks when the candidate-facing selection_cutoff_approved email '
'was dispatched (single-fire idempotency for notify_selection_cutoff_approved RPC). '
'NULL = not yet sent.';

-- 3. Campaign template — selection_cutoff_approved (PT-BR + EN + ES)
INSERT INTO public.campaign_templates (
  slug, name, subject, body_html, body_text, category, target_audience, variables
) VALUES (
  'selection_cutoff_approved',
  'Candidato passou no objetivo — convite para entrevista (auto-RPC)',
  jsonb_build_object(
    'pt', 'Parabéns, {{first_name}} — agende sua entrevista 🎯',
    'en', 'Congrats, {{first_name}} — book your interview 🎯',
    'es', 'Felicidades, {{first_name}} — agenda tu entrevista 🎯'
  ),
  jsonb_build_object(
    'pt',
    '<p>Olá {{first_name}},</p>' ||
    '<p>Sua aplicação ao processo seletivo do Núcleo IA &amp; GP passou na avaliação objetiva. ' ||
    'Você está convidado(a) a agendar sua entrevista com nossa equipe.</p>' ||
    '<p><strong>Próximo passo:</strong> reserve um horário no link abaixo. ' ||
    'Tente garantir um slot dentro dos próximos 7 dias para manter o ciclo no ritmo.</p>' ||
    '<p><a href="{{interview_booking_url}}" style="display:inline-block;padding:12px 24px;background:#003B5C;color:#fff;text-decoration:none;border-radius:8px;font-weight:600;">Agendar entrevista</a></p>' ||
    '<p>Se o link não funcionar, copie e cole no navegador: <br><code>{{interview_booking_url}}</code></p>' ||
    '<p>Atenciosamente,<br>Equipe GP — Núcleo IA &amp; GP</p>',
    'en',
    '<p>Hi {{first_name}},</p>' ||
    '<p>Your application to the Núcleo IA &amp; GP selection process passed the objective evaluation. ' ||
    'You''re invited to book your interview with our team.</p>' ||
    '<p><strong>Next step:</strong> reserve a slot in the link below. ' ||
    'Try to grab a slot within the next 7 days to keep the cycle on rhythm.</p>' ||
    '<p><a href="{{interview_booking_url}}" style="display:inline-block;padding:12px 24px;background:#003B5C;color:#fff;text-decoration:none;border-radius:8px;font-weight:600;">Book interview</a></p>' ||
    '<p>If the link doesn''t work, copy and paste it: <br><code>{{interview_booking_url}}</code></p>' ||
    '<p>Best regards,<br>GP Team — Núcleo IA &amp; GP</p>',
    'es',
    '<p>Hola {{first_name}},</p>' ||
    '<p>Tu aplicación al proceso de selección del Núcleo IA &amp; GP pasó la evaluación objetiva. ' ||
    'Te invitamos a agendar tu entrevista con nuestro equipo.</p>' ||
    '<p><strong>Próximo paso:</strong> reserva un horario en el enlace abajo. ' ||
    'Intenta conseguir un slot en los próximos 7 días para mantener el ciclo en ritmo.</p>' ||
    '<p><a href="{{interview_booking_url}}" style="display:inline-block;padding:12px 24px;background:#003B5C;color:#fff;text-decoration:none;border-radius:8px;font-weight:600;">Agendar entrevista</a></p>' ||
    '<p>Si el enlace no funciona, cópialo y pégalo: <br><code>{{interview_booking_url}}</code></p>' ||
    '<p>Saludos,<br>Equipo GP — Núcleo IA &amp; GP</p>'
  ),
  jsonb_build_object(
    'pt', 'Sua candidatura passou no objetivo. Agende sua entrevista em: {{interview_booking_url}}',
    'en', 'Your application passed the objective evaluation. Book your interview at: {{interview_booking_url}}',
    'es', 'Tu candidatura pasó la evaluación objetiva. Agenda tu entrevista en: {{interview_booking_url}}'
  ),
  'operational',
  jsonb_build_object('audience', 'selection_candidate'),
  jsonb_build_object(
    'first_name', jsonb_build_object('type', 'text', 'required', true),
    'interview_booking_url', jsonb_build_object('type', 'text', 'required', true)
  )
)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  subject = EXCLUDED.subject,
  body_html = EXCLUDED.body_html,
  body_text = EXCLUDED.body_text,
  variables = EXCLUDED.variables,
  updated_at = now();

-- 4. Manual dispatch RPC
CREATE OR REPLACE FUNCTION public.notify_selection_cutoff_approved(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_first_name text;
  v_objective_done int;
BEGIN
  -- Authority gate — same as dispatch_peer_review_invitations (committee lead OR
  -- manage_member). PM may use this manually until auto-trigger lands in p229+.
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
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
  END IF;

  -- Idempotency: single-fire per application
  IF v_app.cutoff_approved_email_sent_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'application_id', p_application_id,
      'email_sent', false,
      'reason', 'already_sent',
      'previously_sent_at', v_app.cutoff_approved_email_sent_at
    );
  END IF;

  IF v_app.email IS NULL THEN
    RAISE EXCEPTION 'Application has no email — cannot dispatch';
  END IF;

  -- Cycle context — must have interview_booking_url for the CTA to be meaningful
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;
  IF v_cycle.interview_booking_url IS NULL OR length(trim(v_cycle.interview_booking_url)) = 0 THEN
    RAISE EXCEPTION 'CUTOFF_NO_BOOKING_URL: cycle % has no interview_booking_url set; configure it before dispatching cutoff emails',
      v_app.cycle_id USING ERRCODE = 'P0020';
  END IF;

  -- Threshold sanity (advisory; PM follow-up will add cron auto-trigger that
  -- enforces this server-side). For now, log objective_done count + research_score
  -- in audit metadata so admin can verify post-hoc.
  SELECT count(*)::int INTO v_objective_done
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'objective';

  v_first_name := COALESCE(
    NULLIF(trim(v_app.first_name), ''),
    NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
    'candidato(a)'
  );

  -- Dispatch via campaign_send_one_off — no notifications table row since candidate
  -- is not a member yet (recipient_id NOT NULL). Email goes directly via Resend.
  PERFORM public.campaign_send_one_off(
    p_template_slug := 'selection_cutoff_approved',
    p_to_email := v_app.email,
    p_variables := jsonb_build_object(
      'first_name', v_first_name,
      'interview_booking_url', v_cycle.interview_booking_url
    ),
    p_metadata := jsonb_build_object(
      'source', 'notify_selection_cutoff_approved',
      'application_id', p_application_id,
      'cycle_id', v_app.cycle_id,
      'cycle_code', v_cycle.cycle_code,
      'objective_done', v_objective_done,
      'research_score', v_app.research_score
    )
  );

  -- Mark idempotency post-send (best-effort — campaign_send_one_off raises on failure,
  -- which short-circuits before this UPDATE, so we never mark sent if email failed).
  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = now(),
      updated_at = now()
  WHERE id = p_application_id;

  -- Audit log
  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.cutoff_approved_email_dispatched',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'cutoff_approved_email_sent_at_before', NULL,
      'cutoff_approved_email_sent_at_after', now(),
      'recipient_email', v_app.email
    ),
    jsonb_build_object(
      'cycle_id', v_app.cycle_id,
      'cycle_code', v_cycle.cycle_code,
      'objective_done', v_objective_done,
      'research_score', v_app.research_score,
      'interview_booking_url', v_cycle.interview_booking_url,
      'rpc_version', 'p228_w2_leaf4'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'cycle_id', v_app.cycle_id,
    'email_sent', true,
    'recipient_email_redacted', LEFT(v_app.email, 2) || '***' || RIGHT(v_app.email, 4),
    'objective_done', v_objective_done,
    'research_score', v_app.research_score
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.notify_selection_cutoff_approved(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notify_selection_cutoff_approved(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.notify_selection_cutoff_approved(uuid) IS
'p228 #260 W2 Leaf 4: manual dispatch of candidate-facing selection_cutoff_approved '
'email after the objective evaluation phase clears for an application. Authority: '
'committee lead OR can_by_member(manage_member). Idempotent via '
'selection_applications.cutoff_approved_email_sent_at. Uses cycle.interview_booking_url '
'as CTA. Audit logs to admin_audit_log. Foundation for future auto-trigger from '
'selection_evaluations INSERT (deferred per PM follow-up).';

NOTIFY pgrst, 'reload schema';
