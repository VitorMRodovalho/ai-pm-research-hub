-- p150 B-light (2026-05-12) — video screening visibility in admin/selection.
--
-- Why:
--   * Today the dashboard only exposes a binary video_screening_done boolean.
--     PM cannot tell apart "uploaded" / "opted_out" / "no decision yet".
--   * No RPC exists to fetch per-pillar video screening rows for a candidate;
--     RLS on pmi_video_screenings is rpc-only deny-all, so frontend cannot
--     even hit the table.
--
-- What:
--   1) Extend get_selection_dashboard with 3 new aggregate fields per
--      application: video_screening_status_agg, video_screening_uploaded_count,
--      video_screening_total_rows. Existing video_screening_done preserved
--      for backwards compat.
--   2) NEW RPC get_application_video_screenings(p_application_id uuid) returns
--      per-row video screenings ordered by pillar+question_index. Gate:
--      can_by_member(view_internal_analytics) — same gate as
--      get_selection_dashboard. Returns transcription + storage links so
--      committee can review even without an AI subjective score (that's
--      B-full territory; this is just visibility today).
--
-- Rollback: restore previous get_selection_dashboard body from session log
--   snapshot; DROP FUNCTION get_application_video_screenings.

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
        'research_score', a.research_score,
        'leader_score', a.leader_score,
        'rank_researcher', a.rank_researcher,
        'rank_leader', a.rank_leader,
        'promotion_path', a.promotion_path,
        'linked_application_id', a.linked_application_id,
        'rank_chapter', a.rank_chapter, 'rank_overall', a.rank_overall,
        'linkedin_url', a.linkedin_url, 'resume_url', a.resume_url,
        'tags', a.tags, 'feedback', a.feedback,
        'motivation', a.motivation_letter,
        'experience_years', a.seniority_years,
        'membership_status', a.membership_status,
        'certifications', a.certifications,
        'is_returning_member', a.is_returning_member,
        'application_date', a.application_date,
        'academic_background', a.academic_background,
        'areas_of_interest', a.areas_of_interest,
        'availability_declared', a.availability_declared,
        'non_pmi_experience', a.non_pmi_experience,
        'proposed_theme', a.proposed_theme,
        'leadership_experience', a.leadership_experience,
        'created_at', a.created_at,
        'interview_status', a.interview_status,
        'interview_reschedule_reason', a.interview_reschedule_reason,
        'interview_reschedule_requested_at', a.interview_reschedule_requested_at,
        'member_credly_url', (SELECT m.credly_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
        'member_photo_url', (SELECT m.photo_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
        'ai_analysis_done', (a.consent_ai_analysis_at IS NOT NULL AND a.ai_analysis IS NOT NULL),
        'peer_eval_count', (
          SELECT count(*)::int FROM public.selection_evaluations e
          WHERE e.application_id = a.id
            AND e.evaluation_type = 'objective'
            AND e.submitted_at IS NOT NULL
        ),
        'peer_eval_distinct_evaluators', (
          SELECT count(DISTINCT e.evaluator_id)::int FROM public.selection_evaluations e
          WHERE e.application_id = a.id
            AND e.evaluation_type = 'objective'
            AND e.submitted_at IS NOT NULL
        ),
        'peer_invites_pending', (
          SELECT count(*)::int FROM public.notifications n
          WHERE n.type = 'peer_review_requested'
            AND n.source_id = a.id
            AND NOT EXISTS (
              SELECT 1 FROM public.selection_evaluations e2
              WHERE e2.application_id = a.id AND e2.evaluator_id = n.recipient_id
            )
        ),
        'interview_scheduled', EXISTS (
          SELECT 1 FROM public.selection_interviews si
          WHERE si.application_id = a.id
            AND si.status IN ('scheduled', 'completed', 'rescheduled')
        ),
        'token_consumed', EXISTS (
          SELECT 1 FROM public.onboarding_tokens t
          WHERE t.source_id = a.id
            AND t.source_type = 'pmi_application'
            AND COALESCE(t.access_count, 0) > 0
        ),
        'video_screening_done', EXISTS (
          SELECT 1 FROM public.pmi_video_screenings v
          WHERE v.application_id = a.id
            AND v.status IN ('uploaded', 'transcribing', 'transcribed', 'opted_out')
        ),
        -- p150 B-light: tri-state aggregate (uploaded > opted_out > none)
        'video_screening_status_agg', (
          SELECT CASE
            WHEN count(*) = 0 THEN 'none'
            WHEN count(*) FILTER (WHERE v.status IN ('uploaded','transcribing','transcribed')) > 0 THEN 'uploaded'
            WHEN count(*) FILTER (WHERE v.status = 'opted_out') = count(*) THEN 'opted_out'
            ELSE 'partial'
          END
          FROM public.pmi_video_screenings v
          WHERE v.application_id = a.id
        ),
        'video_screening_uploaded_count', (
          SELECT count(*)::int FROM public.pmi_video_screenings v
          WHERE v.application_id = a.id
            AND v.status IN ('uploaded','transcribing','transcribed')
        ),
        'video_screening_total_rows', (
          SELECT count(*)::int FROM public.pmi_video_screenings v
          WHERE v.application_id = a.id
        ),
        'my_eval_status', COALESCE(
          (SELECT
            CASE
              WHEN e.submitted_at IS NOT NULL THEN 'submitted'
              ELSE 'draft'
            END
            FROM public.selection_evaluations e
            WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id
            LIMIT 1),
          CASE
            WHEN EXISTS (
              SELECT 1 FROM public.notifications n
              WHERE n.type = 'peer_review_requested'
                AND n.source_id = a.id
                AND n.recipient_id = v_caller_id
            ) THEN 'invited'
            ELSE 'not_invited'
          END
        ),
        'my_eval_score', (
          SELECT e.weighted_subtotal FROM public.selection_evaluations e
          WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL
          LIMIT 1
        )
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
      'with_peer_evals_2plus', (
        SELECT count(*) FROM public.selection_applications a
        WHERE a.cycle_id = v_cycle_id
          AND (
            SELECT count(DISTINCT e.evaluator_id)
            FROM public.selection_evaluations e
            WHERE e.application_id = a.id
              AND e.evaluation_type = 'objective'
              AND e.submitted_at IS NOT NULL
          ) >= 2
      ),
      'with_interview_scheduled', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled','completed','rescheduled'))),
      -- p150 B-light: video screening rollup
      'with_video_uploaded', (
        SELECT count(*) FROM public.selection_applications a
        WHERE a.cycle_id = v_cycle_id
          AND EXISTS (
            SELECT 1 FROM public.pmi_video_screenings v
            WHERE v.application_id = a.id
              AND v.status IN ('uploaded','transcribing','transcribed')
          )
      ),
      'with_video_opted_out', (
        SELECT count(*) FROM public.selection_applications a
        WHERE a.cycle_id = v_cycle_id
          AND EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id)
          AND NOT EXISTS (
            SELECT 1 FROM public.pmi_video_screenings v
            WHERE v.application_id = a.id
              AND v.status IN ('uploaded','transcribing','transcribed')
          )
      ),
      'my_evals_submitted', (SELECT count(*) FROM public.selection_evaluations e JOIN public.selection_applications a ON a.id = e.application_id WHERE a.cycle_id = v_cycle_id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL),
      'my_evals_pending', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) AND NOT EXISTS (SELECT 1 FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id))
    )
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- NEW RPC: per-application video screening detail (lazy-load on modal tab open)
CREATE OR REPLACE FUNCTION public.get_application_video_screenings(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Same gate as get_selection_dashboard. Committee members (lead/member of the
  -- cycle) and admins reach view_internal_analytics through can() via engagements.
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'application_id', p_application_id,
    'rows', COALESCE(jsonb_agg(jsonb_build_object(
      'id', v.id,
      'pillar', v.pillar,
      'question_index', v.question_index,
      'question_text', v.question_text,
      'status', v.status,
      'storage_provider', v.storage_provider,
      'drive_folder_id', v.drive_folder_id,
      'drive_file_id', v.drive_file_id,
      'drive_file_name', v.drive_file_name,
      'youtube_url', v.youtube_url,
      'duration_seconds', v.duration_seconds,
      'file_size_bytes', v.file_size_bytes,
      'mime_type', v.mime_type,
      'transcription', v.transcription,
      'transcription_provider', v.transcription_provider,
      'transcription_model_version', v.transcription_model_version,
      'transcription_at', v.transcription_at,
      'transcription_confidence', v.transcription_confidence,
      'failure_reason', v.failure_reason,
      'retry_count', v.retry_count,
      'uploaded_at', v.uploaded_at,
      'created_at', v.created_at,
      'updated_at', v.updated_at
    ) ORDER BY v.pillar, v.question_index), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total', count(*),
      'uploaded', count(*) FILTER (WHERE v.status IN ('uploaded','transcribing','transcribed')),
      'opted_out', count(*) FILTER (WHERE v.status = 'opted_out'),
      'failed', count(*) FILTER (WHERE v.status = 'failed'),
      'first_uploaded_at', min(v.uploaded_at) FILTER (WHERE v.uploaded_at IS NOT NULL),
      'last_uploaded_at', max(v.uploaded_at) FILTER (WHERE v.uploaded_at IS NOT NULL),
      'total_duration_seconds', COALESCE(sum(v.duration_seconds) FILTER (WHERE v.status IN ('uploaded','transcribed')), 0)::int
    )
  ) INTO v_result
  FROM public.pmi_video_screenings v
  WHERE v.application_id = p_application_id;

  RETURN COALESCE(v_result, jsonb_build_object(
    'application_id', p_application_id, 'rows', '[]'::jsonb,
    'summary', jsonb_build_object('total', 0, 'uploaded', 0, 'opted_out', 0, 'failed', 0)
  ));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_application_video_screenings(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
