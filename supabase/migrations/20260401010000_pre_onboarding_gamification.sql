-- Pre-Onboarding Gamification (#18)
-- 3 RPCs: seed_pre_onboarding_steps, check_pre_onboarding_auto_steps, get_candidate_onboarding_progress
-- Uses existing onboarding_progress table with new step_keys and metadata.phase = 'pre_onboarding'

-- RPC 1: Seed pre-onboarding steps for a candidate
CREATE OR REPLACE FUNCTION seed_pre_onboarding_steps(
  p_application_id uuid,
  p_member_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count int := 0;
  v_steps text[] := ARRAY['create_account', 'setup_credly', 'explore_platform', 'read_blog', 'start_pmi_certs'];
  v_xp int[] := ARRAY[50, 75, 50, 50, 150];
  v_sla_days int[] := ARRAY[7, 14, 14, 14, 30];
  v_step text;
  v_i int;
BEGIN
  FOR v_i IN 1..array_length(v_steps, 1) LOOP
    v_step := v_steps[v_i];
    IF NOT EXISTS (
      SELECT 1 FROM onboarding_progress
      WHERE application_id = p_application_id AND step_key = v_step
    ) THEN
      INSERT INTO onboarding_progress (application_id, member_id, step_key, status, sla_deadline, metadata)
      VALUES (
        p_application_id,
        p_member_id,
        v_step,
        'pending',
        now() + (v_sla_days[v_i] || ' days')::interval,
        jsonb_build_object('xp', v_xp[v_i], 'phase', 'pre_onboarding')
      );
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN json_build_object('seeded', v_count, 'application_id', p_application_id);
END;
$$;

-- RPC 2: Auto-detect and complete pre-onboarding steps
CREATE OR REPLACE FUNCTION check_pre_onboarding_auto_steps(p_member_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_completed int := 0;
  v_member record;
  v_pages int;
  v_has_blog boolean;
BEGIN
  SELECT id, auth_id, name, photo_url, credly_url
  INTO v_member
  FROM members WHERE id = p_member_id;

  IF v_member.id IS NULL THEN
    RETURN json_build_object('error', 'Member not found');
  END IF;

  -- Step: create_account
  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'create_account' AND status = 'pending'
  AND v_member.auth_id IS NOT NULL;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'create_account' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: setup_credly
  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'setup_credly' AND status = 'pending'
  AND v_member.credly_url IS NOT NULL AND v_member.credly_url != '';
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'setup_credly' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: explore_platform (3+ pages)
  SELECT coalesce(sum(pages_visited), 0) INTO v_pages
  FROM member_activity_sessions WHERE member_id = p_member_id;

  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'explore_platform' AND status = 'pending'
  AND v_pages >= 3;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'explore_platform' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: read_blog
  SELECT EXISTS (
    SELECT 1 FROM member_activity_sessions
    WHERE member_id = p_member_id
    AND (first_page LIKE '%/blog%' OR last_page LIKE '%/blog%')
  ) INTO v_has_blog;

  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'read_blog' AND status = 'pending'
  AND v_has_blog;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'read_blog' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: start_pmi_certs — manual or Credly sync (no auto-detect)

  RETURN json_build_object('auto_completed', v_completed, 'member_id', p_member_id);
END;
$$;

-- RPC 3: Get candidate onboarding progress (frontend dashboard)
CREATE OR REPLACE FUNCTION get_candidate_onboarding_progress(p_member_id uuid DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_mid uuid;
  v_result json;
BEGIN
  v_mid := p_member_id;
  IF v_mid IS NULL THEN
    SELECT id INTO v_mid FROM members WHERE auth_id = auth.uid();
  END IF;

  IF v_mid IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  -- Run auto-detection first
  PERFORM check_pre_onboarding_auto_steps(v_mid);

  SELECT json_build_object(
    'member_id', v_mid,
    'steps', coalesce((
      SELECT json_agg(json_build_object(
        'step_key', op.step_key,
        'status', op.status,
        'completed_at', op.completed_at,
        'sla_deadline', op.sla_deadline,
        'xp', coalesce((op.metadata->>'xp')::int, 0),
        'phase', coalesce(op.metadata->>'phase', 'onboarding')
      ) ORDER BY
        CASE op.step_key
          WHEN 'create_account' THEN 1
          WHEN 'complete_profile' THEN 2
          WHEN 'setup_credly' THEN 3
          WHEN 'explore_platform' THEN 4
          WHEN 'read_blog' THEN 5
          WHEN 'start_pmi_certs' THEN 6
          WHEN 'code_of_conduct' THEN 7
          WHEN 'volunteer_term' THEN 8
          WHEN 'vep_acceptance' THEN 9
          WHEN 'first_meeting' THEN 10
          WHEN 'meet_tribe' THEN 11
          WHEN 'start_trail' THEN 12
          ELSE 99
        END
      )
      FROM onboarding_progress op
      WHERE op.member_id = v_mid
    ), '[]'::json),
    'pre_onboarding', json_build_object(
      'total', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding'),
      'completed', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding' AND status = 'completed'),
      'xp_earned', coalesce((SELECT sum((metadata->>'xp')::int) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding' AND status = 'completed'), 0),
      'xp_total', coalesce((SELECT sum((metadata->>'xp')::int) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding'), 0)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;
