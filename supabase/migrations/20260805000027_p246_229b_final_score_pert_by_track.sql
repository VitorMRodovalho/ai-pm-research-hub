-- p246 #229b Foundation — Final-score PERT régua by track (researcher vs leader)
--
-- WHAT: Add final_score_pert_* columns on selection_applications (track-resolved per app)
--       + extend _compute_pert_cutoff_core to handle 'final_score' column
--       + extend recompute_all_active_pert_cutoffs to compute for both tracks
--       + extend get_selection_dashboard payload (cycle-level blocks + per-app fields + interview_score visibility).
--
-- WHY: PM dispatch (#229b) — surface "PERT do final_score por tipo de vaga/trilha" so PM can
--      see, per candidate: PERT Objetiva + position, Nota da Entrevista, Score Final, and
--      Score Final's position against the new final régua. Researcher final_score (obj+interview)
--      and leader final_score (0.7r + 0.3le) have different scales, so they need SEPARATE
--      cohorts (mirrors p219 Phase 1's separation of leader_extra cohort from objective).
--
-- ROLLBACK:
--   ALTER TABLE public.selection_applications
--     DROP COLUMN final_score_pert_target,
--     DROP COLUMN final_score_pert_band_lower,
--     DROP COLUMN final_score_pert_band_upper,
--     DROP COLUMN final_score_pert_cutoff_method,
--     DROP COLUMN final_score_pert_cohort_n,
--     DROP COLUMN final_score_pert_calc_at;
--   -- Restore _compute_pert_cutoff_core + recompute_all_active_pert_cutoffs + get_selection_dashboard
--   -- from pre-p246 versions (p197c + p232 #229 Phase 2 baselines).
--
-- NOT in scope (per PM constraints): no interview band (interview score has no PERT régua); no
--   auto status changes (PM-approved policy required); leader_extra stays separate (not mixed
--   into objective).

-- ============================================================================
-- 1. Schema: 6 new columns on selection_applications (track-resolved per app)
-- ============================================================================

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS final_score_pert_target numeric,
  ADD COLUMN IF NOT EXISTS final_score_pert_band_lower numeric,
  ADD COLUMN IF NOT EXISTS final_score_pert_band_upper numeric,
  ADD COLUMN IF NOT EXISTS final_score_pert_cutoff_method text,
  ADD COLUMN IF NOT EXISTS final_score_pert_cohort_n integer,
  ADD COLUMN IF NOT EXISTS final_score_pert_calc_at timestamptz;

COMMENT ON COLUMN public.selection_applications.final_score_pert_target IS
  'p246 #229b — PERT régua target for final_score, track-resolved per app at recompute time. Researcher-track app gets researcher cohort target; leader-track app gets leader cohort target.';

-- ============================================================================
-- 2. Extend _compute_pert_cutoff_core to support final_score column
--    (CREATE OR REPLACE — same 5-arg signature, no consumer break)
-- ============================================================================

CREATE OR REPLACE FUNCTION public._compute_pert_cutoff_core(
  p_cycle_id uuid,
  p_role text DEFAULT 'researcher'::text,
  p_filter_active_only boolean DEFAULT true,
  p_score_column text DEFAULT 'objective_score_avg'::text,
  p_actor_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_cycle record;
  v_cohort record;
  v_target numeric;
  v_band_lower numeric;
  v_band_upper numeric;
  v_method text;
  v_n int;
  v_updated_rows int;
  v_fallback_target numeric;
  v_is_leader_extra boolean;
  v_is_final_score boolean;
BEGIN
  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score', 'leader_extra_pert_score') THEN
    RETURN jsonb_build_object(
      'error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg', 'final_score', 'research_score', 'leader_extra_pert_score'),
      'received', p_score_column
    );
  END IF;

  v_is_leader_extra := (p_score_column = 'leader_extra_pert_score');
  v_is_final_score := (p_score_column = 'final_score');

  SELECT sc.id, sc.cycle_code INTO v_cycle FROM public.selection_cycles sc WHERE sc.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('error', 'cycle_not_found', 'cycle_id', p_cycle_id);
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
        WHEN 'leader_extra_pert_score' THEN sa.leader_extra_pert_score
      END AS s
    FROM public.selection_applications sa
    WHERE sa.cycle_id IN (SELECT id FROM prior_cycles)
      AND sa.role_applied = p_role
      AND sa.status = 'approved'
      AND CASE p_score_column
            WHEN 'objective_score_avg' THEN sa.objective_score_avg IS NOT NULL
            WHEN 'final_score' THEN sa.final_score IS NOT NULL
            WHEN 'research_score' THEN sa.research_score IS NOT NULL
            WHEN 'leader_extra_pert_score' THEN sa.leader_extra_pert_score IS NOT NULL
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
  SELECT COUNT(*)::int AS n, MIN(s) AS s_min, MAX(s) AS s_max, AVG(s) AS s_avg
  INTO v_cohort FROM cohort_apps;

  v_n := COALESCE(v_cohort.n, 0);

  IF v_n >= 10 THEN
    v_target := (2 * v_cohort.s_min + 4 * v_cohort.s_avg + 2 * v_cohort.s_max) / 8;
    v_method := 'dynamic';
  ELSE
    -- p246 #229b: fallback lookup, scoped per-column AND track-aware for final_score
    -- (final_score is per-track; mixing researcher/leader scales would be misleading).
    IF v_is_final_score THEN
      SELECT MAX(final_score_pert_target)
      INTO v_fallback_target
      FROM public.selection_applications
      WHERE cycle_id != p_cycle_id
        AND role_applied = p_role
        AND final_score_pert_target IS NOT NULL;
    ELSE
      SELECT MAX(CASE WHEN v_is_leader_extra THEN leader_extra_pert_target ELSE pert_target_score END)
      INTO v_fallback_target
      FROM public.selection_applications
      WHERE cycle_id != p_cycle_id
        AND CASE WHEN v_is_leader_extra THEN leader_extra_pert_target IS NOT NULL ELSE pert_target_score IS NOT NULL END;
    END IF;
    IF v_fallback_target IS NULL THEN
      v_target := NULL; v_method := 'disabled';
    ELSE
      v_target := v_fallback_target; v_method := 'historical_fallback';
    END IF;
  END IF;

  IF v_target IS NOT NULL THEN
    v_band_lower := v_target * 0.90;
    v_band_upper := v_target * 1.10;
  END IF;

  -- p246 #229b: per-column write branch — final_score is TRACK-SCOPED (only apps with
  -- matching role_applied get the régua, since per-track cohorts have distinct scales).
  IF v_is_leader_extra THEN
    UPDATE public.selection_applications
    SET leader_extra_pert_target = v_target,
        leader_extra_pert_band_lower = v_band_lower,
        leader_extra_pert_band_upper = v_band_upper,
        leader_extra_pert_cutoff_method = v_method,
        leader_extra_pert_cohort_n = v_n,
        leader_extra_pert_calc_at = now()
    WHERE cycle_id = p_cycle_id;
  ELSIF v_is_final_score THEN
    UPDATE public.selection_applications
    SET final_score_pert_target = v_target,
        final_score_pert_band_lower = v_band_lower,
        final_score_pert_band_upper = v_band_upper,
        final_score_pert_cutoff_method = v_method,
        final_score_pert_cohort_n = v_n,
        final_score_pert_calc_at = now()
    WHERE cycle_id = p_cycle_id
      AND role_applied = p_role;
  ELSE
    UPDATE public.selection_applications
    SET pert_target_score = v_target,
        pert_band_lower = v_band_lower,
        pert_band_upper = v_band_upper,
        pert_cutoff_method = v_method,
        pert_cohort_n = v_n,
        pert_calc_at = now()
    WHERE cycle_id = p_cycle_id;
  END IF;
  GET DIAGNOSTICS v_updated_rows = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    p_actor_id, 'pert_cutoff_computed', 'selection_cycle', p_cycle_id,
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
    jsonb_build_object('source', '_compute_pert_cutoff_core', 'actor_kind', CASE WHEN p_actor_id IS NULL THEN 'system' ELSE 'human' END)
  );

  RETURN jsonb_build_object(
    'success', true, 'cycle_id', p_cycle_id, 'cycle_code', v_cycle.cycle_code,
    'role', p_role, 'score_column_used', p_score_column,
    'cohort_n', v_n,
    'cohort_stats', jsonb_build_object('min', v_cohort.s_min, 'max', v_cohort.s_max, 'avg', v_cohort.s_avg),
    'target_score', v_target, 'band_lower', v_band_lower, 'band_upper', v_band_upper,
    'method', v_method, 'rows_updated', v_updated_rows, 'computed_at', now()
  );
END;
$$;

-- ============================================================================
-- 3. Extend recompute_all_active_pert_cutoffs to compute final_score per track
--    (CREATE OR REPLACE — no-arg signature preserved)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.recompute_all_active_pert_cutoffs()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_cycle record;
  v_results jsonb := '[]'::jsonb;
  v_n int := 0;
  v_result_obj jsonb;
  v_result_le jsonb;
  v_result_fs_researcher jsonb;
  v_result_fs_leader jsonb;
BEGIN
  FOR v_cycle IN
    SELECT id, cycle_code, phase FROM public.selection_cycles
    WHERE phase IN ('evaluating', 'interviews', 'open_apps')
    ORDER BY created_at DESC
  LOOP
    v_result_obj := public._compute_pert_cutoff_core(v_cycle.id, 'researcher', true, 'objective_score_avg', NULL);
    v_result_le := public._compute_pert_cutoff_core(v_cycle.id, 'leader', true, 'leader_extra_pert_score', NULL);
    -- p246 #229b: also compute final_score régua per track (researcher cohort + leader cohort)
    v_result_fs_researcher := public._compute_pert_cutoff_core(v_cycle.id, 'researcher', true, 'final_score', NULL);
    v_result_fs_leader := public._compute_pert_cutoff_core(v_cycle.id, 'leader', true, 'final_score', NULL);
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'phase', v_cycle.phase,
      'objective_result', v_result_obj,
      'leader_extra_result', v_result_le,
      'final_score_researcher_result', v_result_fs_researcher,
      'final_score_leader_result', v_result_fs_leader
    ));
    v_n := v_n + 1;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'pert_cutoff_recompute_batch', 'selection_cycles', NULL,
    jsonb_build_object('cycles_processed', v_n, 'per_cycle', v_results),
    jsonb_build_object(
      'source', 'recompute_all_active_pert_cutoffs',
      'dimensions', jsonb_build_array('objective', 'leader_extra', 'final_score_researcher', 'final_score_leader')
    )
  );

  RETURN jsonb_build_object('success', true, 'cycles_processed', v_n, 'per_cycle', v_results);
