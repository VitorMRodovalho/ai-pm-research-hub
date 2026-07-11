-- #1016 + #1017 — route the two remaining anonymizers through the shared _erase_application_pii
-- helper (#946), so a person's selection-application child-table PII is actually erased.
--
-- Before this, both left the same gap #946 closed on the cron member/pre-member paths:
--   #1017 admin_anonymize_member (manual LGPD Art. 18): did a LIGHT ~6-field scrub of
--         selection_applications by email; never touched pmi_video_screenings / ai_analysis_runs /
--         eval-interview notes / membership snapshots / ai_calibration_runs.sample_payload.
--   #1016 anonymize_by_engagement_kind (cron jobid 17, V4 person-anchored): scrubbed persons/members
--         but NEVER touched the person's prior application children at all.
-- Both now resolve application id(s) by the target's (pre-scrub) email(s) and loop the shared helper,
-- folding the returned counts (no PII) into the existing audit row. Everything else is verbatim.
--
-- Latent bug surfaced by the #1017 QA: all three anonymizers set members.member_status='archived',
-- but members_member_status_check never allowed 'archived' -> every REAL anonymization would fail on
-- the members UPDATE (line 34). Never triggered in prod (no 5-year retention candidate yet; the manual
-- Art. 18 path was never run on a real subject). Add 'archived' to the allowed set (the anonymizers'
-- clear intent; anonymized members are is_active=false, and every consumer matches specific statuses
-- positively or `!= 'active'`, so a new value is simply excluded). Unblocks all three at once, incl.
-- the #946 cron anonymize_inactive_members which this PR does not otherwise touch.
ALTER TABLE public.members DROP CONSTRAINT IF EXISTS members_member_status_check;
ALTER TABLE public.members ADD CONSTRAINT members_member_status_check
  CHECK (member_status = ANY (ARRAY['active','observer','alumni','inactive','candidate','archived']));

-- ─────────────────────────────────────────────────────────────────────────────
-- #1017 — manual Art. 18 path
-- ─────────────────────────────────────────────────────────────────────────────
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
  -- #1017: route applications through the shared _erase_application_pii helper
  v_app_ids uuid[];
  v_app_id uuid;
  v_child jsonb;
  v_c_resume int := 0;
  v_c_video int := 0;
  v_c_children int := 0;
  v_c_calib int := 0;
  v_c_apps int := 0;
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

  -- #1017: erase the member's selection application(s) uniformly via the shared helper (was a
  -- LIGHT ~6-field scrub that left child tables + full mother-row + calibration name). Resolve the
  -- ids by the captured (pre-scrub) email, snapshot first (the helper mutates the mother-row email).
  SELECT array_agg(id) INTO v_app_ids
  FROM public.selection_applications WHERE email = v_target_email;
  IF v_app_ids IS NOT NULL THEN
    FOREACH v_app_id IN ARRAY v_app_ids LOOP
      v_child := public._erase_application_pii(v_app_id);
      v_c_resume   := v_c_resume   + COALESCE((v_child->>'resume_objects_deleted')::int, 0);
      v_c_video    := v_c_video    + COALESCE((v_child->>'video_screenings_deleted')::int, 0);
      v_c_children := v_c_children + COALESCE((v_child->>'child_rows_deleted')::int, 0);
      v_c_calib    := v_c_calib    + COALESCE((v_child->>'calibration_runs_scrubbed')::int, 0);
      v_c_apps     := v_c_apps + 1;
    END LOOP;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'lgpd_manual_anonymization', 'member', p_member_id,
    jsonb_build_object(
      'anonymized_at', now(),
      'original_name_hash', md5(COALESCE(v_target_name, '')),
      'legal_basis', 'LGPD Lei 13.709/2018 Art. 18 — manual admin anonymization',
      'offboarding_record_cleared', true,
      'applications_erased', v_c_apps,
      'resume_objects_deleted', v_c_resume,
      'video_screenings_deleted', v_c_video,
      'child_rows_deleted', v_c_children,
      'calibration_runs_scrubbed', v_c_calib
    ));

  RETURN jsonb_build_object(
    'anonymized', true,
    'member_id', p_member_id,
    'applications_erased', v_c_apps,
    'resume_objects_deleted', v_c_resume,
    'video_screenings_deleted', v_c_video,
    'child_rows_deleted', v_c_children,
    'calibration_runs_scrubbed', v_c_calib
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- #1016 — V4 engagement-kind retention cron (person-anchored)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.anonymize_by_engagement_kind(p_dry_run boolean DEFAULT true, p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_person record;
  v_count int := 0;
  v_skipped int := 0;
  v_results jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_strictest_policy text;
  -- #1016: route the person's application(s) through the shared _erase_application_pii helper
  v_member_email text;
  v_emails text[];
  v_app_ids uuid[];
  v_app_id uuid;
  v_child jsonb;
  v_c_resume int;
  v_c_video int;
  v_c_children int;
  v_c_calib int;
  v_c_apps int;
  v_apps_erased_total int := 0;
  v_child_rows_erased_total int := 0;
BEGIN
  FOR v_person IN
    SELECT
      p.id AS person_id,
      p.name AS person_name,
      p.email AS person_email,
      p.legacy_member_id,
      CASE
        WHEN bool_or(ek.anonymization_policy = 'retain_for_legal') THEN 'retain_for_legal'
        WHEN bool_or(ek.anonymization_policy = 'anonymize') THEN 'anonymize'
        ELSE 'delete'
      END AS effective_policy,
      max(e.end_date + make_interval(days => COALESCE(ek.retention_days_after_end, 1825))) AS latest_retention_end,
      count(*) AS engagement_count
    FROM public.persons p
    JOIN public.engagements e ON e.person_id = p.id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE p.anonymized_at IS NULL
      AND e.status IN ('offboarded', 'expired')
      AND e.end_date IS NOT NULL
      AND (e.end_date + make_interval(days => COALESCE(ek.retention_days_after_end, 1825))) < CURRENT_DATE
    GROUP BY p.id, p.name, p.email, p.legacy_member_id
    HAVING NOT EXISTS (
      SELECT 1 FROM public.engagements e2
      WHERE e2.person_id = p.id AND e2.status IN ('active', 'suspended')
    )
    ORDER BY max(e.end_date) ASC
    LIMIT p_limit
  LOOP
    BEGIN
      v_strictest_policy := v_person.effective_policy;

      -- #976 PR-4 (15.4.5 / §9.1 Opção B): preserva quem detém licença viva (signature is_current).
      -- In-loop skip (não WHERE-exclusion) p/ dar VISIBILIDADE ao DPO (review legal HIGH): registra o
      -- deferimento e sinaliza que requisições LGPD Art.18(IV) desse titular roteiam ao DPO (tradeoff
      -- Art.16(I) base de retenção por licença de PI × Art.18(IV) apagamento). legacy_member_id NULL
      -- (pessoa sem member) => sem ledger possível => segue p/ anonimização normal.
      IF v_person.legacy_member_id IS NOT NULL AND EXISTS (
           SELECT 1 FROM public.member_document_signatures mds
           WHERE mds.member_id = v_person.legacy_member_id AND mds.is_current = true) THEN
        v_skipped := v_skipped + 1;
        IF NOT p_dry_run THEN
          INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
          VALUES (NULL, 'lgpd.anonymization_deferred_ip_license', 'member', v_person.legacy_member_id,
            jsonb_build_object('person_id', v_person.person_id,
              'legal_basis', 'LGPD Art. 16(I) — IP license enforcement (Termo 15.4.5)',
              'art18_requests_require_dpo_review', true, 'signature_is_current', true,
              'source', 'cron:anonymize_by_engagement_kind'));
        END IF;
        v_results := v_results || jsonb_build_object(
          'person_id', v_person.person_id, 'action', 'license_preserved', 'reason', 'member_document_signatures is_current'
        );
        CONTINUE;
      END IF;

      IF v_strictest_policy = 'retain_for_legal' THEN
        v_skipped := v_skipped + 1;
        v_results := v_results || jsonb_build_object(
          'person_id', v_person.person_id, 'action', 'retained', 'reason', 'retain_for_legal policy'
        );
        CONTINUE;
      END IF;

      IF NOT p_dry_run THEN
        -- #1016: erase the person's selection application(s) via the shared helper BEFORE scrubbing
        -- the person/member emails (resolution is email-anchored). person email + optional member email.
        v_emails := '{}';
        IF v_person.person_email IS NOT NULL THEN v_emails := array_append(v_emails, v_person.person_email); END IF;
        IF v_person.legacy_member_id IS NOT NULL THEN
          SELECT email INTO v_member_email FROM public.members WHERE id = v_person.legacy_member_id;
          IF v_member_email IS NOT NULL THEN v_emails := array_append(v_emails, v_member_email); END IF;
        END IF;
        v_c_resume := 0; v_c_video := 0; v_c_children := 0; v_c_calib := 0; v_c_apps := 0;
        IF array_length(v_emails, 1) > 0 THEN
          SELECT array_agg(DISTINCT id) INTO v_app_ids
          FROM public.selection_applications WHERE email = ANY(v_emails);
          IF v_app_ids IS NOT NULL THEN
            FOREACH v_app_id IN ARRAY v_app_ids LOOP
              v_child := public._erase_application_pii(v_app_id);
              v_c_resume   := v_c_resume   + COALESCE((v_child->>'resume_objects_deleted')::int, 0);
              v_c_video    := v_c_video    + COALESCE((v_child->>'video_screenings_deleted')::int, 0);
              v_c_children := v_c_children + COALESCE((v_child->>'child_rows_deleted')::int, 0);
              v_c_calib    := v_c_calib    + COALESCE((v_child->>'calibration_runs_scrubbed')::int, 0);
              v_c_apps     := v_c_apps + 1;
            END LOOP;
          END IF;
        END IF;
        v_apps_erased_total := v_apps_erased_total + v_c_apps;
        v_child_rows_erased_total := v_child_rows_erased_total + v_c_children;

        UPDATE public.persons SET
          name = 'Pessoa Anonimizada #' || SUBSTR(v_person.person_id::text, 1, 8),
          email = 'anon_' || SUBSTR(v_person.person_id::text, 1, 8) || '@removed.local',
          auth_id = NULL, anonymized_at = now()
        WHERE id = v_person.person_id;

        IF v_person.legacy_member_id IS NOT NULL THEN
          UPDATE public.members SET
            name = 'Membro Anonimizado #' || SUBSTR(v_person.legacy_member_id::text, 1, 8),
            email = 'anon_' || SUBSTR(v_person.legacy_member_id::text, 1, 8) || '@removed.local',
            phone = NULL, phone_encrypted = NULL, pmi_id = NULL, pmi_id_encrypted = NULL,
            linkedin_url = NULL, photo_url = NULL, credly_url = NULL, credly_badges = NULL,
            address = NULL, city = NULL, birth_date = NULL, state = NULL, country = NULL,
            signature_url = NULL, secondary_emails = NULL, last_active_pages = NULL,
            auth_id = NULL, secondary_auth_ids = NULL, is_active = false,
            member_status = 'archived', anonymized_at = now(), anonymized_by = NULL, updated_at = now()
          WHERE id = v_person.legacy_member_id;
          DELETE FROM public.notifications WHERE member_id = v_person.legacy_member_id;
          DELETE FROM public.notification_preferences WHERE member_id = v_person.legacy_member_id;
        END IF;

        UPDATE public.engagements SET status = 'anonymized', updated_at = now()
        WHERE person_id = v_person.person_id;

        IF v_strictest_policy = 'delete' THEN
          DELETE FROM public.persons WHERE id = v_person.person_id;
        END IF;

        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'lgpd_v4_anonymization', 'person', v_person.person_id,
          jsonb_build_object(
            'policy', v_strictest_policy, 'engagement_count', v_person.engagement_count,
            'retention_end', v_person.latest_retention_end, 'legacy_member_id', v_person.legacy_member_id,
            'legal_basis', 'LGPD Art. 16 — retention limit per engagement_kind (ADR-0008)',
            'source', 'cron:anonymize_by_engagement_kind',
            'applications_erased', v_c_apps,
            'resume_objects_deleted', v_c_resume,
            'video_screenings_deleted', v_c_video,
            'child_rows_deleted', v_c_children,
            'calibration_runs_scrubbed', v_c_calib
          ));
      END IF;

      v_count := v_count + 1;
      v_results := v_results || jsonb_build_object(
        'person_id', v_person.person_id, 'action', v_strictest_policy,
        'retention_end', v_person.latest_retention_end, 'engagements', v_person.engagement_count
      );
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object('person_id', v_person.person_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run, 'processed', v_count, 'skipped', v_skipped,
    'applications_erased_total', v_apps_erased_total,
    'child_rows_erased_total', v_child_rows_erased_total,
    'results', v_results, 'errors', v_errors, 'executed_at', now()
  );
END;
$function$;
