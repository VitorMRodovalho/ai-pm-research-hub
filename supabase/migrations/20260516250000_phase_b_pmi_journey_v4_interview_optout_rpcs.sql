-- p82: PMI Journey v4 — interview opt-out RPCs (all-or-nothing)
-- See: docs/adr/ADR-0066-pmi-journey-v4-phase-1.md
-- Workflow: candidate opts for live interview → all 5 pillars marked opted_out
-- + app.status transitions to interview_pending. Reversible via revert_interview_optout.

CREATE OR REPLACE FUNCTION public.opt_out_all_pillars(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_organization_id uuid;
  v_app_status text;
  v_pillars text[] := ARRAY['background','communication','proactivity','teamwork','culture_alignment'];
  v_question_indices int[] := ARRAY[1,2,3,4,5];
  i int;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'video_screening' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing video_screening scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type does not support video screening (got %)', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;
  v_organization_id := v_token_row.organization_id;

  SELECT status INTO v_app_status FROM selection_applications WHERE id = v_application_id;

  FOR i IN 1..5 LOOP
    INSERT INTO pmi_video_screenings (
      application_id, pillar, question_index, question_text,
      storage_provider, status, organization_id
    ) VALUES (
      v_application_id, v_pillars[i], v_question_indices[i],
      'Optou por entrevista ao vivo (cobre os 5 pilares)',
      'opted_out', 'opted_out', v_organization_id
    )
    ON CONFLICT (application_id, pillar, question_index) DO UPDATE SET
      storage_provider = 'opted_out',
      status = 'opted_out',
      drive_file_id = NULL,
      drive_folder_id = NULL,
      drive_file_name = NULL,
      youtube_url = NULL,
      uploaded_at = NULL,
      failure_reason = NULL,
      retry_count = 0,
      updated_at = now();
  END LOOP;

  IF v_app_status IN ('submitted','screening','objective_eval','objective_cutoff') THEN
    UPDATE selection_applications
    SET status = 'interview_pending', updated_at = now()
    WHERE id = v_application_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'pillars_opted_out', 5,
    'app_status_before', v_app_status,
    'app_status_after', CASE
      WHEN v_app_status IN ('submitted','screening','objective_eval','objective_cutoff') THEN 'interview_pending'
      ELSE v_app_status
    END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.revert_interview_optout(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_app_status text;
  v_deleted int;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'video_screening' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing video_screening scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type does not support video screening (got %)', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  WITH deleted AS (
    DELETE FROM pmi_video_screenings
    WHERE application_id = v_application_id
      AND status = 'opted_out'
      AND storage_provider = 'opted_out'
    RETURNING id
  )
  SELECT count(*)::int INTO v_deleted FROM deleted;

  SELECT status INTO v_app_status FROM selection_applications WHERE id = v_application_id;

  IF v_app_status = 'interview_pending' THEN
    UPDATE selection_applications
    SET status = 'screening', updated_at = now()
    WHERE id = v_application_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'pillars_reverted', v_deleted,
    'app_status_before', v_app_status,
    'app_status_after', CASE WHEN v_app_status = 'interview_pending' THEN 'screening' ELSE v_app_status END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.opt_out_all_pillars(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revert_interview_optout(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
