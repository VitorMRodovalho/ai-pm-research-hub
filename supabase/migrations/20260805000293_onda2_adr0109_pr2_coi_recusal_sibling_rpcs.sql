-- ADR-0109 PR-2 — replicate the selection COI recusal gate into the sibling selection surfaces.
--
-- ADR-0109 (WS-4) introduced selection_coi_recused(p_caller_id, p_cycle_id) and gated get_selection_rankings
-- (the scores surface). This fast-follow extends the SAME gate to the remaining surfaces that expose
-- candidate data and are reachable by a view_internal_analytics / curate_content holder who is also an
-- active candidate in the cycle:
--   get_selection_dashboard, get_selection_pipeline_metrics, get_selection_health,
--   get_application_score_breakdown (also backs the MCP get_application_detail tool), get_vep_divergence_report.
--
-- Mechanics: each body is the live pg_get_functiondef body with a single gate block injected right after the
-- cycle is resolved (and, for the application-scoped score breakdown, after the application row is loaded and
-- BEFORE the PII access log). GP/superadmin is never recused (the helper short-circuits on manage_platform).
-- Restoration is automatic — recusal is derived (candidate-in-cycle), not a stored flag.
--
-- Applied to prod via apply_migration using a DO block that replace()s a single asserted anchor per function
-- (preserving each body byte-for-byte); this file is the byte-faithful post-apply SSOT for the drift gate.
-- 0 instances at apply time (no access holder is an active candidate in cycle4-2026) → forward-defense.

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

  -- ADR-0109 PR-2 COI recusal: an active candidate in this cycle is recused from this selection surface.
  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
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
          'objective_rank', a.objective_rank,
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
          'interview_score', a.interview_score,
          'cutoff_approved_email_sent_at', a.cutoff_approved_email_sent_at,
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
            'video_screening_done', EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded', 'transcribing', 'transcribed', 'opted_out')),
            'interview_stuck', (
              a.status = 'interview_scheduled'
              AND EXISTS (
                SELECT 1 FROM public.selection_interviews si
                WHERE si.application_id = a.id
                  AND si.status = 'scheduled'
                  AND si.conducted_at IS NULL
                  AND si.scheduled_at IS NOT NULL
                  AND si.scheduled_at < now() - COALESCE(
                        (SELECT value_interval FROM public.sla_policies WHERE policy_key = 'stuck_scheduled_grace'),
                        interval '48 hours')
              )
            )
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
            'pmi_memberships', COALESCE(a.pmi_memberships, '[]'::jsonb),
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
            'reconciled_at', a.vep_reconciled_at,
            'offer_expires_at', a.vep_offer_expires_at,
            'expired_at', a.vep_expired_at
          ),
          'my_eval_status', COALESCE(
            (SELECT CASE WHEN e.submitted_at IS NOT NULL THEN 'submitted' ELSE 'draft' END
              FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id LIMIT 1),
            CASE WHEN EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) THEN 'invited' ELSE 'not_invited' END
          ),
          'my_eval_score', (SELECT e.weighted_subtotal FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL LIMIT 1)
        )
      ORDER BY COALESCE(a.leader_score, a.research_score, a.final_score) DESC NULLS LAST)
      FROM (
        SELECT
          sa.*,
          ROW_NUMBER() OVER (
            PARTITION BY sa.role_applied
            ORDER BY sa.objective_score_avg DESC NULLS LAST, sa.id ASC
          )::int AS objective_rank
        FROM public.selection_applications sa
        WHERE sa.cycle_id = v_cycle_id
      ) a
    ), '[]'::jsonb),
    'stats', v_stats_a || v_stats_b
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_selection_pipeline_metrics(p_cycle_id uuid DEFAULT NULL::uuid, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_funnel jsonb;
  v_by_chapter jsonb;
  v_conversion_rate numeric;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- V4: view_internal_analytics covers admin/GP + sponsor + chapter_liaison
  IF NOT (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  IF p_cycle_id IS NOT NULL THEN
    v_cycle_id := p_cycle_id;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles
    ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'no_cycle_found');
  END IF;

  -- ADR-0109 PR-2 COI recusal: an active candidate in this cycle is recused from this selection surface.
  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  SELECT jsonb_build_object(
    'total_applications', COUNT(*),
    'screening', COUNT(*) FILTER (WHERE status = 'screening'),
    'objective_eval', COUNT(*) FILTER (WHERE status = 'objective_eval'),
    'passed_cutoff', COUNT(*) FILTER (WHERE status NOT IN ('submitted', 'screening', 'objective_eval', 'objective_cutoff', 'rejected', 'withdrawn', 'cancelled')),
    'interview_pending', COUNT(*) FILTER (WHERE status = 'interview_pending'),
    'interview_scheduled', COUNT(*) FILTER (WHERE status = 'interview_scheduled'),
    'interview_done', COUNT(*) FILTER (WHERE status = 'interview_done'),
    'interview_noshow', COUNT(*) FILTER (WHERE status = 'interview_noshow'),
    'final_eval', COUNT(*) FILTER (WHERE status = 'final_eval'),
    'approved', COUNT(*) FILTER (WHERE status = 'approved'),
    'rejected', COUNT(*) FILTER (WHERE status = 'rejected'),
    'waitlist', COUNT(*) FILTER (WHERE status = 'waitlist'),
    'converted', COUNT(*) FILTER (WHERE status = 'converted'),
    'withdrawn', COUNT(*) FILTER (WHERE status = 'withdrawn')
  ) INTO v_funnel
  FROM public.selection_applications
  WHERE cycle_id = v_cycle_id
    AND (p_chapter IS NULL OR chapter = p_chapter);

  SELECT jsonb_agg(
    jsonb_build_object(
      'chapter', chapter,
      'total', total,
      'approved', approved,
      'rejected', rejected,
      'waitlist', waitlist,
      'converted', converted,
      'avg_score', avg_score
    )
  ) INTO v_by_chapter
  FROM (
    SELECT
      sa.chapter,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE sa.status = 'approved') AS approved,
      COUNT(*) FILTER (WHERE sa.status = 'rejected') AS rejected,
      COUNT(*) FILTER (WHERE sa.status = 'waitlist') AS waitlist,
      COUNT(*) FILTER (WHERE sa.status = 'converted') AS converted,
      ROUND(AVG(sa.final_score), 2) AS avg_score
    FROM public.selection_applications sa
    WHERE sa.cycle_id = v_cycle_id
      AND (p_chapter IS NULL OR sa.chapter = p_chapter)
    GROUP BY sa.chapter
    ORDER BY sa.chapter
  ) sub;

  v_conversion_rate := CASE
    WHEN (v_funnel->>'total_applications')::int > 0
    THEN ROUND(((v_funnel->>'approved')::int + (v_funnel->>'converted')::int)::numeric /
         (v_funnel->>'total_applications')::int * 100, 1)
    ELSE 0
  END;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'chapter_filter', p_chapter,
    'funnel', v_funnel,
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'conversion_rate', v_conversion_rate
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_selection_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_active_cycle jsonb;
  v_application_counts jsonb;
  v_stale_tokens integer;
  v_welcome_backlog integer;
  v_crons jsonb;
  v_health_signal text;
  v_critical_cron_down boolean := false;
  v_cron_names text[] := ARRAY[
    'send-notification-emails',
    'retry-pending-ai-analyses',
    'nudge-reschedule-pending-daily',
    'detect-onboarding-overdue-daily'
  ];
  v_cron_name text;
  v_cron_data jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  -- Active cycle
  SELECT jsonb_build_object(
    'id', c.id,
    'cycle_code', c.cycle_code,
    'title', c.title,
    'status', c.status,
    'phase', c.phase,
    'created_at', c.created_at
  )
  INTO v_active_cycle
  FROM public.selection_cycles c
  ORDER BY c.created_at DESC
  LIMIT 1;

  -- ADR-0109 PR-2 COI recusal: an active candidate in the active cycle is recused from this surface.
  IF v_active_cycle IS NOT NULL AND public.selection_coi_recused(v_caller_id, (v_active_cycle->>'id')::uuid) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  -- Application counts no ciclo ativo
  SELECT jsonb_build_object(
    'total', count(*),
    'submitted', count(*) FILTER (WHERE status='submitted'),
    'screening', count(*) FILTER (WHERE status='screening'),
    'objective_eval', count(*) FILTER (WHERE status='objective_eval'),
    'interview_pending', count(*) FILTER (WHERE status='interview_pending'),
    'interview_scheduled', count(*) FILTER (WHERE status='interview_scheduled'),
    'interview_done', count(*) FILTER (WHERE status='interview_done'),
    'final_eval', count(*) FILTER (WHERE status='final_eval'),
    'approved', count(*) FILTER (WHERE status IN ('approved','converted')),
    'rejected', count(*) FILTER (WHERE status IN ('rejected','objective_cutoff')),
    'cancelled', count(*) FILTER (WHERE status IN ('cancelled','withdrawn')),
    'waitlist', count(*) FILTER (WHERE status='waitlist'),
    'created_last_7d', count(*) FILTER (WHERE created_at >= now() - interval '7 days')
  )
  INTO v_application_counts
  FROM public.selection_applications
  WHERE cycle_id = (v_active_cycle->>'id')::uuid;

  -- Stale tokens: onboarding_tokens não consumidos há >48h
  SELECT count(*) INTO v_stale_tokens
  FROM public.onboarding_tokens t
  JOIN public.selection_applications a ON a.id = t.source_id
  WHERE t.source_type = 'pmi_application'
    AND COALESCE(t.access_count, 0) = 0
    AND t.created_at < now() - interval '48 hours'
    AND a.cycle_id = (v_active_cycle->>'id')::uuid;

  -- Welcome backlog: approved sem token consumed (proxy para welcome não dispatched)
  SELECT count(*) INTO v_welcome_backlog
  FROM public.selection_applications a
  WHERE a.cycle_id = (v_active_cycle->>'id')::uuid
    AND a.status IN ('approved','converted')
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_tokens t
      WHERE t.source_id = a.id AND t.source_type = 'pmi_application' AND COALESCE(t.access_count, 0) > 0
    );

  -- Cron health para cada cron relevante
  v_crons := '[]'::jsonb;
  FOREACH v_cron_name IN ARRAY v_cron_names LOOP
    SELECT jsonb_build_object(
      'jobname', v_cron_name,
      'active', j.active,
      'schedule', j.schedule,
      'last_run_at', (
        SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid
      ),
      'last_status', (
        SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid
        ORDER BY start_time DESC LIMIT 1
      ),
      'last_5_status', (
        SELECT jsonb_agg(jsonb_build_object('start', start_time, 'status', status, 'msg', return_message) ORDER BY start_time DESC)
        FROM (
          SELECT start_time, status, return_message FROM cron.job_run_details d2
          WHERE d2.jobid = j.jobid ORDER BY start_time DESC LIMIT 5
        ) t
      )
    )
    INTO v_cron_data
    FROM cron.job j
    WHERE j.jobname = v_cron_name;

    IF v_cron_data IS NULL THEN
      v_cron_data := jsonb_build_object(
        'jobname', v_cron_name,
        'active', false,
        'error', 'cron job not registered'
      );
      -- Critical: 4 monitored crons, all should exist
      v_critical_cron_down := true;
    END IF;

    v_crons := v_crons || jsonb_build_array(v_cron_data);
  END LOOP;

  -- Health signal
  v_health_signal := CASE
    WHEN v_critical_cron_down OR v_stale_tokens >= 5 THEN 'red'
    WHEN v_stale_tokens > 0 OR v_welcome_backlog > 0 THEN 'yellow'
    ELSE 'green'
  END;

  RETURN jsonb_build_object(
    'active_cycle', COALESCE(v_active_cycle, jsonb_build_object('error', 'no cycle found')),
    'application_counts', v_application_counts,
    'stale_tokens_48h', v_stale_tokens,
    'welcome_backlog', v_welcome_backlog,
    'crons', v_crons,
    'health_signal', v_health_signal,
    'fetched_at', now()
  );