END;
$$;

-- ============================================================================
-- 4. Extend get_selection_dashboard payload
--    (CREATE OR REPLACE — same 1-arg signature p_cycle_code text)
--    Adds: cycle.final_score_cutoff_researcher + cycle.final_score_cutoff_leader (2 blocks)
--          + applications[i] gains: interview_score, final_score_pert_target/band_lower/
--            band_upper/cutoff_method/cohort_n/calc_at (7 new per-app fields in chunk 2 to
--            stay under PG 100-arg cap on chunk 1).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_selection_dashboard(p_cycle_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
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
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
      -- p246 #229b: final_score régua per track (separate cohorts: researcher pool vs leader pool)
      'final_score_cutoff_researcher', (SELECT jsonb_build_object(
        'target_score', MAX(final_score_pert_target),
        'band_lower', MAX(final_score_pert_band_lower),
        'band_upper', MAX(final_score_pert_band_upper),
        'cohort_n', MAX(final_score_pert_cohort_n),
        'method', MAX(final_score_pert_cutoff_method),
        'calc_at', MAX(final_score_pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE final_score_pert_target IS NOT NULL),
        'apps_with_score', COUNT(*) FILTER (WHERE final_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND role_applied = 'researcher'),
      'final_score_cutoff_leader', (SELECT jsonb_build_object(
        'target_score', MAX(final_score_pert_target),
        'band_lower', MAX(final_score_pert_band_lower),
        'band_upper', MAX(final_score_pert_band_upper),
        'cohort_n', MAX(final_score_pert_cohort_n),
        'method', MAX(final_score_pert_cutoff_method),
        'calc_at', MAX(final_score_pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE final_score_pert_target IS NOT NULL),
        'apps_with_score', COUNT(*) FILTER (WHERE final_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND role_applied = 'leader')
    ) FROM public.selection_cycles c WHERE c.id = v_cycle_id),
    'applications', COALESCE((
      SELECT jsonb_agg(
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
          'leader_extra_pert_score', a.leader_extra_pert_score
        ) || jsonb_build_object(
          -- p246 #229b: interview_score + final_score per-app PERT fields (chunk 2 to stay under PG 100-arg cap)
          'interview_score', a.interview_score,
          'final_score_pert_target', a.final_score_pert_target,
          'final_score_pert_band_lower', a.final_score_pert_band_lower,
          'final_score_pert_band_upper', a.final_score_pert_band_upper,
          'final_score_pert_cutoff_method', a.final_score_pert_cutoff_method,
          'final_score_pert_cohort_n', a.final_score_pert_cohort_n,
          'final_score_pert_calc_at', a.final_score_pert_calc_at,
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
$$;

-- ============================================================================
-- 5. Reload PostgREST schema cache
-- ============================================================================

NOTIFY pgrst, 'reload schema';
