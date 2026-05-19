-- p200 (OPP-196.E, ADR-0087 §2 Batch C, 2026-05-19): V4 swap
-- `'curator' = ANY(designations)` (in various forms) → `can_by_member('curate_content')`
-- in 4 governance/curation fns.
--
-- Functions touched:
--   get_application_score_breakdown — `v_caller.designations && ARRAY['curator']` clause
--   review_change_request           — `EXISTS unnest WHERE d='curator'` branch
--   submit_change_request           — `NOT EXISTS unnest WHERE d='curator'` in OR chain
--   upsert_publication_submission_event — extract curator from IN list; keep others as V3

CREATE OR REPLACE FUNCTION public.get_application_score_breakdown(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_evals jsonb;
  v_blind boolean;
  v_hidden text[];
  v_returning_match record;
  v_ai_triage jsonb;
  v_briefing jsonb;
  v_pert jsonb;
  v_returning jsonb;
  v_profile jsonb;
  v_pmi_history jsonb;
  v_core jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF NOT FOUND OR NOT (
    v_caller.is_superadmin = true
    OR public.can_by_member(v_caller.id, 'manage_member')
    OR public.can_by_member(v_caller.id, 'curate_content')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  -- p197c B3: expanded PII access log
  PERFORM public._log_application_pii_access(
    p_application_id,
    v_caller.id,
    ARRAY['email','applicant_name','evaluations','evaluator_notes','criterion_notes',
          'ai_analysis','ai_triage_reasoning','last_briefing_jsonb',
          'profile_about_me','profile_specialties','service_history_chapters','pmi_memberships',
          'previous_cycles'],
    'get_application_score_breakdown'
  );

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  v_blind := COALESCE(v_cycle.phase, 'planning') IN ('evaluating', 'interviews')
             AND v_caller.is_superadmin IS NOT TRUE;

  IF v_blind THEN
    SELECT jsonb_agg(jsonb_build_object(
      'evaluation_type', e.evaluation_type,
      'evaluator_name', m.name,
      'evaluator_id', m.id,
      'weighted_subtotal', e.weighted_subtotal,
      'submitted_at', e.submitted_at,
      'scores', e.scores,
      'notes', e.notes,
      'criterion_notes', e.criterion_notes,
      'is_own', true
    ) ORDER BY e.evaluation_type)
    INTO v_evals
    FROM public.selection_evaluations e
    JOIN public.members m ON m.id = e.evaluator_id
    WHERE e.application_id = p_application_id
      AND e.submitted_at IS NOT NULL
      AND e.evaluator_id = v_caller.id;

    v_hidden := ARRAY['other_evaluators_names', 'other_evaluators_scores',
                      'other_evaluators_subtotals', 'other_evaluators_notes'];
  ELSE
    SELECT jsonb_agg(jsonb_build_object(
      'evaluation_type', e.evaluation_type,
      'evaluator_name', m.name,
      'evaluator_id', m.id,
      'weighted_subtotal', e.weighted_subtotal,
      'submitted_at', e.submitted_at,
      'scores', e.scores,
      'notes', e.notes,
      'criterion_notes', e.criterion_notes,
      'is_own', e.evaluator_id = v_caller.id
    ) ORDER BY e.evaluation_type, m.name)
    INTO v_evals
    FROM public.selection_evaluations e
    JOIN public.members m ON m.id = e.evaluator_id
    WHERE e.application_id = p_application_id AND e.submitted_at IS NOT NULL;

    v_hidden := ARRAY[]::text[];
  END IF;

  SELECT id, name, member_status, operational_role, offboarded_at
  INTO v_returning_match
  FROM public.members WHERE lower(email) = lower(v_app.email) LIMIT 1;

  v_core := jsonb_build_object(
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'email', v_app.email,
    'role_applied', v_app.role_applied,
    'promotion_path', v_app.promotion_path,
    'status', v_app.status,
    'chapter', v_app.chapter,
    'research_score', v_app.research_score,
    'leader_score', v_app.leader_score,
    'final_score', v_app.final_score,
    'objective_score_avg', v_app.objective_score_avg,
    'interview_score', v_app.interview_score,
    'rank_researcher', v_app.rank_researcher,
    'rank_leader', v_app.rank_leader,
    'linked_application_id', v_app.linked_application_id
  );

  v_ai_triage := jsonb_build_object(
    'score', v_app.ai_triage_score,
    'reasoning', v_app.ai_triage_reasoning,
    'confidence', v_app.ai_triage_confidence,
    'model', v_app.ai_triage_model,
    'at', v_app.ai_triage_at,
    'consent_at', v_app.consent_ai_analysis_at
  );

  v_briefing := jsonb_build_object(
    'ai_analysis', v_app.ai_analysis,
    'last_briefing_jsonb', v_app.last_briefing_jsonb,
    'last_briefing_at', v_app.last_briefing_at,
    'last_briefing_model', v_app.last_briefing_model
  );

  v_pert := jsonb_build_object(
    'target_score', v_app.pert_target_score,
    'band_lower', v_app.pert_band_lower,
    'band_upper', v_app.pert_band_upper,
    'cohort_n', v_app.pert_cohort_n,
    'method', v_app.pert_cutoff_method,
    'calc_at', v_app.pert_calc_at,
    'final_score_position', CASE
      WHEN v_app.final_score IS NULL OR v_app.pert_band_lower IS NULL OR v_app.pert_band_upper IS NULL THEN NULL
      WHEN v_app.final_score < v_app.pert_band_lower THEN 'below'
      WHEN v_app.final_score > v_app.pert_band_upper THEN 'above'
      ELSE 'within'
    END,
    'research_score_position', CASE
      WHEN v_app.research_score IS NULL OR v_app.pert_band_lower IS NULL OR v_app.pert_band_upper IS NULL THEN NULL
      WHEN v_app.research_score < v_app.pert_band_lower THEN 'below'
      WHEN v_app.research_score > v_app.pert_band_upper THEN 'above'
      ELSE 'within'
    END
  );

  v_returning := jsonb_build_object(
    'is_returning_member', v_app.is_returning_member,
    'previous_cycles', v_app.previous_cycles,
    'application_count', v_app.application_count,
    'returning_member_match', CASE WHEN v_returning_match.id IS NOT NULL THEN jsonb_build_object(
      'member_id', v_returning_match.id,
      'name', v_returning_match.name,
      'member_status', v_returning_match.member_status,
      'operational_role', v_returning_match.operational_role,
      'offboarded_at', v_returning_match.offboarded_at
    ) ELSE NULL END
  );

  v_profile := jsonb_build_object(
    'profile_about_me', v_app.profile_about_me,
    'profile_specialties', v_app.profile_specialties,
    'profile_company', v_app.profile_company,
    'profile_designation', v_app.profile_designation,
    'profile_industry', v_app.profile_industry,
    'profile_certifications', v_app.profile_certifications,
    'profile_location', v_app.profile_location,
    'credly_url', v_app.credly_url,
    'linkedin_url', v_app.linkedin_url
  );

  v_pmi_history := jsonb_build_object(
    'service_history_count', v_app.service_history_count,
    'service_history_chapters', v_app.service_history_chapters,
    'service_first_start_date', v_app.service_first_start_date,
    'service_latest_end_date', v_app.service_latest_end_date,
    'pmi_memberships', v_app.pmi_memberships
  );

  RETURN v_core
    || jsonb_build_object(
      'evaluations', COALESCE(v_evals, '[]'::jsonb),
      'blind_review_active', v_blind,
      'cycle_phase', COALESCE(v_cycle.phase, 'unknown'),
      'hidden_fields', v_hidden,
      'ai_triage', v_ai_triage,
      'briefing', v_briefing,
      'pert_cutoff', v_pert,
      'returning_context', v_returning,
      'profile_lite', v_profile,
      'pmi_history', v_pmi_history
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.review_change_request(p_cr_id uuid, p_action text, p_notes text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_mid uuid; v_cr record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id=auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  v_mid := v_caller.id;
  SELECT * INTO v_cr FROM change_requests WHERE id=p_cr_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','CR not found'); END IF;
  -- p178 ADR-0011 inline V4 refactor: top-level authority via can_by_member(manage_platform).
  -- Covers superadmin + manager + deputy_manager + co_gp (per engagement_kind_permissions seed).
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content').
  -- sponsor/chapter_liaison legacy paths preserved as fallback; full V3→V4
  -- sweep of the change_requests action surface is deferred to a dedicated ADR-0011 batch session.
  IF NOT can_by_member(v_mid, 'manage_platform') THEN
    IF can_by_member(v_mid, 'curate_content') THEN
      IF v_cr.cr_type='structural' AND p_action='approve' THEN
        RETURN jsonb_build_object('error','Curators cannot approve structural CRs'); END IF;
    ELSIF v_caller.operational_role IN ('sponsor','chapter_liaison') THEN NULL;
    ELSE RETURN jsonb_build_object('error','Unauthorized'); END IF;
  END IF;
  IF p_action='approve' THEN
    UPDATE change_requests SET status='approved',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=COALESCE(p_notes,review_notes),
      approved_by_members=array_append(COALESCE(approved_by_members,'{}'),v_mid),
      approved_at=now(),updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='reject' THEN
    UPDATE change_requests SET status='rejected',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=p_notes,updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='request_changes' THEN
    UPDATE change_requests SET status='under_review',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=p_notes,updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='implement' THEN
    IF v_cr.status!='approved' THEN RETURN jsonb_build_object('error','Must be approved first'); END IF;
    UPDATE change_requests SET status='implemented',implemented_by=v_mid,implemented_at=now(),
      manual_version_to='R3',updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action = 'withdraw' THEN
    IF v_cr.status NOT IN ('draft', 'submitted', 'under_review') THEN
      RETURN jsonb_build_object('error', 'Cannot withdraw approved/implemented CR'); END IF;
    UPDATE change_requests SET status = 'withdrawn', review_notes = COALESCE(p_notes, review_notes), updated_at = now() WHERE id = p_cr_id;
  ELSIF p_action = 'resubmit' THEN
    IF v_cr.status != 'under_review' THEN
      RETURN jsonb_build_object('error', 'Can only resubmit CRs under review'); END IF;
    UPDATE change_requests SET status = 'submitted', submitted_at = now(), review_notes = COALESCE(p_notes, review_notes), updated_at = now() WHERE id = p_cr_id;
  ELSE RETURN jsonb_build_object('error','Invalid action'); END IF;

  IF v_cr.submitted_by IS NOT NULL AND v_cr.submitted_by != v_mid THEN
    PERFORM create_notification(v_cr.submitted_by, 'cr_status_changed', 'change_request', p_cr_id, v_cr.title, v_mid);
  END IF;

  RETURN jsonb_build_object('success',true,'cr_number',v_cr.cr_number,'new_status',p_action);
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_change_request(p_title text, p_description text, p_cr_type text, p_manual_section_ids uuid[] DEFAULT NULL::uuid[], p_gc_references text[] DEFAULT NULL::text[], p_impact_level text DEFAULT 'medium'::text, p_impact_description text DEFAULT NULL::text, p_justification text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_mid uuid; v_crn text; v_nid uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id=auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  v_mid := v_caller.id;
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager','deputy_manager','tribe_leader')
    AND NOT public.can_by_member(v_mid, 'curate_content')
  THEN RETURN jsonb_build_object('error','Unauthorized'); END IF;
  IF p_cr_type NOT IN ('editorial','operational','structural','emergency') THEN
    RETURN jsonb_build_object('error','Invalid cr_type'); END IF;
  SELECT 'CR-'||LPAD((COALESCE(MAX(SUBSTRING(cr_number FROM 4)::int),0)+1)::text,3,'0')
    INTO v_crn FROM change_requests WHERE cr_number ~ '^CR-\d+$';
  INSERT INTO change_requests (
    cr_number,title,description,cr_type,status,priority,
    manual_section_ids,gc_references,impact_level,impact_description,justification,
    requested_by,requested_by_role,submitted_at,manual_version_from,created_at,updated_at
  ) VALUES (
    v_crn,p_title,p_description,p_cr_type,'submitted',p_impact_level,
    p_manual_section_ids,p_gc_references,p_impact_level,p_impact_description,p_justification,
    v_mid,v_caller.operational_role,now(),'R2',now(),now()
  ) RETURNING id INTO v_nid;
  RETURN jsonb_build_object('success',true,'id',v_nid,'cr_number',v_crn);
END; $function$;

CREATE OR REPLACE FUNCTION public.upsert_publication_submission_event(p_board_item_id uuid, p_channel text DEFAULT 'projectmanagement_com'::text, p_submitted_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_outcome text DEFAULT 'pending'::text, p_notes text DEFAULT NULL::text, p_external_link text DEFAULT NULL::text, p_published_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS publication_submission_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid;
  v_member public.members%rowtype;
  v_row public.publication_submission_events%rowtype;
begin
  v_actor := auth.uid();
  if v_actor is null then raise exception 'Auth required'; end if;
  select * into v_member from public.members where auth_id = v_actor and is_active = true limit 1;
  if v_member.id is null then raise exception 'Member not found'; end if;
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  -- Other designations (co_gp, comms_leader, comms_member) preserved as V3.
  if not (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager', 'communicator')
    or public.can_by_member(v_member.id, 'curate_content')
    or exists (select 1 from unnest(coalesce(v_member.designations, array[]::text[])) d where d in ('co_gp', 'comms_leader', 'comms_member'))
  ) then raise exception 'Publication workflow access required'; end if;
  insert into public.publication_submission_events (board_item_id, channel, submitted_at, outcome, notes, external_link, published_at, updated_by)
  values (p_board_item_id, coalesce(nullif(trim(p_channel), ''), 'projectmanagement_com'), p_submitted_at, p_outcome, nullif(trim(p_notes), ''), nullif(trim(p_external_link), ''), p_published_at, v_member.id)
  returning * into v_row;
  return v_row;
end;
$function$;

NOTIFY pgrst, 'reload schema';
