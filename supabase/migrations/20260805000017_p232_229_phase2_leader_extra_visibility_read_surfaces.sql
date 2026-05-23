-- ============================================================
-- p232 #229 Phase 2: leader_extra cohort visibility in read surfaces
-- ============================================================
-- WHAT: extend 3 RPCs so the leader_extra dimension (already separated
-- in submit_evaluation + _compute_pert_cutoff_core via p209 Phase 1 +
-- p219 leaf) is also visible to consumers:
--   1. get_pert_cutoff_summary  — accept p_score_column='leader_extra_pert_score'
--                                  + read from leader_extra_pert_target/band_*
--   2. get_application_score_breakdown — add `leader_extra_cutoff` block + position
--   3. get_selection_dashboard — add `leader_extra_cutoff` sibling to `pert_cutoff`
--                                in the `cycle` payload
--
-- WHY: Phase 1 closed the math drift (submit_evaluation no longer mutates
-- objective_score_avg) and the core cutoff machinery supports both
-- dimensions (_compute_pert_cutoff_core branches on p_score_column;
-- recompute_all_active_pert_cutoffs already calls both per cycle).
-- But the read surfaces still only expose objective:
--   - get_pert_cutoff_summary rejects 'leader_extra_pert_score' at CHECK
--     and its distribution math reads pert_target_score / pert_band_*
--     unconditionally.
--   - get_application_score_breakdown returns only `pert_cutoff` (objective).
--   - get_selection_dashboard.cycle.pert_cutoff is objective-only.
-- This migration closes the visibility loop without changing the cutoff
-- write path (which is already correct).
--
-- ROLLBACK: re-apply the pre-p232 bodies (captured from pg_get_functiondef
-- before this migration). Each function is CREATE OR REPLACE so signature
-- is unchanged.
--
-- FORWARD-DEFENSE: tests/contracts/pert-leader-extra-dimension.test.mjs
-- asserts: CHECK allows leader_extra_pert_score; summary dual-track math;
-- breakdown carries leader_extra_cutoff key; dashboard cycle carries
-- leader_extra_cutoff key.
-- ============================================================

