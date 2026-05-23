-- p228 #260 W2 Leaf 3: soft AI gate + no_ai_context path in dispatch_peer_review_invitations
--
-- PM Policy Matrix Amendment D D-sel-3 (#260, 2026-05-23). p227 audit Q5
-- surfaced cycle 4 impact: 14/38 cycle4 apps were hard-blocked by AI
-- precondition (consent_ai_analysis_at IS NULL OR ai_analysis IS NULL),
-- preventing peer review dispatch despite valid application status.
--
-- PM decision: SOFT GATE with no_ai_context path:
--   - if consent + AI analysis exists, peer review includes AI context (as before)
--   - if consent/analysis is absent, peer review may proceed without AI context
--   - do not generate/simulate AI analysis without consent (function never did this;
--     it only consumes pre-generated analysis)
--   - admin override allowed only if audited (this PR exposes `p_force_no_ai_context`
--     boolean parameter — both implicit and explicit no-AI paths log to admin_audit_log)
--
-- Behavior change matrix:
--   Before  | consent NULL | analysis NULL  → RAISE 'PEER_PRECONDITION' (hard block)
--   After   | consent + analysis present    → dispatch with v_no_ai_context=false
--           | consent OR analysis missing   → dispatch with v_no_ai_context=true
--                                              (notification body adapted; audit logged)
--           | p_force_no_ai_context=true    → dispatch with v_no_ai_context=true
--                                              (admin override; audit logged as explicit)
--
-- Forward-compat: no_ai_context flag flows into notification body, admin_audit_log
-- changes JSON, and the function's returned jsonb. Email template `peer_review_request`
-- is NOT modified in this leaf — peer reviewers see context status in admin UI when
-- they click through. Future leaf can add template-side variable if needed.
--
-- Authority gate unchanged: still requires committee lead OR manage_member capability
-- (rls_can / can_by_member). Soft AI gate is orthogonal to authority gate.
--
-- DDL note: this leaf adds a NEW parameter `p_force_no_ai_context boolean DEFAULT false`
-- to the function signature. Per CLAUDE.md database rule (GC-097 §4), parameter count
-- changes require DROP + CREATE (CREATE OR REPLACE would create a new overload instead
-- of replacing). GRANTs are restored after CREATE.

-- DROP old 2-arg signature first to avoid PostgreSQL creating a parallel overload.
-- CREATE OR REPLACE for the 3-arg signature is then equivalent to CREATE (since no
-- function with that exact signature exists yet) AND keeps the function discoverable
-- by the contract test's `findLatestFunctionMatch` helper (regex requires the
-- CREATE OR REPLACE prefix).
DROP FUNCTION IF EXISTS public.dispatch_peer_review_invitations(uuid, integer);

