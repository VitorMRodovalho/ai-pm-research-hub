-- #91 G4 — surface offboarding context for returning candidates in selection review.
-- Selection committee gets `is_returning_member=true` from import_vep_applications,
-- but the OFFBOARDING context (return_interest, return_window_suggestion,
-- lessons_learned, recommendation_for_future, reason_category) was orphaned until
-- p45 G3 created member_offboarding_records. This RPC bridges the two.
--
-- Privacy: requires manage_member (selection committee tier).
-- Returns minimal flag set if no member match; null offboarding_context if matched
-- member is currently active (edge case: re-applying mid-cycle without offboarding).
--
-- Rollback: DROP FUNCTION IF EXISTS public.get_application_returning_context(uuid);

CREATE OR REPLACE FUNCTION public.get_application_returning_context(
  p_application_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id           uuid;
  v_can_view_full       boolean;
  v_app                 record;
  v_matched_member      record;
  v_offboard_record     record;
  v_category            record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  SELECT public.can_by_member(v_caller_id, 'manage_member') INTO v_can_view_full;
  IF NOT v_can_view_full THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member action';
  END IF;

  SELECT id, email, applicant_name, cycle_id, status, is_returning_member,
         previous_cycles, application_count
  INTO v_app
  FROM public.selection_applications
  WHERE id = p_application_id;

  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('found', false, 'application_id', p_application_id);
  END IF;

  SELECT id, name, chapter, member_status, operational_role, offboarded_at
  INTO v_matched_member
  FROM public.members
  WHERE lower(email) = lower(v_app.email)
  LIMIT 1;

  IF v_matched_member.id IS NULL THEN
    RETURN jsonb_build_object(
      'found', true,
      'application_id', p_application_id,
      'is_returning_member', v_app.is_returning_member,
      'previous_cycles', to_jsonb(v_app.previous_cycles),
      'application_count', v_app.application_count,
      'matched_member', null,
      'offboarding_context', null
    );
  END IF;

  SELECT *
  INTO v_offboard_record
  FROM public.member_offboarding_records
  WHERE member_id = v_matched_member.id;

  IF v_offboard_record.id IS NULL THEN
    RETURN jsonb_build_object(
      'found', true,
      'application_id', p_application_id,
      'is_returning_member', v_app.is_returning_member,
      'previous_cycles', to_jsonb(v_app.previous_cycles),
      'application_count', v_app.application_count,
      'matched_member', jsonb_build_object(
        'id', v_matched_member.id,
        'name', v_matched_member.name,
        'chapter', v_matched_member.chapter,
        'member_status', v_matched_member.member_status,
        'operational_role', v_matched_member.operational_role,
        'offboarded_at', v_matched_member.offboarded_at
      ),
      'offboarding_context', null
    );
  END IF;

  IF v_offboard_record.reason_category_code IS NOT NULL THEN
    SELECT code, label_pt, is_volunteer_fault, preserves_return_eligibility
    INTO v_category
    FROM public.offboard_reason_categories
    WHERE code = v_offboard_record.reason_category_code;
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'application_id', p_application_id,
    'is_returning_member', v_app.is_returning_member,
    'previous_cycles', to_jsonb(v_app.previous_cycles),
    'application_count', v_app.application_count,
    'matched_member', jsonb_build_object(
      'id', v_matched_member.id,
      'name', v_matched_member.name,
      'chapter', v_matched_member.chapter,
      'member_status', v_matched_member.member_status,
      'operational_role', v_matched_member.operational_role,
      'offboarded_at', v_matched_member.offboarded_at
    ),
    'offboarding_context', jsonb_build_object(
      'record_id', v_offboard_record.id,
      'offboarded_at', v_offboard_record.offboarded_at,
      'offboarded_by', v_offboard_record.offboarded_by,
      'reason_category_code', v_offboard_record.reason_category_code,
      'reason_category_label_pt', v_category.label_pt,
      'is_volunteer_fault', COALESCE(v_category.is_volunteer_fault, false),
      'preserves_return_eligibility', COALESCE(v_category.preserves_return_eligibility, true),
      'reason_detail', v_offboard_record.reason_detail,
      'return_interest', v_offboard_record.return_interest,
      'return_window_suggestion', v_offboard_record.return_window_suggestion,
      'lessons_learned', v_offboard_record.lessons_learned,
      'recommendation_for_future', v_offboard_record.recommendation_for_future,
      'tribe_id_at_offboard', v_offboard_record.tribe_id_at_offboard,
      'cycle_code_at_offboard', v_offboard_record.cycle_code_at_offboard,
      'has_full_interview', v_offboard_record.exit_interview_full_text IS NOT NULL
    )
  );
END;
$$;

COMMENT ON FUNCTION public.get_application_returning_context(uuid) IS
  '#91 G4 — bridges selection_applications.is_returning_member with member_offboarding_records context. Returns return_interest, lessons_learned, recommendation_for_future for selection committee review of returning candidates. Requires manage_member.';

REVOKE ALL ON FUNCTION public.get_application_returning_context(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_application_returning_context(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
