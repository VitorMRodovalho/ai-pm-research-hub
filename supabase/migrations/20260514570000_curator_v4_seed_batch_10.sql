-- Decision #1 A: seed view_internal_analytics for volunteer/curator.
-- Destrava Phase B'' batch 10 (3 RPCs admin/curator scope que dependiam
-- desse seed para conversão V3→V4).

INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES ('volunteer', 'curator', 'view_internal_analytics', 'global')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_selection_rankings(p_cycle_code text DEFAULT NULL::text, p_track text DEFAULT 'both'::text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_researcher jsonb;
  v_leader jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: admin/GP/curator only');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found');
  END IF;

  IF p_track IN ('researcher', 'both') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank_researcher,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'status', status,
      'promotion_path', promotion_path
    ) ORDER BY rank_researcher), '[]'::jsonb)
    INTO v_researcher
    FROM public.selection_applications
    WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL;
  END IF;

  IF p_track IN ('leader', 'both') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank_leader,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'leader_score', leader_score,
      'status', status,
      'promotion_path', promotion_path
    ) ORDER BY rank_leader), '[]'::jsonb)
    INTO v_leader
    FROM public.selection_applications
    WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL;
  END IF;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'track', p_track,
    'researcher_track', COALESCE(v_researcher, '[]'::jsonb),
    'leader_track', COALESCE(v_leader, '[]'::jsonb),
    'formula', jsonb_build_object(
      'research_score', 'objective_pert + interview_pert',
      'leader_score', 'research_score * 0.7 + leader_extra_pert * 0.3',
      'tiebreaker', 'Standard Competition Ranking (ISO 80000-2) + applicant_name ASC'
    )
  );
END;
$function$;

COMMENT ON FUNCTION public.get_selection_rankings(text, text) IS
'Phase B''V4 batch 10: dual-track ranking. Authority: view_internal_analytics (admin/GP + sponsor + chapter_liaison + curator).';

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
        'member_credly_url', (SELECT m.credly_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
        'member_photo_url', (SELECT m.photo_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1)
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
      'researcher_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL)
    )
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_selection_dashboard(text) IS
'Phase B''V4 batch 10: cycle dashboard. Authority: view_internal_analytics (admin/GP + sponsor + chapter_liaison + curator).';

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

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
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

COMMENT ON FUNCTION public.get_selection_pipeline_metrics(uuid, text) IS
'Phase B''V4 batch 10: funil métricas. Authority: view_internal_analytics (admin/GP + sponsor + chapter_liaison + curator).';

NOTIFY pgrst, 'reload schema';
