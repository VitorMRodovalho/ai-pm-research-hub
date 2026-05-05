-- p92 Phase C — Peer review round-robin dispatch
-- Audit context: docs/specs/p91-selection-journey-audit.md Bug #5
-- Decision: PM 2026-05-05 ratify round-robin between committee evaluators+leads
-- Status transition: 'submitted'/'screening' → 'objective_eval' on first invitation
-- Reuses: campaign_send_one_off (template peer_review_request), notifications,
--         create_notification helper, can_by_member authority gate.

-- ===== 1. Helper: _get_peer_review_eligibility =====
-- Returns committee members who can be invited as peers for an application.
-- Excludes: observers (cannot evaluate), already invited for this app, already
-- submitted eval for this app, candidate themselves.
CREATE OR REPLACE FUNCTION public._get_peer_review_eligibility(
  p_application_id uuid
)
RETURNS TABLE (
  peer_member_id uuid,
  peer_name text,
  peer_email text,
  load_count int,
  last_invited_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $func$
DECLARE
  v_app record;
BEGIN
  SELECT cycle_id, email INTO v_app
  FROM public.selection_applications
  WHERE id = p_application_id;

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found: %', p_application_id;
  END IF;

  RETURN QUERY
  SELECT
    m.id AS peer_member_id,
    m.name AS peer_name,
    m.email AS peer_email,
    -- load_count = submitted evals + pending invitations (not yet evaluated).
    -- Including pending ensures true round-robin rotation within a batch dispatch
    -- (without it, peer with 0 submitted always wins until they actually evaluate).
    (
      SELECT count(*)::int
      FROM public.selection_evaluations e
      JOIN public.selection_applications sa ON sa.id = e.application_id
      WHERE e.evaluator_id = m.id AND sa.cycle_id = v_app.cycle_id
    )
    +
    (
      SELECT count(*)::int
      FROM public.notifications n
      JOIN public.selection_applications sa ON sa.id = n.source_id
      WHERE n.type = 'peer_review_requested'
        AND n.recipient_id = m.id
        AND sa.cycle_id = v_app.cycle_id
        AND NOT EXISTS (
          SELECT 1 FROM public.selection_evaluations e2
          WHERE e2.application_id = n.source_id AND e2.evaluator_id = m.id
        )
    ) AS load_count,
    -- last_invited_at: most recent peer_review_requested notification
    (
      SELECT max(n.created_at)
      FROM public.notifications n
      JOIN public.selection_applications sa ON sa.id = n.source_id
      WHERE n.type = 'peer_review_requested'
        AND n.recipient_id = m.id
        AND sa.cycle_id = v_app.cycle_id
    ) AS last_invited_at
  FROM public.selection_committee sc
  JOIN public.members m ON m.id = sc.member_id
  WHERE sc.cycle_id = v_app.cycle_id
    AND sc.role IN ('evaluator', 'lead')
    -- Exclude already invited for this specific application
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.type = 'peer_review_requested'
        AND n.recipient_id = m.id
        AND n.source_id = p_application_id
    )
    -- Exclude already submitted eval for this application
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations e
      WHERE e.application_id = p_application_id
        AND e.evaluator_id = m.id
    )
    -- Exclude the candidate themselves (if they happen to be a member)
    AND m.email != v_app.email
  ORDER BY load_count ASC, last_invited_at ASC NULLS FIRST, m.name ASC;
END;
$func$;

