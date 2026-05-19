-- p197 hotfix (2026-05-19): jsonb_build_object 100-arg limit hit in initial p197 — split application
-- object into 4 chunks merged via || to stay within PostgreSQL's hardcoded jsonb_build_object cap.
--
-- RECOVERY NOTE (BUG-199.B p199-b, 2026-05-19): applied to DB live as immediate
-- hotfix of 20260519013730 (which crashed with `cannot pass more than 100
-- arguments to a function` at runtime). FS file was lost when Supabase fork-bomb
-- killed the session (CR-051). Body recovered byte-equivalent from
-- supabase_migrations.schema_migrations.statements on 2026-05-19.
-- DB live state matches THIS migration (the fix), NOT the bugged 013730 body.
-- If anyone runs `supabase db reset` locally, the sequence 013730 → 013900 will
-- correctly land at the fixed state.

DROP FUNCTION IF EXISTS public.get_evaluation_form(uuid, text);

CREATE OR REPLACE FUNCTION public.get_evaluation_form(p_application_id uuid, p_evaluation_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_draft record;
  v_criteria jsonb;
  v_criteria_enriched jsonb;
  v_max_weighted numeric := 0;
  v_returning_match record;
  v_app_core jsonb;
  v_app_body jsonb;
  v_app_profile jsonb;
  v_app_pmi_history jsonb;
  v_app_returning jsonb;
  v_app_ai jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found: %', p_application_id; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  PERFORM public._log_application_pii_access(
    p_application_id, v_caller.id,
    ARRAY[
      'email','applicant_name','linkedin_url','resume_url','resume_storage_path','cv_extracted_text',
      'motivation_letter','leadership_experience','academic_background','reason_for_applying',
      'profile_about_me','profile_specialties','profile_company','profile_designation',
      'profile_industry','profile_certifications','profile_linkedin_url',
      'service_history_chapters','pmi_memberships','previous_cycles','linkedin_relevant_posts'
    ],
    'get_evaluation_form:' || p_evaluation_type
  );

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  SELECT * INTO v_draft FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluator_id = v_caller.id
    AND evaluation_type = p_evaluation_type;

  SELECT jsonb_agg(
    jsonb_build_object(
      'key', c->>'key', 'label', c->>'label', 'guide', c->>'guide',
      'weight', COALESCE((c->>'weight')::numeric, 1),
      'max', COALESCE((c->>'max')::numeric, 10),
      'max_weighted_contribution', COALESCE((c->>'weight')::numeric, 1) * COALESCE((c->>'max')::numeric, 10),
      'your_score', CASE WHEN v_draft.scores IS NOT NULL AND v_draft.scores ? (c->>'key')
                          THEN (v_draft.scores->>(c->>'key'))::numeric ELSE NULL END,
      'your_weighted_contribution', CASE WHEN v_draft.scores IS NOT NULL AND v_draft.scores ? (c->>'key')
                                          THEN COALESCE((c->>'weight')::numeric, 1) * (v_draft.scores->>(c->>'key'))::numeric ELSE NULL END,
      'your_criterion_note', CASE WHEN v_draft.criterion_notes IS NOT NULL AND v_draft.criterion_notes ? (c->>'key')
                                   THEN v_draft.criterion_notes->>(c->>'key') ELSE NULL END
    )
  ) INTO v_criteria_enriched
  FROM jsonb_array_elements(v_criteria) c;

  SELECT SUM(COALESCE((c->>'weight')::numeric, 1) * COALESCE((c->>'max')::numeric, 10))
  INTO v_max_weighted
  FROM jsonb_array_elements(v_criteria) c;

  SELECT id, name, member_status, operational_role, offboarded_at
  INTO v_returning_match
  FROM public.members WHERE lower(email) = lower(v_app.email) LIMIT 1;

  -- Build application object in chunks (PG jsonb_build_object 100-arg cap workaround)
  v_app_core := jsonb_build_object(
    'id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'email', v_app.email,
    'chapter', v_app.chapter,
    'role_applied', v_app.role_applied,
    'promotion_path', v_app.promotion_path,
    'certifications', v_app.certifications,
    'linkedin_url', v_app.linkedin_url,
    'resume_url', v_app.resume_url,
    'resume_storage_path', v_app.resume_storage_path,
    'resume_synced_at', v_app.resume_synced_at,
    'cv_extracted_text', v_app.cv_extracted_text,
    'membership_status', v_app.membership_status,
    'status', v_app.status,
    'credly_url', v_app.credly_url,
    'is_open_to_volunteer', v_app.is_open_to_volunteer
  );

  v_app_body := jsonb_build_object(
    'motivation_letter', v_app.motivation_letter,
    'reason_for_applying', v_app.reason_for_applying,
    'chapter_affiliation', v_app.chapter_affiliation,
    'non_pmi_experience', v_app.non_pmi_experience,
    'areas_of_interest', v_app.areas_of_interest,
    'availability_declared', v_app.availability_declared,
    'proposed_theme', v_app.proposed_theme,
    'leadership_experience', v_app.leadership_experience,
    'academic_background', v_app.academic_background
  );

  v_app_profile := jsonb_build_object(
    'profile_about_me', v_app.profile_about_me,
    'profile_specialties', v_app.profile_specialties,
    'profile_company', v_app.profile_company,
    'profile_designation', v_app.profile_designation,
    'profile_industry', v_app.profile_industry,
    'profile_certifications', v_app.profile_certifications,
    'profile_volunteer_interest', v_app.profile_volunteer_interest,
    'profile_location', v_app.profile_location,
    'profile_state', v_app.profile_state,
    'profile_country', v_app.profile_country,
    'profile_linkedin_url', v_app.profile_linkedin_url,
    'linkedin_relevant_posts', v_app.linkedin_relevant_posts,
    'ai_pm_focus_tags', v_app.ai_pm_focus_tags
  );

  v_app_pmi_history := jsonb_build_object(
    'service_history_count', v_app.service_history_count,
    'service_history_chapters', v_app.service_history_chapters,
    'service_first_start_date', v_app.service_first_start_date,
    'service_latest_end_date', v_app.service_latest_end_date,
    'pmi_memberships', v_app.pmi_memberships
  );

  v_app_returning := jsonb_build_object(
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

  v_app_ai := jsonb_build_object(
    'consent_ai_analysis_at', v_app.consent_ai_analysis_at,
    'ai_analysis', v_app.ai_analysis,
    'ai_triage_score', v_app.ai_triage_score,
    'ai_triage_reasoning', v_app.ai_triage_reasoning,
    'ai_triage_confidence', v_app.ai_triage_confidence,
    'ai_triage_at', v_app.ai_triage_at,
    'ai_triage_model', v_app.ai_triage_model,
    'last_briefing_jsonb', v_app.last_briefing_jsonb,
    'last_briefing_at', v_app.last_briefing_at,
    'last_briefing_model', v_app.last_briefing_model
  );

  RETURN jsonb_build_object(
    'application', v_app_core || v_app_body || v_app_profile || v_app_pmi_history || v_app_returning || v_app_ai,
    'criteria', v_criteria,
    'criteria_with_weights', COALESCE(v_criteria_enriched, '[]'::jsonb),
    'max_weighted_subtotal', v_max_weighted,
    'pert_cutoff', jsonb_build_object(
      'target_score', v_app.pert_target_score,
      'band_lower', v_app.pert_band_lower,
      'band_upper', v_app.pert_band_upper,
      'cohort_n', v_app.pert_cohort_n,
      'method', v_app.pert_cutoff_method,
      'calc_at', v_app.pert_calc_at
    ),
    'evaluation_type', p_evaluation_type,
    'committee_role', COALESCE(v_committee.role, 'platform_admin'),
    'draft', CASE WHEN v_draft IS NOT NULL THEN jsonb_build_object(
      'id', v_draft.id, 'scores', v_draft.scores, 'notes', v_draft.notes,
      'criterion_notes', COALESCE(v_draft.criterion_notes, '{}'::jsonb),
      'weighted_subtotal', v_draft.weighted_subtotal, 'submitted_at', v_draft.submitted_at
    ) ELSE NULL END,
    'is_locked', CASE WHEN v_draft.submitted_at IS NOT NULL THEN true ELSE false END
  );
END;
$function$;

COMMENT ON FUNCTION public.get_evaluation_form(uuid, text) IS
  'p197 (2026-05-19) enriched payload: adds VEP semantic context (cv_extracted_text, resume_storage_path, '
  'profile_* LinkedIn enrichment, service_history_*, pmi_memberships, returning_member_match), '
  'criteria_with_weights (computed contributions + draft inlined), max_weighted_subtotal, '
  'and pert_cutoff (cohort of approved active members). Motivated by Fabricio MCP submit anomaly '
  '2026-05-19 (Luíse Quintana, diff -52 vs first evaluator). Auth unchanged: committee membership '
  'OR manage_platform. Built via 6-chunk jsonb_build_object || merge to dodge PG 100-arg cap.';
