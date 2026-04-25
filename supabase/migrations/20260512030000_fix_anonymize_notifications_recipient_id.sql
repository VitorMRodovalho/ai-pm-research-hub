-- Fix pre-existing bug: anonymize functions referenced notifications.member_id
-- but the column is `recipient_id` (notification_preferences IS member_id).
-- Discovered during p45 #91 G3 anonymize extend; never fired in prod (zero
-- anonymizations to date), but would fail with 42703 "column member_id does
-- not exist" the first time LGPD anonymization runs. 1-line fix in 2 functions.
--
-- Rollback: not applicable (this is a fix; reverting reintroduces the bug).

CREATE OR REPLACE FUNCTION public.admin_anonymize_member(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_target_email text;
  v_target_name text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
  WHERE auth_id = auth.uid() AND is_superadmin = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: only superadmin can anonymize members';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: superadmin must also have manage_member engagement';
  END IF;

  SELECT email, name INTO v_target_email, v_target_name
  FROM public.members WHERE id = p_member_id;

  IF v_target_email IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE public.members SET
    name = 'Membro Anonimizado #' || SUBSTR(p_member_id::text, 1, 8),
    email = 'anon_' || SUBSTR(p_member_id::text, 1, 8) || '@removed.local',
    phone = NULL, phone_encrypted = NULL,
    pmi_id = NULL, pmi_id_encrypted = NULL,
    linkedin_url = NULL, photo_url = NULL,
    credly_url = NULL, credly_badges = NULL,
    address = NULL, city = NULL, birth_date = NULL,
    state = NULL, country = NULL,
    signature_url = NULL, secondary_emails = NULL,
    last_active_pages = NULL, auth_id = NULL, secondary_auth_ids = NULL,
    is_active = false, member_status = 'archived',
    anonymized_at = now(), anonymized_by = v_caller_id,
    updated_at = now()
  WHERE id = p_member_id;

  UPDATE public.member_offboarding_records SET
    reason_detail = NULL, exit_interview_full_text = NULL,
    return_window_suggestion = NULL, lessons_learned = NULL,
    recommendation_for_future = NULL, attachment_urls = '{}'::text[],
    updated_at = now()
  WHERE member_id = p_member_id;

  -- BUG FIX: column is `recipient_id`, not `member_id` (notification_preferences IS member_id).
  DELETE FROM public.notifications WHERE recipient_id = p_member_id;
  DELETE FROM public.notification_preferences WHERE member_id = p_member_id;

  UPDATE public.selection_applications SET
    applicant_name = 'Candidato Anonimizado',
    email = 'anon@removed.local',
    phone = NULL, linkedin_url = NULL,
    resume_url = NULL, motivation_letter = NULL
  WHERE email = v_target_email;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'lgpd_manual_anonymization', 'member', p_member_id,
    jsonb_build_object(
      'anonymized_at', now(),
      'original_name_hash', md5(COALESCE(v_target_name, '')),
      'legal_basis', 'LGPD Lei 13.709/2018 Art. 18 — manual admin anonymization',
      'offboarding_record_cleared', true
    ));

  RETURN jsonb_build_object('anonymized', true, 'member_id', p_member_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.anonymize_inactive_members(
  p_dry_run boolean DEFAULT true,
  p_years int DEFAULT 5,
  p_limit int DEFAULT 500
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_candidate record;
  v_count int := 0;
  v_skipped int := 0;
  v_ids uuid[] := '{}';
  v_errors jsonb := '[]'::jsonb;
BEGIN
  FOR v_candidate IN
    SELECT * FROM public.list_anonymization_candidates(p_years) LIMIT p_limit
  LOOP
    BEGIN
      IF NOT p_dry_run THEN
        UPDATE public.members SET
          name = 'Membro Anonimizado #' || SUBSTR(v_candidate.member_id::text, 1, 8),
          email = 'anon_' || SUBSTR(v_candidate.member_id::text, 1, 8) || '@removed.local',
          phone = NULL, phone_encrypted = NULL,
          pmi_id = NULL, pmi_id_encrypted = NULL,
          linkedin_url = NULL, photo_url = NULL,
          credly_url = NULL, credly_badges = NULL,
          address = NULL, city = NULL, birth_date = NULL,
          state = NULL, country = NULL,
          signature_url = NULL, secondary_emails = NULL,
          last_active_pages = NULL, auth_id = NULL, secondary_auth_ids = NULL,
          is_active = false, member_status = 'archived',
          anonymized_at = now(), anonymized_by = NULL,
          updated_at = now()
        WHERE id = v_candidate.member_id;

        UPDATE public.member_offboarding_records SET
          reason_detail = NULL, exit_interview_full_text = NULL,
          return_window_suggestion = NULL, lessons_learned = NULL,
          recommendation_for_future = NULL, attachment_urls = '{}'::text[],
          updated_at = now()
        WHERE member_id = v_candidate.member_id;

        -- BUG FIX: column is `recipient_id`, not `member_id`.
        DELETE FROM public.notifications WHERE recipient_id = v_candidate.member_id;
        DELETE FROM public.notification_preferences WHERE member_id = v_candidate.member_id;

        UPDATE public.selection_applications SET
          applicant_name = 'Candidato Anonimizado',
          email = 'anon@removed.local',
          phone = NULL, linkedin_url = NULL,
          resume_url = NULL, motivation_letter = NULL
        WHERE email = v_candidate.email;

        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'lgpd_automated_anonymization', 'member', v_candidate.member_id,
          jsonb_build_object(
            'anonymized_at', now(),
            'years_inactive', v_candidate.years_inactive,
            'inactivity_anchor', v_candidate.inactivity_anchor,
            'retention_years', p_years,
            'legal_basis', 'LGPD Lei 13.709/2018 Art. 16 — retention limit reached',
            'source', 'cron:anonymize_inactive_members',
            'offboarding_record_cleared', true
          ));
      END IF;

      v_count := v_count + 1;
      v_ids := array_append(v_ids, v_candidate.member_id);
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object('member_id', v_candidate.member_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'years_threshold', p_years,
    'processed', v_count,
    'skipped', v_skipped,
    'member_ids', to_jsonb(v_ids),
    'errors', v_errors,
    'executed_at', now()
  );
END;
$$;
