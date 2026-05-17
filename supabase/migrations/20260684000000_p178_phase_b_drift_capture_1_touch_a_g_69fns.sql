-- p178 Phase B drift capture — 1-touch bucket A-G (69 fns).
--
-- Recurring drift-recovery under Q-C/Phase-C charter
-- (docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md §Phase C). Each fn below is currently
-- in the 1-touch bucket of `RPC_BODY_DRIFT_ALLOWLIST_P175.txt` — captured by
-- exactly one prior migration whose body has since drifted from live.
--
-- Bodies pulled via pg_get_functiondef() — live IS canonical at the time of
-- capture. After apply, these fns are clean per Phase C body-hash drift contract
-- and can be removed from the allowlist. BODY_DRIFT_BASELINE_SIZE 157→88.
--
-- Rollback: not needed — capturing live state. To revert a single fn, restore
-- its prior CREATE OR REPLACE FUNCTION body from the migration in `latest_file`
-- (see p178 audit report at /tmp/drift-audit/p178-postfix-v2.json).

CREATE OR REPLACE FUNCTION public.admin_decide_dual_track(p_application_id uuid, p_researcher_decision text, p_leader_decision text, p_feedback text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id          uuid;
  v_app                record;
  v_sibling_app        record;
  v_researcher_app_id  uuid;
  v_leader_app_id      uuid;
  v_scored             record;
  v_unscored_id        uuid;
  v_researcher_result  json;
  v_leader_result      json;
  v_copied_scores      boolean := false;
  v_allowed_decisions  text[] := ARRAY['approved','rejected','waitlist'];
BEGIN
  -- Auth
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  -- Validate decisions
  IF NOT (p_researcher_decision = ANY(v_allowed_decisions)) THEN
    RETURN json_build_object('error', 'Invalid researcher_decision: ' || p_researcher_decision);
  END IF;
  IF NOT (p_leader_decision = ANY(v_allowed_decisions)) THEN
    RETURN json_build_object('error', 'Invalid leader_decision: ' || p_leader_decision);
  END IF;

  -- Resolve pair
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  IF v_app.promotion_path IS DISTINCT FROM 'dual_track' OR v_app.linked_application_id IS NULL THEN
    RETURN json_build_object('error', 'Application is not part of a dual_track pair');
  END IF;

  SELECT * INTO v_sibling_app FROM public.selection_applications WHERE id = v_app.linked_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Sibling application not found'); END IF;

  -- Determine researcher/leader app id
  IF v_app.role_applied = 'researcher' AND v_sibling_app.role_applied = 'leader' THEN
    v_researcher_app_id := v_app.id;
    v_leader_app_id     := v_sibling_app.id;
  ELSIF v_app.role_applied = 'leader' AND v_sibling_app.role_applied = 'researcher' THEN
    v_researcher_app_id := v_sibling_app.id;
    v_leader_app_id     := v_app.id;
  ELSE
    RETURN json_build_object('error', 'Pair roles are not researcher+leader (' || v_app.role_applied || ' + ' || v_sibling_app.role_applied || ')');
  END IF;

  -- Auto-copy role-agnostic scores (objective + interview) from scored to unscored.
  -- Done before applying decisions so that downstream final_score recompute (next ranking
  -- recalc) sees consistent data on both apps.
  SELECT id, objective_score_avg, interview_score INTO v_scored
  FROM   public.selection_applications
  WHERE  id IN (v_researcher_app_id, v_leader_app_id)
    AND  objective_score_avg IS NOT NULL
  ORDER BY (CASE WHEN id = v_leader_app_id THEN 0 ELSE 1 END)  -- prefer leader if both scored
  LIMIT 1;

  IF FOUND THEN
    v_unscored_id := CASE WHEN v_scored.id = v_researcher_app_id THEN v_leader_app_id ELSE v_researcher_app_id END;

    UPDATE public.selection_applications
    SET    objective_score_avg = COALESCE(objective_score_avg, v_scored.objective_score_avg),
           interview_score     = COALESCE(interview_score,     v_scored.interview_score),
           updated_at          = now()
    WHERE  id = v_unscored_id
      AND  (objective_score_avg IS NULL OR interview_score IS NULL);

    IF FOUND THEN v_copied_scores := true; END IF;
  END IF;

  -- Apply per-role decisions via existing single-app RPC (preserves onboarding seed,
  -- Op B promotion, notification, audit log behaviors).
  v_researcher_result := public.admin_update_application(
    v_researcher_app_id,
    jsonb_build_object(
      'status',   p_researcher_decision,
      'feedback', COALESCE(p_feedback, '')
    )
  );

  v_leader_result := public.admin_update_application(
    v_leader_app_id,
    jsonb_build_object(
      'status',   p_leader_decision,
      'feedback', COALESCE(p_feedback, '')
    )
  );

  -- Cross-decision audit entry (separable from per-app audits done by admin_update_application)
  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_dual_track_decision',
    'info',
    v_app.applicant_name || ': researcher=' || p_researcher_decision || ', leader=' || p_leader_decision,
    jsonb_build_object(
      'researcher_app_id',  v_researcher_app_id,
      'leader_app_id',      v_leader_app_id,
      'researcher_decision', p_researcher_decision,
      'leader_decision',    p_leader_decision,
      'scores_copied',      v_copied_scores,
      'feedback',           p_feedback,
      'caller_id',          v_caller_id
    )
  );

  RETURN json_build_object(
    'success',             true,
    'researcher_app_id',   v_researcher_app_id,
    'leader_app_id',       v_leader_app_id,
    'researcher_decision', p_researcher_decision,
    'leader_decision',     p_leader_decision,
    'scores_copied',       v_copied_scores,
    'researcher_result',   v_researcher_result,
    'leader_result',       v_leader_result
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_ingestion_source_sla(p_source text, p_expected_max_minutes integer DEFAULT 120, p_timeout_minutes integer DEFAULT 240, p_escalation_severity text DEFAULT 'warning'::text, p_enabled boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  -- ADR-0028 service-role-bypass adapter (Pacote M, p64)
  IF auth.role() = 'service_role' THEN
    NULL;
  ELSE
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'authentication_required';
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'permission_denied: manage_platform required';
    END IF;
  END IF;

  IF p_escalation_severity NOT IN ('info', 'warning', 'critical') THEN
    RAISE EXCEPTION 'Invalid escalation severity: %', p_escalation_severity;
  END IF;

  INSERT INTO public.ingestion_source_sla(
    source, expected_max_minutes, timeout_minutes, escalation_severity, enabled, updated_at, updated_by
  ) VALUES (
    trim(p_source),
    greatest(coalesce(p_expected_max_minutes, 120), 1),
    greatest(coalesce(p_timeout_minutes, 240), 1),
    p_escalation_severity,
    coalesce(p_enabled, true),
    now(),
    COALESCE(v_caller_id, NULL::uuid)  -- service_role caller → NULL actor (column nullable)
  )
  ON CONFLICT (source)
  DO UPDATE SET
    expected_max_minutes = EXCLUDED.expected_max_minutes,
    timeout_minutes = EXCLUDED.timeout_minutes,
    escalation_severity = EXCLUDED.escalation_severity,
    enabled = EXCLUDED.enabled,
    updated_at = now(),
    updated_by = COALESCE(v_caller_id, NULL::uuid);

  RETURN jsonb_build_object('success', true, 'source', trim(p_source));
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_setting(p_key text, p_new_value jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_old_value jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ADR-0011: can_by_member with manage_platform action (seeded above)
  -- is_superadmin fallback preserves legacy superadmin flag for emergency access
  IF NOT (v_caller.is_superadmin IS TRUE
       OR public.can_by_member(v_caller.id, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RETURN jsonb_build_object('error', 'Reason is required');
  END IF;

  SELECT value INTO v_old_value FROM public.platform_settings WHERE key = p_key;

  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'platform.setting_changed',
    'setting',
    NULL,
    jsonb_build_object('previous_value', v_old_value, 'new_value', p_new_value),
    jsonb_build_object('setting_key', p_key, 'reason', p_reason)
  );

  UPDATE public.platform_settings
  SET value = p_new_value,
      changed_by = v_caller.id,
      changed_at = now(),
      change_reason = p_reason
  WHERE key = p_key;

  RETURN jsonb_build_object(
    'success', true,
    'key', p_key,
    'previous', v_old_value,
    'new', p_new_value
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.advance_approval_gate(p_chain_id uuid, p_target_status text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_chain public.approval_chains%ROWTYPE;
  v_now timestamptz := now();
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: requires manage_member' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_chain FROM public.approval_chains WHERE id = p_chain_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval_chain not found (id=%)', p_chain_id USING ERRCODE = 'no_data_found';
  END IF;

  IF p_target_status NOT IN ('review', 'active', 'withdrawn', 'superseded') THEN
    RAISE EXCEPTION 'Invalid target status: % (allowed: review, active, withdrawn, superseded)', p_target_status USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF v_chain.status = 'draft' AND p_target_status NOT IN ('review', 'withdrawn') THEN
    RAISE EXCEPTION 'Illegal transition: draft -> %', p_target_status USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_chain.status = 'review' AND p_target_status NOT IN ('withdrawn') THEN
    RAISE EXCEPTION 'Illegal transition: review -> % (review->approved is automatic via sign_ip_ratification)', p_target_status USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_chain.status = 'approved' AND p_target_status NOT IN ('active', 'withdrawn', 'superseded') THEN
    RAISE EXCEPTION 'Illegal transition: approved -> %', p_target_status USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_chain.status = 'active' AND p_target_status NOT IN ('withdrawn', 'superseded') THEN
    RAISE EXCEPTION 'Illegal transition: active -> %', p_target_status USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_chain.status IN ('withdrawn', 'superseded') THEN
    RAISE EXCEPTION 'Chain is in terminal state %, no transitions allowed', v_chain.status USING ERRCODE = 'invalid_parameter_value';
  END IF;

  UPDATE public.approval_chains SET
    status = p_target_status,
    opened_at = CASE WHEN p_target_status = 'review' AND v_chain.opened_at IS NULL THEN v_now ELSE opened_at END,
    opened_by = CASE WHEN p_target_status = 'review' AND v_chain.opened_by IS NULL THEN v_caller_id ELSE opened_by END,
    activated_at = CASE WHEN p_target_status = 'active' THEN v_now ELSE activated_at END,
    closed_at = CASE WHEN p_target_status IN ('withdrawn', 'superseded') THEN v_now ELSE closed_at END,
    closed_by = CASE WHEN p_target_status IN ('withdrawn', 'superseded') THEN v_caller_id ELSE closed_by END,
    notes = CASE WHEN p_reason IS NOT NULL
                 THEN coalesce(notes || E'\n---\n', '') || '[' || p_target_status || '] ' || p_reason
                 ELSE notes END,
    updated_at = v_now
  WHERE id = p_chain_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (
    v_caller_id,
    'approval_chain.advanced_to_' || p_target_status,
    'approval_chain',
    p_chain_id,
    jsonb_build_object(
      'document_id', v_chain.document_id,
      'version_id', v_chain.version_id,
      'from_status', v_chain.status,
      'to_status', p_target_status,
      'reason', p_reason
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'chain_id', p_chain_id,
    'from_status', v_chain.status,
    'to_status', p_target_status,
    'advanced_at', v_now,
    'advanced_by', v_caller_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.advance_idea_stage(p_idea_id uuid, p_new_stage text, p_review_sub_stage text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_proposer uuid;
  v_current_stage text;
  v_is_committee boolean;
  v_stages_order text[] := ARRAY['draft','proposed','researching','writing','review','curation','approved','published','archived']::text[];
  v_current_idx int;
  v_new_idx int;
  v_requires_committee boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_new_stage NOT IN ('draft','proposed','researching','writing','review','curation','approved','published','archived') THEN
    RAISE EXCEPTION 'invalid new_stage %', p_new_stage;
  END IF;
  IF p_review_sub_stage IS NOT NULL AND p_review_sub_stage NOT IN ('tribe_review','leader_review') THEN
    RAISE EXCEPTION 'invalid review_sub_stage %', p_review_sub_stage;
  END IF;

  SELECT proposer_member_id, stage INTO v_proposer, v_current_stage
  FROM public.publication_ideas WHERE id = p_idea_id;
  IF v_proposer IS NULL THEN RAISE EXCEPTION 'Idea not found: %', p_idea_id; END IF;

  v_is_committee := public.can_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');

  -- approved/published gates committee only
  v_requires_committee := p_new_stage IN ('approved','published');
  IF v_requires_committee AND NOT v_is_committee THEN
    RAISE EXCEPTION 'Unauthorized: stage % requires manage_event (comitê)', p_new_stage;
  END IF;

  -- Other transitions: proposer or committee
  IF v_caller_id <> v_proposer AND NOT v_is_committee THEN
    RAISE EXCEPTION 'Unauthorized: only proposer or comitê can advance stage';
  END IF;

  v_current_idx := array_position(v_stages_order, v_current_stage);
  v_new_idx := array_position(v_stages_order, p_new_stage);

  -- Allow archived from anywhere; allow rework review/curation→writing; otherwise forward only
  IF p_new_stage <> 'archived'
     AND NOT (v_current_stage IN ('review','curation') AND p_new_stage = 'writing')
     AND v_new_idx <= v_current_idx THEN
    RAISE EXCEPTION 'Cannot move stage backwards from % to %', v_current_stage, p_new_stage;
  END IF;

  -- terminal states cannot be left
  IF v_current_stage IN ('published','archived') THEN
    RAISE EXCEPTION 'Cannot move idea out of terminal stage %', v_current_stage;
  END IF;

  UPDATE public.publication_ideas
     SET stage = p_new_stage,
         review_sub_stage = CASE
           WHEN p_new_stage = 'review' THEN p_review_sub_stage
           ELSE NULL
         END,
         approved_by = CASE WHEN p_new_stage = 'approved' THEN v_caller_id ELSE approved_by END,
         approved_at = CASE WHEN p_new_stage = 'approved' THEN now() ELSE approved_at END,
         published_at = CASE WHEN p_new_stage = 'published' THEN now() ELSE published_at END,
         archived_reason = CASE WHEN p_new_stage = 'archived' THEN COALESCE(p_notes, archived_reason) ELSE archived_reason END
   WHERE id = p_idea_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'advance_idea_stage', 'publication_idea', p_idea_id,
    jsonb_build_object(
      'from_stage', v_current_stage, 'to_stage', p_new_stage,
      'sub_stage', p_review_sub_stage, 'notes', p_notes
    ),
    jsonb_build_object('source','mcp','issue','#94','wave','W2','as_committee', v_is_committee AND v_caller_id <> v_proposer)
  );

  RETURN jsonb_build_object(
    'success', true, 'idea_id', p_idea_id,
    'from_stage', v_current_stage, 'to_stage', p_new_stage
  );
END; $function$;

CREATE OR REPLACE FUNCTION public.anonymize_application_for_ai_training(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app record;
  v_pseudo text;
  v_outcome text;
  v_score numeric;
BEGIN
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- Generate stable pseudonym (deterministic by id, no PII leak)
  v_pseudo := 'Candidato_' || substring(p_application_id::text, 1, 8);

  -- Final outcome label (for concordance analysis)
  v_outcome := CASE
    WHEN v_app.status = 'approved' THEN 'approved'
    WHEN v_app.status = 'rejected' THEN 'rejected'
    WHEN v_app.status IN ('converted','interview_done') THEN v_app.status
    ELSE 'other'
  END;

  v_score := v_app.objective_score_avg;

  RETURN jsonb_build_object(
    -- Identifiers anonymized
    'application_id', p_application_id,
    'pseudo_name', v_pseudo,

    -- Role + content (preserved — domain content, low individual identification)
    'role_applied', v_app.role_applied,
    'motivation_letter', v_app.motivation_letter,
    'non_pmi_experience', v_app.non_pmi_experience,
    'leadership_experience', v_app.leadership_experience,
    'academic_background', v_app.academic_background,
    'proposed_theme', v_app.proposed_theme,
    'reason_for_applying', v_app.reason_for_applying,
    'certifications', v_app.certifications,
    'areas_of_interest', v_app.areas_of_interest,
    'availability_declared', v_app.availability_declared,

    -- Outcome labels (for validation analysis)
    'final_outcome', v_outcome,
    'objective_score_avg', v_score,
    'has_human_evals', (
      SELECT COUNT(*) FROM public.selection_evaluations WHERE application_id = p_application_id
    ),

    -- Explicitly null fields (PII strippped)
    'applicant_name', NULL,
    'email', NULL,
    'phone', NULL,
    'linkedin_url', NULL,
    'credly_url', NULL,
    'pmi_id', NULL,
    'chapter', NULL
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_change_request(p_cr_id uuid, p_action text, p_comment text DEFAULT NULL::text, p_ip inet DEFAULT NULL::inet, p_user_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_name text;
  v_member_role text;
  v_is_superadmin boolean;
  v_cr record;
  v_hash text;
  v_total_sponsors int;
  v_total_approvals int;
  v_quorum_needed int;
  v_quorum_met boolean;
BEGIN
  SELECT id, name, operational_role, is_superadmin
  INTO v_member_id, v_member_name, v_member_role, v_is_superadmin
  FROM members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  IF v_member_role != 'sponsor' AND COALESCE(v_is_superadmin, false) != true THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  IF p_action NOT IN ('approved', 'rejected', 'abstained') THEN
    RETURN jsonb_build_object('error', 'invalid_action');
  END IF;

  SELECT * INTO v_cr FROM change_requests WHERE id = p_cr_id;
  IF v_cr IS NULL THEN
    RETURN jsonb_build_object('error', 'cr_not_found');
  END IF;

  IF v_cr.status NOT IN ('submitted', 'proposed', 'under_review', 'open', 'pending_review', 'in_review') THEN
    RETURN jsonb_build_object('error', 'cr_not_approvable', 'status', v_cr.status);
  END IF;

  v_hash := encode(sha256(convert_to(
    p_cr_id::text || v_member_id::text || p_action || now()::text || 'nucleo-ia-governance-salt', 'UTF8'
  )), 'hex');

  INSERT INTO cr_approvals (cr_id, member_id, action, comment, signature_hash, signed_ip, signed_user_agent)
  VALUES (p_cr_id, v_member_id, p_action, p_comment, v_hash, p_ip, p_user_agent)
  ON CONFLICT (cr_id, member_id)
  DO UPDATE SET action = EXCLUDED.action, comment = EXCLUDED.comment,
    signature_hash = EXCLUDED.signature_hash, signed_ip = EXCLUDED.signed_ip,
    signed_user_agent = EXCLUDED.signed_user_agent, created_at = now();

  UPDATE change_requests
  SET approved_by_members = (
    SELECT array_agg(DISTINCT member_id) FROM cr_approvals WHERE cr_id = p_cr_id AND action = 'approved'
  ),
  status = CASE
    WHEN status IN ('submitted', 'open', 'pending_review') THEN 'under_review'
    ELSE status
  END
  WHERE id = p_cr_id;

  SELECT count(*) INTO v_total_sponsors FROM members WHERE operational_role = 'sponsor' AND is_active = true;
  SELECT count(*) INTO v_total_approvals FROM cr_approvals WHERE cr_id = p_cr_id AND action = 'approved';

  v_quorum_needed := GREATEST(CEIL(v_total_sponsors::numeric * 3 / 5), 1);
  v_quorum_met := v_total_approvals >= v_quorum_needed;

  IF v_quorum_met THEN
    UPDATE change_requests SET status = 'approved', approved_at = now()
    WHERE id = p_cr_id AND status != 'approved';

    INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (v_member_id, 'cr_approved_quorum', 'change_request', p_cr_id,
      jsonb_build_object('cr_number', v_cr.cr_number, 'approvals', v_total_approvals, 'quorum', v_quorum_needed));

    -- Notify sponsors + GP on quorum met
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'governance_cr_approved',
      v_cr.cr_number || ' aprovado por quorum!',
      v_cr.title || ' aprovado com ' || v_total_approvals || '/' || v_quorum_needed || ' votos.',
      '/governance', 'change_request', p_cr_id
    FROM members m
    WHERE (m.operational_role IN ('sponsor', 'manager') OR m.is_superadmin = true) AND m.is_active = true;
  ELSE
    -- Notify other sponsors about the vote
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'governance_cr_vote',
      v_cr.cr_number || ': ' || v_member_name || ' votou ' || p_action,
      v_cr.title, '/governance', 'change_request', p_cr_id
    FROM members m
    WHERE m.operational_role = 'sponsor' AND m.is_active = true AND m.id != v_member_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'action', p_action, 'signature_hash', v_hash,
    'approvals', v_total_approvals, 'quorum_needed', v_quorum_needed,
    'quorum_met', v_quorum_met,
    'cr_status', CASE WHEN v_quorum_met THEN 'approved' ELSE 'under_review' END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.auto_archive_done_cards()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_count int; v_system_id uuid;
BEGIN
  UPDATE board_items SET status = 'archived', updated_at = now()
  WHERE status = 'done' AND updated_at < now() - interval '30 days';
  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count > 0 THEN
    -- Use GP as system actor (actor_id is NOT NULL)
    SELECT id INTO v_system_id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1;
    IF v_system_id IS NOT NULL THEN
      INSERT INTO admin_audit_log (actor_id, action, target_type, metadata)
      VALUES (v_system_id, 'auto_archive_cards', 'board_item',
        jsonb_build_object('count', v_count, 'threshold_days', 30));
    END IF;
  END IF;

  RETURN jsonb_build_object('archived', v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.auto_link_interview_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parsed_name text;
  v_top_app_id uuid;
  v_top_score numeric;
  v_runner_up_score numeric;
  v_top_app_name text;
BEGIN
  IF NEW.type <> 'entrevista' THEN RETURN NEW; END IF;
  IF NEW.selection_application_id IS NOT NULL THEN RETURN NEW; END IF;
  IF NEW.title IS NULL OR NEW.title !~ '\([^)]+\)' THEN RETURN NEW; END IF;

  v_parsed_name := trim(both ' ' from substring(NEW.title from '\(([^)]+)\)'));
  IF v_parsed_name IS NULL OR length(v_parsed_name) < 3 THEN RETURN NEW; END IF;

  SELECT app_id, score, runner_up
    INTO v_top_app_id, v_top_score, v_runner_up_score
  FROM (
    SELECT sa.id AS app_id,
           similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)) AS score,
           LAG(similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)), 1) OVER (
             ORDER BY similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)) DESC
           ) AS runner_up
    FROM selection_applications sa
    WHERE similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)) > 0.5
    ORDER BY score DESC
    LIMIT 2
  ) ranked
  WHERE ranked.runner_up IS NULL
  LIMIT 1;

  IF v_top_app_id IS NULL OR v_top_score < 0.7 THEN
    RETURN NEW;
  END IF;

  SELECT MAX(similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)))
    INTO v_runner_up_score
  FROM selection_applications sa
  WHERE sa.id <> v_top_app_id
    AND similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)) > 0.5;

  IF v_runner_up_score IS NOT NULL AND (v_top_score - v_runner_up_score) < 0.15 THEN
    RETURN NEW;
  END IF;

  SELECT applicant_name INTO v_top_app_name FROM selection_applications WHERE id = v_top_app_id;

  NEW.selection_application_id := v_top_app_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL,
    'auto_link_interview_event_title_parse',
    'event',
    NEW.id,
    jsonb_build_object(
      'before', jsonb_build_object('selection_application_id', NULL),
      'after',  jsonb_build_object('selection_application_id', v_top_app_id)
    ),
    jsonb_build_object(
      'parsed_name', v_parsed_name,
      'applicant_name', v_top_app_name,
      'similarity_score', v_top_score,
      'runner_up_score', COALESCE(v_runner_up_score, 0),
      'event_title', NEW.title,
      'method', 'auto_link_p170_att3'
    )
  );

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_mark_excused(p_member_id uuid, p_date_from date, p_date_to date, p_reason text DEFAULT NULL::text, p_override_existing boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid; v_caller_role text; v_is_admin boolean; v_caller_tribe int;
  v_member_tribe int;
  v_count int := 0;
  v_skipped int := 0;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT tribe_id INTO v_member_tribe FROM public.members WHERE id = p_member_id;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_member_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage members of own tribe';
  END IF;

  -- Count what would be skipped (for diagnostic info)
  IF NOT p_override_existing THEN
    SELECT COUNT(*) INTO v_skipped
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= p_date_from AND e.date <= p_date_to
      AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms')
      AND (
        e.type IN ('geral', 'kickoff')
        OR (e.type = 'tribo' AND i.legacy_tribe_id = v_member_tribe)
        OR (e.type = 'lideranca' AND EXISTS (SELECT 1 FROM members m WHERE m.id = p_member_id AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')))
      )
      AND EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.excused = false);
  END IF;

  INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason)
  SELECT e.id, p_member_id, false, true, p_reason
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.date >= p_date_from AND e.date <= p_date_to
    AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms')
    AND (
      e.type IN ('geral', 'kickoff')
      OR (e.type = 'tribo' AND i.legacy_tribe_id = v_member_tribe)
      OR (e.type = 'lideranca' AND EXISTS (SELECT 1 FROM members m WHERE m.id = p_member_id AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')))
    )
    AND (
      p_override_existing
      OR NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.excused = false)
    )
  ON CONFLICT (event_id, member_id) DO UPDATE SET
    present = false,
    excused = true,
    excuse_reason = p_reason,
    updated_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN json_build_object(
    'success', true,
    'events_marked', v_count,
    'events_skipped', v_skipped,
    'date_from', p_date_from,
    'date_to', p_date_to,
    'override_used', p_override_existing
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.can(p_person_id uuid, p_action text, p_resource_type text DEFAULT NULL::text, p_resource_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.person_id = p_person_id
      AND ae.is_authoritative = true
      AND (
        -- Organization/global scope: always grants
        ekp.scope IN ('organization', 'global')
        -- Initiative-scoped: must match the resource
        OR (
          ekp.scope = 'initiative'
          AND ae.initiative_id IS NOT NULL
          AND (
            -- Match by initiative UUID
            ae.initiative_id = p_resource_id
            -- Match by legacy tribe_id (p_resource_id is null but engagement has tribe)
            OR (p_resource_id IS NULL AND ae.legacy_tribe_id IS NOT NULL)
            -- Match by legacy tribe_id integer passed as text in resource_type
            OR (p_resource_type = 'tribe' AND ae.legacy_tribe_id = (p_resource_id::text)::integer)
          )
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.cancel_re_engagement(p_pipeline_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_pipeline record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_pipeline FROM public.re_engagement_pipeline WHERE id = p_pipeline_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Pipeline entry not found'); END IF;

  IF v_pipeline.state IN ('cancelled','accepted','declined') THEN
    RETURN jsonb_build_object('error','Cannot cancel from state: ' || v_pipeline.state::text);
  END IF;

  UPDATE public.re_engagement_pipeline SET
    state = 'cancelled',
    cancelled_at = now(),
    cancelled_by = v_caller.id,
    cancellation_reason = p_reason
  WHERE id = p_pipeline_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 're_engagement.cancelled', 're_engagement_pipeline', p_pipeline_id,
    jsonb_build_object('member_id', v_pipeline.member_id, 'previous_state', v_pipeline.state::text),
    jsonb_strip_nulls(jsonb_build_object('reason', p_reason))
  );

  RETURN jsonb_build_object('success', true, 'pipeline_id', p_pipeline_id);
END $function$;

CREATE OR REPLACE FUNCTION public.capture_vep_baseline(p_label text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_baseline_id uuid;
  v_org_id uuid;
  v_summary jsonb;
BEGIN
  SELECT id, organization_id INTO v_caller_id, v_org_id
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Forbidden: view_internal_analytics required';
  END IF;
  IF p_label IS NULL OR length(trim(p_label)) = 0 THEN
    RAISE EXCEPTION 'label is required';
  END IF;

  WITH vep_status_dist AS (
    SELECT vep_status_raw, count(*) AS n
    FROM public.selection_applications
    WHERE vep_status_raw IS NOT NULL
    GROUP BY vep_status_raw
  ),
  cycle_cov AS (
    SELECT
      c.cycle_code,
      c.status AS cycle_status,
      count(*) AS apps,
      count(*) FILTER (WHERE a.vep_status_raw IS NOT NULL) AS vep_observed,
      max(c.created_at) AS c_created
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    GROUP BY c.cycle_code, c.status
    ORDER BY max(c.created_at) DESC
  )
  SELECT jsonb_build_object(
    'captured_at', now(),
    'selection_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.vep_status_raw IN ('Withdrawn','Declined','OfferNotExtended','Expired')
        AND a.status NOT IN ('rejected','withdrawn','cancelled')
        AND COALESCE(a.vep_reconciled_at < a.vep_last_seen_at, true)
    ),
    'onboarding_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.status IN ('approved','converted')
        AND a.vep_status_raw IN ('Submitted','Active')
        AND COALESCE(a.vep_reconciled_at < a.vep_last_seen_at, true)
    ),
    'active_members_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.vep_status_raw IS NOT NULL
        AND a.vep_status_raw NOT IN ('Active')
        AND EXISTS (
          SELECT 1 FROM public.members m
          WHERE m.is_active = true
            AND lower(m.email) = lower(a.email)
        )
    ),
    'total_observed', (
      SELECT count(*) FROM public.selection_applications WHERE vep_status_raw IS NOT NULL
    ),
    'total_apps', (
      SELECT count(*) FROM public.selection_applications
    ),
    'latest_ingest_at', (
      SELECT max(vep_last_seen_at) FROM public.selection_applications
    ),
    'missing_from_latest_vep', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.vep_status_raw IS NOT NULL
        AND a.vep_last_seen_at < (
          SELECT max(vep_last_seen_at) - interval '5 minutes'
          FROM public.selection_applications
        )
    ),
    'vep_status_distribution', COALESCE(
      (SELECT jsonb_object_agg(vep_status_raw, n) FROM vep_status_dist),
      '{}'::jsonb
    ),
    'cycle_coverage', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'cycle_code', cycle_code,
        'cycle_status', cycle_status,
        'apps', apps,
        'vep_observed', vep_observed,
        'pct', CASE WHEN apps > 0 THEN round((vep_observed::numeric / apps) * 100, 1) ELSE 0 END
      ) ORDER BY c_created DESC) FROM cycle_cov),
      '[]'::jsonb
    )
  ) INTO v_summary;

  INSERT INTO public.vep_reconciliation_baselines
    (captured_by, label, notes, summary, organization_id)
  VALUES
    (v_caller_id, trim(p_label), p_notes, v_summary, v_org_id)
  RETURNING id INTO v_baseline_id;

  RETURN jsonb_build_object(
    'id', v_baseline_id,
    'captured_at', v_summary->>'captured_at',
    'label', trim(p_label),
    'summary', v_summary
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.capture_visitor_lead(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_lead_id uuid;
  v_email text;
  v_name text;
  v_consent boolean;
  v_referrer_id uuid;
  v_existing_id uuid;
BEGIN
  v_email := NULLIF(TRIM(LOWER(p_payload->>'email')), '');
  v_name := NULLIF(TRIM(p_payload->>'name'), '');
  v_consent := COALESCE((p_payload->>'lgpd_consent')::boolean, false);

  IF v_email IS NULL OR v_name IS NULL THEN
    RETURN jsonb_build_object('error','name and email are required');
  END IF;

  IF NOT v_consent THEN
    RETURN jsonb_build_object('error','LGPD consent is required');
  END IF;

  -- Soft email format check
  IF v_email !~ '^[^@]+@[^@]+\.[^@]+$' THEN
    RETURN jsonb_build_object('error','invalid email format');
  END IF;

  -- Optional referrer (member_id from URL query ?ref=xxx)
  IF p_payload ? 'referrer_member_id' AND (p_payload->>'referrer_member_id') ~ '^[0-9a-f-]{36}$' THEN
    v_referrer_id := (p_payload->>'referrer_member_id')::uuid;
    -- Verify exists
    PERFORM 1 FROM public.members WHERE id = v_referrer_id;
    IF NOT FOUND THEN v_referrer_id := NULL; END IF;
  END IF;

  -- Idempotent: if same email already exists with status='new', return existing
  SELECT id INTO v_existing_id
  FROM public.visitor_leads
  WHERE LOWER(TRIM(email)) = v_email AND status = 'new'
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    -- Update with new payload (last-wins on optional fields)
    UPDATE public.visitor_leads SET
      phone = COALESCE(NULLIF(TRIM(p_payload->>'phone'),''), phone),
      chapter_interest = COALESCE(NULLIF(TRIM(p_payload->>'chapter_interest'),''), chapter_interest),
      role_interest = COALESCE(NULLIF(TRIM(p_payload->>'role_interest'),''), role_interest),
      message = COALESCE(NULLIF(TRIM(p_payload->>'message'),''), message),
      utm_data = COALESCE(p_payload->'utm_data', utm_data),
      referrer_member_id = COALESCE(v_referrer_id, referrer_member_id),
      source = COALESCE(NULLIF(TRIM(p_payload->>'source'),''), source)
    WHERE id = v_existing_id;
    RETURN jsonb_build_object('success', true, 'lead_id', v_existing_id, 'idempotent', true);
  END IF;

  INSERT INTO public.visitor_leads (
    name, email, phone, chapter_interest, role_interest, message,
    lgpd_consent, source, status, utm_data, referrer_member_id
  ) VALUES (
    v_name, v_email,
    NULLIF(TRIM(p_payload->>'phone'), ''),
    NULLIF(TRIM(p_payload->>'chapter_interest'), ''),
    NULLIF(TRIM(p_payload->>'role_interest'), ''),
    NULLIF(TRIM(p_payload->>'message'), ''),
    true,
    COALESCE(NULLIF(TRIM(p_payload->>'source'), ''), 'website'),
    'new',
    p_payload->'utm_data',
    v_referrer_id
  )
  RETURNING id INTO v_lead_id;

  RETURN jsonb_build_object('success', true, 'lead_id', v_lead_id);
END $function$;

CREATE OR REPLACE FUNCTION public.check_pre_onboarding_auto_steps(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_completed int := 0;
  v_member record;
  v_pages int;
  v_has_blog boolean;
  v_profile_complete boolean;
BEGIN
  SELECT id, auth_id, name, photo_url, credly_url,
         phone, linkedin_url, pmi_id, address, city, birth_date
  INTO v_member
  FROM members WHERE id = p_member_id;

  IF v_member.id IS NULL THEN
    RETURN json_build_object('error', 'Member not found');
  END IF;

  -- Step: create_account
  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'create_account' AND status = 'pending'
  AND v_member.auth_id IS NOT NULL;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'create_account' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: complete_profile — requires all key personal fields for Volunteer Agreement
  v_profile_complete := v_member.photo_url IS NOT NULL
    AND v_member.phone IS NOT NULL AND length(trim(v_member.phone)) > 0
    AND v_member.linkedin_url IS NOT NULL AND length(trim(v_member.linkedin_url)) > 0
    AND v_member.pmi_id IS NOT NULL AND length(trim(v_member.pmi_id)) > 0
    AND v_member.address IS NOT NULL AND length(trim(v_member.address)) > 0
    AND v_member.city IS NOT NULL AND length(trim(v_member.city)) > 0
    AND v_member.birth_date IS NOT NULL;

  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'complete_profile' AND status = 'pending'
  AND v_profile_complete;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'complete_profile' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: setup_credly
  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'setup_credly' AND status = 'pending'
  AND v_member.credly_url IS NOT NULL AND v_member.credly_url != '';
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'setup_credly' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: explore_platform
  SELECT coalesce(sum(pages_visited), 0) INTO v_pages
  FROM member_activity_sessions WHERE member_id = p_member_id;

  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'explore_platform' AND status = 'pending'
  AND v_pages >= 3;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'explore_platform' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: read_blog
  SELECT EXISTS (
    SELECT 1 FROM member_activity_sessions
    WHERE member_id = p_member_id
    AND (first_page LIKE '%/blog%' OR last_page LIKE '%/blog%')
  ) INTO v_has_blog;

  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'read_blog' AND status = 'pending'
  AND v_has_blog;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'read_blog' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  RETURN json_build_object(
    'auto_completed', v_completed,
    'member_id', p_member_id,
    'profile_complete', v_profile_complete
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.comms_executive_kpis()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb; v_channels jsonb;
  v_total_audience bigint := 0; v_weekly_reach bigint := 0;
  v_avg_engagement numeric := 0; v_growth_pct numeric := 0;
  v_this_week_audience bigint := 0; v_last_week_audience bigint := 0;
BEGIN
  WITH latest_per_channel AS (
    SELECT DISTINCT ON (channel) channel, audience, reach, engagement_rate, metric_date, payload
    FROM public.comms_metrics_daily ORDER BY channel, metric_date DESC
  )
  SELECT COALESCE(SUM(audience), 0),
    COALESCE(jsonb_agg(jsonb_build_object('channel', channel, 'audience', audience, 'reach', reach, 'engagement_rate', engagement_rate, 'date', metric_date)), '[]'::jsonb)
  INTO v_total_audience, v_channels FROM latest_per_channel;

  SELECT COALESCE(SUM(reach), 0) INTO v_weekly_reach FROM public.comms_metrics_daily WHERE metric_date >= CURRENT_DATE - 7;

  WITH eng AS (
    SELECT DISTINCT ON (channel) channel, engagement_rate, audience
    FROM public.comms_metrics_daily WHERE engagement_rate IS NOT NULL ORDER BY channel, metric_date DESC
  )
  SELECT CASE WHEN SUM(audience) > 0 THEN SUM(engagement_rate * audience) / SUM(audience) ELSE 0 END
  INTO v_avg_engagement FROM eng;

  v_this_week_audience := v_total_audience;
  SELECT COALESCE(SUM(sub.audience), 0) INTO v_last_week_audience
  FROM (SELECT DISTINCT ON (channel) channel, audience FROM public.comms_metrics_daily WHERE metric_date <= CURRENT_DATE - 7 ORDER BY channel, metric_date DESC) sub;

  IF v_last_week_audience > 0 THEN
    v_growth_pct := ROUND(((v_this_week_audience - v_last_week_audience)::numeric / v_last_week_audience) * 100, 1);
  END IF;

  v_result := jsonb_build_object(
    'total_audience', v_total_audience, 'weekly_reach', v_weekly_reach,
    'avg_engagement', ROUND(v_avg_engagement, 4), 'audience_growth_pct', v_growth_pct,
    'channel_breakdown', v_channels,
    'media_count', (SELECT COUNT(*) FROM public.comms_media_items)::int,
    'top_media_count', (SELECT COUNT(*) FROM public.comms_media_items WHERE published_at >= NOW() - interval '30 days')::int
  );
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.compute_pert_cutoff(p_cycle_id uuid, p_role text DEFAULT 'researcher'::text, p_filter_active_only boolean DEFAULT true, p_score_column text DEFAULT 'objective_score_avg'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_cycle record;
  v_cohort record;
  v_target numeric;
  v_band_lower numeric;
  v_band_upper numeric;
  v_method text;
  v_n int;
  v_updated_rows int;
  v_fallback_target numeric;
BEGIN
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_member');
  END IF;

  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score') THEN
    RETURN jsonb_build_object(
      'error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg', 'final_score', 'research_score'),
      'received', p_score_column
    );
  END IF;

  SELECT sc.id, sc.cycle_code INTO v_cycle
  FROM public.selection_cycles sc WHERE sc.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('error', 'cycle_not_found');
  END IF;

  WITH prior_cycles AS (
    SELECT id FROM public.selection_cycles
    WHERE id != p_cycle_id
      AND created_at < (SELECT created_at FROM public.selection_cycles WHERE id = p_cycle_id)
  ),
  cohort_apps AS (
    SELECT
      CASE p_score_column
        WHEN 'objective_score_avg' THEN sa.objective_score_avg
        WHEN 'final_score' THEN sa.final_score
        WHEN 'research_score' THEN sa.research_score
      END AS s
    FROM public.selection_applications sa
    WHERE sa.cycle_id IN (SELECT id FROM prior_cycles)
      AND sa.role_applied = p_role
      AND sa.status = 'approved'
      AND CASE p_score_column
            WHEN 'objective_score_avg' THEN sa.objective_score_avg IS NOT NULL
            WHEN 'final_score' THEN sa.final_score IS NOT NULL
            WHEN 'research_score' THEN sa.research_score IS NOT NULL
          END
      AND (
        NOT p_filter_active_only
        OR EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.persons pp ON pp.id = e.person_id
          WHERE pp.legacy_member_id IS NOT NULL
            AND e.kind = 'volunteer'
            AND e.role = p_role
            AND e.status = 'active'
            AND lower(coalesce(sa.email,'')) IN (
              SELECT lower(m.email) FROM public.members m
              WHERE m.id = pp.legacy_member_id AND m.email IS NOT NULL
            )
        )
      )
  )
  SELECT
    COUNT(*)::int AS n,
    MIN(s) AS s_min,
    MAX(s) AS s_max,
    AVG(s) AS s_avg
  INTO v_cohort
  FROM cohort_apps;

  v_n := COALESCE(v_cohort.n, 0);

  IF v_n >= 10 THEN
    v_target := (2 * v_cohort.s_min + 4 * v_cohort.s_avg + 2 * v_cohort.s_max) / 8;
    v_method := 'dynamic';
  ELSE
    SELECT MAX(pert_target_score) INTO v_fallback_target
    FROM public.selection_applications
    WHERE pert_target_score IS NOT NULL
      AND cycle_id != p_cycle_id;
    IF v_fallback_target IS NULL THEN
      v_target := NULL;
      v_method := 'disabled';
    ELSE
      v_target := v_fallback_target;
      v_method := 'historical_fallback';
    END IF;
  END IF;

  IF v_target IS NOT NULL THEN
    v_band_lower := v_target * 0.90;
    v_band_upper := v_target * 1.10;
  END IF;

  UPDATE public.selection_applications
  SET pert_target_score = v_target,
      pert_band_lower = v_band_lower,
      pert_band_upper = v_band_upper,
      pert_cutoff_method = v_method,
      pert_cohort_n = v_n,
      pert_calc_at = now()
  WHERE cycle_id = p_cycle_id;
  GET DIAGNOSTICS v_updated_rows = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_member.id,
    'pert_cutoff_computed',
    'selection_cycle',
    p_cycle_id,
    jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'role', p_role,
      'score_column_used', p_score_column,
      'filter_active_only', p_filter_active_only,
      'cohort_n', v_n,
      'cohort_min', v_cohort.s_min,
      'cohort_max', v_cohort.s_max,
      'cohort_avg', v_cohort.s_avg,
      'target_score', v_target,
      'band_lower', v_band_lower,
      'band_upper', v_band_upper,
      'method', v_method,
      'rows_updated', v_updated_rows
    ),
    jsonb_build_object(
      'source', 'compute_pert_cutoff',
      'p131_t18_backstage', true,
      'p131_followup_score_column_default_objective_score_avg', true
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code,
    'role', p_role,
    'score_column_used', p_score_column,
    'cohort_n', v_n,
    'cohort_stats', jsonb_build_object(
      'min', v_cohort.s_min,
      'max', v_cohort.s_max,
      'avg', v_cohort.s_avg
    ),
    'target_score', v_target,
    'band_lower', v_band_lower,
    'band_upper', v_band_upper,
    'method', v_method,
    'rows_updated', v_updated_rows,
    'computed_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_manual_version(p_proposal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_signer_id uuid;
  v_signer_name text;
  v_proposal record;
  v_count int;
  v_approved_crs jsonb;
  v_doc_id uuid;
  v_previous_version text;
  v_recipient_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, name INTO v_signer_id, v_signer_name FROM public.members WHERE auth_id = auth.uid();
  IF v_signer_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- ADR-0044: V4 catalog gate (manage_platform)
  IF NOT public.can_by_member(v_signer_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Requires manage_platform permission';
  END IF;

  SELECT * INTO v_proposal FROM public.pending_manual_version_approvals WHERE id = p_proposal_id;
  IF v_proposal.id IS NULL THEN
    RETURN jsonb_build_object('error', 'proposal_not_found');
  END IF;

  IF v_proposal.status <> 'pending' THEN
    RETURN jsonb_build_object('error', 'proposal_not_pending', 'current_status', v_proposal.status);
  END IF;

  -- 24h window enforcement
  IF v_proposal.expires_at <= now() THEN
    UPDATE public.pending_manual_version_approvals
    SET status = 'expired', updated_at = now()
    WHERE id = p_proposal_id AND status = 'pending';
    RETURN jsonb_build_object('error', 'proposal_expired', 'expired_at', v_proposal.expires_at);
  END IF;

  -- 2-of-N: signer must be different from proposer
  IF v_signer_id = v_proposal.proposed_by THEN
    RETURN jsonb_build_object('error', 'self_signoff_forbidden',
      'message', 'Proposer cannot confirm their own proposal — 2-of-N requires different signoff');
  END IF;

  -- Re-validate approved CRs (in case some were unapproved during the 24h window)
  SELECT count(*) INTO v_count FROM public.change_requests WHERE status = 'approved';
  IF v_count = 0 THEN RETURN jsonb_build_object('error', 'no_approved_crs_at_confirm'); END IF;

  -- Re-validate version label not used since proposal
  IF EXISTS (
    SELECT 1 FROM public.governance_documents
    WHERE doc_type = 'manual' AND version = v_proposal.version_label
  ) THEN
    RETURN jsonb_build_object('error', 'version_label_now_in_use');
  END IF;

  -- Execute the actual manual version generation
  SELECT COALESCE(jsonb_agg(jsonb_build_object('cr_number', cr_number, 'title', title, 'category', category,
    'approved_at', approved_at) ORDER BY cr_number), '[]'::jsonb) INTO v_approved_crs
  FROM public.change_requests WHERE status = 'approved';

  SELECT version INTO v_previous_version FROM public.governance_documents
  WHERE doc_type = 'manual' AND status = 'active' ORDER BY created_at DESC LIMIT 1;

  UPDATE public.governance_documents SET status = 'superseded'
  WHERE doc_type = 'manual' AND status = 'active';

  INSERT INTO public.governance_documents (title, doc_type, version, status, description, valid_from)
  VALUES (
    'Manual de Governança e Operações — ' || v_proposal.version_label,
    'manual',
    v_proposal.version_label,
    'active',
    'Versão gerada via 2-of-N approval (ADR-0044). ' || v_count::text ||
      ' CRs incorporados. Proposto por ' || (SELECT name FROM public.members WHERE id = v_proposal.proposed_by) ||
      '; confirmado por ' || v_signer_name || '. ' || COALESCE(v_proposal.notes, ''),
    now()
  )
  RETURNING id INTO v_doc_id;

  UPDATE public.change_requests
  SET status = 'implemented',
      implemented_at = now(),
      implemented_by = v_signer_id,
      manual_version_from = COALESCE(v_previous_version, 'R2'),
      manual_version_to = v_proposal.version_label
  WHERE status = 'approved';

  -- Update proposal: status='confirmed', signoff captured
  UPDATE public.pending_manual_version_approvals
  SET status = 'confirmed',
      signoff_member_id = v_signer_id,
      signoff_at = now(),
      governance_document_id = v_doc_id,
      updated_at = now()
  WHERE id = p_proposal_id;

  -- Audit log: confirmation event with both actors
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_signer_id, 'manual_version_confirmed', 'governance_document', v_doc_id,
    jsonb_build_object(
      'proposal_id', p_proposal_id,
      'proposed_by', v_proposal.proposed_by,
      'signoff_by', v_signer_id,
      'version', v_proposal.version_label,
      'previous', v_previous_version,
      'crs_count', v_count,
      'notes', v_proposal.notes
    ));

  -- Notify chapter board members + sponsors of new manual version
  FOR v_recipient_id IN
    SELECT DISTINCT m.id
    FROM public.members m
    JOIN public.persons p ON p.legacy_member_id = m.id
    JOIN public.auth_engagements ae ON ae.person_id = p.id
    WHERE m.is_active = true
      AND ae.is_authoritative = true
      AND (
        (ae.kind = 'volunteer' AND ae.role IN ('manager','deputy_manager','co_gp'))
        OR (ae.kind = 'chapter_board' AND ae.role IN ('liaison','board_member'))
        OR (ae.kind = 'sponsor' AND ae.role = 'sponsor')
      )
  LOOP
    PERFORM public.create_notification(
      v_recipient_id,
      'governance_manual_proposed',
      'governance_document',
      v_doc_id,
      'Manual ' || v_proposal.version_label || ' publicado',
      v_signer_id,
      v_count::text || ' alterações incorporadas. Proposto e confirmado por 2-of-N approval.'
    );
  END LOOP;

  -- Announcement draft
  INSERT INTO public.announcements (title, message, type, is_active, created_by, starts_at)
  VALUES (
    'Manual de Governança ' || v_proposal.version_label || ' publicado',
    'O Manual foi atualizado com ' || v_count::text || ' alterações aprovadas pelos presidentes dos capítulos (2-of-N approval).',
    'governance',
    false,
    v_signer_id,
    now()
  );

  RETURN jsonb_build_object(
    'success', true,
    'document_id', v_doc_id,
    'version', v_proposal.version_label,
    'previous_version', v_previous_version,
    'crs_implemented', v_approved_crs,
    'proposed_by', v_proposal.proposed_by,
    'signoff_by', v_signer_id,
    'proposed_at', v_proposal.proposed_at,
    'confirmed_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.convert_action_to_card(p_action_item_id uuid, p_board_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_status text DEFAULT 'todo'::text, p_due_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action record;
  v_board record;
  v_new_card_id uuid;
  v_position int;
  v_final_title text;
  v_final_description text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- V4 gate: write_board (creating cards is board mutation)
  IF NOT public.can_by_member(v_caller_id, 'write_board') THEN
    RAISE EXCEPTION 'Requires write_board permission';
  END IF;

  SELECT * INTO v_action FROM public.meeting_action_items WHERE id = p_action_item_id;
  IF v_action.id IS NULL THEN
    RETURN jsonb_build_object('error', 'action_item_not_found');
  END IF;

  IF v_action.board_item_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'action_already_linked_to_card',
      'existing_board_item_id', v_action.board_item_id);
  END IF;

  SELECT pb.id, pb.organization_id, pb.is_active INTO v_board
  FROM public.project_boards pb WHERE pb.id = p_board_id;
  IF v_board.id IS NULL THEN
    RETURN jsonb_build_object('error', 'board_not_found');
  END IF;
  IF v_board.is_active = false THEN
    RETURN jsonb_build_object('error', 'board_inactive');
  END IF;

  -- Compute next position (max+1 in board)
  SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
  FROM public.board_items WHERE board_id = p_board_id;

  -- Defaults from action item if not overridden
  v_final_title := COALESCE(NULLIF(trim(p_title), ''), substring(v_action.description from 1 for 80));
  v_final_description := COALESCE(p_description, v_action.description ||
    E'\n\n_Convertido de action item da reunião ' || v_action.event_id::text || '_');

  -- Create the new card
  INSERT INTO public.board_items (
    board_id, title, description, status, assignee_id, due_date, position, created_at, updated_at
  ) VALUES (
    p_board_id, v_final_title, v_final_description, p_status,
    v_action.assignee_id, COALESCE(p_due_date, v_action.due_date), v_position, now(), now()
  )
  RETURNING id INTO v_new_card_id;

  -- Lifecycle event
  INSERT INTO public.board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (p_board_id, v_new_card_id, 'created',
    'Created from action item ' || p_action_item_id::text, v_caller_id);

  -- Update action item to point to the new card
  UPDATE public.meeting_action_items
  SET board_item_id = v_new_card_id, updated_at = now()
  WHERE id = p_action_item_id;

  -- Link the card to the originating event via board_item_event_links
  INSERT INTO public.board_item_event_links (
    organization_id, board_item_id, event_id, link_type, author_id, note
  ) VALUES (
    v_board.organization_id, v_new_card_id, v_action.event_id, 'action_emerged',
    v_caller_id, 'Card created from action item: ' || v_action.description
  )
  ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'action_item_id', p_action_item_id,
    'new_board_item_id', v_new_card_id,
    'board_id', p_board_id,
    'position', v_position,
    'created_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_action_item(p_event_id uuid, p_description text, p_assignee_id uuid DEFAULT NULL::uuid, p_due_date date DEFAULT NULL::date, p_board_item_id uuid DEFAULT NULL::uuid, p_checklist_item_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT 'action'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action_id uuid;
  v_assignee_name text;
  v_event record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- V4 gate: manage_event (mirrors ADR-0045 RLS on board_item_event_links)
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  -- Validate event exists
  SELECT id, title INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN RETURN jsonb_build_object('error', 'event_not_found'); END IF;

  -- Validate kind
  IF p_kind NOT IN ('action','decision','followup','general') THEN
    RETURN jsonb_build_object('error', 'invalid_kind',
      'valid_kinds', jsonb_build_array('action','decision','followup','general'));
  END IF;

  -- Validate description
  IF p_description IS NULL OR length(trim(p_description)) = 0 THEN
    RETURN jsonb_build_object('error', 'description_required');
  END IF;

  -- Lookup assignee name (snapshot, even if assignee gets renamed later)
  IF p_assignee_id IS NOT NULL THEN
    SELECT name INTO v_assignee_name FROM public.members WHERE id = p_assignee_id;
    IF v_assignee_name IS NULL THEN
      RETURN jsonb_build_object('error', 'assignee_not_found', 'assignee_id', p_assignee_id);
    END IF;
  END IF;

  INSERT INTO public.meeting_action_items (
    event_id, description, assignee_id, assignee_name, due_date,
    board_item_id, checklist_item_id, kind, status, created_by
  ) VALUES (
    p_event_id, trim(p_description), p_assignee_id, v_assignee_name, p_due_date,
    p_board_item_id, p_checklist_item_id, p_kind,
    CASE WHEN p_kind = 'decision' THEN 'completed' ELSE 'open' END,
    v_caller_id
  )
  RETURNING id INTO v_action_id;

  -- If linked to a board_item, also create board_item_event_links entry
  IF p_board_item_id IS NOT NULL THEN
    INSERT INTO public.board_item_event_links (
      organization_id, board_item_id, event_id, link_type, author_id, note
    )
    SELECT bi.organization_id, p_board_item_id, p_event_id,
      CASE p_kind
        WHEN 'decision' THEN 'decision'
        WHEN 'action' THEN 'action_emerged'
        ELSE 'discussed'
      END,
      v_caller_id, trim(p_description)
    FROM public.board_items bi
    WHERE bi.id = p_board_item_id
    ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'action_item_id', v_action_id,
    'event_id', p_event_id,
    'kind', p_kind,
    'created_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_event(p_type text, p_title text, p_date date, p_duration_minutes integer DEFAULT 90, p_tribe_id integer DEFAULT NULL::integer, p_meeting_link text DEFAULT NULL::text, p_nature text DEFAULT 'recorrente'::text, p_visibility text DEFAULT 'all'::text, p_agenda_text text DEFAULT NULL::text, p_agenda_url text DEFAULT NULL::text, p_external_attendees text[] DEFAULT NULL::text[], p_invited_member_ids uuid[] DEFAULT NULL::uuid[], p_audience_level text DEFAULT NULL::text, p_time_start time without time zone DEFAULT NULL::time without time zone)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_tribe_id integer;
  v_is_admin boolean;
  v_event_id uuid;
  v_audience text;
  v_initiative_id uuid;
  v_time_start time without time zone;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_member_tribe_id
  FROM members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT public.can_by_member(v_member_id, 'manage_event') THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized: requires manage_event permission');
  END IF;

  IF p_type NOT IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN
    RETURN json_build_object('success', false, 'error', 'Invalid event type: ' || p_type);
  END IF;

  IF p_nature NOT IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN
    p_nature := 'avulsa';
  END IF;

  IF p_type IN ('parceria','entrevista','1on1') THEN
    p_visibility := 'gp_only';
  ELSIF p_visibility NOT IN ('all','leadership','gp_only') THEN
    p_visibility := 'all';
  END IF;

  IF p_type = 'tribo' AND p_tribe_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'tribe_id required for tribe events');
  END IF;

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    IF p_type NOT IN ('tribo') THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe events');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_member_tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
    p_external_attendees := NULL;
    p_invited_member_ids := NULL;
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  v_audience := COALESCE(p_audience_level,
    CASE p_type
      WHEN 'tribo'     THEN 'tribe'
      WHEN 'lideranca' THEN 'leadership'
      WHEN 'comms'     THEN 'leadership'
      ELSE 'all'
    END
  );

  -- Derive time_start: explicit param > tribe slot for ISODOW > tribe first slot > '19:00'
  v_time_start := p_time_start;
  IF v_time_start IS NULL AND p_tribe_id IS NOT NULL THEN
    SELECT time_start INTO v_time_start
    FROM public.tribe_meeting_slots
    WHERE tribe_id = p_tribe_id
      AND day_of_week = EXTRACT(ISODOW FROM p_date)::int
    LIMIT 1;
    IF v_time_start IS NULL THEN
      SELECT time_start INTO v_time_start
      FROM public.tribe_meeting_slots
      WHERE tribe_id = p_tribe_id
      ORDER BY day_of_week
      LIMIT 1;
    END IF;
  END IF;
  v_time_start := COALESCE(v_time_start, '19:00:00'::time);

  INSERT INTO events (
    type, title, date, time_start, duration_minutes,
    initiative_id,
    audience_level, meeting_link,
    nature, visibility, agenda_text, agenda_url,
    external_attendees, invited_member_ids, created_by
  )
  VALUES (
    p_type, p_title, p_date, v_time_start, p_duration_minutes,
    v_initiative_id,
    v_audience, p_meeting_link,
    p_nature, p_visibility, p_agenda_text, p_agenda_url,
    p_external_attendees, p_invited_member_ids, auth.uid()
  )
  RETURNING id INTO v_event_id;

  IF p_agenda_text IS NOT NULL OR p_agenda_url IS NOT NULL THEN
    UPDATE events SET agenda_posted_at = now(), agenda_posted_by = v_member_id
    WHERE id = v_event_id;
  END IF;

  RETURN json_build_object('success', true, 'event_id', v_event_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_external_signer_invite(p_email text, p_name text, p_organization text, p_relationship text, p_chapter_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_member record;
  v_person_id uuid;
  v_member_id uuid;
  v_org_id uuid;
  v_existing_person uuid;
  v_existing_member uuid;
BEGIN
  SELECT m.id, m.name, m.operational_role INTO v_actor_member
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_actor_member.id IS NULL THEN RETURN jsonb_build_object('error','not_authenticated'); END IF;
  IF NOT public.can_by_member(v_actor_member.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','access_denied','message','manage_member required');
  END IF;

  IF p_email IS NULL OR length(trim(p_email)) = 0 THEN RETURN jsonb_build_object('error','email_required'); END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN RETURN jsonb_build_object('error','name_required'); END IF;

  SELECT id INTO v_existing_person FROM public.persons WHERE lower(email) = lower(p_email);
  IF v_existing_person IS NOT NULL THEN
    SELECT id INTO v_existing_member FROM public.members WHERE person_id = v_existing_person LIMIT 1;
    IF v_existing_member IS NOT NULL THEN
      RETURN jsonb_build_object('error','already_exists','person_id',v_existing_person,'member_id',v_existing_member);
    END IF;
    v_person_id := v_existing_person;
  END IF;

  v_org_id := '2b4f58ab-7c45-4170-8718-b77ee69ff906';

  IF v_person_id IS NULL THEN
    INSERT INTO public.persons (organization_id, name, email, consent_status, consent_accepted_at, consent_version)
    VALUES (v_org_id, trim(p_name), lower(trim(p_email)), 'pending_magic_link', now(), 'v2.1-external-signer')
    RETURNING id INTO v_person_id;
  END IF;

  INSERT INTO public.members (
    person_id, name, email, chapter, operational_role, member_status, is_active,
    organization_id, consent_status, consent_accepted_at, consent_version, created_at, updated_at
  ) VALUES (
    v_person_id, trim(p_name), lower(trim(p_email)), COALESCE(p_chapter_code,'EXTERNAL'),
    'external_signer', 'active', true,
    v_org_id, 'pending_magic_link', now(), 'v2.1-external-signer', now(), now()
  ) RETURNING id INTO v_member_id;

  INSERT INTO public.auth_engagements (
    person_id, organization_id, kind, role, status,
    start_date, end_date, legal_basis, is_authoritative
  ) VALUES (
    v_person_id, v_org_id, 'external_signer', 'signer', 'active',
    CURRENT_DATE, (CURRENT_DATE + interval '1 year')::date, 'legitimate_interest', true
  );

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_actor_member.id, 'external_signer_invite_created', 'member', v_member_id,
    jsonb_build_object('email', lower(trim(p_email)), 'name', trim(p_name),
      'organization', p_organization, 'relationship', p_relationship, 'chapter_code', p_chapter_code));

  RETURN jsonb_build_object('success', true, 'person_id', v_person_id, 'member_id', v_member_id,
    'email', lower(trim(p_email)),
    'note', 'Magic-link URL generation pending Phase IP-3 Edge Function.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_external_speaker_engagement(p_partner_entity_id uuid, p_lead_person_id uuid, p_initiative_title text, p_co_person_id uuid DEFAULT NULL::uuid, p_initiative_kind text DEFAULT 'congress'::text, p_initiative_description text DEFAULT NULL::text, p_deadlines jsonb DEFAULT '[]'::jsonb, p_whatsapp_url text DEFAULT NULL::text, p_meeting_link text DEFAULT NULL::text, p_drive_folder_url text DEFAULT NULL::text, p_board_domain_key text DEFAULT 'publications_submissions'::text, p_org_id uuid DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_person_id uuid;
  v_caller_member_id uuid;
  v_initiative_id uuid;
  v_board_id uuid;
  v_lead_engagement_id uuid;
  v_co_engagement_id uuid;
  v_interaction_id uuid;
  v_board_items_count int := 0;
  v_deadline jsonb;
  v_partner_name text;
  v_lead_exists boolean;
  v_co_exists boolean;
  v_position int := 1;
BEGIN
  -- ─── Auth resolution ───
  SELECT p.id INTO v_caller_person_id
  FROM public.persons p WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  -- ─── Authorization ───
  IF NOT (
    public.can(v_caller_person_id, 'manage_partner', 'organization', p_org_id)
    OR public.can(v_caller_person_id, 'manage_member', 'organization', p_org_id)
  ) THEN
    RETURN jsonb_build_object(
      'error', 'Unauthorized: requires manage_partner or manage_member at organization scope'
    );
  END IF;

  -- ─── Validate inputs ───
  IF p_initiative_title IS NULL OR length(trim(p_initiative_title)) = 0 THEN
    RETURN jsonb_build_object('error', 'initiative_title is required');
  END IF;

  SELECT pe.name INTO v_partner_name
  FROM public.partner_entities pe
  WHERE pe.id = p_partner_entity_id AND pe.organization_id = p_org_id;

  IF v_partner_name IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'partner_entity not found in this organization',
      'partner_entity_id', p_partner_entity_id
    );
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.persons WHERE id = p_lead_person_id) INTO v_lead_exists;
  IF NOT v_lead_exists THEN
    RETURN jsonb_build_object('error', 'lead_person not found', 'lead_person_id', p_lead_person_id);
  END IF;

  IF p_co_person_id IS NOT NULL THEN
    IF p_co_person_id = p_lead_person_id THEN
      RETURN jsonb_build_object('error', 'co_person must differ from lead_person');
    END IF;
    SELECT EXISTS(SELECT 1 FROM public.persons WHERE id = p_co_person_id) INTO v_co_exists;
    IF NOT v_co_exists THEN
      RETURN jsonb_build_object('error', 'co_person not found', 'co_person_id', p_co_person_id);
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.engagement_kinds
    WHERE slug = 'speaker'
      AND p_initiative_kind = ANY(initiative_kinds_allowed)
  ) THEN
    RETURN jsonb_build_object(
      'error', format('speaker engagements not allowed for initiative_kind "%s"', p_initiative_kind),
      'hint', 'Allowed kinds: research_tribe, study_group, congress, workshop'
    );
  END IF;

  -- ─── Step 1: initiative ───
  INSERT INTO public.initiatives (
    kind, organization_id, title, description, status, origin_partner_entity_id, metadata
  )
  VALUES (
    p_initiative_kind,
    p_org_id,
    p_initiative_title,
    p_initiative_description,
    'active',
    p_partner_entity_id,
    jsonb_strip_nulls(jsonb_build_object(
      'whatsapp_url', p_whatsapp_url,
      'meeting_link', p_meeting_link,
      'drive_folder_url', p_drive_folder_url,
      'source', 'create_external_speaker_engagement',
      'created_by_person', v_caller_person_id::text
    ))
  )
  RETURNING id INTO v_initiative_id;

  -- ─── Step 2: project_board (global scope) ───
  INSERT INTO public.project_boards (
    board_name, source, board_scope, domain_key, initiative_id, organization_id, created_by
  )
  VALUES (
    p_initiative_title || ' — Milestones',
    'manual',
    'global',
    p_board_domain_key,
    v_initiative_id,
    p_org_id,
    v_caller_member_id
  )
  RETURNING id INTO v_board_id;

  -- ─── Step 3: lead speaker engagement ───
  INSERT INTO public.engagements (
    person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id
  )
  VALUES (
    p_lead_person_id, v_initiative_id, 'speaker', 'lead_presenter', 'active', 'consent',
    v_caller_person_id,
    jsonb_build_object(
      'presenter_role', 'lead',
      'source', 'create_external_speaker_engagement',
      'partner_entity_id', p_partner_entity_id::text
    ),
    p_org_id
  )
  RETURNING id INTO v_lead_engagement_id;

  -- ─── Step 4: co speaker engagement (optional) ───
  IF p_co_person_id IS NOT NULL THEN
    INSERT INTO public.engagements (
      person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id
    )
    VALUES (
      p_co_person_id, v_initiative_id, 'speaker', 'co_presenter', 'active', 'consent',
      v_caller_person_id,
      jsonb_build_object(
        'presenter_role', 'co',
        'source', 'create_external_speaker_engagement',
        'partner_entity_id', p_partner_entity_id::text
      ),
      p_org_id
    )
    RETURNING id INTO v_co_engagement_id;
  END IF;

  -- ─── Step 5: board_items from p_deadlines ───
  IF p_deadlines IS NOT NULL AND jsonb_typeof(p_deadlines) = 'array'
     AND jsonb_array_length(p_deadlines) > 0 THEN
    FOR v_deadline IN SELECT * FROM jsonb_array_elements(p_deadlines)
    LOOP
      IF v_deadline ->> 'title' IS NULL THEN
        RAISE EXCEPTION 'deadlines[%].title is required', v_position - 1;
      END IF;
      IF v_deadline ->> 'due_date' IS NULL THEN
        RAISE EXCEPTION 'deadlines[%].due_date is required (YYYY-MM-DD)', v_position - 1;
      END IF;

      INSERT INTO public.board_items (
        board_id, title, description, status, due_date, baseline_date,
        tags, source_type, source_partner_id, is_portfolio_item, position,
        organization_id, created_by
      )
      VALUES (
        v_board_id,
        v_deadline ->> 'title',
        v_deadline ->> 'description',
        COALESCE(v_deadline ->> 'status', 'todo'),
        (v_deadline ->> 'due_date')::date,
        COALESCE((v_deadline ->> 'baseline_date')::date, (v_deadline ->> 'due_date')::date),
        COALESCE(
          ARRAY(SELECT jsonb_array_elements_text(v_deadline -> 'tags')),
          '{}'::text[]
        ),
        'external_partner',
        p_partner_entity_id,
        COALESCE((v_deadline ->> 'is_portfolio_item')::boolean, false),
        v_position,
        p_org_id,
        v_caller_member_id
      );
      v_board_items_count := v_board_items_count + 1;
      v_position := v_position + 1;
    END LOOP;
  END IF;

  -- ─── Step 6: partner_interaction log (type='note' per CHECK constraint) ───
  -- partner_interactions.interaction_type CHECK = ANY(email|whatsapp|linkedin|call|meeting|note|status_change)
  -- Use 'note' with summary prefix "Initiative created" to preserve semantic intent.
  INSERT INTO public.partner_interactions (
    partner_id, interaction_type, summary, details, actor_member_id
  )
  VALUES (
    p_partner_entity_id,
    'note',
    format('Initiative created: "%s"', p_initiative_title),
    format(
      'initiative_id=%s; kind=%s; lead_person_id=%s%s; board_items=%s; via=create_external_speaker_engagement',
      v_initiative_id::text,
      p_initiative_kind,
      p_lead_person_id::text,
      CASE WHEN p_co_person_id IS NOT NULL THEN '; co_person_id=' || p_co_person_id::text ELSE '' END,
      v_board_items_count::text
    ),
    v_caller_member_id
  )
  RETURNING id INTO v_interaction_id;

  -- ─── Step 7: bump partner last_interaction_at ───
  UPDATE public.partner_entities
  SET last_interaction_at = now(), updated_at = now()
  WHERE id = p_partner_entity_id;

  -- ─── Return summary ───
  RETURN jsonb_build_object(
    'ok', true,
    'initiative_id', v_initiative_id,
    'board_id', v_board_id,
    'lead_engagement_id', v_lead_engagement_id,
    'co_engagement_id', v_co_engagement_id,
    'partner_interaction_id', v_interaction_id,
    'board_items_count', v_board_items_count,
    'partner_name', v_partner_name
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_initiative(p_kind text, p_title text, p_description text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb, p_parent_initiative_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_kind_row record;
  v_count integer;
  v_new_id uuid;
BEGIN
  SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = p_kind;
  IF v_kind_row IS NULL THEN
    RAISE EXCEPTION 'Unknown initiative kind: %', p_kind USING ERRCODE = 'P0004';
  END IF;

  IF v_kind_row.max_concurrent_per_org IS NOT NULL THEN
    SELECT count(*) INTO v_count
    FROM public.initiatives
    WHERE kind = p_kind
      AND organization_id = public.auth_org()
      AND status IN ('draft', 'active');

    IF v_count >= v_kind_row.max_concurrent_per_org THEN
      RAISE EXCEPTION 'Maximum concurrent initiatives of kind "%" reached (limit: %)',
        p_kind, v_kind_row.max_concurrent_per_org USING ERRCODE = 'P0005';
    END IF;
  END IF;

  INSERT INTO public.initiatives (kind, title, description, metadata, parent_initiative_id, organization_id)
  VALUES (p_kind, p_title, p_description, p_metadata, p_parent_initiative_id, public.auth_org())
  RETURNING id INTO v_new_id;

  IF v_kind_row.has_board THEN
    INSERT INTO public.project_boards (board_name, initiative_id, source, is_active, organization_id)
    VALUES (p_title, v_new_id, 'manual', true, public.auth_org());
  END IF;

  RETURN v_new_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_initiative_invitations(p_initiative_id uuid, p_invitee_member_ids uuid[], p_kind_scope text, p_message text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_initiative record;
  v_kind_allows_owner boolean;
  v_is_admin boolean;
  v_is_owner boolean;
  v_invitee uuid;
  v_results jsonb := '[]'::jsonb;
  v_invitation_id uuid;
  v_skip_reason text;
BEGIN
  -- Validate caller
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate message length (min 50 per ux R5; CHECK enforces too)
  IF length(p_message) < 50 THEN
    RAISE EXCEPTION 'Message must be at least 50 characters (current: %)', length(p_message)
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Validate initiative
  SELECT i.* INTO v_initiative FROM public.initiatives i WHERE i.id = p_initiative_id;
  IF v_initiative.id IS NULL THEN
    RAISE EXCEPTION 'Initiative not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_initiative.status NOT IN ('active', 'draft') THEN
    RAISE EXCEPTION 'Initiative is not active' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Validate kind_scope allowed for this initiative
  IF NOT EXISTS (
    SELECT 1 FROM public.engagement_kinds ek
    WHERE ek.slug = p_kind_scope AND v_initiative.kind = ANY(ek.initiative_kinds_allowed)
  ) THEN
    RAISE EXCEPTION 'Engagement kind "%" not allowed for initiative kind "%"', p_kind_scope, v_initiative.kind
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Authority check: admin (manage_member) OR owner/coordinator with kind_scope allowing 'owner'/'coordinator'
  v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');

  IF NOT v_is_admin THEN
    v_is_owner := EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = v_caller_person_id
        AND e.initiative_id = p_initiative_id
        AND e.status = 'active'
        AND (e.kind LIKE '%_owner' OR e.kind LIKE '%_coordinator' OR e.role IN ('owner','coordinator','lead'))
    );

    SELECT EXISTS (
      SELECT 1 FROM public.engagement_kinds ek
      WHERE ek.slug = p_kind_scope
        AND ('owner' = ANY(ek.created_by_role) OR 'coordinator' = ANY(ek.created_by_role))
    ) INTO v_kind_allows_owner;

    IF NOT (v_is_owner AND v_kind_allows_owner) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member OR owner/coordinator of initiative AND kind_scope allows owner/coordinator creation'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Process each invitee
  FOREACH v_invitee IN ARRAY p_invitee_member_ids
  LOOP
    v_invitation_id := NULL;
    v_skip_reason := NULL;

    -- Skip if invitee not active
    IF NOT EXISTS (SELECT 1 FROM public.members WHERE id = v_invitee AND is_active = true) THEN
      v_skip_reason := 'invitee_not_active';
    -- Skip if already has active engagement in initiative
    ELSIF EXISTS (
      SELECT 1 FROM public.engagements e
      JOIN public.members m ON m.person_id = e.person_id
      WHERE m.id = v_invitee AND e.initiative_id = p_initiative_id AND e.status = 'active'
    ) THEN
      v_skip_reason := 'already_engaged';
    -- Skip if pending invitation exists
    ELSIF EXISTS (
      SELECT 1 FROM public.initiative_invitations
      WHERE initiative_id = p_initiative_id AND invitee_member_id = v_invitee AND status = 'pending'
    ) THEN
      v_skip_reason := 'pending_invitation_exists';
    ELSE
      INSERT INTO public.initiative_invitations
        (initiative_id, invitee_member_id, inviter_member_id, kind_scope, message)
      VALUES
        (p_initiative_id, v_invitee, v_caller_member_id, p_kind_scope, p_message)
      RETURNING id INTO v_invitation_id;
    END IF;

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'invitee_member_id', v_invitee,
      'invitation_id', v_invitation_id,
      'created', v_invitation_id IS NOT NULL,
      'skip_reason', v_skip_reason
    ));
  END LOOP;

  RETURN jsonb_build_object(
    'initiative_id', p_initiative_id,
    'kind_scope', p_kind_scope,
    'invitations', v_results,
    'authorized_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END,
    'expires_at', (now() + interval '72 hours')
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_next_geral_meeting(p_meeting_link text, p_youtube_url text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_interval_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_last_date date;
  v_next_date date;
  v_event_id uuid;
  v_recurrence uuid := '8ef692c1-8cae-486c-ab7b-2d3536188ef5';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Forbidden: only authorized managers can create general meetings';
  END IF;

  IF p_meeting_link IS NULL OR length(trim(p_meeting_link)) = 0 THEN
    RAISE EXCEPTION 'meeting_link required';
  END IF;

  SELECT MAX(date) INTO v_last_date FROM public.events WHERE type = 'geral';
  v_last_date := COALESCE(v_last_date, CURRENT_DATE);
  v_next_date := GREATEST(v_last_date + p_interval_days, CURRENT_DATE);

  INSERT INTO public.events (
    type, title, date, time_start, duration_minutes,
    meeting_link, youtube_url,
    visibility, audience_level,
    recurrence_group, source,
    created_by, created_at, updated_at
  ) VALUES (
    'geral',
    COALESCE(p_title, 'Reunião Geral — ' || to_char(v_next_date, 'YYYY-MM-DD')),
    v_next_date, '19:30', 90,
    p_meeting_link, p_youtube_url,
    'all', 'all',
    v_recurrence, 'manual',
    v_caller_id, now(), now()
  ) RETURNING id INTO v_event_id;

  RETURN jsonb_build_object(
    'event_id', v_event_id,
    'date', v_next_date,
    'meeting_link', p_meeting_link,
    'youtube_url', p_youtube_url,
    'title', COALESCE(p_title, 'Reunião Geral — ' || to_char(v_next_date, 'YYYY-MM-DD'))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_recurring_weekly_events(p_type text, p_title_template text, p_start_date date, p_duration_minutes integer DEFAULT 60, p_n_weeks integer DEFAULT 10, p_meeting_link text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_is_recorded boolean DEFAULT false, p_audience_level text DEFAULT NULL::text, p_time_start time without time zone DEFAULT NULL::time without time zone)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller        RECORD;
  v_group_id      UUID := gen_random_uuid();
  v_week          INTEGER;
  v_date          DATE;
  v_title         TEXT;
  v_ids           UUID[] := '{}';
  v_new_id        UUID;
  v_initiative_id UUID;
  v_time_start    time without time zone;
  v_default_slot  time without time zone;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_caller IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT (v_caller.is_superadmin OR public.can_by_member(v_caller.id, 'manage_event')) THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions: requires manage_event');
  END IF;

  IF v_caller.operational_role = 'tribe_leader' AND NOT v_caller.is_superadmin THEN
    IF p_type NOT IN ('tribo', 'tribe_meeting') THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe meetings');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
  END IF;

  IF p_type = 'tribe_meeting' THEN
    p_type := 'tribo';
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;

    -- Pre-compute the tribe's first slot as fallback when ISODOW does not match
    SELECT time_start INTO v_default_slot
    FROM public.tribe_meeting_slots
    WHERE tribe_id = p_tribe_id
    ORDER BY day_of_week
    LIMIT 1;
  END IF;

  FOR v_week IN 1..p_n_weeks LOOP
    v_date  := p_start_date + ((v_week - 1) * 7);
    v_title := REPLACE(
                 REPLACE(p_title_template, '{n}', v_week::TEXT),
                 '{date}', TO_CHAR(v_date, 'DD/MM')
               );

    -- Per-week time_start: explicit > tribe slot for ISODOW of v_date > tribe first slot > '19:00'
    v_time_start := p_time_start;
    IF v_time_start IS NULL AND p_tribe_id IS NOT NULL THEN
      SELECT time_start INTO v_time_start
      FROM public.tribe_meeting_slots
      WHERE tribe_id = p_tribe_id
        AND day_of_week = EXTRACT(ISODOW FROM v_date)::int
      LIMIT 1;
      v_time_start := COALESCE(v_time_start, v_default_slot);
    END IF;
    v_time_start := COALESCE(v_time_start, '19:00:00'::time);

    INSERT INTO public.events
      (type, title, date, time_start, duration_minutes, initiative_id, meeting_link,
       is_recorded, recurrence_group, created_by, audience_level)
    VALUES
      (p_type, v_title, v_date, v_time_start, p_duration_minutes,
       v_initiative_id, p_meeting_link, p_is_recorded, v_group_id, auth.uid(),
       p_audience_level)
    RETURNING id INTO v_new_id;

    v_ids := array_append(v_ids, v_new_id);
  END LOOP;

  RETURN json_build_object(
    'success',          true,
    'recurrence_group', v_group_id,
    'events_created',   p_n_weeks,
    'event_ids',        v_ids
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_card_comment(p_comment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_comment record;
  v_authorized boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_comment FROM public.board_item_comments WHERE id = p_comment_id;
  IF v_comment.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Comment not found');
  END IF;

  -- Author OR write_board OR admin
  v_authorized := v_comment.author_id = v_caller_id
    OR public.can_by_member(v_caller_id, 'write_board')
    OR public.can_by_member(v_caller_id, 'manage_member');

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE public.board_item_comments
  SET deleted_at = now(), updated_at = now()
  WHERE id = p_comment_id;

  RETURN jsonb_build_object('success', true, 'comment_id', p_comment_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_checklist_item(p_checklist_item_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_item record;
  v_card record;
  v_board record;
  v_authorized boolean;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  SELECT * INTO v_item FROM board_item_checklists WHERE id = p_checklist_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Checklist item not found'; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = v_item.board_item_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_card.board_id;

  v_authorized := public.can_by_member(v_caller_id, 'write_board')
    OR v_card.assignee_id = v_caller_id
    OR EXISTS (
      SELECT 1 FROM board_members bm
      WHERE bm.board_id = v_board.id AND bm.member_id = v_caller_id
      AND bm.board_role IN ('admin', 'editor')
    );

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership, or board editor role';
  END IF;

  DELETE FROM board_item_checklists WHERE id = p_checklist_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id, 'activity_deleted',
    v_item.text || COALESCE(' (motivo: ' || p_reason || ')', ''),
    v_caller_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.deselect_tribe()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  _member_id UUID;
BEGIN
  SELECT id INTO _member_id FROM members 
  WHERE auth_id = auth.uid()
     OR email = (SELECT email FROM auth.users WHERE id = auth.uid())
     OR (SELECT email FROM auth.users WHERE id = auth.uid()) = ANY(secondary_emails)
  LIMIT 1;
  
  IF _member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Membro não encontrado');
  END IF;
  
  DELETE FROM tribe_selections WHERE member_id = _member_id;
  RETURN json_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.detect_inactive_members(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_threshold int;
  v_candidates jsonb := '[]'::jsonb;
  v_count int := 0;
  v_notified int := 0;
  v_cron_context boolean;
BEGIN
  -- Cron-context auth bypass (ADR-0028 pattern)
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF NOT v_cron_context AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NOT v_cron_context THEN
    PERFORM 1 FROM public.members
    WHERE auth_id = auth.uid()
      AND public.can_by_member(id, 'manage_member');
    IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized: requires manage_member'; END IF;
  END IF;

  SELECT COALESCE((value::text)::int, 180) INTO v_threshold
  FROM public.site_config WHERE key = 'inactivity_threshold_days';
  v_threshold := COALESCE(v_threshold, 180);

  WITH inactive AS (
    SELECT
      m.id AS member_id,
      m.name,
      m.email,
      m.tribe_id,
      m.chapter,
      m.created_at AS member_created_at,
      (SELECT MAX(a.checked_in_at) FROM public.attendance a
        WHERE a.member_id = m.id AND a.present = true) AS last_attendance_at,
      m.updated_at AS last_member_update_at
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.is_active = true
      AND m.anonymized_at IS NULL
      AND m.name <> 'VP Desenvolvimento Profissional (PMI-GO)'
      -- Exclude very recent joins (need at least threshold days history)
      AND m.created_at < (now() - make_interval(days => v_threshold))
      -- Either no attendance ever, OR last attendance older than threshold
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.member_id = m.id AND a.present = true
          AND a.checked_in_at > (now() - make_interval(days => v_threshold))
      )
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'member_id', member_id,
    'name', name,
    'chapter', chapter,
    'tribe_id', tribe_id,
    'last_attendance_at', last_attendance_at,
    'days_since_last_attendance',
      CASE WHEN last_attendance_at IS NULL
        THEN EXTRACT(DAY FROM now() - member_created_at)::int
        ELSE EXTRACT(DAY FROM now() - last_attendance_at)::int
      END
  )), '[]'::jsonb), COALESCE(COUNT(*), 0)
  INTO v_candidates, v_count
  FROM inactive;

  -- Notify managers (only if not dry run AND there are candidates)
  IF NOT p_dry_run AND v_count > 0 THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT mgr.id,
           'arm9_inactivity_alert',
           v_count || ' membro(s) sem atividade há mais de ' || v_threshold || ' dias',
           'Considerar transição para status inactive. Lista disponível em /admin/members?filter=inactive_candidates',
           '/admin/members?filter=inactive_candidates',
           'arm9_inactivity_detection',
           NULL
    FROM public.members mgr
    WHERE mgr.is_active = true AND mgr.operational_role IN ('manager','deputy_manager');
    GET DIAGNOSTICS v_notified = ROW_COUNT;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'arm9.inactivity_detection_run', NULL, NULL,
      jsonb_build_object('threshold_days', v_threshold, 'candidates_count', v_count, 'managers_notified', v_notified),
      jsonb_build_object('dry_run', false, 'source', 'cron_or_manual')
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'threshold_days', v_threshold,
    'candidates_count', v_count,
    'candidates', v_candidates,
    'managers_notified', v_notified,
    'dry_run', p_dry_run
  );
END $function$;

CREATE OR REPLACE FUNCTION public.detect_stale_events_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_inserted integer := 0;
BEGIN
  -- 24-48h window (gives líder 1 day to react before falling into wider monitoring)
  SELECT count(*) INTO v_count
  FROM events e
  WHERE e.date BETWEEN CURRENT_DATE - 2 AND CURRENT_DATE - 1
    AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id);

  IF v_count > 0 THEN
    INSERT INTO notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'event_stale_no_attendance',
           format('%s evento(s) sem attendance marcado', v_count),
           format('%s evento(s) passado(s) há mais de 24h não tem nenhuma marcação de presença. Cancele se a reunião não aconteceu OU marque presença em /attendance.', v_count),
           'digest_weekly',
           now()
    FROM members m
    WHERE m.is_active = true
      AND m.operational_role IN ('manager', 'deputy_manager');
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'stale_count', v_count,
    'notifications_inserted', v_inserted,
    'window_hours', 48,
    'run_at', now()
  );
END $function$;

CREATE OR REPLACE FUNCTION public.detect_stale_portfolio_items_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_inserted integer := 0;
  v_stale_threshold interval := '60 days';
BEGIN
  SELECT count(*) INTO v_count
  FROM board_items bi
  WHERE bi.is_portfolio_item = true
    AND bi.status NOT IN ('done', 'archived')
    AND bi.updated_at < now() - v_stale_threshold;

  -- Only insert reminder if there is something stale (smart-skip empty digest per ADR-0022)
  IF v_count > 0 THEN
    INSERT INTO notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'portfolio_stale_reminder',
           format('%s portfolio item(s) precisam de update', v_count),
           format('%s itens marcados is_portfolio_item=true sem update há mais de 60 dias. Revise via /admin/portfolio.', v_count),
           'digest_weekly',
           now()
    FROM members m
    WHERE m.is_active = true
      AND m.operational_role IN ('manager', 'deputy_manager');

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'stale_count', v_count,
    'notifications_inserted', v_inserted,
    'threshold_days', 60,
    'run_at', now()
  );
END $function$;

CREATE OR REPLACE FUNCTION public.dismiss_visitor_lead(p_lead_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_lead record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_lead FROM public.visitor_leads WHERE id = p_lead_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Lead not found'); END IF;

  IF v_lead.status IN ('promoted','dismissed') THEN
    RETURN jsonb_build_object('error','Cannot dismiss from state: ' || v_lead.status);
  END IF;

  UPDATE public.visitor_leads SET
    status = 'dismissed',
    dismissed_at = now(),
    dismissed_by = v_caller.id,
    dismissal_reason = p_reason
  WHERE id = p_lead_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 'visitor_lead.dismissed', 'visitor_lead', p_lead_id,
    jsonb_build_object('previous_status', v_lead.status),
    jsonb_strip_nulls(jsonb_build_object('reason', p_reason, 'lead_email', v_lead.email))
  );

  RETURN jsonb_build_object('success', true, 'lead_id', p_lead_id);
END $function$;

CREATE OR REPLACE FUNCTION public.generate_weekly_card_digest_cron()
 RETURNS TABLE(member_id uuid, notified boolean, reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_m record;
  v_overdue jsonb;
  v_pending jsonb;
  v_next jsonb;
  v_has_content boolean;
  v_body text;
  v_title text;
  v_pending_count int;
  v_overdue_count int;
  v_next_count int;
BEGIN
  FOR v_m IN
    SELECT id, name, email
    FROM public.members
    WHERE is_active = true
      AND notify_weekly_digest = true
  LOOP
    v_overdue := COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'days_overdue', CURRENT_DATE - bi.due_date,
        'initiative_title', i.title
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = v_m.id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date < CURRENT_DATE - INTERVAL '7 days'
    ), '[]'::jsonb);

    v_pending := COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'days_overdue', GREATEST(0, CURRENT_DATE - bi.due_date),
        'initiative_title', i.title
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = v_m.id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE
    ), '[]'::jsonb);

    v_next := COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'initiative_title', i.title
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = v_m.id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date > CURRENT_DATE
        AND bi.due_date <= CURRENT_DATE + INTERVAL '7 days'
    ), '[]'::jsonb);

    v_overdue_count := jsonb_array_length(v_overdue);
    v_pending_count := jsonb_array_length(v_pending);
    v_next_count := jsonb_array_length(v_next);
    v_has_content := v_overdue_count > 0 OR v_pending_count > 0 OR v_next_count > 0;

    IF v_has_content THEN
      v_title := 'Resumo semanal: ' ||
        CASE WHEN v_overdue_count > 0 THEN v_overdue_count::text || ' atrasada' ||
             CASE WHEN v_overdue_count > 1 THEN 's' ELSE '' END || ' + ' ELSE '' END ||
        v_pending_count::text || ' recente' ||
        CASE WHEN v_pending_count <> 1 THEN 's' ELSE '' END || ' + ' ||
        v_next_count::text || ' próxima semana';

      v_body := 'Olá, ' || COALESCE(v_m.name, 'voluntário(a)') || '!' || E'\n\n' ||
        'Aqui vai seu resumo semanal de atividades no Núcleo IA & GP.' || E'\n\n';

      IF v_overdue_count > 0 THEN
        v_body := v_body || 'ATRASADAS MAIS DE 7 DIAS (' || v_overdue_count || '):' || E'\n';
        v_body := v_body || (
          SELECT string_agg(
            '- ' || (item->>'title') ||
            ' — ' || (item->>'days_overdue') || ' dias atrasado' ||
            COALESCE(' (' || (item->>'initiative_title') || ')', ''),
            E'\n'
          )
          FROM jsonb_array_elements(v_overdue) AS item
        ) || E'\n\n';
      END IF;

      IF v_pending_count > 0 THEN
        v_body := v_body || 'PENDENTES DOS ÚLTIMOS 7 DIAS (' || v_pending_count || '):' || E'\n';
        v_body := v_body || (
          SELECT string_agg(
            '- ' || (item->>'title') ||
            ' — vence ' || (item->>'due_date') ||
            CASE WHEN (item->>'days_overdue')::int > 0
                 THEN ' (' || (item->>'days_overdue') || ' dias atraso)'
                 ELSE '' END ||
            COALESCE(' (' || (item->>'initiative_title') || ')', ''),
            E'\n'
          )
          FROM jsonb_array_elements(v_pending) AS item
        ) || E'\n\n';
      END IF;

      IF v_next_count > 0 THEN
        v_body := v_body || 'PRÓXIMOS 7 DIAS (' || v_next_count || '):' || E'\n';
        v_body := v_body || (
          SELECT string_agg(
            '- ' || (item->>'title') ||
            ' — vence ' || (item->>'due_date') ||
            COALESCE(' (' || (item->>'initiative_title') || ')', ''),
            E'\n'
          )
          FROM jsonb_array_elements(v_next) AS item
        ) || E'\n\n';
      END IF;

      v_body := v_body || 'Acesse a plataforma para atualizar cards, negociar prazos ou marcar tarefas concluídas.';

      INSERT INTO public.notifications (
        recipient_id, type, title, body, link, is_read
      )
      VALUES (
        v_m.id,
        'weekly_card_digest_member',
        v_title,
        v_body,
        '/workspace',
        false
      );
      member_id := v_m.id; notified := true; reason := 'sent';
    ELSE
      member_id := v_m.id; notified := false; reason := 'no_pending_cards_skip';
    END IF;
    RETURN NEXT;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_active_engagements(p_person_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_target_person_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_person_id IS NULL THEN
    SELECT p.id INTO v_target_person_id FROM public.persons p WHERE p.legacy_member_id = v_caller_member_id;
  ELSE
    v_target_person_id := p_person_id;
    IF v_target_person_id != (SELECT id FROM public.persons WHERE legacy_member_id = v_caller_member_id) THEN
      IF NOT public.can(auth.uid(), 'manage_member', NULL, NULL) THEN
        RETURN jsonb_build_object('error', 'Unauthorized: manage_member required');
      END IF;
    END IF;
  END IF;

  IF v_target_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', e.id, 'kind', e.kind, 'kind_display', ek.display_name, 'role', e.role,
      'status', e.status, 'initiative_id', e.initiative_id, 'initiative_name', i.name,
      'initiative_kind', i.kind, 'start_date', e.start_date, 'end_date', e.end_date,
      'legal_basis', e.legal_basis, 'has_agreement', (e.agreement_certificate_id IS NOT NULL),
      'is_authoritative', (e.status = 'active' AND e.start_date <= CURRENT_DATE
        AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
        AND (e.agreement_certificate_id IS NOT NULL OR NOT COALESCE(ek.requires_agreement, false))),
      'granted_at', e.granted_at
    ) ORDER BY e.start_date DESC
  ), '[]'::jsonb) INTO v_result
  FROM public.engagements e
  JOIN public.engagement_kinds ek ON ek.slug = e.kind
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.person_id = v_target_person_id AND e.status = 'active';

  RETURN jsonb_build_object('person_id', v_target_person_id, 'engagements', v_result, 'count', jsonb_array_length(v_result));
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_application_returning_context(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_can_view_full       boolean;
  v_app                 record;
  v_matched_member      record;
  v_offboard_record     record;
  v_category            record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  SELECT public.can_by_member(v_caller_id, 'manage_member') INTO v_can_view_full;
  IF NOT v_can_view_full THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member action';
  END IF;

  -- Look up application by id; require email match for member lookup
  SELECT id, email, applicant_name, cycle_id, status, is_returning_member,
         previous_cycles, application_count
  INTO v_app
  FROM public.selection_applications
  WHERE id = p_application_id;

  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('found', false, 'application_id', p_application_id);
  END IF;

  -- Match via email (canonicalized lowercase)
  SELECT id, name, chapter, member_status, operational_role, offboarded_at
  INTO v_matched_member
  FROM public.members
  WHERE lower(email) = lower(v_app.email)
  LIMIT 1;

  IF v_matched_member.id IS NULL THEN
    -- No prior member match — no offboarding context to return
    RETURN jsonb_build_object(
      'found', true,
      'application_id', p_application_id,
      'is_returning_member', v_app.is_returning_member,
      'previous_cycles', to_jsonb(v_app.previous_cycles),
      'application_count', v_app.application_count,
      'matched_member', null,
      'offboarding_context', null
    );
  END IF;

  -- Fetch offboarding record if exists
  SELECT *
  INTO v_offboard_record
  FROM public.member_offboarding_records
  WHERE member_id = v_matched_member.id;

  IF v_offboard_record.id IS NULL THEN
    -- Member exists but no offboarding record (active member re-applying, edge case)
    RETURN jsonb_build_object(
      'found', true,
      'application_id', p_application_id,
      'is_returning_member', v_app.is_returning_member,
      'previous_cycles', to_jsonb(v_app.previous_cycles),
      'application_count', v_app.application_count,
      'matched_member', jsonb_build_object(
        'id', v_matched_member.id,
        'name', v_matched_member.name,
        'chapter', v_matched_member.chapter,
        'member_status', v_matched_member.member_status,
        'operational_role', v_matched_member.operational_role,
        'offboarded_at', v_matched_member.offboarded_at
      ),
      'offboarding_context', null
    );
  END IF;

  -- Resolve category label
  IF v_offboard_record.reason_category_code IS NOT NULL THEN
    SELECT code, label_pt, is_volunteer_fault, preserves_return_eligibility
    INTO v_category
    FROM public.offboard_reason_categories
    WHERE code = v_offboard_record.reason_category_code;
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'application_id', p_application_id,
    'is_returning_member', v_app.is_returning_member,
    'previous_cycles', to_jsonb(v_app.previous_cycles),
    'application_count', v_app.application_count,
    'matched_member', jsonb_build_object(
      'id', v_matched_member.id,
      'name', v_matched_member.name,
      'chapter', v_matched_member.chapter,
      'member_status', v_matched_member.member_status,
      'operational_role', v_matched_member.operational_role,
      'offboarded_at', v_matched_member.offboarded_at
    ),
    'offboarding_context', jsonb_build_object(
      'record_id', v_offboard_record.id,
      'offboarded_at', v_offboard_record.offboarded_at,
      'offboarded_by', v_offboard_record.offboarded_by,
      'reason_category_code', v_offboard_record.reason_category_code,
      'reason_category_label_pt', v_category.label_pt,
      'is_volunteer_fault', COALESCE(v_category.is_volunteer_fault, false),
      'preserves_return_eligibility', COALESCE(v_category.preserves_return_eligibility, true),
      'reason_detail', v_offboard_record.reason_detail,
      'return_interest', v_offboard_record.return_interest,
      'return_window_suggestion', v_offboard_record.return_window_suggestion,
      'lessons_learned', v_offboard_record.lessons_learned,
      'recommendation_for_future', v_offboard_record.recommendation_for_future,
      'tribe_id_at_offboard', v_offboard_record.tribe_id_at_offboard,
      'cycle_code_at_offboard', v_offboard_record.cycle_code_at_offboard,
      'has_full_interview', v_offboard_record.exit_interview_full_text IS NOT NULL
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_audit_log(p_actor_id uuid DEFAULT NULL::uuid, p_target_id uuid DEFAULT NULL::uuid, p_action text DEFAULT NULL::text, p_date_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_date_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_entries jsonb;
  v_total bigint;
  v_actors jsonb;
  v_search text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ADR-0011: audit log carries member changes + settings (PII-adjacent)
  -- Use manage_platform (seeded in B8.1) OR is_superadmin fallback
  IF NOT (v_caller.is_superadmin IS TRUE
       OR public.can_by_member(v_caller.id, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  v_search := CASE WHEN p_action IS NOT NULL AND trim(p_action) != ''
                   THEN '%' || trim(p_action) || '%' ELSE NULL END;

  WITH unified AS (
    SELECT
      al.id::text AS id,
      'members'::text AS category,
      al.created_at AS event_date,
      al.actor_id AS actor_id,
      actor.name AS actor_name,
      CASE al.action
        WHEN 'member.status_transition' THEN 'status_change'
        WHEN 'member.role_change' THEN 'role_change'
        ELSE replace(al.action, 'member.', '')
      END AS action,
      target.name AS target_name,
      al.target_id AS target_id,
      CASE al.action
        WHEN 'member.status_transition' THEN
          COALESCE(al.changes->>'previous_status','') || ' → ' || COALESCE(al.changes->>'new_status','')
        WHEN 'member.role_change' THEN
          COALESCE(al.changes->>'field','') || ': ' ||
          COALESCE(al.changes->>'old_value','') || ' → ' || COALESCE(al.changes->>'new_value','')
        ELSE al.changes::text
      END AS summary,
      COALESCE(al.metadata->>'reason_detail', al.metadata->>'reason') AS detail
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor  ON actor.id  = al.actor_id
    LEFT JOIN public.members target ON target.id = al.target_id
    WHERE al.target_type = 'member'
      AND al.action IN ('member.status_transition','member.role_change')
    UNION ALL
    SELECT
      ble.id::text, 'boards', ble.created_at,
      ble.actor_member_id, actor.name, ble.action,
      COALESCE(bi.title, 'Card'), ble.item_id,
      COALESCE(ble.previous_status, '') ||
        CASE WHEN ble.new_status IS NOT NULL AND ble.previous_status IS NOT NULL THEN ' → ' || ble.new_status
             WHEN ble.new_status IS NOT NULL THEN ble.new_status ELSE '' END,
      ble.reason
    FROM public.board_lifecycle_events ble
    LEFT JOIN public.board_items bi ON bi.id = ble.item_id
    LEFT JOIN public.members actor ON actor.id = ble.actor_member_id
    UNION ALL
    SELECT
      al.id::text, 'settings', al.created_at,
      al.actor_id, actor.name, 'setting_changed',
      COALESCE(al.metadata->>'setting_key', '(unknown)'),
      NULL::uuid,
      COALESCE(al.changes->>'previous_value', '?') || ' → ' ||
      COALESCE(al.changes->>'new_value', '?'),
      al.metadata->>'reason'
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.action = 'platform.setting_changed'
    UNION ALL
    SELECT
      pi.id::text, 'partnerships', pi.created_at,
      pi.actor_member_id, actor.name, pi.interaction_type,
      pe.name, NULL::uuid, pi.summary, pi.outcome
    FROM public.partner_interactions pi
    JOIN public.partner_entities pe ON pe.id = pi.partner_id
    LEFT JOIN public.members actor ON actor.id = pi.actor_member_id
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', u.id, 'category', u.category, 'created_at', u.event_date,
      'actor_id', u.actor_id, 'actor_name', COALESCE(u.actor_name, 'Sistema'),
      'action', u.action, 'target_name', u.target_name, 'target_id', u.target_id,
      'changes', NULL, 'summary', u.summary, 'detail', u.detail
    ) ORDER BY u.event_date DESC
  )
  INTO v_entries
  FROM unified u
  WHERE (p_actor_id IS NULL OR u.actor_id = p_actor_id)
    AND (p_target_id IS NULL OR u.target_id = p_target_id)
    AND (p_date_from IS NULL OR u.event_date >= p_date_from)
    AND (p_date_to IS NULL OR u.event_date <= p_date_to)
    AND (v_search IS NULL
      OR u.action ILIKE v_search OR u.category ILIKE v_search
      OR u.target_name ILIKE v_search OR u.summary ILIKE v_search
      OR COALESCE(u.detail,'') ILIKE v_search
      OR COALESCE(u.actor_name,'') ILIKE v_search)
  LIMIT p_limit OFFSET p_offset;

  WITH unified2 AS (
    SELECT al.actor_id AS actor_id, al.created_at AS event_date,
           CASE al.action WHEN 'member.status_transition' THEN 'status_change'
                          WHEN 'member.role_change' THEN 'role_change'
                          ELSE replace(al.action,'member.','') END AS action,
           'members'::text AS category,
           target.name AS target_name,
           CASE al.action
             WHEN 'member.status_transition' THEN
               COALESCE(al.changes->>'previous_status','')||' → '||COALESCE(al.changes->>'new_status','')
             WHEN 'member.role_change' THEN
               COALESCE(al.changes->>'old_value','')||' → '||COALESCE(al.changes->>'new_value','')
             ELSE al.changes::text END AS summary,
           COALESCE(al.metadata->>'reason_detail', al.metadata->>'reason') AS detail,
           actor.name AS actor_name,
           al.target_id
    FROM public.admin_audit_log al
    LEFT JOIN public.members target ON target.id = al.target_id
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.target_type = 'member'
      AND al.action IN ('member.status_transition','member.role_change')
    UNION ALL
    SELECT ble.actor_member_id, ble.created_at, ble.action, 'boards',
           COALESCE(bi.title,'Card'),
           COALESCE(ble.previous_status,'')||COALESCE(' → '||ble.new_status,''),
           ble.reason, actor.name, ble.item_id
    FROM public.board_lifecycle_events ble
    LEFT JOIN public.board_items bi ON bi.id = ble.item_id
    LEFT JOIN public.members actor ON actor.id = ble.actor_member_id
    UNION ALL
    SELECT al.actor_id, al.created_at, 'setting_changed', 'settings',
           COALESCE(al.metadata->>'setting_key','(unknown)'),
           COALESCE(al.changes->>'previous_value','?')||' → '||COALESCE(al.changes->>'new_value','?'),
           al.metadata->>'reason', actor.name, NULL::uuid
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.action = 'platform.setting_changed'
    UNION ALL
    SELECT pi.actor_member_id, pi.created_at, pi.interaction_type, 'partnerships',
           pe.name, pi.summary, pi.outcome, actor.name, NULL::uuid
    FROM public.partner_interactions pi
    JOIN public.partner_entities pe ON pe.id = pi.partner_id
    LEFT JOIN public.members actor ON actor.id = pi.actor_member_id
  )
  SELECT count(*) INTO v_total FROM unified2 u
  WHERE (p_actor_id IS NULL OR u.actor_id = p_actor_id)
    AND (p_target_id IS NULL OR u.target_id = p_target_id)
    AND (p_date_from IS NULL OR u.event_date >= p_date_from)
    AND (p_date_to IS NULL OR u.event_date <= p_date_to)
    AND (v_search IS NULL
      OR u.action ILIKE v_search OR u.category ILIKE v_search
      OR u.target_name ILIKE v_search OR u.summary ILIKE v_search
      OR COALESCE(u.detail,'') ILIKE v_search
      OR COALESCE(u.actor_name,'') ILIKE v_search);

  SELECT jsonb_agg(DISTINCT jsonb_build_object('id', a.id, 'name', a.name))
  INTO v_actors
  FROM (
    SELECT DISTINCT al.actor_id AS id FROM public.admin_audit_log al
      WHERE al.actor_id IS NOT NULL
    UNION SELECT DISTINCT ble.actor_member_id FROM public.board_lifecycle_events ble
      WHERE ble.actor_member_id IS NOT NULL
    UNION SELECT DISTINCT pi.actor_member_id FROM public.partner_interactions pi
      WHERE pi.actor_member_id IS NOT NULL
  ) ids JOIN public.members a ON a.id = ids.id;

  RETURN jsonb_build_object(
    'entries', COALESCE(v_entries, '[]'::jsonb),
    'total', COALESCE(v_total, 0),
    'actors', COALESCE(v_actors, '[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_board_drive_links(p_board_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'linked_by_name', m.name,
    'linked_at', l.linked_at
  ) ORDER BY l.linked_at DESC), '[]'::jsonb)
  INTO v_result
  FROM public.board_drive_links l
  LEFT JOIN public.members m ON m.id = l.linked_by
  WHERE l.board_id = p_board_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object(
    'board_id', p_board_id,
    'drive_links', v_result,
    'fetched_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_candidate_onboarding_progress(p_member_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mid uuid;
  v_result json;
BEGIN
  -- Use provided member_id or resolve from auth
  v_mid := p_member_id;
  IF v_mid IS NULL THEN
    SELECT id INTO v_mid FROM members WHERE auth_id = auth.uid();
  END IF;
  
  IF v_mid IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  -- First run auto-detection
  PERFORM check_pre_onboarding_auto_steps(v_mid);

  SELECT json_build_object(
    'member_id', v_mid,
    'steps', coalesce((
      SELECT json_agg(json_build_object(
        'step_key', op.step_key,
        'status', op.status,
        'completed_at', op.completed_at,
        'sla_deadline', op.sla_deadline,
        'xp', coalesce((op.metadata->>'xp')::int, 0),
        'phase', coalesce(op.metadata->>'phase', 'onboarding')
      ) ORDER BY 
        CASE op.step_key 
          WHEN 'create_account' THEN 1
          WHEN 'complete_profile' THEN 2
          WHEN 'setup_credly' THEN 3
          WHEN 'explore_platform' THEN 4
          WHEN 'read_blog' THEN 5
          WHEN 'start_pmi_certs' THEN 6
          WHEN 'code_of_conduct' THEN 7
          WHEN 'volunteer_term' THEN 8
          WHEN 'vep_acceptance' THEN 9
          WHEN 'first_meeting' THEN 10
          WHEN 'meet_tribe' THEN 11
          WHEN 'start_trail' THEN 12
          ELSE 99
        END
      )
      FROM onboarding_progress op
      WHERE op.member_id = v_mid
    ), '[]'::json),
    'pre_onboarding', json_build_object(
      'total', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding'),
      'completed', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding' AND status = 'completed'),
      'xp_earned', coalesce((SELECT sum((metadata->>'xp')::int) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding' AND status = 'completed'), 0),
      'xp_total', coalesce((SELECT sum((metadata->>'xp')::int) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding'), 0)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_card_detail(p_card_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_card record;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN NULL; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = p_card_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Card not found: %', p_card_id; END IF;

  RETURN jsonb_build_object(
    'card', to_jsonb(v_card),
    'board', (
      SELECT jsonb_build_object(
        'id', pb.id,
        'name', pb.board_name,
        'initiative_id', pb.initiative_id,
        'domain_key', pb.domain_key
      )
      FROM project_boards pb WHERE pb.id = v_card.board_id
    ),
    'assignee', (
      SELECT jsonb_build_object('id', m.id, 'name', m.name, 'operational_role', m.operational_role)
      FROM members m WHERE m.id = v_card.assignee_id
    ),
    'reviewer', (
      SELECT jsonb_build_object('id', m.id, 'name', m.name)
      FROM members m WHERE m.id = v_card.reviewer_id
    ),
    'checklist', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ci.id,
        'text', ci.text,
        'is_completed', ci.is_completed,
        'position', ci.position,
        'assigned_to', ci.assigned_to,
        'assigned_to_name', (SELECT m.name FROM members m WHERE m.id = ci.assigned_to),
        'target_date', ci.target_date,
        'completed_at', ci.completed_at,
        'completed_by', ci.completed_by,
        'assigned_at', ci.assigned_at
      ) ORDER BY ci.position, ci.created_at)
      FROM board_item_checklists ci WHERE ci.board_item_id = p_card_id
    ), '[]'::jsonb),
    'assignments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', ba.member_id,
        'member_name', (SELECT m.name FROM members m WHERE m.id = ba.member_id),
        'role', ba.role,
        'assigned_at', ba.assigned_at
      ))
      FROM board_item_assignments ba WHERE ba.item_id = p_card_id
    ), '[]'::jsonb),
    'timeline', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'action', ble.action,
        'reason', ble.reason,
        'actor_member_id', ble.actor_member_id,
        'actor_name', (SELECT m.name FROM members m WHERE m.id = ble.actor_member_id),
        'created_at', ble.created_at,
        'previous_status', ble.previous_status,
        'new_status', ble.new_status
      ) ORDER BY ble.created_at DESC)
      FROM (
        SELECT * FROM board_lifecycle_events
        WHERE item_id = p_card_id
        ORDER BY created_at DESC
        LIMIT 10
      ) ble
    ), '[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_chain_audit_report(p_chain_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_chain record;
  v_doc record;
  v_version record;
  v_submitter record;
  v_timeline jsonb;
  v_signoffs_full jsonb;
  v_audit_entries jsonb;
  v_integrity_summary jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: requires manage_member' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id,
         ac.opened_at, ac.opened_by, ac.approved_at, ac.closed_at, ac.closed_by, ac.notes
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN jsonb_build_object('error','chain_not_found'); END IF;

  SELECT gd.id, gd.title, gd.doc_type, gd.status AS doc_status
  INTO v_doc FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_number, dv.version_label, dv.locked_at, dv.locked_by,
         dv.published_at, dv.published_by, dv.authored_by, dv.authored_at
  INTO v_version FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT m.id, m.name, m.email, m.chapter, m.operational_role
  INTO v_submitter FROM public.members m WHERE m.id = v_chain.opened_by;

  -- Timeline cronológica: merge eventos de múltiplas fontes
  WITH events AS (
    SELECT 'version_authored' AS kind, v_version.authored_at AS at_ts,
           jsonb_build_object(
             'actor', (SELECT jsonb_build_object('id', m.id, 'name', m.name) FROM public.members m WHERE m.id = v_version.authored_by),
             'version_label', v_version.version_label
           ) AS data
    WHERE v_version.authored_at IS NOT NULL
    UNION ALL
    SELECT 'version_locked', v_version.locked_at,
           jsonb_build_object(
             'actor', (SELECT jsonb_build_object('id', m.id, 'name', m.name) FROM public.members m WHERE m.id = v_version.locked_by),
             'version_label', v_version.version_label
           )
    WHERE v_version.locked_at IS NOT NULL
    UNION ALL
    SELECT 'chain_opened', v_chain.opened_at,
           jsonb_build_object(
             'actor', jsonb_build_object('id', v_submitter.id, 'name', v_submitter.name, 'chapter', v_submitter.chapter),
             'gates_count', jsonb_array_length(v_chain.gates)
           )
    WHERE v_chain.opened_at IS NOT NULL
    UNION ALL
    SELECT 'signoff_recorded', s.signed_at,
           jsonb_build_object(
             'actor', jsonb_build_object('id', m.id, 'name', m.name, 'chapter', m.chapter, 'role', m.operational_role),
             'gate_kind', s.gate_kind,
             'signoff_type', s.signoff_type,
             'signoff_id', s.id,
             'hash_short', SUBSTRING(s.signature_hash FROM 1 FOR 12)
           )
    FROM public.approval_signoffs s
    LEFT JOIN public.members m ON m.id = s.signer_id
    WHERE s.approval_chain_id = v_chain.id
    UNION ALL
    SELECT 'chain_approved', v_chain.approved_at,
           jsonb_build_object('status_transition', jsonb_build_object('from','review','to','approved'))
    WHERE v_chain.approved_at IS NOT NULL
    UNION ALL
    SELECT 'chain_closed', v_chain.closed_at,
           jsonb_build_object(
             'actor', (SELECT jsonb_build_object('id', m.id, 'name', m.name) FROM public.members m WHERE m.id = v_chain.closed_by)
           )
    WHERE v_chain.closed_at IS NOT NULL
  )
  SELECT jsonb_agg(
    jsonb_build_object('kind', kind, 'at', at_ts, 'data', data)
    ORDER BY at_ts
  ) INTO v_timeline FROM events;

  -- Signoffs completos com sections_verified + full content_snapshot
  SELECT jsonb_agg(
    jsonb_build_object(
      'signoff_id', s.id,
      'gate_kind', s.gate_kind,
      'signoff_type', s.signoff_type,
      'signer', jsonb_build_object(
        'id', s.signer_id,
        'name', m.name,
        'email', m.email,
        'chapter', m.chapter,
        'role', m.operational_role,
        'pmi_id', m.pmi_id,
        'designations', m.designations
      ),
      'signed_at', s.signed_at,
      'signature_hash', s.signature_hash,
      'signature_hash_short', SUBSTRING(s.signature_hash FROM 1 FOR 16),
      'sections_verified', s.sections_verified,
      'sections_verified_count', COALESCE(jsonb_array_length(s.sections_verified), 0),
      'comment_body', s.comment_body,
      'content_snapshot', s.content_snapshot,
      'referenced_policy_version_id', s.referenced_policy_version_id
    ) ORDER BY s.signed_at
  )
  INTO v_signoffs_full
  FROM public.approval_signoffs s
  LEFT JOIN public.members m ON m.id = s.signer_id
  WHERE s.approval_chain_id = v_chain.id;

  -- admin_audit_log correlacionado (chain + signoffs + version)
  SELECT jsonb_agg(
    jsonb_build_object(
      'log_id', aal.id,
      'timestamp', aal.created_at,
      'actor', (SELECT jsonb_build_object('id', m.id, 'name', m.name) FROM public.members m WHERE m.id = aal.actor_id),
      'action', aal.action,
      'target_type', aal.target_type,
      'target_id', aal.target_id,
      'metadata', aal.metadata,
      'changes', aal.changes
    ) ORDER BY aal.created_at
  )
  INTO v_audit_entries
  FROM public.admin_audit_log aal
  WHERE aal.target_id = p_chain_id
     OR aal.target_id = v_chain.version_id
     OR aal.target_id = v_chain.document_id
     OR (aal.target_type = 'approval_signoff'
         AND aal.target_id IN (SELECT id FROM public.approval_signoffs WHERE approval_chain_id = p_chain_id));

  -- Integrity summary: count signoffs + hashes presence
  SELECT jsonb_build_object(
    'total_signoffs', COUNT(*),
    'with_hash', COUNT(*) FILTER (WHERE signature_hash IS NOT NULL AND LENGTH(signature_hash) > 0),
    'with_snapshot', COUNT(*) FILTER (WHERE content_snapshot IS NOT NULL),
    'with_policy_version_ref', COUNT(*) FILTER (WHERE referenced_policy_version_id IS NOT NULL),
    'with_notification_read_evidence', COUNT(*) FILTER (WHERE (content_snapshot->>'notification_read_evidence')::boolean = true),
    'with_sections_verified', COUNT(*) FILTER (WHERE sections_verified IS NOT NULL AND jsonb_array_length(sections_verified) > 0)
  )
  INTO v_integrity_summary
  FROM public.approval_signoffs
  WHERE approval_chain_id = p_chain_id;

  RETURN jsonb_build_object(
    'chain_id', v_chain.id,
    'chain_status', v_chain.status,
    'chain_opened_at', v_chain.opened_at,
    'chain_approved_at', v_chain.approved_at,
    'chain_closed_at', v_chain.closed_at,
    'chain_notes', v_chain.notes,
    'gates_config', v_chain.gates,
    'document', jsonb_build_object(
      'id', v_doc.id, 'title', v_doc.title, 'doc_type', v_doc.doc_type, 'status', v_doc.doc_status
    ),
    'version', jsonb_build_object(
      'id', v_version.id, 'number', v_version.version_number, 'label', v_version.version_label,
      'locked_at', v_version.locked_at, 'published_at', v_version.published_at
    ),
    'submitter', jsonb_build_object(
      'id', v_submitter.id, 'name', v_submitter.name, 'email', v_submitter.email,
      'chapter', v_submitter.chapter, 'role', v_submitter.operational_role
    ),
    'timeline', COALESCE(v_timeline, '[]'::jsonb),
    'signoffs', COALESCE(v_signoffs_full, '[]'::jsonb),
    'audit_log_entries', COALESCE(v_audit_entries, '[]'::jsonb),
    'integrity_summary', v_integrity_summary,
    'generated_at', now(),
    'generated_by', jsonb_build_object('id', v_caller_id,
      'name', (SELECT name FROM public.members WHERE id = v_caller_id))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_chain_for_pdf(p_chain_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_chain record;
  v_doc record;
  v_version record;
  v_submitter record;
  v_gates_detail jsonb;
  v_policy_version record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: requires manage_member' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id,
         ac.opened_at, ac.opened_by, ac.approved_at, ac.closed_at, ac.notes
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN jsonb_build_object('error','chain_not_found'); END IF;

  SELECT gd.id, gd.title, gd.doc_type, gd.status AS doc_status, gd.description
  INTO v_doc FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.locked_at, dv.published_at, dv.notes AS version_notes
  INTO v_version FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT m.id, m.name, m.email, m.chapter, m.operational_role
  INTO v_submitter FROM public.members m WHERE m.id = v_chain.opened_by;

  -- Para cada gate, agregar signers com evidence trail completo
  SELECT jsonb_agg(
    jsonb_build_object(
      'kind', g->>'kind',
      'order', (g->>'order')::int,
      'threshold', g->>'threshold',
      'label', CASE g->>'kind'
        WHEN 'curator' THEN 'Curadoria'
        WHEN 'leader_awareness' THEN 'Ciência das lideranças'
        WHEN 'submitter_acceptance' THEN 'Aceite do GP'
        WHEN 'chapter_witness' THEN 'Testemunho de capítulo'
        WHEN 'president_go' THEN 'Presidência PMI-GO'
        WHEN 'president_others' THEN 'Presidências outros capítulos'
        WHEN 'volunteers_in_role_active' THEN 'Ratificação voluntários em função'
        WHEN 'member_ratification' THEN 'Ratificação membros'
        WHEN 'external_signer' THEN 'Signatário externo'
        ELSE g->>'kind'
      END,
      'signers', (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'signoff_id', s.id,
            'signer_id', s.signer_id,
            'signer_name', m.name,
            'signer_chapter', m.chapter,
            'signer_role', m.operational_role,
            'signoff_type', s.signoff_type,
            'signed_at', s.signed_at,
            'signature_hash_short', SUBSTRING(s.signature_hash FROM 1 FOR 12),
            'comment_body', s.comment_body,
            'sections_verified_count', COALESCE(jsonb_array_length(s.sections_verified), 0),
            'notification_read_at', s.content_snapshot->>'notification_read_at',
            'notification_read_evidence', COALESCE((s.content_snapshot->>'notification_read_evidence')::boolean, false),
            'referenced_policy_version_label', s.content_snapshot->>'referenced_policy_version_label',
            'ue_consent_recorded', COALESCE((s.content_snapshot->>'ue_consent_recorded')::boolean, false)
          ) ORDER BY s.signed_at
        ), '[]'::jsonb)
        FROM public.approval_signoffs s
        LEFT JOIN public.members m ON m.id = s.signer_id
        WHERE s.approval_chain_id = v_chain.id AND s.gate_kind = g->>'kind'
      )
    ) ORDER BY (g->>'order')::int
  )
  INTO v_gates_detail
  FROM jsonb_array_elements(v_chain.gates) g;

  -- Política vigente no momento da geração do PDF (para header)
  SELECT gd.id, dv.version_label, dv.locked_at
  INTO v_policy_version
  FROM public.governance_documents gd
  LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
  WHERE gd.doc_type = 'policy' AND gd.status IN ('active','under_review')
  ORDER BY CASE WHEN gd.status='active' THEN 0 ELSE 1 END LIMIT 1;

  RETURN jsonb_build_object(
    'chain_id', v_chain.id,
    'chain_status', v_chain.status,
    'chain_opened_at', v_chain.opened_at,
    'chain_approved_at', v_chain.approved_at,
    'chain_closed_at', v_chain.closed_at,
    'chain_notes', v_chain.notes,
    'document', jsonb_build_object(
      'id', v_doc.id,
      'title', v_doc.title,
      'doc_type', v_doc.doc_type,
      'status', v_doc.doc_status,
      'description', v_doc.description
    ),
    'version', jsonb_build_object(
      'id', v_version.id,
      'number', v_version.version_number,
      'label', v_version.version_label,
      'content_html', v_version.content_html,
      'locked_at', v_version.locked_at,
      'published_at', v_version.published_at,
      'notes', v_version.version_notes
    ),
    'submitter', jsonb_build_object(
      'id', v_submitter.id,
      'name', v_submitter.name,
      'email', v_submitter.email,
      'chapter', v_submitter.chapter,
      'role', v_submitter.operational_role
    ),
    'gates', COALESCE(v_gates_detail, '[]'::jsonb),
    'policy_at_pdf_generation', CASE
      WHEN v_policy_version.id IS NOT NULL THEN
        jsonb_build_object(
          'document_id', v_policy_version.id,
          'version_label', v_policy_version.version_label,
          'locked_at', v_policy_version.locked_at
        )
      ELSE NULL
    END,
    'generated_at', now(),
    'generated_by', jsonb_build_object('id', v_caller_id)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_chain_workflow_detail(p_chain_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_chain record;
  v_gates jsonb;
  v_signoffs jsonb;
  v_submitter jsonb;
BEGIN
  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id, ac.opened_at, ac.opened_by,
         gd.title, gd.doc_type, dv.version_label, dv.locked_at
  INTO v_chain
  FROM public.approval_chains ac
  JOIN public.governance_documents gd ON gd.id = ac.document_id
  LEFT JOIN public.document_versions dv ON dv.id = ac.version_id
  WHERE ac.id = p_chain_id;

  IF v_chain.id IS NULL THEN
    RETURN jsonb_build_object('error','chain_not_found');
  END IF;

  -- Submitter info
  SELECT jsonb_build_object('id', m.id, 'name', m.name, 'chapter', m.chapter, 'role', m.operational_role)
  INTO v_submitter
  FROM public.members m WHERE m.id = v_chain.opened_by;

  -- Per-gate aggregate: signed_count + signers + eligible_pending + days_stale
  SELECT jsonb_agg(
    jsonb_build_object(
      'kind', g->>'kind',
      'order', (g->>'order')::int,
      'threshold', g->>'threshold',
      'signed_count', (
        SELECT COUNT(*) FROM public.approval_signoffs s
        WHERE s.approval_chain_id = v_chain.id
          AND s.gate_kind = g->>'kind'
          AND s.signoff_type IN ('approval','acknowledge')
      ),
      'signers', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'name', m.name,
          'chapter', m.chapter,
          'signed_at', s.signed_at,
          'signoff_type', s.signoff_type,
          'hash_short', SUBSTRING(s.signature_hash FROM 1 FOR 12)
        ) ORDER BY s.signed_at), '[]'::jsonb)
        FROM public.approval_signoffs s
        LEFT JOIN public.members m ON m.id = s.signer_id
        WHERE s.approval_chain_id = v_chain.id AND s.gate_kind = g->>'kind'
      ),
      'eligible_pending', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'chapter', m.chapter)
          ORDER BY m.name), '[]'::jsonb)
        FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, v_chain.id, g->>'kind')
          AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
            WHERE s.approval_chain_id = v_chain.id
              AND s.gate_kind = g->>'kind'
              AND s.signer_id = m.id)
      )
    ) ORDER BY (g->>'order')::int
  )
  INTO v_gates
  FROM jsonb_array_elements(v_chain.gates) g;

  RETURN jsonb_build_object(
    'chain_id', v_chain.id,
    'chain_status', v_chain.status,
    'document_id', v_chain.document_id,
    'document_title', v_chain.title,
    'doc_type', v_chain.doc_type,
    'version_id', v_chain.version_id,
    'version_label', v_chain.version_label,
    'locked_at', v_chain.locked_at,
    'opened_at', v_chain.opened_at,
    'submitter', v_submitter,
    'gates', COALESCE(v_gates, '[]'::jsonb),
    'days_open', CASE WHEN v_chain.opened_at IS NOT NULL
      THEN EXTRACT(EPOCH FROM (now() - v_chain.opened_at))/86400
      ELSE NULL END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_comms_to_adoption_funnel(p_period_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id   uuid;
  v_period      interval := (greatest(p_period_days, 1) || ' days')::interval;
  v_since_ts    timestamptz := now() - v_period;
  v_since_date  date        := current_date - greatest(p_period_days, 1);
  v_social      jsonb;
  v_engagement  jsonb;
  v_apps        jsonb;
  v_approved    jsonb;
  v_top_content jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT (public.can_by_member(v_caller_id, 'view_internal_analytics')
       OR public.can_by_member(v_caller_id, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ── Stage 1: Social reach (latest snapshot per channel within period) ──
  WITH latest_per_channel AS (
    SELECT DISTINCT ON (channel)
      channel, audience, reach, engagement_rate, metric_date
    FROM public.comms_metrics_daily
    WHERE metric_date >= v_since_date
    ORDER BY channel, metric_date DESC
  ),
  period_reach AS (
    SELECT channel, sum(reach) AS reach_sum
    FROM public.comms_metrics_daily
    WHERE metric_date >= v_since_date
    GROUP BY channel
  )
  SELECT jsonb_build_object(
    'total_audience_latest', coalesce((SELECT sum(audience) FROM latest_per_channel), 0),
    'total_reach_period',    coalesce((SELECT sum(reach_sum) FROM period_reach), 0),
    'by_channel', coalesce(jsonb_agg(jsonb_build_object(
      'channel',           l.channel,
      'audience_latest',   l.audience,
      'reach_period',      coalesce(p.reach_sum, 0),
      'engagement_rate',   l.engagement_rate
    ) ORDER BY l.audience DESC NULLS LAST), '[]'::jsonb)
  ) INTO v_social
  FROM latest_per_channel l
  LEFT JOIN period_reach p ON p.channel = l.channel;

  -- ── Stage 2: Site engagement on content pages (logged-in proxy) ──
  WITH grouped AS (
    SELECT
      CASE
        WHEN first_page LIKE '/blog/%' THEN 'blog'
        WHEN first_page LIKE '/cpmai%' THEN 'cpmai'
        WHEN first_page LIKE '/trail%' THEN 'trail'
        WHEN first_page LIKE '/presentations%' THEN 'presentations'
        WHEN first_page LIKE '/gamification%' THEN 'gamification'
        WHEN first_page = '/' OR first_page LIKE '/en/%' OR first_page LIKE '/es/%' THEN 'home'
        ELSE 'other'
      END AS landing_group,
      member_id
    FROM public.member_activity_sessions
    WHERE session_date >= v_since_date
  ),
  agg AS (
    SELECT landing_group, count(*) AS sessions, count(DISTINCT member_id) AS members
    FROM grouped
    GROUP BY landing_group
  )
  SELECT jsonb_build_object(
    'content_sessions',      coalesce((SELECT sum(sessions) FROM agg WHERE landing_group IN ('blog','cpmai','trail','presentations','gamification')), 0),
    'content_unique_members', coalesce((SELECT sum(members)  FROM agg WHERE landing_group IN ('blog','cpmai','trail','presentations','gamification')), 0),
    'home_sessions',         coalesce((SELECT sessions FROM agg WHERE landing_group='home'), 0),
    'home_unique_members',   coalesce((SELECT members  FROM agg WHERE landing_group='home'), 0),
    'by_landing_group', coalesce(jsonb_agg(jsonb_build_object(
      'group',           a.landing_group,
      'sessions',        a.sessions,
      'unique_members',  a.members
    ) ORDER BY a.sessions DESC), '[]'::jsonb)
  ) INTO v_engagement
  FROM agg a;

  -- ── Stage 3: Applications submitted in period ──
  SELECT jsonb_build_object(
    'total',     count(*),
    'via_vep',   count(*) FILTER (WHERE referral_source = 'vep'),
    'other',     count(*) FILTER (WHERE referral_source IS DISTINCT FROM 'vep'),
    'by_role',   coalesce(jsonb_object_agg(role_applied, role_count), '{}'::jsonb)
  ) INTO v_apps
  FROM (
    SELECT
      role_applied,
      count(*) AS role_count,
      referral_source
    FROM public.selection_applications
    WHERE created_at >= v_since_ts
    GROUP BY role_applied, referral_source
  ) a
  GROUP BY ();

  IF v_apps IS NULL THEN
    v_apps := jsonb_build_object('total', 0, 'via_vep', 0, 'other', 0, 'by_role', '{}'::jsonb);
  END IF;

  -- ── Stage 4: Approved + converted in period ──
  SELECT jsonb_build_object(
    'total',         count(*),
    'approved',      count(*) FILTER (WHERE status = 'approved'),
    'converted',     count(*) FILTER (WHERE status = 'converted'),
    'approval_rate', CASE
      WHEN (SELECT count(*) FROM public.selection_applications WHERE created_at >= v_since_ts) > 0
      THEN round(count(*)::numeric * 100.0 / (SELECT count(*) FROM public.selection_applications WHERE created_at >= v_since_ts), 1)
      ELSE NULL
    END
  ) INTO v_approved
  FROM public.selection_applications
  WHERE status IN ('approved', 'converted')
    AND updated_at >= v_since_ts;

  -- ── Top content (engagement signal, NOT attribution) ──
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'channel',      m.channel,
    'media_type',   m.media_type,
    'permalink',    m.permalink,
    'caption_excerpt', left(coalesce(m.caption, ''), 80),
    'views',        m.views,
    'likes',        m.likes,
    'comments',     m.comments,
    'published_at', m.published_at
  ) ORDER BY (coalesce(m.likes,0) + coalesce(m.comments,0) + coalesce(m.views,0)) DESC), '[]'::jsonb)
  INTO v_top_content
  FROM (
    SELECT *
    FROM public.comms_media_items
    WHERE published_at >= v_since_ts
    ORDER BY (coalesce(likes,0) + coalesce(comments,0) + coalesce(views,0)) DESC
    LIMIT 6
  ) m;

  RETURN jsonb_build_object(
    'period_days',  p_period_days,
    'period_since', v_since_ts,
    'generated_at', now(),
    'caveat',       'Correlation, not attribution. Pre-login pageviews + UTM tracking infrastructure pending (Phase B backlog). PMI VEP external form does not pass UTM. Funnel reflects what is measurable today: post-login engagement + total application counts in period.',
    'stages', jsonb_build_object(
      'social_reach',    v_social,
      'site_engagement', v_engagement,
      'applications',    v_apps,
      'approved',        v_approved
    ),
    'top_content', v_top_content
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_cpmai_course_dashboard(p_course_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid; v_person_id uuid; v_initiative_id uuid; v_initiative record; v_result jsonb;
BEGIN
  SELECT m.id, m.person_id INTO v_member_id, v_person_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF p_course_id IS NOT NULL THEN
    SELECT * INTO v_initiative FROM public.initiatives WHERE metadata->>'cpmai_legacy_course_id' = p_course_id::text AND kind = 'study_group';
  ELSE
    SELECT * INTO v_initiative FROM public.initiatives WHERE kind = 'study_group' AND status != 'archived' ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_initiative IS NULL THEN RETURN jsonb_build_object('error', 'No course found'); END IF;
  v_initiative_id := v_initiative.id;
  SELECT jsonb_build_object(
    'course', jsonb_build_object('id', v_initiative.id, 'title', v_initiative.title, 'description', v_initiative.description, 'status', v_initiative.status,
      'max_capacity', (v_initiative.metadata->>'max_enrollment')::integer, 'enrollment_deadline', v_initiative.metadata->>'enrollment_deadline',
      'start_date', v_initiative.metadata->>'start_date', 'end_date', v_initiative.metadata->>'end_date',
      'min_attendance_pct', (v_initiative.metadata->>'min_attendance_pct')::numeric, 'min_mock_score', (v_initiative.metadata->>'min_mock_score')::numeric),
    'domains', COALESCE(v_initiative.metadata->'domains', '[]'::jsonb),
    'my_enrollment', (SELECT jsonb_build_object('id', e.id, 'status', e.status, 'enrolled_at', e.start_date, 'completed_at', e.end_date, 'certificate_issued_at', NULL)
      FROM public.engagements e WHERE e.initiative_id = v_initiative_id AND e.person_id = v_person_id AND e.kind IN ('study_group_participant', 'study_group_owner') LIMIT 1),
    'my_progress', COALESCE((SELECT jsonb_agg(jsonb_build_object('module_id', p.payload->>'module_id', 'status', p.payload->>'status', 'completed_at', p.payload->>'completed_at'))
      FROM public.initiative_member_progress p WHERE p.initiative_id = v_initiative_id AND p.person_id = v_person_id AND p.progress_type = 'module_completion'), '[]'::jsonb),
    'my_mock_scores', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'score_pct', (p.payload->>'score_pct')::numeric, 'total_questions', (p.payload->>'total_questions')::integer,
      'correct_answers', (p.payload->>'correct_answers')::integer, 'mock_source', p.payload->>'mock_source', 'taken_at', p.recorded_at) ORDER BY p.recorded_at DESC)
      FROM public.initiative_member_progress p WHERE p.initiative_id = v_initiative_id AND p.person_id = v_person_id AND p.progress_type = 'mock_score'), '[]'::jsonb),
    'upcoming_sessions', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', ev.id, 'title', ev.title, 'session_type', ev.type, 'scheduled_at', ev.date,
      'duration_minutes', ev.duration_minutes, 'external_url', ev.meeting_link, 'recording_url', NULL, 'domain_id', NULL) ORDER BY ev.date)
      FROM public.events ev WHERE ev.initiative_id = v_initiative_id AND ev.date >= now() - interval '1 day'), '[]'::jsonb),
    'enrollment_count', (SELECT count(*) FROM public.engagements WHERE initiative_id = v_initiative_id AND kind IN ('study_group_participant', 'study_group_owner') AND status IN ('active', 'offboarded'))
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_digest_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_member_pending integer;
  v_jobs jsonb;
  v_health text;
  v_max_days_since integer;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  -- Pending digest_weekly notifications not yet delivered
  SELECT count(*)
  INTO v_member_pending
  FROM public.notifications
  WHERE delivery_mode = 'digest_weekly'
    AND digest_delivered_at IS NULL;

  SELECT jsonb_object_agg(jobname, snapshot)
  INTO v_jobs
  FROM (
    SELECT
      j.jobname,
      jsonb_build_object(
        'jobid', j.jobid,
        'schedule', j.schedule,
        'active', j.active,
        'last_run_at', (SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid),
        'last_status', (SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1),
        'days_since_last_run', (
          SELECT extract(epoch FROM (now() - max(start_time))) / 86400
          FROM cron.job_run_details d WHERE d.jobid = j.jobid
        ),
        'failed_runs_last_30d', (
          SELECT count(*) FROM cron.job_run_details d
          WHERE d.jobid = j.jobid AND d.status = 'failed' AND d.start_time >= now() - interval '30 days'
        )
      ) AS snapshot
    FROM cron.job j
    WHERE j.jobname IN ('send-weekly-member-digest', 'send-weekly-leader-digest', 'weekly-card-digest-saturday')
  ) sub;

  -- Worst days-since across the 3 jobs (digest is weekly Saturday — expect <=8d)
  SELECT max(coalesce(days, 999))::integer INTO v_max_days_since
  FROM (
    SELECT extract(epoch FROM (now() - max(d.start_time))) / 86400 AS days
    FROM cron.job j
    LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
    WHERE j.jobname IN ('send-weekly-member-digest', 'send-weekly-leader-digest', 'weekly-card-digest-saturday')
    GROUP BY j.jobid
  ) t;

  -- Health: green if all crons fired in last 8 days (weekly + 1 day grace).
  -- Yellow: never ran (<999) or member_pending > 100 (backlog signaling ingestion bug).
  -- Red: any cron silent >8 days AND member_pending > 0.
  v_health := CASE
    WHEN v_max_days_since <= 8 AND v_member_pending < 100 THEN 'green'
    WHEN v_max_days_since = 999 THEN 'yellow'
    WHEN v_member_pending > 0 AND v_max_days_since > 8 THEN 'red'
    WHEN v_member_pending >= 100 THEN 'yellow'
    ELSE 'yellow'
  END;

  RETURN jsonb_build_object(
    'member_digest_pending', v_member_pending,
    'cron_jobs', coalesce(v_jobs, '{}'::jsonb),
    'max_days_since_any_job_ran', v_max_days_since,
    'health_signal', v_health,
    'note', 'Weekly Saturday crons. days_since=999 means never ran (newly registered). pending>100 may indicate digest_weekly mode notifications accumulating without consumer.',
    'fetched_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dual_track_merged_payload(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id  uuid;
  v_app        record;
  v_sibling    record;
  v_researcher record;
  v_leader     record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Application not found');
  END IF;

  -- Non-pair case
  IF v_app.linked_application_id IS NULL OR v_app.promotion_path IS DISTINCT FROM 'dual_track' THEN
    RETURN jsonb_build_object(
      'is_dual_track', false,
      'pair_role_in_view', v_app.role_applied,
      'primary_app', to_jsonb(v_app)
    );
  END IF;

  SELECT * INTO v_sibling FROM public.selection_applications WHERE id = v_app.linked_application_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'is_dual_track', false,
      'error', 'Sibling application missing despite linked_application_id',
      'primary_app', to_jsonb(v_app)
    );
  END IF;

  -- Identify researcher/leader
  IF v_app.role_applied = 'researcher' THEN
    v_researcher := v_app;
    v_leader     := v_sibling;
  ELSE
    v_researcher := v_sibling;
    v_leader     := v_app;
  END IF;

  RETURN jsonb_build_object(
    'is_dual_track',     true,
    'pair_role_in_view', v_app.role_applied,
    'researcher_app',    to_jsonb(v_researcher),
    'leader_app',        to_jsonb(v_leader),
    'merged_essays', jsonb_build_object(
      'motivation_letter',     COALESCE(v_leader.motivation_letter,     v_researcher.motivation_letter),
      'non_pmi_experience',    COALESCE(v_leader.non_pmi_experience,    v_researcher.non_pmi_experience),
      'areas_of_interest',     COALESCE(v_researcher.areas_of_interest, v_leader.areas_of_interest),
      'proposed_theme',        COALESCE(v_leader.proposed_theme,        v_researcher.proposed_theme),
      'leadership_experience', COALESCE(v_leader.leadership_experience, v_researcher.leadership_experience),
      'academic_background',   COALESCE(v_leader.academic_background,   v_researcher.academic_background)
    ),
    'merged_ai_analysis', jsonb_build_object(
      'ai_triage_score',       COALESCE(v_leader.ai_triage_score,       v_researcher.ai_triage_score),
      'ai_triage_reasoning',   COALESCE(v_leader.ai_triage_reasoning,   v_researcher.ai_triage_reasoning),
      'ai_triage_confidence',  COALESCE(v_leader.ai_triage_confidence,  v_researcher.ai_triage_confidence),
      'ai_triage_at',          GREATEST(v_leader.ai_triage_at,          v_researcher.ai_triage_at),
      'ai_triage_model',       COALESCE(v_leader.ai_triage_model,       v_researcher.ai_triage_model),
      'ai_pm_focus_tags', (
        SELECT to_jsonb(array_agg(DISTINCT t))
        FROM (
          SELECT jsonb_array_elements_text(COALESCE(v_leader.ai_pm_focus_tags, '[]'::jsonb)) AS t
          UNION
          SELECT jsonb_array_elements_text(COALESCE(v_researcher.ai_pm_focus_tags, '[]'::jsonb))
        ) u
      ),
      'has_researcher_analysis', v_researcher.ai_triage_at IS NOT NULL,
      'has_leader_analysis',     v_leader.ai_triage_at IS NOT NULL
    ),
    'scores_summary', jsonb_build_object(
      'researcher_objective', v_researcher.objective_score_avg,
      'researcher_interview', v_researcher.interview_score,
      'researcher_final',     v_researcher.final_score,
      'leader_objective',     v_leader.objective_score_avg,
      'leader_interview',     v_leader.interview_score,
      'leader_final',         v_leader.final_score
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_event_champion_suggestions(p_event_id uuid)
 RETURNS TABLE(member_id uuid, member_name text, designation_summary text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event_org uuid;
  v_suggestions uuid[];
BEGIN
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event')
     AND NOT public.can_by_member(v_caller_id, 'award_champion') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event or award_champion';
  END IF;

  SELECT e.suggested_champion_ids, e.organization_id INTO v_suggestions, v_event_org
  FROM public.events e WHERE e.id = p_event_id;

  IF v_event_org IS NULL THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;
  IF v_event_org != v_caller_org THEN
    RAISE EXCEPTION 'event_not_in_caller_org';
  END IF;

  IF v_suggestions IS NULL OR cardinality(v_suggestions) = 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    m.id AS member_id,
    m.name AS member_name,
    CASE WHEN cardinality(m.designations) > 0
      THEN array_to_string(m.designations, ', ')
      ELSE COALESCE(m.operational_role, '—')
    END AS designation_summary
  FROM public.members m
  WHERE m.id = ANY(v_suggestions)
    AND m.organization_id = v_caller_org
  ORDER BY m.name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_executive_kpis()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_total_active INT; v_total_verified INT; v_multi_cycle INT;
  v_retention_pct NUMERIC; v_total_artifacts INT; v_total_tribes INT;
  v_avg_per_tribe NUMERIC; v_chapters INT;
BEGIN
  SELECT COUNT(*) INTO v_total_active FROM members WHERE is_active = true AND current_cycle_active = true;
  SELECT COUNT(*) INTO v_total_verified FROM members WHERE pmi_id_verified = true AND COALESCE(current_cycle_active, is_active, false) = true;
  SELECT COUNT(*) INTO v_multi_cycle FROM members WHERE is_active = true AND current_cycle_active = true AND array_length(cycles, 1) > 1;
  IF v_total_active > 0 THEN v_retention_pct := ROUND((v_multi_cycle::NUMERIC / v_total_active) * 100, 1); ELSE v_retention_pct := 0; END IF;

  -- ADR-0012 archival: publication_submissions (ex-artifacts)
  SELECT COUNT(*) INTO v_total_artifacts FROM publication_submissions WHERE status = 'published'::submission_status;

  SELECT COUNT(*) INTO v_total_tribes FROM tribes WHERE is_active = true;
  IF v_total_tribes > 0 THEN
    SELECT ROUND(AVG(cnt), 1) INTO v_avg_per_tribe FROM (
      SELECT COUNT(*) AS cnt FROM members
      WHERE tribe_id IS NOT NULL AND COALESCE(current_cycle_active, is_active, false) = true
      GROUP BY tribe_id) sub;
  ELSE v_avg_per_tribe := 0; END IF;
  SELECT COUNT(DISTINCT chapter) INTO v_chapters FROM members
  WHERE chapter IS NOT NULL AND COALESCE(current_cycle_active, is_active, false) = true;

  RETURN json_build_object(
    'total_active', v_total_active, 'pmi_verified', v_total_verified,
    'multi_cycle', v_multi_cycle, 'retention_pct', v_retention_pct,
    'published_artifacts', v_total_artifacts, 'active_tribes', v_total_tribes,
    'avg_per_tribe', v_avg_per_tribe, 'chapters', v_chapters
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_idea_pipeline(p_tribe_id integer DEFAULT NULL::integer, p_stage_filter text DEFAULT NULL::text, p_series_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_committee boolean;
  v_result jsonb;
  v_summary jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  v_is_committee := public.can_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      pi.id,
      pi.title,
      pi.summary,
      pi.stage,
      pi.review_sub_stage,
      pi.tribe_id,
      pi.initiative_id,
      pi.proposer_member_id,
      mp.name AS proposer_name,
      pi.author_ids,
      pi.proposed_channels,
      pi.target_languages,
      pi.source_type,
      pi.source_id,
      pi.series_id,
      COALESCE(ps.title_i18n->>'pt-BR', ps.slug) AS series_title,
      ps.slug AS series_slug,
      pi.series_position,
      pi.metadata,
      pi.rejection_reason,
      pi.archived_reason,
      pi.approved_by,
      ma.name AS approved_by_name,
      pi.approved_at,
      pi.published_at,
      pi.created_at,
      pi.updated_at
    FROM public.publication_ideas pi
    LEFT JOIN public.members mp ON mp.id = pi.proposer_member_id
    LEFT JOIN public.members ma ON ma.id = pi.approved_by
    LEFT JOIN public.publication_series ps ON ps.id = pi.series_id
    WHERE (p_stage_filter IS NULL OR pi.stage = p_stage_filter)
      AND (p_tribe_id IS NULL OR pi.tribe_id = p_tribe_id)
      AND (p_series_id IS NULL OR pi.series_id = p_series_id)
      AND (v_is_committee OR pi.proposer_member_id = v_caller_id)
    ORDER BY pi.created_at DESC
  ) r;

  -- Summary by stage (visible scope only)
  SELECT jsonb_object_agg(stage, cnt) INTO v_summary
  FROM (
    SELECT stage, COUNT(*) AS cnt
    FROM public.publication_ideas pi
    WHERE (v_is_committee OR pi.proposer_member_id = v_caller_id)
      AND (p_tribe_id IS NULL OR pi.tribe_id = p_tribe_id)
      AND (p_series_id IS NULL OR pi.series_id = p_series_id)
    GROUP BY stage
  ) s;

  RETURN jsonb_build_object(
    'ideas', v_result,
    'count', jsonb_array_length(v_result),
    'is_committee', v_is_committee,
    'by_stage', COALESCE(v_summary, '{}'::jsonb)
  );
END; $function$;

CREATE OR REPLACE FUNCTION public.get_initiative_board_summary(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_board_id uuid;
  v_counts jsonb;
  v_recent jsonb;
  v_total integer;
BEGIN
  SELECT pb.id INTO v_board_id
  FROM project_boards pb
  WHERE pb.initiative_id = p_initiative_id AND pb.is_active = true
  LIMIT 1;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No board linked');
  END IF;

  -- Count by status
  SELECT coalesce(jsonb_object_agg(s.status, s.cnt), '{}'::jsonb), coalesce(sum(s.cnt), 0)
  INTO v_counts, v_total
  FROM (
    SELECT status, count(*)::int as cnt
    FROM board_items
    WHERE board_id = v_board_id AND status != 'archived'
    GROUP BY status
  ) s;

  -- Recent 10 items
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'title', r.title, 'status', r.status,
    'due_date', r.due_date, 'assignee_id', r.assignee_id
  )), '[]'::jsonb)
  INTO v_recent
  FROM (
    SELECT id, title, status, due_date, assignee_id
    FROM board_items
    WHERE board_id = v_board_id AND status != 'archived'
    ORDER BY created_at DESC LIMIT 10
  ) r;

  RETURN jsonb_build_object(
    'board_id', v_board_id,
    'total', v_total,
    'by_status', v_counts,
    'recent', v_recent
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_manual_diff()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_current_version text; v_implemented_crs jsonb; v_pending_crs jsonb;
BEGIN
  SELECT version INTO v_current_version FROM governance_documents
  WHERE doc_type = 'manual' AND status = 'active' ORDER BY created_at DESC LIMIT 1;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('cr_number', cr_number, 'title', title, 'category', category,
    'manual_version_to', manual_version_to, 'implemented_at', implemented_at) ORDER BY cr_number), '[]'::jsonb)
  INTO v_implemented_crs FROM change_requests WHERE status = 'implemented';

  SELECT COALESCE(jsonb_agg(jsonb_build_object('cr_number', cr_number, 'title', title, 'category', category,
    'status', status, 'priority', priority, 'approved_at', approved_at) ORDER BY cr_number), '[]'::jsonb)
  INTO v_pending_crs FROM change_requests WHERE status IN ('submitted', 'proposed', 'under_review', 'approved', 'open', 'pending_review', 'in_review');

  RETURN jsonb_build_object(
    'current_version', COALESCE(v_current_version, 'R2'),
    'implemented_crs', v_implemented_crs,
    'pending_crs', v_pending_crs,
    'total_implemented', (SELECT count(*) FROM change_requests WHERE status = 'implemented'),
    'total_pending', (SELECT count(*) FROM change_requests WHERE status IN ('submitted','proposed','under_review','approved','open','pending_review','in_review')),
    'total_approved_ready', (SELECT count(*) FROM change_requests WHERE status = 'approved')
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_manual_sections(p_version text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id',id,'section_number',section_number,
    'title_pt',title_pt,'title_en',title_en,'title_es',title_es,
    'content_pt',content_pt,'content_en',content_en,'content_es',content_es,
    'manual_version',manual_version,
    'parent_section_id',parent_section_id,'sort_order',sort_order,
    'page_start',page_start,'page_end',page_end,'approved_at',approved_at
  ) ORDER BY sort_order) INTO v_result
  FROM manual_sections WHERE is_current=true AND (p_version IS NULL OR manual_version=p_version);
  RETURN COALESCE(v_result,'[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_member_offboarding_record(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_can_view boolean;
  v_record   public.member_offboarding_records%ROWTYPE;
  v_member   record;
  v_category record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  SELECT * INTO v_record FROM public.member_offboarding_records WHERE member_id = p_member_id;
  IF v_record.id IS NULL THEN
    RETURN jsonb_build_object('found', false, 'member_id', p_member_id);
  END IF;

  v_can_view :=
    EXISTS (SELECT 1 FROM public.members WHERE id = v_caller_id AND is_superadmin = true)
    OR (v_record.member_id = v_caller_id)
    OR (v_record.offboarded_by = v_caller_id)
    OR public.can_by_member(v_caller_id, 'manage_member');

  IF NOT v_can_view THEN
    RAISE EXCEPTION 'Unauthorized: cannot view this offboarding record';
  END IF;

  SELECT id, name, chapter, member_status, operational_role
  INTO v_member FROM public.members WHERE id = p_member_id;

  IF v_record.reason_category_code IS NOT NULL THEN
    SELECT code, label_pt, label_en, is_volunteer_fault, preserves_return_eligibility
    INTO v_category FROM public.offboard_reason_categories
    WHERE code = v_record.reason_category_code;
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'record', jsonb_build_object(
      'id', v_record.id,
      'member_id', v_record.member_id,
      'offboarded_at', v_record.offboarded_at,
      'offboarded_by', v_record.offboarded_by,
      'reason_category_code', v_record.reason_category_code,
      'reason_category_label_pt', v_category.label_pt,
      'reason_detail', v_record.reason_detail,
      'exit_interview_full_text', v_record.exit_interview_full_text,
      'exit_interview_source', v_record.exit_interview_source,
      'return_interest', v_record.return_interest,
      'return_window_suggestion', v_record.return_window_suggestion,
      'tribe_id_at_offboard', v_record.tribe_id_at_offboard,
      'chapter_at_offboard', v_record.chapter_at_offboard,
      'cycle_code_at_offboard', v_record.cycle_code_at_offboard,
      'lessons_learned', v_record.lessons_learned,
      'recommendation_for_future', v_record.recommendation_for_future,
      'referred_by_tribe_leader', v_record.referred_by_tribe_leader,
      'attachment_urls', to_jsonb(v_record.attachment_urls),
      'created_at', v_record.created_at,
      'updated_at', v_record.updated_at
    ),
    'member', jsonb_build_object(
      'id', v_member.id,
      'name', v_member.name,
      'chapter', v_member.chapter,
      'member_status', v_member.member_status,
      'operational_role', v_member.operational_role
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_application_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_apps jsonb;
BEGIN
  SELECT id, email, name INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb) INTO v_apps
  FROM (
    SELECT
      a.id AS application_id,
      a.cycle_id,
      sc.cycle_code,
      sc.title AS cycle_title,
      sc.phase,
      sc.status AS cycle_status,
      sc.close_date,
      a.role_applied,
      a.promotion_path,
      a.status,
      a.cycle_decision_date,
      a.created_at,
      a.updated_at,
      -- Surface candidato-editable fields so they know what's on file
      a.linkedin_url,
      a.resume_url,
      a.credly_url,
      a.motivation_letter IS NOT NULL AS has_motivation,
      a.consent_ai_analysis_at IS NOT NULL AS ai_consent_granted,
      -- During evaluating phase: show submitted count without identities
      CASE
        WHEN sc.phase = 'evaluating' THEN (
          SELECT COUNT(*)::int FROM public.selection_evaluations e
          WHERE e.application_id = a.id AND e.submitted_at IS NOT NULL
        )
        ELSE NULL
      END AS submitted_evaluations_count,
      -- Status final flag
      a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled']) AS is_final
    FROM public.selection_applications a
    JOIN public.selection_cycles sc ON sc.id = a.cycle_id
    WHERE lower(trim(a.email)) = lower(trim(v_caller.email))
  ) r;

  RETURN jsonb_build_object(
    'member_id', v_caller.id,
    'email', v_caller.email,
    'applications', v_apps,
    'count', jsonb_array_length(v_apps)
  );
END; $function$;

CREATE OR REPLACE FUNCTION public.get_my_committee_assignments()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_committee_cycles uuid[];
  v_assignments jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  -- Cycles where caller is in committee
  SELECT array_agg(DISTINCT cycle_id) INTO v_committee_cycles
  FROM public.selection_committee
  WHERE member_id = v_caller_id;

  IF v_committee_cycles IS NULL OR array_length(v_committee_cycles, 1) IS NULL THEN
    RETURN jsonb_build_object(
      'is_committee_member', false,
      'assignments', '[]'::jsonb,
      'count', 0
    );
  END IF;

  -- Applications in those cycles + caller's evaluation status per app
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb) INTO v_assignments
  FROM (
    SELECT
      a.id AS application_id,
      a.cycle_id,
      sc.cycle_code,
      sc.phase AS cycle_phase,
      a.applicant_name,
      a.role_applied,
      a.promotion_path,
      a.status,
      a.created_at,
      -- Caller's own evaluation status on this app
      EXISTS (
        SELECT 1 FROM public.selection_evaluations e
        WHERE e.application_id = a.id
          AND e.evaluator_id = v_caller_id
          AND e.submitted_at IS NOT NULL
      ) AS i_have_submitted,
      (
        SELECT count(*)::int FROM public.selection_evaluations e
        WHERE e.application_id = a.id
          AND e.evaluator_id = v_caller_id
      ) AS my_evaluation_rows,
      sc.min_evaluators
    FROM public.selection_applications a
    JOIN public.selection_cycles sc ON sc.id = a.cycle_id
    WHERE a.cycle_id = ANY(v_committee_cycles)
      AND a.status NOT IN ('withdrawn','cancelled')
  ) r;

  RETURN jsonb_build_object(
    'is_committee_member', true,
    'cycle_ids', to_jsonb(v_committee_cycles),
    'assignments', v_assignments,
    'count', jsonb_array_length(v_assignments)
  );
END; $function$;

CREATE OR REPLACE FUNCTION public.get_my_evaluation_feedback()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_evals jsonb;
  v_reveal_phases text[] := ARRAY['evaluations_closed','interviews','interviews_closed','ranking','announcement','onboarding']::text[];
BEGIN
  SELECT id, email, name INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  -- Most recent application
  SELECT a.id, a.objective_score_avg, a.interview_score, a.research_score, a.leader_score,
         a.feedback, a.status, sc.phase, sc.cycle_code
  INTO v_app
  FROM public.selection_applications a
  JOIN public.selection_cycles sc ON sc.id = a.cycle_id
  WHERE lower(trim(a.email)) = lower(trim(v_caller.email))
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error','no_application');
  END IF;

  -- Gate: only post-reveal phase OR final status
  IF NOT (v_app.phase = ANY(v_reveal_phases))
     AND v_app.status NOT IN ('approved','converted','rejected','objective_cutoff') THEN
    RETURN jsonb_build_object(
      'feedback_available', false,
      'reason', 'phase_not_revealed',
      'current_phase', v_app.phase,
      'note', 'Feedback será disponibilizado quando o ciclo entrar em fase de revelação (evaluations_closed em diante).'
    );
  END IF;

  -- Aggregate evaluations (own application only)
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.evaluation_type), '[]'::jsonb) INTO v_evals
  FROM (
    SELECT e.evaluation_type, e.weighted_subtotal, e.scores, e.notes, e.submitted_at
    FROM public.selection_evaluations e
    WHERE e.application_id = v_app.id AND e.submitted_at IS NOT NULL
  ) r;

  RETURN jsonb_build_object(
    'feedback_available', true,
    'application_id', v_app.id,
    'cycle_code', v_app.cycle_code,
    'phase', v_app.phase,
    'status', v_app.status,
    'objective_score_avg', v_app.objective_score_avg,
    'interview_score', v_app.interview_score,
    'research_score', v_app.research_score,
    'leader_score', v_app.leader_score,
    'narrative_feedback', v_app.feedback,
    'evaluations', v_evals
  );