-- ----------------------------------------------------------------
-- 1) get_pert_cutoff_summary — dual-track CHECK + math
-- ----------------------------------------------------------------
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
  v_is_leader_extra boolean;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL OR NOT public.can_by_member(v_member_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'access_denied');
  END IF;

  -- p232 #229 Phase 2: allow leader_extra_pert_score (was only obj/final/research)
  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score', 'leader_extra_pert_score') THEN
    RETURN jsonb_build_object('error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg','final_score','research_score','leader_extra_pert_score'));
  END IF;

  v_is_leader_extra := (p_score_column = 'leader_extra_pert_score');

  SELECT id, cycle_code INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF v_cycle.id IS NULL THEN RETURN jsonb_build_object('error', 'cycle_not_found'); END IF;

  -- p232 #229 Phase 2: dual-track read — leader_extra_* columns when LE,
  -- pert_* columns otherwise. Distribution check still uses MESMA coluna
  -- que o target foi calculado (p131 #22 invariant preserved per dimension).
  IF v_is_leader_extra THEN
    SELECT
      COUNT(*) AS apps_total,
      COUNT(*) FILTER (WHERE leader_extra_pert_target IS NOT NULL) AS apps_with_pert,
      MAX(leader_extra_pert_calc_at) AS last_calc_at,
      MAX(leader_extra_pert_cohort_n) AS cohort_n,
      MAX(leader_extra_pert_target) AS target_score,
      MAX(leader_extra_pert_band_lower) AS band_lower,
      MAX(leader_extra_pert_band_upper) AS band_upper,
      MAX(leader_extra_pert_cutoff_method) AS method,
      COUNT(*) FILTER (
        WHERE leader_extra_pert_score IS NOT NULL
          AND leader_extra_pert_band_lower IS NOT NULL
          AND leader_extra_pert_score < leader_extra_pert_band_lower
      ) AS below_band,
      COUNT(*) FILTER (
        WHERE leader_extra_pert_score IS NOT NULL
          AND leader_extra_pert_band_upper IS NOT NULL
          AND leader_extra_pert_score > leader_extra_pert_band_upper
      ) AS above_band,
      COUNT(*) FILTER (
        WHERE leader_extra_pert_score IS NOT NULL
          AND leader_extra_pert_band_lower IS NOT NULL
          AND leader_extra_pert_band_upper IS NOT NULL
          AND leader_extra_pert_score BETWEEN leader_extra_pert_band_lower AND leader_extra_pert_band_upper
      ) AS within_band,
      COUNT(*) FILTER (WHERE leader_extra_pert_score IS NULL) AS not_yet_scored
    INTO v_summary
    FROM public.selection_applications
    WHERE cycle_id = p_cycle_id;
  ELSE
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
  END IF;

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

COMMENT ON FUNCTION public.get_pert_cutoff_summary(uuid, text) IS
  'p232 #229 Phase 2: dual-track summary. p_score_column ∈ {objective_score_avg, final_score, research_score, leader_extra_pert_score}. When leader_extra_pert_score, reads leader_extra_pert_target/band_*/calc_at/cohort_n/cutoff_method columns and distribution buckets leader_extra_pert_score vs leader_extra_pert_band_*.';

-- ----------------------------------------------------------------
-- 2) get_application_score_breakdown — add leader_extra_cutoff block
-- ----------------------------------------------------------------
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
  v_leader_extra_cutoff jsonb;
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
    -- p232 #229 Phase 2: expose leader_extra_pert_score in core (was only in evaluations[])
    'leader_extra_pert_score', v_app.leader_extra_pert_score,
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

  -- p232 #229 Phase 2: separate leader_extra cutoff block + position
  v_leader_extra_cutoff := jsonb_build_object(
    'target_score', v_app.leader_extra_pert_target,
    'band_lower', v_app.leader_extra_pert_band_lower,
    'band_upper', v_app.leader_extra_pert_band_upper,
    'cohort_n', v_app.leader_extra_pert_cohort_n,
    'method', v_app.leader_extra_pert_cutoff_method,
    'calc_at', v_app.leader_extra_pert_calc_at,
    'leader_extra_score_position', CASE
      WHEN v_app.leader_extra_pert_score IS NULL OR v_app.leader_extra_pert_band_lower IS NULL OR v_app.leader_extra_pert_band_upper IS NULL THEN NULL
      WHEN v_app.leader_extra_pert_score < v_app.leader_extra_pert_band_lower THEN 'below'
      WHEN v_app.leader_extra_pert_score > v_app.leader_extra_pert_band_upper THEN 'above'
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
      'leader_extra_cutoff', v_leader_extra_cutoff,
      'returning_context', v_returning,
      'profile_lite', v_profile,
      'pmi_history', v_pmi_history
    );
END;
$function$;

COMMENT ON FUNCTION public.get_application_score_breakdown(uuid) IS
  'p232 #229 Phase 2: jsonb response now includes top-level leader_extra_pert_score + leader_extra_cutoff{target/band/cohort_n/method/calc_at/leader_extra_score_position} alongside existing pert_cutoff (objective). Closes leader_extra visibility loop opened by p209 Phase 1 mitigation.';

