-- p197c B3 (2026-05-19): enrich get_application_score_breakdown into the committee
-- "decision pack" — single RPC that gives evaluator + committee everything they need to
-- decide on a candidate. Previously they had to call 4-5 RPCs separately.
--
-- Changes:
-- - evaluations[] now includes notes (164/233 had notes — info was hidden) + criterion_notes
-- - +AI triage block (score, reasoning, confidence, model, at)
-- - +ai_analysis (Gemini qualitative)
-- - +briefing block (last_briefing_jsonb, at, model)
-- - +pert_cutoff block (target/band/cohort) for cohort_position context
-- - +returning_context inline (is_returning, previous_cycles, application_count, matched_member)
-- - +profile_lite (about_me, specialties, company, designation, certifications, location)
-- - +service_history_lite (count, chapters, dates) + pmi_memberships
--
-- Blind mode preserved: during phase=evaluating, non-superadmin sees only OWN eval row.
-- AI/triage/briefing/pert/returning/profile are exposed unconditionally — these are CONTEXT
-- INPUT to evaluation, not other-evaluator output (ADR-0059 covers peer score blindness).
-- PII access log expanded to capture the new fields.
--
-- Rollback: drop and re-apply prior get_application_score_breakdown body.

DROP FUNCTION IF EXISTS public.get_application_score_breakdown(uuid);

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
  IF NOT FOUND OR NOT (
    v_caller.is_superadmin = true
    OR public.can_by_member(v_caller.id, 'manage_member')
    OR (v_caller.designations && ARRAY['curator'])
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

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

COMMENT ON FUNCTION public.get_application_score_breakdown(uuid) IS
  'p197c B3 (2026-05-19) committee decision pack: evaluations[] now includes notes + criterion_notes (164/233 evals had notes — previously hidden); +ai_triage, +briefing (last_briefing_jsonb + ai_analysis), +pert_cutoff (target + band + final/research_score_position), +returning_context (is_returning + previous_cycles + matched_member), +profile_lite (about_me + specialties + company + designation + certifications + location), +pmi_history (service_history + memberships). Blind mode preserved for peer scores/notes only — context fields (AI/pert/returning/profile) always visible since they are evaluation INPUT, not peer OUTPUT (ADR-0059). Eliminates need for 4-5 separate RPC calls in committee final-decision flow.';