END;
$function$;

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

  -- ADR-0109 PR-2 COI recusal: an active candidate in this application cycle is recused.
  IF public.selection_coi_recused(v_caller.id, v_app.cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
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

CREATE OR REPLACE FUNCTION public.get_vep_divergence_report()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_selection jsonb;
  v_onboarding jsonb;
  v_active jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ADR-0109 PR-2 COI recusal: this report exposes candidate PII across ALL open cycles; recuse a
  -- caller who is an active candidate in ANY currently-open cycle (not only the latest).
  IF EXISTS (
    SELECT 1 FROM public.selection_cycles sc
    WHERE sc.status = 'open' AND public.selection_coi_recused(v_caller_id, sc.id)
  ) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) em um ciclo aberto — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id,
    'applicant_name', a.applicant_name,
    'email', a.email,
    'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code,
    'nucleo_status', a.status,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Comitê: marcar withdrawn/rejected no Núcleo'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_selection
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.vep_status_raw IN ('Withdrawn', 'Declined', 'OfferNotExtended')
    AND a.status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')
    AND c.status = 'open'
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id,
    'applicant_name', a.applicant_name,
    'email', a.email,
    'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code,
    'nucleo_status', a.status,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Recruiter PMI: marcar Complete/OfferExtended no VEP'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_onboarding
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.status IN ('approved', 'converted')
    AND a.vep_status_raw IN ('Submitted', 'Active')
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'member_id', m.id,
    'member_name', m.name,
    'email', m.email,
    'pmi_id', a.pmi_id,
    'is_active', m.is_active,
    'last_engagement_end_date', latest_eng.end_date,
    'latest_application_id', a.id,
    'cycle_code', c.cycle_code,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Recruiter PMI: marcar Complete no VEP (membro offboarded)'
  ) ORDER BY m.name), '[]'::jsonb) INTO v_active
  FROM public.members m
  JOIN LATERAL (
    SELECT sa.* FROM public.selection_applications sa
    WHERE lower(sa.email) = lower(m.email)
      AND sa.vep_status_raw IS NOT NULL
    ORDER BY sa.imported_at DESC NULLS LAST
    LIMIT 1
  ) a ON true
  LEFT JOIN public.selection_cycles c ON c.id = a.cycle_id
  LEFT JOIN LATERAL (
    SELECT end_date FROM public.engagements e
    WHERE e.person_id = m.person_id
      AND e.end_date IS NOT NULL
    ORDER BY e.end_date DESC
    LIMIT 1
  ) latest_eng ON true
  WHERE m.is_active = false
    AND a.vep_status_raw IN ('Submitted', 'Active')
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  v_result := jsonb_build_object(
    'selection_divergent', v_selection,
    'onboarding_divergent', v_onboarding,
    'active_members_divergent', v_active,
    'summary', jsonb_build_object(
      'total_divergent', (
        jsonb_array_length(v_selection) +
        jsonb_array_length(v_onboarding) +
        jsonb_array_length(v_active)
      ),
      'selection_count', jsonb_array_length(v_selection),
      'onboarding_count', jsonb_array_length(v_onboarding),
      'active_members_count', jsonb_array_length(v_active),
      'generated_at', now()
    )
  );

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