END; $function$;

CREATE OR REPLACE FUNCTION public.get_my_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  -- Auto-generate progress rows
  INSERT INTO onboarding_progress (member_id, step_key, status)
  SELECT v_member_id, s.id, 'pending'
  FROM onboarding_steps s
  WHERE NOT EXISTS (SELECT 1 FROM onboarding_progress op WHERE op.member_id = v_member_id AND op.step_key = s.id);

  SELECT jsonb_build_object(
    'member_id', v_member_id,
    'total_steps', (SELECT count(*) FROM onboarding_steps WHERE is_required),
    'completed_steps', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_member_id AND status = 'completed' AND step_key IN (SELECT id FROM onboarding_steps)),
    'all_complete', (NOT EXISTS (
      SELECT 1 FROM onboarding_steps s
      JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      WHERE s.is_required AND op.status != 'completed'
    )),
    'steps', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.step_order) FROM (
      SELECT s.id AS step_id, s.step_order, s.label_pt, s.label_en, s.label_es,
        s.description_pt, s.description_en, s.description_es, s.icon, s.is_required,
        COALESCE(op.status, 'pending') AS status, op.completed_at, op.metadata
      FROM onboarding_steps s
      LEFT JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      ORDER BY s.step_order
    ) t)
  ) INTO v_result;
  RETURN v_result;
