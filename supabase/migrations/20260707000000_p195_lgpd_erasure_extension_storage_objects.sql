-- ============================================================
-- p195 LGPD Erasure Extension: storage.objects cleanup
-- ============================================================
-- WHAT: extend both LGPD anonymization paths to delete corresponding
-- resume PDFs from `selection-resumes` bucket — closes the compliance gap
-- introduced when VEP resume Opção B+ mirroring was added in p195.
--
-- AFFECTED FUNCTIONS (both bodies extended; signatures UNCHANGED):
--   1. admin_anonymize_member(p_member_id uuid)    — Art. 18 manual (superadmin)
--   2. anonymize_inactive_members(p_dry_run, p_years, p_limit)  — 5y cron auto
--
-- WHY (LGPD compliance):
-- Without this extension, Art. 18 right-to-erasure + Art. 16 retention limit
-- would scrub the DB (members + selection_applications PII) but leave resume
-- PDFs lingering in the bucket. After p195 mirroring, every active candidate
-- has a binary at `cycle-{cycle_code}/{applicantId}.pdf` that needs deletion
-- alongside member anonymization.
--
-- BEHAVIOR:
--   - BEFORE the existing UPDATE selection_applications scrub, collect
--     resume_storage_path values for rows being scrubbed.
--   - DELETE FROM storage.objects WHERE bucket_id = 'selection-resumes'
--     AND name = ANY(paths). Supabase storage server reclaims the underlying
--     binary on next housekeeping pass (per Supabase Storage docs).
--   - Existing UPDATE also clears resume_storage_path + resume_synced_at
--     (previously only resume_url was nulled — left storage path orphaned).
--   - audit log changes JSONB gains `resume_objects_deleted` count.
--
-- PERMISSIONS: SECURITY DEFINER functions run as their owner (typically
-- supabase_admin) which has direct DELETE on storage.objects. No additional
-- grants needed.
--
-- ROLLBACK: re-apply prior bodies (no storage delete + no resume_storage_path
-- scrub). storage.objects deleted by this version cannot be restored from DB
-- (binary is gone from storage backend after housekeeping).
-- ============================================================

-- ─── 1. admin_anonymize_member — Art. 18 manual erasure ───────────────────
CREATE OR REPLACE FUNCTION public.admin_anonymize_member(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_target_email text;
  v_target_name text;
  v_resume_paths text[];
  v_resume_deleted_count int := 0;
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

  -- p195 LGPD storage extension: capture resume paths BEFORE scrubbing the
  -- selection_applications rows, then delete the storage objects.
  SELECT array_agg(resume_storage_path)
  INTO v_resume_paths
  FROM public.selection_applications
  WHERE email = v_target_email
    AND resume_storage_path IS NOT NULL;

  IF v_resume_paths IS NOT NULL AND array_length(v_resume_paths, 1) > 0 THEN
    DELETE FROM storage.objects
    WHERE bucket_id = 'selection-resumes'
      AND name = ANY(v_resume_paths);
    GET DIAGNOSTICS v_resume_deleted_count = ROW_COUNT;
  END IF;

  UPDATE public.selection_applications SET
    applicant_name = 'Candidato Anonimizado',
    email = 'anon@removed.local',
    phone = NULL, linkedin_url = NULL,
    resume_url = NULL,
    resume_storage_path = NULL,  -- p195
    resume_synced_at = NULL,      -- p195
    motivation_letter = NULL
  WHERE email = v_target_email;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'lgpd_manual_anonymization', 'member', p_member_id,
    jsonb_build_object(
      'anonymized_at', now(),
      'original_name_hash', md5(COALESCE(v_target_name, '')),
      'legal_basis', 'LGPD Lei 13.709/2018 Art. 18 — manual admin anonymization',
      'offboarding_record_cleared', true,
      'resume_objects_deleted', v_resume_deleted_count
    ));

  RETURN jsonb_build_object(
    'anonymized', true,
    'member_id', p_member_id,
    'resume_objects_deleted', v_resume_deleted_count
  );
END;
$function$;

-- ─── 2. anonymize_inactive_members — 5y cron retention limit ──────────────
CREATE OR REPLACE FUNCTION public.anonymize_inactive_members(p_dry_run boolean DEFAULT true, p_years integer DEFAULT 5, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_candidate record;
  v_count int := 0;
  v_skipped int := 0;
  v_ids uuid[] := '{}';
  v_errors jsonb := '[]'::jsonb;
  v_resume_paths text[];
  v_resume_deleted_total int := 0;
  v_resume_deleted_this_loop int := 0;
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

        -- p195 LGPD storage extension: capture resume paths + delete binaries.
        SELECT array_agg(resume_storage_path)
        INTO v_resume_paths
        FROM public.selection_applications
        WHERE email = v_candidate.email
          AND resume_storage_path IS NOT NULL;

        v_resume_deleted_this_loop := 0;
        IF v_resume_paths IS NOT NULL AND array_length(v_resume_paths, 1) > 0 THEN
          DELETE FROM storage.objects
          WHERE bucket_id = 'selection-resumes'
            AND name = ANY(v_resume_paths);
          GET DIAGNOSTICS v_resume_deleted_this_loop = ROW_COUNT;
          v_resume_deleted_total := v_resume_deleted_total + v_resume_deleted_this_loop;
        END IF;

        UPDATE public.selection_applications SET
          applicant_name = 'Candidato Anonimizado',
          email = 'anon@removed.local',
          phone = NULL, linkedin_url = NULL,
          resume_url = NULL,
          resume_storage_path = NULL,  -- p195
          resume_synced_at = NULL,      -- p195
          motivation_letter = NULL
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
            'offboarding_record_cleared', true,
            'resume_objects_deleted', v_resume_deleted_this_loop
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
    'resume_objects_deleted_total', v_resume_deleted_total,
    'errors', v_errors,
    'executed_at', now()
  );
END;
$function$;