CREATE OR REPLACE FUNCTION public.dispatch_peer_review_invitations(
  p_application_id uuid,
  p_max_peers integer DEFAULT 2,
  p_force_no_ai_context boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
  v_no_ai_context boolean;
  v_no_ai_reason text;
  v_ai_context_body_note text;
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
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
  END IF;

  -- p228 #260 W2 Leaf 3: soft AI gate — replaces hard PEER_PRECONDITION raise.
  -- AI context is INFORMATIVE, not required. Implicit (data missing) and explicit
  -- (admin override) no-AI paths both surface via v_no_ai_context for downstream
  -- routing of notification body + audit log.
  IF p_force_no_ai_context THEN
    v_no_ai_context := true;
    v_no_ai_reason := 'admin_override';
  ELSIF v_app.consent_ai_analysis_at IS NULL THEN
    v_no_ai_context := true;
    v_no_ai_reason := 'no_consent';
  ELSIF v_app.ai_analysis IS NULL THEN
    v_no_ai_context := true;
    v_no_ai_reason := 'analysis_pending';
  ELSE
    v_no_ai_context := false;
    v_no_ai_reason := NULL;
  END IF;

  IF v_app.status NOT IN ('submitted', 'screening', 'objective_eval') THEN
    RAISE EXCEPTION 'PEER_INVALID_STATUS: status % does not allow peer review dispatch', v_app.status
      USING ERRCODE = 'P0011';
  END IF;

  SELECT count(*)::int INTO v_already_evaluated
  FROM public.selection_evaluations
  WHERE application_id = p_application_id;

  IF v_already_evaluated >= p_max_peers THEN
    RETURN jsonb_build_object(
      'success', true,
      'application_id', p_application_id,
      'invitations_dispatched', 0,
      'reason', 'already_has_min_evals',
      'existing_evaluations', v_already_evaluated,
      'no_ai_context', v_no_ai_context,
      'no_ai_reason', v_no_ai_reason
    );
  END IF;

  SELECT count(*)::int INTO v_existing_invites
  FROM public.notifications n
  WHERE n.type = 'peer_review_requested'
    AND n.source_id = p_application_id
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations e
      WHERE e.application_id = p_application_id
        AND e.evaluator_id = n.recipient_id
    );

  IF (v_existing_invites + v_already_evaluated) >= p_max_peers THEN
    RETURN jsonb_build_object(
      'success', true,
      'application_id', p_application_id,
      'invitations_dispatched', 0,
      'reason', 'already_has_pending_invitations',
      'existing_evaluations', v_already_evaluated,
      'existing_invitations', v_existing_invites,
      'no_ai_context', v_no_ai_context,
      'no_ai_reason', v_no_ai_reason
    );
  END IF;

  -- Notification body language adapts to AI context availability.
  IF v_no_ai_context THEN
    v_ai_context_body_note := 'Sem pré-análise de IA disponível (' ||
      CASE v_no_ai_reason
        WHEN 'no_consent'        THEN 'candidato sem consentimento AI'
        WHEN 'analysis_pending'  THEN 'análise AI ainda pendente'
        WHEN 'admin_override'    THEN 'override administrativo'
        ELSE 'motivo não especificado'
      END ||
      '). Avalie via CV/aplicação direta — sua leitura humana é o sinal canônico.';
  ELSE
    v_ai_context_body_note :=
      'AI pré-análise concluída; sua avaliação humana é o próximo passo.';
  END IF;

  v_eval_url := 'https://nucleoia.vitormr.dev/admin/selection?app_id=' || p_application_id || '&action=evaluate';

  FOR v_peer IN
    SELECT * FROM public._get_peer_review_eligibility(p_application_id)
    LIMIT (p_max_peers - v_already_evaluated - v_existing_invites)
  LOOP
    v_peer_first_name := split_part(v_peer.peer_name, ' ', 1);

    INSERT INTO public.notifications (
      recipient_id, type, title, body, link,
      source_type, source_id, actor_id, delivery_mode
    )
    VALUES (
      v_peer.peer_member_id,
      'peer_review_requested',
      'Avaliação de candidato: ' || v_app.applicant_name,
      'Você foi convidado(a) a avaliar a candidatura de ' || v_app.applicant_name ||
        COALESCE(' (' || v_app.chapter || ')', '') ||
        ' para a vaga de ' || COALESCE(v_app.role_applied, 'voluntário') || '. ' ||
        v_ai_context_body_note,
      '/admin/selection?app_id=' || p_application_id,
      'selection_application',
      p_application_id,
      v_caller.id,
      public._delivery_mode_for('peer_review_requested')
    )
    RETURNING id INTO v_notification_id;

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
          'cycle_id', v_app.cycle_id,
          'no_ai_context', v_no_ai_context,
          'no_ai_reason', v_no_ai_reason
        )
      );
    EXCEPTION WHEN OTHERS THEN
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

  IF v_invitations_dispatched > 0 AND v_app.status IN ('submitted', 'screening') THEN
    UPDATE public.selection_applications
    SET status = 'objective_eval', updated_at = now()
    WHERE id = p_application_id;
  END IF;

  -- Audit log: state delta + extra context. p228 W2 Leaf 3 adds no_ai_context + reason
  -- so admin trail captures the soft-gate decision for compliance review.
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
      'skipped', v_skipped_payload,
      'no_ai_context', v_no_ai_context,
      'no_ai_reason', v_no_ai_reason
    ),
    jsonb_build_object(
      'cycle_id', v_app.cycle_id,
      'organization_id', v_app.organization_id,
      'max_peers_requested', p_max_peers,
      'existing_evaluations', v_already_evaluated,
      'existing_invitations', v_existing_invites,
      'force_no_ai_context_param', p_force_no_ai_context,
      'rpc_version', 'p228_w2_leaf3'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'invitations_dispatched', v_invitations_dispatched,
    'invited', v_invited_payload,
    'skipped', v_skipped_payload,
    'application_status', CASE WHEN v_invitations_dispatched > 0 AND v_app.status IN ('submitted', 'screening') THEN 'objective_eval' ELSE v_app.status END,
    'no_ai_context', v_no_ai_context,
    'no_ai_reason', v_no_ai_reason
  );
END;
$function$;

-- Restore grants matching pre-leaf-3 state (authenticated callers via admin UI +
-- service_role via MCP/PostgREST). Anon explicitly excluded — peer dispatch is
-- evaluator-facing and requires authenticated context for can_by_member checks.
REVOKE ALL ON FUNCTION public.dispatch_peer_review_invitations(uuid, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dispatch_peer_review_invitations(uuid, integer, boolean) TO authenticated, service_role;

COMMENT ON FUNCTION public.dispatch_peer_review_invitations(uuid, integer, boolean) IS
'p228 #260 W2 Leaf 3: soft AI gate. Dispatches peer review invitations for a '
'selection_application. AI context optional — function flags no_ai_context=true '
'when consent_ai_analysis_at IS NULL, ai_analysis IS NULL, or p_force_no_ai_context=true '
'(admin override). Notification body + admin_audit_log adapt accordingly. Authority '
'gate (committee lead OR manage_member) unchanged. Returns jsonb with success, '
'invitations_dispatched, invited, skipped, application_status, no_ai_context, no_ai_reason.';

NOTIFY pgrst, 'reload schema';