END; $function$;

CREATE OR REPLACE FUNCTION public.get_my_pending_evaluations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_cycle record;
  v_pending jsonb;
  v_completed_count int;
  v_total_count int;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Caller must be selection_committee member of the active evaluating cycle (or admin)
  IF NOT EXISTS (
    SELECT 1 FROM public.selection_committee sc
    JOIN public.selection_cycles c ON c.id = sc.cycle_id
    WHERE sc.member_id = v_caller_member_id AND c.phase = 'evaluating'
  ) AND NOT public.can_by_member(v_caller_member_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: caller is not on active evaluating committee'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Find current evaluating cycle
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE phase = 'evaluating' LIMIT 1;
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('cycle', null, 'pending', '[]'::jsonb, 'completed_count', 0, 'total_count', 0);
  END IF;

  -- Pending = applications in cycle where caller hasn't submitted yet
  SELECT jsonb_agg(jsonb_build_object(
    'application_id', sa.id,
    'applicant_name', sa.applicant_name,
    'role_applied', sa.role_applied,
    'promotion_path', sa.promotion_path,
    'created_at', sa.created_at,
    'has_my_evaluation_in_progress',
      EXISTS (SELECT 1 FROM public.selection_evaluations se
              WHERE se.application_id = sa.id AND se.evaluator_id = v_caller_member_id
                AND se.submitted_at IS NULL)
  ) ORDER BY sa.created_at)
  INTO v_pending
  FROM public.selection_applications sa
  WHERE sa.cycle_id = v_cycle.id
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations se
      WHERE se.application_id = sa.id
        AND se.evaluator_id = v_caller_member_id
        AND se.submitted_at IS NOT NULL
    );

  -- Counts for fila health
  SELECT count(*)
  INTO v_completed_count
  FROM public.selection_applications sa
  JOIN public.selection_evaluations se ON se.application_id = sa.id
  WHERE sa.cycle_id = v_cycle.id
    AND se.evaluator_id = v_caller_member_id
    AND se.submitted_at IS NOT NULL;

  SELECT count(*) INTO v_total_count FROM public.selection_applications WHERE cycle_id = v_cycle.id;

  RETURN jsonb_build_object(
    'cycle_code', v_cycle.cycle_code,
    'cycle_phase', v_cycle.phase,
    'pending', COALESCE(v_pending, '[]'::jsonb),
    'pending_count', COALESCE(jsonb_array_length(v_pending), 0),
    'completed_count', v_completed_count,
    'total_count', v_total_count,
    'progress_pct', CASE WHEN v_total_count > 0 THEN round((v_completed_count::numeric / v_total_count) * 100, 1) ELSE 0 END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_signatures(p_include_superseded boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_gates jsonb;
  v_ratifications jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'signoff_id', s.id,
    'chain_id', s.approval_chain_id,
    'gate_kind', s.gate_kind,
    'signoff_type', s.signoff_type,
    'signed_at', s.signed_at,
    'signature_hash', s.signature_hash,
    'sections_verified', s.sections_verified,
    'comment_body', s.comment_body,
    'document_title', d.title,
    'document_type', d.doc_type,
    'chain_status', ac.status
  ) ORDER BY s.signed_at DESC), '[]'::jsonb)
  INTO v_gates
  FROM public.approval_signoffs s
  LEFT JOIN public.approval_chains ac ON ac.id = s.approval_chain_id
  LEFT JOIN public.governance_documents d ON d.id = ac.document_id
  WHERE s.signer_id = v_caller_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'signature_id', ms.id,
    'document_id', ms.document_id,
    'document_title', d.title,
    'document_type', d.doc_type,
    'version_id', ms.signed_version_id,
    'signed_at', ms.signed_at,
    'is_current', ms.is_current,
    'superseded_at', ms.superseded_at,
    'superseded_by_version_id', ms.superseded_by_version_id,
    'certificate_id', ms.certificate_id
  ) ORDER BY ms.signed_at DESC), '[]'::jsonb)
  INTO v_ratifications
  FROM public.member_document_signatures ms
  LEFT JOIN public.governance_documents d ON d.id = ms.document_id
  WHERE ms.member_id = v_caller_id
    AND (p_include_superseded OR ms.is_current = true);

  RETURN jsonb_build_object(
    'gate_signoffs', v_gates,
    'document_ratifications', v_ratifications,
    'gate_count', jsonb_array_length(v_gates),
    'ratification_count', jsonb_array_length(v_ratifications)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_offboarding_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_total int;
  v_with_interview int;
  v_return_interest int;
  v_by_category jsonb;
  v_by_chapter jsonb;
  v_by_cycle jsonb;
  v_recent jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member action';
  END IF;

  SELECT
    count(*),
    count(*) FILTER (WHERE exit_interview_full_text IS NOT NULL),
    count(*) FILTER (WHERE return_interest = true)
  INTO v_total, v_with_interview, v_return_interest
  FROM public.member_offboarding_records;

  SELECT jsonb_agg(jsonb_build_object(
    'reason_category_code', sub.reason_category_code,
    'reason_category_label_pt', sub.label_pt,
    'count', sub.cnt
  ) ORDER BY sub.cnt DESC, sub.reason_category_code)
  INTO v_by_category
  FROM (
    SELECT r.reason_category_code, c.label_pt, count(*)::int AS cnt
    FROM public.member_offboarding_records r
    LEFT JOIN public.offboard_reason_categories c ON c.code = r.reason_category_code
    GROUP BY r.reason_category_code, c.label_pt
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('chapter', sub.chapter, 'count', sub.cnt) ORDER BY sub.cnt DESC, sub.chapter)
  INTO v_by_chapter
  FROM (
    SELECT chapter_at_offboard AS chapter, count(*)::int AS cnt
    FROM public.member_offboarding_records
    WHERE chapter_at_offboard IS NOT NULL
    GROUP BY chapter_at_offboard
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('cycle_code', sub.cycle, 'count', sub.cnt) ORDER BY sub.cycle DESC NULLS LAST)
  INTO v_by_cycle
  FROM (
    SELECT cycle_code_at_offboard AS cycle, count(*)::int AS cnt
    FROM public.member_offboarding_records
    GROUP BY cycle_code_at_offboard
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'member_id', r.member_id,
    'member_name', m.name,
    'chapter', m.chapter,
    'offboarded_at', r.offboarded_at,
    'reason_category_code', r.reason_category_code,
    'has_full_interview', r.exit_interview_full_text IS NOT NULL
  ) ORDER BY r.offboarded_at DESC)
  INTO v_recent
  FROM public.member_offboarding_records r
  JOIN public.members m ON m.id = r.member_id
  WHERE r.offboarded_at >= now() - interval '90 days';

  RETURN jsonb_build_object(
    'total_records', v_total,
    'with_full_interview', v_with_interview,
    'with_return_interest', v_return_interest,
    'interview_completion_pct', ROUND(100.0 * v_with_interview / NULLIF(v_total, 0), 1),
    'by_reason_category', COALESCE(v_by_category, '[]'::jsonb),
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'by_cycle', COALESCE(v_by_cycle, '[]'::jsonb),
    'recent_90d', COALESCE(v_recent, '[]'::jsonb),
    'generated_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_pending_ratifications()
 RETURNS TABLE(chain_id uuid, document_id uuid, document_title text, doc_type text, version_id uuid, version_label text, version_locked_at timestamp with time zone, gates jsonb, opened_at timestamp with time zone, status text, eligible_gates text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT ac.id, gd.id, gd.title, gd.doc_type, dv.id, dv.version_label, dv.locked_at,
    ac.gates, ac.opened_at, ac.status,
    (SELECT ARRAY_AGG(g->>'kind' ORDER BY (g->>'order')::int)
     FROM jsonb_array_elements(ac.gates) g
     WHERE public._can_sign_gate(v_member_id, ac.id, g->>'kind')
       AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
         WHERE s.approval_chain_id = ac.id AND s.gate_kind = g->>'kind' AND s.signer_id = v_member_id))
  FROM public.approval_chains ac
  JOIN public.governance_documents gd ON gd.id = ac.document_id
  JOIN public.document_versions dv ON dv.id = ac.version_id
  WHERE ac.status IN ('review','approved')
  ORDER BY ac.opened_at DESC NULLS LAST, ac.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_person(p_person_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_target_person_id uuid;
  v_can_pii boolean;
  v_person record;
BEGIN
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_person_id IS NULL THEN
    SELECT p.id INTO v_target_person_id FROM public.persons p WHERE p.legacy_member_id = v_caller_member_id;
  ELSE
    v_target_person_id := p_person_id;
  END IF;

  IF v_target_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  IF v_target_person_id = (SELECT id FROM public.persons WHERE legacy_member_id = v_caller_member_id) THEN
    v_can_pii := true;
  ELSE
    SELECT public.can(auth.uid(), 'view_pii', NULL, NULL) INTO v_can_pii;
  END IF;

  SELECT * INTO v_person FROM public.persons WHERE id = v_target_person_id;
  IF v_person IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  RETURN jsonb_build_object(
    'id', v_person.id,
    'name', v_person.name,
    'photo_url', v_person.photo_url,
    'linkedin_url', v_person.linkedin_url,
    'city', v_person.city,
    'state', v_person.state,
    'country', v_person.country,
    'credly_url', v_person.credly_url,
    'credly_badges', COALESCE(v_person.credly_badges, '[]'::jsonb),
    'consent_status', v_person.consent_status,
    'email', CASE WHEN v_can_pii THEN v_person.email ELSE NULL END,
    'phone', CASE WHEN v_can_pii AND v_person.share_whatsapp THEN v_person.phone ELSE NULL END,
    'address', CASE WHEN v_can_pii AND v_person.share_address THEN v_person.address ELSE NULL END,
    'birth_date', CASE WHEN v_can_pii AND v_person.share_birth_date THEN v_person.birth_date::text ELSE NULL END,
    'pmi_id', CASE WHEN v_can_pii THEN v_person.pmi_id ELSE NULL END,
    'legacy_member_id', v_person.legacy_member_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_pert_cutoff_summary(p_cycle_id uuid, p_score_column text DEFAULT 'objective_score_avg'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_summary record;
  v_cycle record;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL OR NOT public.can_by_member(v_member_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'access_denied');
  END IF;

  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score') THEN
    RETURN jsonb_build_object('error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg','final_score','research_score'));
  END IF;

  SELECT id, cycle_code INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF v_cycle.id IS NULL THEN RETURN jsonb_build_object('error', 'cycle_not_found'); END IF;

  -- p131 #22 fix: distribution check usa MESMA coluna que o target foi calculado
  SELECT
    COUNT(*) AS apps_total,
    COUNT(*) FILTER (WHERE pert_target_score IS NOT NULL) AS apps_with_pert,
    MAX(pert_calc_at) AS last_calc_at,
    MAX(pert_cohort_n) AS cohort_n,
    MAX(pert_target_score) AS target_score,
    MAX(pert_band_lower) AS band_lower,
    MAX(pert_band_upper) AS band_upper,
    MAX(pert_cutoff_method) AS method,
    COUNT(*) FILTER (
      WHERE CASE p_score_column
              WHEN 'objective_score_avg' THEN objective_score_avg IS NOT NULL AND objective_score_avg < pert_band_lower
              WHEN 'final_score' THEN final_score IS NOT NULL AND final_score < pert_band_lower
              WHEN 'research_score' THEN research_score IS NOT NULL AND research_score < pert_band_lower
            END
    ) AS below_band,
    COUNT(*) FILTER (
      WHERE CASE p_score_column
              WHEN 'objective_score_avg' THEN objective_score_avg IS NOT NULL AND objective_score_avg > pert_band_upper
              WHEN 'final_score' THEN final_score IS NOT NULL AND final_score > pert_band_upper
              WHEN 'research_score' THEN research_score IS NOT NULL AND research_score > pert_band_upper
            END
    ) AS above_band,
    COUNT(*) FILTER (
      WHERE CASE p_score_column
              WHEN 'objective_score_avg' THEN objective_score_avg IS NOT NULL AND objective_score_avg BETWEEN pert_band_lower AND pert_band_upper
              WHEN 'final_score' THEN final_score IS NOT NULL AND final_score BETWEEN pert_band_lower AND pert_band_upper
              WHEN 'research_score' THEN research_score IS NOT NULL AND research_score BETWEEN pert_band_lower AND pert_band_upper
            END
    ) AS within_band,
    COUNT(*) FILTER (
      WHERE CASE p_score_column
              WHEN 'objective_score_avg' THEN objective_score_avg IS NULL
              WHEN 'final_score' THEN final_score IS NULL
              WHEN 'research_score' THEN research_score IS NULL
            END
    ) AS not_yet_scored
  INTO v_summary
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code,
    'score_column_used', p_score_column,
    'apps_total', v_summary.apps_total,
    'apps_with_pert', v_summary.apps_with_pert,
    'last_calc_at', v_summary.last_calc_at,
    'cohort_n', v_summary.cohort_n,
    'target_score', v_summary.target_score,
    'band_lower', v_summary.band_lower,
    'band_upper', v_summary.band_upper,
    'method', v_summary.method,
    'distribution', jsonb_build_object(
      'below_band', v_summary.below_band,
      'within_band', v_summary.within_band,
      'above_band', v_summary.above_band,
      'not_yet_scored', v_summary.not_yet_scored
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_pre_onboarding_leaderboard()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result json;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  SELECT coalesce(json_agg(row_to_json(t) ORDER BY t.xp_earned DESC, t.name), '[]'::json)
  INTO v_result
  FROM (
    SELECT
      m.name,
      m.photo_url,
      count(*) FILTER (WHERE op.status = 'completed') as completed,
      count(*) as total,
      coalesce(sum((op.metadata->>'xp')::int) FILTER (WHERE op.status = 'completed'), 0) as xp_earned,
      coalesce(sum((op.metadata->>'xp')::int), 0) as xp_total,
      CASE WHEN count(*) > 0 THEN round(100.0 * count(*) FILTER (WHERE op.status = 'completed') / count(*)) ELSE 0 END as pct
    FROM onboarding_progress op
    JOIN members m ON m.id = op.member_id
    WHERE op.metadata->>'phase' = 'pre_onboarding'
    GROUP BY m.id, m.name, m.photo_url
  ) t;

  RETURN json_build_object('leaderboard', v_result);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_publication_pipeline_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM public.publication_submissions),
    'by_status', (
      SELECT COALESCE(jsonb_object_agg(s, c), '{}'::jsonb)
      FROM (SELECT status::text as s, count(*) as c FROM public.publication_submissions GROUP BY status) x
    ),
    'by_target_type', (
      SELECT COALESCE(jsonb_object_agg(tt, c), '{}'::jsonb)
      FROM (SELECT target_type::text as tt, count(*) as c FROM public.publication_submissions GROUP BY target_type) x
    ),
    'by_tribe', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'tribe_name', i.title,
        'count', sub.cnt
      )), '[]'::jsonb)
      FROM (
        SELECT initiative_id, count(*) as cnt
        FROM public.publication_submissions
        WHERE initiative_id IS NOT NULL
        GROUP BY initiative_id
      ) sub
      JOIN public.initiatives i ON i.id = sub.initiative_id
    ),
    'estimated_total_cost', (SELECT COALESCE(SUM(estimated_cost_brl), 0) FROM public.publication_submissions),
    'actual_total_cost', (SELECT COALESCE(SUM(actual_cost_brl), 0) FROM public.publication_submissions)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_tribe_members_with_credly(p_tribe_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_is_admin boolean;
  v_result jsonb;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');

  -- Permission: admin (any) OR tribe_leader of own tribe OR researcher in own tribe (sumarizado)
  IF NOT v_is_admin
     AND NOT (v_caller_role = 'tribe_leader' AND v_caller_tribe = p_tribe_id)
     AND v_caller_tribe IS DISTINCT FROM p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized: TL of tribe or admin required');
  END IF;

  WITH tribe_members AS (
    SELECT
      m.id, m.name, m.photo_url, m.operational_role, m.designations, m.chapter,
      m.member_status, m.is_active, m.person_id,
      m.credly_url,
      m.credly_verified_at,
      m.tribe_id,
      m.current_cycle_active
    FROM public.members m
    WHERE m.tribe_id = p_tribe_id
      AND m.member_status = 'active'
  ),
  badges AS (
    SELECT
      member_id,
      count(*) FILTER (WHERE type = 'trail') AS trail_count,
      bool_or(type = 'trail' AND status = 'active') AS trail_completed,
      bool_or(type = 'cert_pmi_senior') AS cert_pmi_senior,
      bool_or(type = 'cpmai') AS cpmai_certified,
      count(*) FILTER (WHERE status = 'active') AS total_badges
    FROM public.certificates
    GROUP BY member_id
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', tm.id,
    'name', tm.name,
    'photo_url', tm.photo_url,
    'operational_role', tm.operational_role,
    'designations', tm.designations,
    'chapter', tm.chapter,
    'current_cycle_active', tm.current_cycle_active,
    'person_id', tm.person_id,
    'credly_url', tm.credly_url,
    'credly_verified_at', tm.credly_verified_at,
    'badges_summary', jsonb_build_object(
      'trail_count', coalesce(b.trail_count, 0),
      'trail_completed', coalesce(b.trail_completed, false),
      'cert_pmi_senior', coalesce(b.cert_pmi_senior, false),
      'cpmai_certified', coalesce(b.cpmai_certified, false),
      'total_badges', coalesce(b.total_badges, 0)
    )
  ) ORDER BY tm.name), '[]'::jsonb)
  INTO v_result
  FROM tribe_members tm
  LEFT JOIN badges b ON b.member_id = tm.id;

  RETURN jsonb_build_object(
    'tribe_id', p_tribe_id,
    'members', v_result,
    'fetched_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_weekly_card_digest(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_is_self boolean;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  v_is_self := (v_caller_id = p_member_id);

  IF NOT v_is_self AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: can only read own digest or requires manage_member permission';
  END IF;

  SELECT jsonb_build_object(
    'member_id', p_member_id,
    'generated_at', now(),
    'this_week_pending', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'board_name', pb.board_name,
        'initiative_title', i.title,
        'days_overdue', GREATEST(0, CURRENT_DATE - bi.due_date)
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = p_member_id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE
    ), '[]'::jsonb),
    'next_week_due', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'board_name', pb.board_name,
        'initiative_title', i.title
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = p_member_id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date > CURRENT_DATE
        AND bi.due_date <= CURRENT_DATE + INTERVAL '7 days'
    ), '[]'::jsonb),
    'overdue_7plus', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'board_name', pb.board_name,
        'initiative_title', i.title,
        'days_overdue', CURRENT_DATE - bi.due_date
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = p_member_id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date < CURRENT_DATE - INTERVAL '7 days'
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