-- ----------------------------------------------------------------
-- 3) get_selection_dashboard — add leader_extra_cutoff to cycle payload
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_selection_dashboard(p_cycle_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_result jsonb;
  v_stats_a jsonb;
  v_stats_b jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found', 'cycle', null, 'applications', '[]'::jsonb, 'stats', jsonb_build_object('total', 0));
  END IF;

  v_stats_a := jsonb_build_object(
    'total', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
    'approved', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted')),
    'rejected', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('rejected', 'objective_cutoff')),
    'pending', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')),
    'cancelled', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('cancelled', 'withdrawn')),
    'waitlist', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status = 'waitlist'),
    'leader_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL),
    'researcher_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL),
    'ai_analysis_done_count', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NOT NULL AND ai_analysis IS NOT NULL),
    'consent_ai_pending', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NULL),
    'consent_ai_consented', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NOT NULL AND consent_ai_analysis_revoked_at IS NULL),
    'consent_ai_revoked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_revoked_at IS NOT NULL)
  );

  v_stats_b := jsonb_build_object(
    'with_peer_evals_2plus', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND (SELECT count(DISTINCT e.evaluator_id) FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL) >= 2),
    'with_interview_scheduled', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled','completed','rescheduled'))),
    'with_interview_today', (
      SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id
        AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id
          AND si.status = 'scheduled'
          AND (si.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::date = (now() AT TIME ZONE 'America/Sao_Paulo')::date)
    ),
    'with_video_uploaded', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed'))),
    'with_video_opted_out', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id) AND NOT EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed'))),
    'with_pmi_member_active', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND pmi_id IS NOT NULL AND pmi_id <> '' AND service_latest_end_date >= CURRENT_DATE),
    'with_chapter_canonical', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND service_history_chapters IS NOT NULL AND service_history_chapters <> '' AND service_history_chapters <> 'PMI Global'),
    'with_re_applicants', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND COALESCE(application_count, 1) > 1),
    'with_briefing_generated', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND last_briefing_at IS NOT NULL),
    'shadow_vep_count', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.cycle_id = v_cycle_id
        AND a.status IN ('approved', 'converted', 'cancelled', 'rejected', 'withdrawn')
        AND EXISTS (
          SELECT 1 FROM public.members m
          WHERE m.is_active = true
            AND lower(m.email) = lower(a.email)
            AND m.created_at < a.created_at
        )
    ),
    'my_evals_submitted', (SELECT count(*) FROM public.selection_evaluations e JOIN public.selection_applications a ON a.id = e.application_id WHERE a.cycle_id = v_cycle_id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL),
    'my_evals_pending', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) AND NOT EXISTS (SELECT 1 FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id))
  );

  SELECT jsonb_build_object(
    'cycle', (SELECT jsonb_build_object(
      'id', c.id, 'cycle_code', c.cycle_code, 'title', c.title, 'status', c.status,
      'interview_booking_url', c.interview_booking_url,
      'interview_questions', COALESCE(c.interview_questions, '[]'::jsonb),
      'pert_cutoff', (SELECT jsonb_build_object(
        'target_score', MAX(pert_target_score),
        'band_lower', MAX(pert_band_lower),
        'band_upper', MAX(pert_band_upper),
        'cohort_n', MAX(pert_cohort_n),
        'method', MAX(pert_cutoff_method),
        'calc_at', MAX(pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE pert_target_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
      -- p232 #229 Phase 2: sibling block for leader_extra dimension
      'leader_extra_cutoff', (SELECT jsonb_build_object(
        'target_score', MAX(leader_extra_pert_target),
        'band_lower', MAX(leader_extra_pert_band_lower),
        'band_upper', MAX(leader_extra_pert_band_upper),
        'cohort_n', MAX(leader_extra_pert_cohort_n),
        'method', MAX(leader_extra_pert_cutoff_method),
        'calc_at', MAX(leader_extra_pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE leader_extra_pert_target IS NOT NULL),
        'apps_with_score', COUNT(*) FILTER (WHERE leader_extra_pert_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id)
    ) FROM public.selection_cycles c WHERE c.id = v_cycle_id),
    'applications', COALESCE((
      SELECT jsonb_agg(
        -- p197d A hotfix2: application row built as 2 jsonb_build_object chunks
        -- merged via || to dodge PG 100-arg cap (~53 fields × 2 args = 106 args).
        jsonb_build_object(
          'id', a.id, 'applicant_name', a.applicant_name, 'email', a.email,
          'phone', a.phone,
          'role_applied', a.role_applied, 'chapter', a.chapter, 'status', a.status,
          'objective_score', a.objective_score_avg, 'final_score', a.final_score,
          'research_score', a.research_score, 'leader_score', a.leader_score,
          'rank_researcher', a.rank_researcher, 'rank_leader', a.rank_leader,
          'promotion_path', a.promotion_path, 'linked_application_id', a.linked_application_id,
          'rank_chapter', a.rank_chapter, 'rank_overall', a.rank_overall,
          'linkedin_url', a.linkedin_url, 'resume_url', a.resume_url,
          'resume_storage_path', a.resume_storage_path,
          'resume_synced_at', a.resume_synced_at,
          'tags', a.tags, 'feedback', a.feedback,
          'motivation', a.motivation_letter, 'experience_years', a.seniority_years,
          'membership_status', a.membership_status, 'certifications', a.certifications,
          'is_returning_member', a.is_returning_member, 'application_date', a.application_date,
          'academic_background', a.academic_background, 'areas_of_interest', a.areas_of_interest,
          'availability_declared', a.availability_declared, 'non_pmi_experience', a.non_pmi_experience,
          'proposed_theme', a.proposed_theme, 'leadership_experience', a.leadership_experience,
          'created_at', a.created_at, 'interview_status', a.interview_status,
          'interview_reschedule_reason', a.interview_reschedule_reason,
          'interview_reschedule_requested_at', a.interview_reschedule_requested_at,
          'consent_ai_status', CASE
            WHEN a.consent_ai_analysis_revoked_at IS NOT NULL THEN 'revoked'
            WHEN a.consent_ai_analysis_at IS NOT NULL THEN 'consented'
            ELSE 'pending'
          END,
          'consent_ai_at', a.consent_ai_analysis_at,
          'consent_ai_revoked_at', a.consent_ai_analysis_revoked_at,
          'member_credly_url', (SELECT m.credly_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
          'member_photo_url', (SELECT m.photo_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
          -- p232 #229 Phase 2: per-row leader_extra fields for table coloring + ranking transparency
          'leader_extra_pert_score', a.leader_extra_pert_score
        ) || jsonb_build_object(
          'peer_eval_count', (
            SELECT count(*)::int FROM public.selection_evaluations e
            WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL
          ),
          'peer_extra', jsonb_build_object(
            'distinct_evaluators', (
              SELECT count(DISTINCT e.evaluator_id)::int FROM public.selection_evaluations e
              WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL
            ),
            'invites_pending', (
              SELECT count(*)::int FROM public.notifications n
              WHERE n.type = 'peer_review_requested' AND n.source_id = a.id
                AND NOT EXISTS (SELECT 1 FROM public.selection_evaluations e2 WHERE e2.application_id = a.id AND e2.evaluator_id = n.recipient_id)
            )
          ),
          'meta', jsonb_build_object(
            'ai_analysis_done', (a.consent_ai_analysis_at IS NOT NULL AND a.ai_analysis IS NOT NULL),
            'interview_scheduled', EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled', 'completed', 'rescheduled')),
            'interview_next_at', (
              SELECT MIN(si.scheduled_at) FROM public.selection_interviews si
              WHERE si.application_id = a.id
                AND si.status = 'scheduled'
                AND si.scheduled_at >= now() - interval '12 hours'
            ),
            'has_interview_today', EXISTS (
              SELECT 1 FROM public.selection_interviews si
              WHERE si.application_id = a.id
                AND si.status = 'scheduled'
                AND (si.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::date = (now() AT TIME ZONE 'America/Sao_Paulo')::date
            ),
            'token_consumed', EXISTS (SELECT 1 FROM public.onboarding_tokens t WHERE t.source_id = a.id AND t.source_type = 'pmi_application' AND COALESCE(t.access_count, 0) > 0),
            'video_screening_done', EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded', 'transcribing', 'transcribed', 'opted_out'))
          ),
          'video_agg', jsonb_build_object(
            'status_agg', (SELECT CASE WHEN count(*) = 0 THEN 'none' WHEN count(*) FILTER (WHERE v.status IN ('uploaded','transcribing','transcribed')) > 0 THEN 'uploaded' WHEN count(*) FILTER (WHERE v.status = 'opted_out') = count(*) THEN 'opted_out' ELSE 'partial' END FROM public.pmi_video_screenings v WHERE v.application_id = a.id),
            'uploaded_count', (SELECT count(*)::int FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed')),
            'total_rows', (SELECT count(*)::int FROM public.pmi_video_screenings v WHERE v.application_id = a.id)
          ),
          'pmi_canonical', jsonb_build_object(
            'chapter_canonical', (
              SELECT trim(c) FROM unnest(string_to_array(COALESCE(a.service_history_chapters, ''), ';')) AS c
              WHERE trim(c) <> '' AND trim(c) <> 'PMI Global' LIMIT 1
            ),
            'is_pmi_member', (a.pmi_id IS NOT NULL AND a.pmi_id <> ''),
            'member_status', CASE
              WHEN a.pmi_id IS NULL OR a.pmi_id = '' THEN 'unknown'
              WHEN a.service_latest_end_date IS NULL THEN 'unknown'
              WHEN a.service_latest_end_date >= CURRENT_DATE THEN 'active'
              ELSE 'past'
            END,
            'member_since', a.service_first_start_date,
            'member_until', a.service_latest_end_date,
            'service_history_count', COALESCE(a.service_history_count, 0),
            'phase_b_fetched_at', a.pmi_data_fetched_at,
            'pmi_id', a.pmi_id
          ),
          'extra_flags', jsonb_build_object(
            'application_count', COALESCE(a.application_count, 1),
            'has_briefing', (a.last_briefing_at IS NOT NULL),
            'briefing_at', a.last_briefing_at,
            'briefing_model', a.last_briefing_model,
            'ai_triage_score', a.ai_triage_score,
            'ai_triage_confidence', a.ai_triage_confidence,
            'is_shadow_vep', (
              a.status IN ('approved', 'converted', 'cancelled', 'rejected', 'withdrawn')
              AND EXISTS (
                SELECT 1 FROM public.members m
                WHERE m.is_active = true
                  AND lower(m.email) = lower(a.email)
                  AND m.created_at < a.created_at
              )
            ),
            'pdf_likely_invalid', EXISTS (
              SELECT 1 FROM storage.objects so
              WHERE so.bucket_id = 'selection-resumes'
                AND so.name = a.resume_storage_path
                AND (so.metadata->>'size')::int < 1000
            )
          ),
          'vep_recon', jsonb_build_object(
            'status_raw', a.vep_status_raw,
            'last_seen_at', a.vep_last_seen_at,
            'reconciled_at', a.vep_reconciled_at
          ),
          'my_eval_status', COALESCE(
            (SELECT CASE WHEN e.submitted_at IS NOT NULL THEN 'submitted' ELSE 'draft' END
              FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id LIMIT 1),
            CASE WHEN EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) THEN 'invited' ELSE 'not_invited' END
          ),
          'my_eval_score', (SELECT e.weighted_subtotal FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL LIMIT 1)
        )
      ORDER BY COALESCE(a.leader_score, a.research_score, a.final_score) DESC NULLS LAST)
      FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id
    ), '[]'::jsonb),
    'stats', v_stats_a || v_stats_b
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_selection_dashboard(text) IS
  'p232 #229 Phase 2: cycle payload now includes sibling leader_extra_cutoff block (target/band/cohort_n/method/calc_at/apps_with_pert/apps_with_score/apps_total) alongside pert_cutoff (objective). Each application row also surfaces leader_extra_pert_score for transparency in cohort coloring + dual-rank visibility.';

-- ----------------------------------------------------------------
-- 4) Drop stale 1-arg overload of get_pert_cutoff_summary
-- ----------------------------------------------------------------
-- The 2-arg overload with p_score_column DEFAULT 'objective_score_avg' is
-- functionally identical when score_column is omitted (returns the same
-- objective summary), AND extends to leader_extra. Keeping the 1-arg
-- overload would cause PostgREST to dispatch to the OLD body when callers
-- omit p_score_column, silently leaking the pre-p232 read surface (no
-- leader_extra support). Drop it.
DROP FUNCTION IF EXISTS public.get_pert_cutoff_summary(uuid);

NOTIFY pgrst, 'reload schema';
