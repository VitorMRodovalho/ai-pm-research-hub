-- p179 LGPD hardening — check_pre_onboarding_auto_steps caller auth gate.
--
-- Carry from p178 council code-reviewer MEDIUM: the function reads PII fields
-- (phone, pmi_id, birth_date, etc.) from `members WHERE id = p_member_id` and
-- the return JSON's `profile_complete` boolean signals whether all PII slots
-- are populated. Without a caller-auth check, ANY caller could probe whether
-- another member has PII set or not.
--
-- Current protection (structural): function is REVOKE'd from `authenticated`
-- and `anon` (migration 20260426145632_track_q_d_internal_helpers_batch3b.sql
-- line 66). Only `postgres` and `service_role` can call it directly.
-- Internal callers (other SECDEF fns via PERFORM) inherit their own caller
-- auth gates — none of them allow arbitrary p_member_id from authenticated.
--
-- This migration adds defense-in-depth: explicit caller check inside the
-- function body. If a future GRANT regresses (someone re-grants to authenticated),
-- the body-level gate still rejects cross-member probing.
--
-- Allowed callers post-fix:
--   1. service_role / postgres / supabase_admin (cron, internal pipelines).
--   2. authenticated user calling for THEIR OWN p_member_id.
--   3. authenticated user with can_by_member(caller, 'manage_member') capability.
--
-- All other callers: RAISE 'Unauthorized: cannot probe another member''s PII'.
--
-- Rollback: revert to prior body (capture in 20260684000000 line 1034+).

CREATE OR REPLACE FUNCTION public.check_pre_onboarding_auto_steps(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_completed int := 0;
  v_member record;
  v_pages int;
  v_has_blog boolean;
  v_profile_complete boolean;
  v_caller_id uuid;
  v_cron_context boolean;
BEGIN
  -- p179 LGPD hardening: defense-in-depth caller auth gate.
  -- Structural protection: REVOKE'd from authenticated. This gate catches
  -- regressions if GRANT changes + ensures internal callers (PERFORM) cannot
  -- bypass when invoked outside the canonical pipeline contexts.
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF NOT v_cron_context THEN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: caller is not a registered member';
    END IF;

    IF v_caller_id <> p_member_id
       AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: cannot probe another member''s onboarding';
    END IF;
  END IF;

  SELECT id, auth_id, name, photo_url, credly_url,
         phone, linkedin_url, pmi_id, address, city, birth_date
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

  -- Step: complete_profile — requires all key personal fields for Volunteer Agreement
  v_profile_complete := v_member.photo_url IS NOT NULL
    AND v_member.phone IS NOT NULL AND length(trim(v_member.phone)) > 0
    AND v_member.linkedin_url IS NOT NULL AND length(trim(v_member.linkedin_url)) > 0
    AND v_member.pmi_id IS NOT NULL AND length(trim(v_member.pmi_id)) > 0
    AND v_member.address IS NOT NULL AND length(trim(v_member.address)) > 0
    AND v_member.city IS NOT NULL AND length(trim(v_member.city)) > 0
    AND v_member.birth_date IS NOT NULL;

  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'complete_profile' AND status = 'pending'
  AND v_profile_complete;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'complete_profile' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: setup_credly
  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'setup_credly' AND status = 'pending'
  AND v_member.credly_url IS NOT NULL AND v_member.credly_url != '';
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'setup_credly' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: explore_platform
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

  RETURN json_build_object(
    'auto_completed', v_completed,
    'member_id', p_member_id,
    'profile_complete', v_profile_complete
  );
END;
$function$;
