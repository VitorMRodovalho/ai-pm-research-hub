-- p152 W3+ (2026-05-12) — add meta.interview_next_at + has_interview_today to dashboard RPC.
--
-- Context: PM ask post Wave 3.7 close — quero filter "Entrevistas hoje" no
-- /admin/selection para correr avaliações objetivas ANTES da entrevista no mesmo
-- dia. Current dashboard RPC has only `meta.interview_scheduled` (boolean) — não
-- dá pra filtrar por data.
--
-- Two new fields in meta sub-object:
--   interview_next_at (timestamptz) — MIN(scheduled_at) where status='scheduled'/'rescheduled'
--     AND scheduled_at >= now() - 12h (próxima entrevista upcoming; tolerates same-day).
--     Earlier MAX-based attempt missed candidates with multiple future interviews
--     (Bruna Zomer: today 18:00 + May 14 18:30 — MAX returned May 14, hiding today).
--   has_interview_today (boolean) — EXISTS check for today in America/Sao_Paulo tz.
--     Dedicated boolean = canonical signal for the "Entrevistas hoje" filter.
--
-- Stats addition: with_interview_today counter (parallel to with_interview_scheduled).
--
-- meta sub-object grows 4 → 6 fields (8 → 12 inner args). Top-level outer args
-- unchanged (~96 outer; healthy margin under 100-arg ceiling).

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

  SELECT jsonb_build_object(
    'cycle', (SELECT jsonb_build_object(
      'id', c.id, 'cycle_code', c.cycle_code, 'title', c.title, 'status', c.status,
      'interview_booking_url', c.interview_booking_url,
      'interview_questions', COALESCE(c.interview_questions, '[]'::jsonb)
    ) FROM public.selection_cycles c WHERE c.id = v_cycle_id),
    'applications', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'applicant_name', a.applicant_name, 'email', a.email,
        'phone', a.phone,
        'role_applied', a.role_applied, 'chapter', a.chapter, 'status', a.status,
        'objective_score', a.objective_score_avg, 'final_score', a.final_score,
        'research_score', a.research_score, 'leader_score', a.leader_score,
        'rank_researcher', a.rank_researcher, 'rank_leader', a.rank_leader,
        'promotion_path', a.promotion_path, 'linked_application_id', a.linked_application_id,
        'rank_chapter', a.rank_chapter, 'rank_overall', a.rank_overall,
        'linkedin_url', a.linkedin_url, 'resume_url', a.resume_url,
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
        'member_credly_url', (SELECT m.credly_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
        'member_photo_url', (SELECT m.photo_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
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
              AND si.status IN ('scheduled', 'rescheduled')
              AND si.scheduled_at >= now() - interval '12 hours'
          ),
          'has_interview_today', EXISTS (
            SELECT 1 FROM public.selection_interviews si
            WHERE si.application_id = a.id
              AND si.status IN ('scheduled', 'rescheduled')
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
          )
        ),
        'my_eval_status', COALESCE(
          (SELECT CASE WHEN e.submitted_at IS NOT NULL THEN 'submitted' ELSE 'draft' END
            FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id LIMIT 1),
          CASE WHEN EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) THEN 'invited' ELSE 'not_invited' END
        ),
        'my_eval_score', (SELECT e.weighted_subtotal FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL LIMIT 1)
      ) ORDER BY COALESCE(a.leader_score, a.research_score, a.final_score) DESC NULLS LAST)
      FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id
    ), '[]'::jsonb),
    'stats', jsonb_build_object(
      'total', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
      'approved', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted')),
      'rejected', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('rejected', 'objective_cutoff')),
      'pending', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')),
      'cancelled', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('cancelled', 'withdrawn')),
      'waitlist', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status = 'waitlist'),
      'leader_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL),
      'researcher_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL),
      'ai_analysis_done_count', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NOT NULL AND ai_analysis IS NOT NULL),
      'with_peer_evals_2plus', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND (SELECT count(DISTINCT e.evaluator_id) FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL) >= 2),
      'with_interview_scheduled', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled','completed','rescheduled'))),
      'with_interview_today', (
        SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id
          AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id
            AND si.status IN ('scheduled', 'rescheduled')
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
    )
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
