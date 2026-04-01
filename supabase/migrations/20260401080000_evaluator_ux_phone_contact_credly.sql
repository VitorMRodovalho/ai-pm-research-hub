-- Evaluator UX: phone/WhatsApp, inline contact edit, Credly link, context panel
-- ============================================================================

-- Update get_selection_dashboard to include phone + member Credly/photo
DROP FUNCTION IF EXISTS get_selection_dashboard(text);
CREATE FUNCTION get_selection_dashboard(p_cycle_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller record; v_cycle_id uuid; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager') AND NOT (v_caller.designations && ARRAY['curator'])) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found', 'cycle', null, 'applications', '[]'::jsonb, 'stats', jsonb_build_object('total', 0));
  END IF;

  SELECT jsonb_build_object(
    'cycle', (SELECT jsonb_build_object(
      'id', c.id, 'cycle_code', c.cycle_code, 'title', c.title, 'status', c.status,
      'interview_booking_url', c.interview_booking_url,
      'interview_questions', COALESCE(c.interview_questions, '[]'::jsonb)
    ) FROM selection_cycles c WHERE c.id = v_cycle_id),
    'applications', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'applicant_name', a.applicant_name, 'email', a.email,
        'phone', a.phone,
        'role_applied', a.role_applied, 'chapter', a.chapter, 'status', a.status,
        'objective_score', a.objective_score_avg, 'final_score', a.final_score,
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
        'member_credly_url', (SELECT m.credly_url FROM members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
        'member_photo_url', (SELECT m.photo_url FROM members m WHERE lower(m.email) = lower(a.email) LIMIT 1)
      ) ORDER BY a.final_score DESC NULLS LAST)
      FROM selection_applications a WHERE a.cycle_id = v_cycle_id
    ), '[]'::jsonb),
    'stats', jsonb_build_object(
      'total', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id),
      'approved', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted')),
      'rejected', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('rejected', 'objective_cutoff')),
      'pending', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')),
      'cancelled', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('cancelled', 'withdrawn')),
      'waitlist', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status = 'waitlist')
    )
  ) INTO v_result;
  RETURN v_result;
END;
$$;

-- RPC to update phone/linkedin inline from the modal
CREATE OR REPLACE FUNCTION update_application_contact(
  p_application_id uuid,
  p_phone text DEFAULT NULL,
  p_linkedin_url text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager') AND NOT (v_caller.designations && ARRAY['curator'])) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE selection_applications SET
    phone = COALESCE(NULLIF(p_phone, ''), phone),
    linkedin_url = COALESCE(NULLIF(p_linkedin_url, ''), linkedin_url),
    updated_at = now()
  WHERE id = p_application_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

NOTIFY pgrst, 'reload schema';