REVOKE ALL ON FUNCTION public._get_peer_review_eligibility(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._get_peer_review_eligibility(uuid) TO authenticated;

COMMENT ON FUNCTION public._get_peer_review_eligibility(uuid) IS
'Internal helper for dispatch_peer_review_invitations. Returns ordered list of '
'eligible peer reviewers (committee evaluator/lead), excluding already-invited and '
'already-submitted. Sort key: load_count ASC, last_invited_at ASC NULLS FIRST.';

-- ===== 2. Main RPC: dispatch_peer_review_invitations =====
CREATE OR REPLACE FUNCTION public.dispatch_peer_review_invitations(
  p_application_id uuid,
  p_max_peers int DEFAULT 2
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $func$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_peer record;
  v_peer_first_name text;
  v_eval_url text;
  v_invitations_dispatched int := 0;
  v_already_evaluated int;
  v_invited_payload jsonb := '[]'::jsonb;
  v_skipped_payload jsonb := '[]'::jsonb;
  v_notification_id uuid;
  v_existing_invites int;
BEGIN
  -- Auth check
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- Load application
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- Authority: caller must be committee lead OR have manage_member
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
  END IF;

  -- Pre-condition: AI analysis + consent done
  IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
    RAISE EXCEPTION 'PEER_PRECONDITION: candidate has no AI analysis; cannot dispatch peer review yet'
      USING ERRCODE = 'P0010';
  END IF;

  -- Pre-condition: status must be submitted/screening/objective_eval
  IF v_app.status NOT IN ('submitted', 'screening', 'objective_eval') THEN
    RAISE EXCEPTION 'PEER_INVALID_STATUS: status % does not allow peer review dispatch', v_app.status
      USING ERRCODE = 'P0011';
  END IF;

  -- Don't re-invite if app already has enough evals
  SELECT count(*)::int INTO v_already_evaluated
  FROM public.selection_evaluations
  WHERE application_id = p_application_id;

  IF v_already_evaluated >= p_max_peers THEN
    RETURN jsonb_build_object(
      'success', true,
      'application_id', p_application_id,
      'invitations_dispatched', 0,
      'reason', 'already_has_min_evals',
      'existing_evaluations', v_already_evaluated
    );
  END IF;

  -- Check pending invitations not yet evaluated
  SELECT count(*)::int INTO v_existing_invites
  FROM public.notifications n
  WHERE n.type = 'peer_review_requested'
    AND n.source_id = p_application_id
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations e
      WHERE e.application_id = p_application_id
        AND e.evaluator_id = n.recipient_id
    );

  -- If pending invitations + already-evaluated already covers max_peers, skip
  IF (v_existing_invites + v_already_evaluated) >= p_max_peers THEN
    RETURN jsonb_build_object(
      'success', true,
      'application_id', p_application_id,
      'invitations_dispatched', 0,
      'reason', 'already_has_pending_invitations',
      'existing_evaluations', v_already_evaluated,
      'existing_invitations', v_existing_invites
    );
  END IF;

  v_eval_url := 'https://nucleoia.vitormr.dev/admin/selection?app_id=' || p_application_id || '&action=evaluate';

  -- Round-robin dispatch
  FOR v_peer IN
    SELECT * FROM public._get_peer_review_eligibility(p_application_id)
    LIMIT (p_max_peers - v_already_evaluated - v_existing_invites)
  LOOP
    v_peer_first_name := split_part(v_peer.peer_name, ' ', 1);

    -- Insert in-platform notification (audit trail)
    INSERT INTO public.notifications (
      recipient_id,
      type,
      title,
      body,
      link,
      source_type,
      source_id,
      actor_id,
      delivery_mode
    )
    VALUES (
      v_peer.peer_member_id,
      'peer_review_requested',
      'Avaliação de candidato: ' || v_app.applicant_name,
      'Você foi convidado(a) a avaliar a candidatura de ' || v_app.applicant_name ||
        COALESCE(' (' || v_app.chapter || ')', '') ||
        ' para a vaga de ' || COALESCE(v_app.role_applied, 'voluntário') || '. ' ||
        'AI pré-análise concluída; sua avaliação humana é o próximo passo.',
      '/admin/selection?app_id=' || p_application_id,
      'selection_application',
      p_application_id,
      v_caller.id,
      'transactional_immediate'
    )
    RETURNING id INTO v_notification_id;

    -- Send email via campaign_send_one_off
    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'peer_review_request',
        p_to_email := v_peer.peer_email,
        p_variables := jsonb_build_object(
          'peer_first_name', v_peer_first_name,
          'applicant_name', v_app.applicant_name,
          'chapter', COALESCE(v_app.chapter, '—'),
          'role_applied', COALESCE(v_app.role_applied, 'voluntário'),
          'eval_url', v_eval_url
        ),
        p_metadata := jsonb_build_object(
          'source', 'dispatch_peer_review_invitations',
          'application_id', p_application_id,
          'peer_member_id', v_peer.peer_member_id,
          'notification_id', v_notification_id,
          'cycle_id', v_app.cycle_id
        )
      );
    EXCEPTION WHEN OTHERS THEN
      -- Log + continue with next peer; the notification serves as fallback
      v_skipped_payload := v_skipped_payload || jsonb_build_object(
        'peer_member_id', v_peer.peer_member_id,
        'peer_name', v_peer.peer_name,
        'reason', 'email_dispatch_failed',
        'error', SQLERRM
      );
      CONTINUE;
    END;

    v_invitations_dispatched := v_invitations_dispatched + 1;
    v_invited_payload := v_invited_payload || jsonb_build_object(
      'peer_member_id', v_peer.peer_member_id,
      'peer_name', v_peer.peer_name,
      'load_count_before', v_peer.load_count,
      'last_invited_at_before', v_peer.last_invited_at,
      'notification_id', v_notification_id
    );
  END LOOP;

  -- Status transition: advance to objective_eval if currently submitted/screening
  IF v_invitations_dispatched > 0 AND v_app.status IN ('submitted', 'screening') THEN
    UPDATE public.selection_applications
    SET status = 'objective_eval', updated_at = now()
    WHERE id = p_application_id;
  END IF;

  -- Audit log: use 'changes' (state delta) + 'metadata' (extra context)
  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.peer_review_dispatched',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'invitations_dispatched', v_invitations_dispatched,
      'status_before', v_app.status,
      'status_after', CASE WHEN v_invitations_dispatched > 0 AND v_app.status IN ('submitted', 'screening') THEN 'objective_eval' ELSE v_app.status END,
      'invited', v_invited_payload,
      'skipped', v_skipped_payload
    ),
    jsonb_build_object(
      'cycle_id', v_app.cycle_id,
      'organization_id', v_app.organization_id,
      'max_peers_requested', p_max_peers,
      'existing_evaluations', v_already_evaluated,
      'existing_invitations', v_existing_invites,
      'rpc_version', 'p92_phase_c_v1'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'invitations_dispatched', v_invitations_dispatched,
    'invited', v_invited_payload,
    'skipped', v_skipped_payload,
    'application_status', CASE WHEN v_invitations_dispatched > 0 AND v_app.status IN ('submitted', 'screening') THEN 'objective_eval' ELSE v_app.status END
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.dispatch_peer_review_invitations(uuid, int) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_peer_review_invitations(uuid, int) TO authenticated;

COMMENT ON FUNCTION public.dispatch_peer_review_invitations(uuid, int) IS
'Round-robin peer review invitation dispatch. Selects up to N committee evaluators '
'(role IN evaluator/lead) ordered by load_count ASC, last_invited_at ASC NULLS FIRST. '
'Inserts in-platform notification + sends peer_review_request email + transitions '
'application status from submitted/screening to objective_eval. Authority: committee '
'lead OR manage_member. Pre-condition: ai_analysis + consent_ai_analysis_at populated.';

-- ===== 3. Email template: peer_review_request (3 langs) =====
INSERT INTO public.campaign_templates (slug, name, subject, body_html, body_text, variables, category, target_audience, created_at, updated_at)
VALUES (
  'peer_review_request',
  'Peer review invitation (selection cycle)',
  jsonb_build_object(
    'pt', 'Avaliação de candidato: {{applicant_name}}',
    'en', 'Candidate review request: {{applicant_name}}',
    'es', 'Evaluación de candidato: {{applicant_name}}'
  ),
  jsonb_build_object(
    'pt', '<p>Olá {{peer_first_name}},</p>' ||
          '<p>Você foi escolhido(a) (round-robin) para avaliar a candidatura de <strong>{{applicant_name}}</strong> ({{chapter}}, vaga de {{role_applied}}).</p>' ||
          '<p>A pré-análise por IA já foi concluída — sua avaliação humana é o próximo passo crítico antes da entrevista. Esperamos 2 avaliações por candidato; você é uma delas.</p>' ||
          '<p><a href="{{eval_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Avaliar candidato</a></p>' ||
          '<p style="color:#666;font-size:13px;">Se você não puder avaliar este(a) candidato(a) (conflito de interesse, indisponibilidade), responda este email — outro avaliador será atribuído.</p>' ||
          '<p>Obrigado!<br/>Núcleo IA &amp; GP — Comitê de Seleção</p>',
    'en', '<p>Hello {{peer_first_name}},</p>' ||
          '<p>You were selected (round-robin) to evaluate <strong>{{applicant_name}}</strong>''s application ({{chapter}}, role: {{role_applied}}).</p>' ||
          '<p>AI pre-analysis is complete — your human review is the next critical step before the interview. We expect 2 evaluations per candidate; you are one of them.</p>' ||
          '<p><a href="{{eval_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Review candidate</a></p>' ||
          '<p style="color:#666;font-size:13px;">If you cannot evaluate this candidate (conflict of interest, unavailability), reply to this email — another reviewer will be assigned.</p>' ||
          '<p>Thank you!<br/>Núcleo IA &amp; GP — Selection Committee</p>',
    'es', '<p>Hola {{peer_first_name}},</p>' ||
          '<p>Has sido seleccionado(a) (round-robin) para evaluar la candidatura de <strong>{{applicant_name}}</strong> ({{chapter}}, rol de {{role_applied}}).</p>' ||
          '<p>El pre-análisis por IA ya finalizó — tu evaluación humana es el próximo paso crítico antes de la entrevista. Esperamos 2 evaluaciones por candidato; tú eres una de ellas.</p>' ||
          '<p><a href="{{eval_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Evaluar candidato</a></p>' ||
          '<p style="color:#666;font-size:13px;">Si no puedes evaluar a este(a) candidato(a) (conflicto de interés, indisponibilidad), responde este correo — se asignará otro revisor.</p>' ||
          '<p>¡Gracias!<br/>Núcleo IA &amp; GP — Comité de Selección</p>'
  ),
  jsonb_build_object(
    'pt', 'Olá {{peer_first_name}},\n\nVocê foi escolhido(a) (round-robin) para avaliar a candidatura de {{applicant_name}} ({{chapter}}, vaga de {{role_applied}}).\n\nPré-análise IA concluída. Sua avaliação humana é o próximo passo crítico.\n\nAvaliar: {{eval_url}}\n\nSe não puder, responda este email.\n\nNúcleo IA & GP',
    'en', 'Hello {{peer_first_name}},\n\nYou were selected (round-robin) to evaluate {{applicant_name}}''s application ({{chapter}}, role: {{role_applied}}).\n\nAI pre-analysis complete. Your human review is the next critical step.\n\nReview: {{eval_url}}\n\nIf unavailable, reply to this email.\n\nNúcleo IA & GP',
    'es', 'Hola {{peer_first_name}},\n\nHas sido seleccionado(a) (round-robin) para evaluar la candidatura de {{applicant_name}} ({{chapter}}, rol: {{role_applied}}).\n\nPre-análisis IA completo. Tu evaluación humana es el próximo paso crítico.\n\nEvaluar: {{eval_url}}\n\nSi no puedes, responde este correo.\n\nNúcleo IA & GP'
  ),
  jsonb_build_object(
    'peer_first_name', jsonb_build_object('type', 'text', 'required', true),
    'applicant_name',  jsonb_build_object('type', 'text', 'required', true),
    'chapter',         jsonb_build_object('type', 'text', 'required', true),
    'role_applied',    jsonb_build_object('type', 'text', 'required', true),
    'eval_url',        jsonb_build_object('type', 'text', 'required', true)
  ),
  'operational',
  jsonb_build_object('audience', 'selection_committee'),
  now(),
  now()
)
ON CONFLICT (slug) DO UPDATE SET
  subject = EXCLUDED.subject,
  body_html = EXCLUDED.body_html,
  body_text = EXCLUDED.body_text,
  variables = EXCLUDED.variables,
  updated_at = now();

NOTIFY pgrst, 'reload schema';
