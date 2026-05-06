-- ARM Onda 2.3: my_eval_status + my_eval_score em get_selection_dashboard
--
-- Resolve FP-4 ux-leader: avaliador não vê na lista o estado de SUA avaliação para
-- cada candidato (precisa abrir modal + tab para descobrir). Adiciona 2 campos
-- por application + 2 stats rollup:
--   - my_eval_status: 'submitted' | 'draft' | 'invited' | 'not_invited'
--   - my_eval_score: weighted_subtotal se submitted, NULL caso contrário
--   - stats.my_evals_submitted: count submitted pelo caller no ciclo
--   - stats.my_evals_pending: count invited mas ainda não avaliados
--
-- Source: selection_evaluations.evaluator_id = caller, com fallback em
-- notifications.peer_review_requested (invited) ou ausência (not_invited).
--
-- Rollback: restaurar versão anterior do RPC (sem os 2 fields + 2 stats).

CREATE OR REPLACE FUNCTION public.get_selection_dashboard(p_cycle_code text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
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
        -- p92 Phase D indicators (5 new fields)
        'ai_analysis_done', (a.consent_ai_analysis_at IS NOT NULL AND a.ai_analysis IS NOT NULL),
        'peer_eval_count', (
          SELECT count(*)::int FROM public.selection_evaluations e WHERE e.application_id = a.id
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
        -- p107 Onda 2.3: avaliador-personal status (FP-4 ux-leader)
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
      -- p92 Phase D indicator stats (rollup counts)
      'ai_analysis_done_count', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NOT NULL AND ai_analysis IS NOT NULL),
      'with_peer_evals_2plus', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND (SELECT count(*) FROM public.selection_evaluations e WHERE e.application_id = a.id) >= 2),
      'with_interview_scheduled', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled','completed','rescheduled'))),
      -- p107 Onda 2.3: rollup do avaliador
      'my_evals_submitted', (SELECT count(*) FROM public.selection_evaluations e JOIN public.selection_applications a ON a.id = e.application_id WHERE a.cycle_id = v_cycle_id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL),
      'my_evals_pending', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) AND NOT EXISTS (SELECT 1 FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id))
    )
  ) INTO v_result;
  RETURN v_result;
END;
$func$;

NOTIFY pgrst, 'reload schema';
