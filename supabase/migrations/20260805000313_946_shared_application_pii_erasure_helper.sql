-- #946 — Unify LGPD erasure of a selection application's PII across BOTH anonymization paths.
--
-- Problem (grounded 2026-07-01, surfaced by the #905 council review):
--   * anonymize_premember_applications (#905, member_id-agnostic) DOES follow PII into the
--     PII-bearing child tables (video/voice transcription, AI runs, evaluation/interview notes,
--     membership snapshots, service history) and does a FULL mother-row scrub.
--   * anonymize_inactive_members (the ACTIVE 5y LGPD cron, jobid 15) is MEMBER-anchored: it loops
--     list_anonymization_candidates by member inactivity and scrubs the selection_applications
--     mother row only LIGHTLY (name/email/phone/linkedin/resume/motivation) WHERE email = member.email.
--     It leaves ALL the child-table PII and most AI/VEP/profile mother-row fields un-erased.
--   So a member anonymized after 5y still leaves behind, for their prior application: video/voice
--   transcription, the full AI dossier, evaluation/interview notes, membership snapshots, service
--   history — plus the AI-triage / scraped-LinkedIn / VEP-id fields on the mother row.
--   Additionally BOTH paths leave ai_calibration_runs.sample_payload holding the original
--   applicant_name inside its jsonb array (restricted to view_internal_analytics, but residual PII).
--
-- Fix (issue #946 "Proposed direction"): extract a shared, path-agnostic erasure helper
-- _erase_application_pii(p_application_id) that performs the per-application erasure (resume binary +
-- child-table DELETE/scrub + full mother-row scrub + ai_calibration_runs.sample_payload name scrub),
-- and have BOTH anonymizers call it so the erasure is UNIFORM. The member path resolves the
-- application ids from the candidate's email (the same set its light scrub used to reach) and calls
-- the helper per application; the pre-member path calls it per candidate application.
--
-- Live grounding (2026-07-01):
--   * ai_calibration_runs: 22 rows; sample_payload is a jsonb ARRAY of {ai_score, applicant_name,
--     application_id, delta_signed, human_score_normalized} — scrub applicant_name, KEEP the scores.
--   * All 14 child tables carry application_id. Member cron jobid 15 is active (p_years=5) with 0
--     candidates today -> applying this is behavior-safe now; it hardens the path for when a member
--     crosses the window ("the window is now" = the cron is live).
--
-- Scope note: a THIRD active anonymizer, anonymize_by_engagement_kind (jobid 17, V4 person/engagement
-- anchored), has the SAME class of gap (scrubs persons/members but never the application children).
-- It is NOT named in #946 and is person-anchored (different email-resolution semantics) -> tracked as
-- a dedicated follow-up that will reuse THIS helper, rather than widening this PR.
--
-- Behavior for callers is strictly MORE erasure (never less); no row is eligible under the 5y window
-- today so nothing is touched on apply. SECDEF grants preserved (service_role only). The helper is
-- locked down (REVOKE PUBLIC/anon/authenticated) so it does NOT re-introduce the #965 SECDEF-drift
-- class (has_function_privilege('anon', ...) stays false -> stays out of the _audit sweep).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Shared per-application erasure helper (path-agnostic; called by both anonymizers).
--    Returns counts (no PII) for the caller to fold into its audit + return payload.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._erase_application_pii(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_resume_path text;
  v_resume_deleted int := 0;
  v_video_deleted int := 0;
  v_children_total int := 0;
  v_calib_scrubbed int := 0;
  v_n int;
BEGIN
  -- (a) delete the resume binary from storage (path lives on the mother row)
  SELECT sa.resume_storage_path INTO v_resume_path
  FROM public.selection_applications sa WHERE sa.id = p_application_id;
  IF v_resume_path IS NOT NULL THEN
    DELETE FROM storage.objects
    WHERE bucket_id = 'selection-resumes' AND name = v_resume_path;
    GET DIAGNOSTICS v_resume_deleted = ROW_COUNT;
  END IF;

  -- (b) DELETE biometric-adjacent video screenings (transcription + Drive/YouTube links).
  --     External binaries (Drive/YouTube) are not reachable from SQL -> follow-up cleanup (#905 R3).
  DELETE FROM public.pmi_video_screenings WHERE application_id = p_application_id;
  GET DIAGNOSTICS v_video_deleted = ROW_COUNT;

  -- (c) DELETE pure candidate-derived child content (no aggregate value once the subject is erased).
  DELETE FROM public.ai_analysis_runs                     WHERE application_id = p_application_id; GET DIAGNOSTICS v_n = ROW_COUNT; v_children_total := v_children_total + v_n;
  DELETE FROM public.ai_processing_log                    WHERE application_id = p_application_id; GET DIAGNOSTICS v_n = ROW_COUNT; v_children_total := v_children_total + v_n;
  DELETE FROM public.ai_score_validations                 WHERE application_id = p_application_id; GET DIAGNOSTICS v_n = ROW_COUNT; v_children_total := v_children_total + v_n;
  DELETE FROM public.selection_evaluation_ai_suggestions  WHERE application_id = p_application_id; GET DIAGNOSTICS v_n = ROW_COUNT; v_children_total := v_children_total + v_n;
  DELETE FROM public.selection_membership_snapshots       WHERE application_id = p_application_id; GET DIAGNOSTICS v_n = ROW_COUNT; v_children_total := v_children_total + v_n;
  DELETE FROM public.selection_application_service_history WHERE application_id = p_application_id; GET DIAGNOSTICS v_n = ROW_COUNT; v_children_total := v_children_total + v_n;
  DELETE FROM public.selection_topic_views                WHERE application_id = p_application_id; GET DIAGNOSTICS v_n = ROW_COUNT; v_children_total := v_children_total + v_n;
  DELETE FROM public.selection_dispatch_url_log           WHERE application_id = p_application_id; GET DIAGNOSTICS v_n = ROW_COUNT; v_children_total := v_children_total + v_n;
  DELETE FROM public.onboarding_progress                  WHERE application_id = p_application_id; GET DIAGNOSTICS v_n = ROW_COUNT; v_children_total := v_children_total + v_n;

  -- (d) SCRUB free-text but KEEP structured scores (de-identified cohort/fairness analytics)
  UPDATE public.selection_evaluations
     SET notes = NULL, criterion_notes = NULL
   WHERE application_id = p_application_id;
  UPDATE public.selection_interviews
     SET notes = NULL, theme_of_interest = NULL, calendar_event_id = NULL
   WHERE application_id = p_application_id;
  UPDATE public.gate_attempts
     SET payload = NULL, gate_failed_reason = NULL
   WHERE application_id = p_application_id;
  UPDATE public.selection_evaluation_anomalies
     SET payload = NULL
   WHERE application_id = p_application_id;

  -- (e) SCRUB the mother row: direct identifiers + free-text + AI (incl. triage + scraped LinkedIn)
  --     + external VEP ids + voice evidence. Mirrors the consent-revocation purge. KEEP: human
  --     scores/ranks/pert/cohort_n, gender/age_band/industry/sector/seniority, coarse geo, cycle_id,
  --     status, tags (categorical), referral_source/referrer_member_id, consent_* ledger fields.
  --     anonymized_at is SET so the pre-member cron never re-touches an already-erased ex-member
  --     application (whose email no longer matches the now-scrubbed member email).
  UPDATE public.selection_applications SET
    applicant_name = 'Candidato Anonimizado',
    first_name = NULL, last_name = NULL,
    email = 'anon_' || substr(id::text, 1, 8) || '@removed.local',
    phone = NULL, pmi_id = NULL,
    linkedin_url = NULL, profile_linkedin_url = NULL, credly_url = NULL,
    resume_url = NULL, resume_storage_path = NULL, resume_synced_at = NULL,
    cv_extracted_text = NULL,
    motivation_letter = NULL, non_pmi_experience = NULL, reason_for_applying = NULL,
    proposed_theme = NULL, leadership_experience = NULL, academic_background = NULL,
    areas_of_interest = NULL, availability_declared = NULL, feedback = NULL,
    conversion_reason = NULL, interview_reschedule_reason = NULL,
    chapter_affiliation = NULL,
    profile_about_me = NULL, profile_specialties = NULL, profile_designation = NULL,
    profile_company = NULL, profile_volunteer_interest = NULL,
    profile_location = NULL, profile_city = NULL, applicant_city = NULL,
    profile_certifications = NULL, certifications = NULL, service_history_chapters = NULL,
    ai_analysis = NULL, ai_triage_reasoning = NULL, last_briefing_jsonb = NULL,
    ai_triage_score = NULL, ai_triage_confidence = NULL, ai_triage_at = NULL, ai_triage_model = NULL,
    linkedin_relevant_posts = NULL, ai_pm_focus_tags = NULL,
    vep_application_id = NULL, vep_opportunity_id = NULL,
    consent_voice_biometric_evidence = NULL, vep_reconciled_note = NULL,
    pmi_memberships = NULL, utm_data = NULL,
    anonymized_at = now(),
    updated_at = now()
  WHERE id = p_application_id;

  -- (f) SCRUB ai_calibration_runs.sample_payload: the jsonb array holds one element per scored
  --     applicant ({ai_score, applicant_name, application_id, delta_signed, human_score_normalized}).
  --     Overwrite applicant_name for this application's element(s); KEEP the numeric calibration data.
  --     Only rewrite rows that actually reference this application (text-compare, order-preserving).
  UPDATE public.ai_calibration_runs r
  SET sample_payload = (
    SELECT jsonb_agg(
      CASE WHEN e->>'application_id' = p_application_id::text
           THEN e || jsonb_build_object('applicant_name', 'Candidato Anonimizado')
           ELSE e END
      ORDER BY ord
    )
    FROM jsonb_array_elements(r.sample_payload) WITH ORDINALITY AS arr(e, ord)
  )
  WHERE r.sample_payload IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(r.sample_payload) e2
      WHERE e2->>'application_id' = p_application_id::text
    );
  GET DIAGNOSTICS v_calib_scrubbed = ROW_COUNT;

  RETURN jsonb_build_object(
    'resume_objects_deleted', v_resume_deleted,
    'video_screenings_deleted', v_video_deleted,
    'child_rows_deleted', v_children_total,
    'calibration_runs_scrubbed', v_calib_scrubbed
  );
END;
$function$;

-- Lock down the helper: internal-only (called from within the two SECDEF anonymizers, which are owned
-- by postgres and therefore execute it regardless of grants). service_role kept for operational
-- single-subject erasure (LGPD Art. 18). REVOKE PUBLIC/anon/authenticated so it never becomes an
-- anon-reachable SECDEF side-effect fn (#965 / ADR-0118 drift class).
REVOKE ALL ON FUNCTION public._erase_application_pii(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._erase_application_pii(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public._erase_application_pii(uuid) TO service_role;

COMMENT ON FUNCTION public._erase_application_pii(uuid) IS
  '#946 shared LGPD erasure of one selection application''s PII (resume binary + child-table DELETE/scrub + full mother-row scrub + ai_calibration_runs.sample_payload name scrub). Called by anonymize_inactive_members (per resolved application) and anonymize_premember_applications. SECDEF, service_role only.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Pre-member anonymizer — replace the inline per-application erasure with the shared helper.
--    Signature/SECDEF/grants unchanged (CREATE OR REPLACE preserves them).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.anonymize_premember_applications(
  p_dry_run boolean DEFAULT true,
  p_years integer DEFAULT 5,
  p_years_withdrawn integer DEFAULT NULL,
  p_limit integer DEFAULT 500
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_cand record;
  v_count int := 0;
  v_skipped int := 0;
  v_ids uuid[] := '{}';
  v_errors jsonb := '[]'::jsonb;
  v_child jsonb;
  v_resume_deleted_total int := 0;
  v_video_deleted_total int := 0;
  v_children_deleted_total int := 0;
  v_calib_scrubbed_total int := 0;
BEGIN
  FOR v_cand IN
    SELECT * FROM public.list_premember_anonymization_candidates(p_years, p_years_withdrawn) LIMIT p_limit
  LOOP
    BEGIN
      IF NOT p_dry_run THEN
        -- shared per-application erasure (resume binary + children + mother row + calibration name)
        v_child := public._erase_application_pii(v_cand.application_id);
        v_resume_deleted_total   := v_resume_deleted_total   + COALESCE((v_child->>'resume_objects_deleted')::int, 0);
        v_video_deleted_total    := v_video_deleted_total    + COALESCE((v_child->>'video_screenings_deleted')::int, 0);
        v_children_deleted_total := v_children_deleted_total  + COALESCE((v_child->>'child_rows_deleted')::int, 0);
        v_calib_scrubbed_total   := v_calib_scrubbed_total   + COALESCE((v_child->>'calibration_runs_scrubbed')::int, 0);

        -- audit (NO PII in the audit row: ids, anchors, counts only)
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'lgpd_premember_anonymization', 'selection_application', v_cand.application_id,
          jsonb_build_object(
            'anonymized_at', now(),
            'retention_anchor', v_cand.retention_anchor,
            'years_since_anchor', v_cand.years_since_anchor,
            'retention_years', p_years,
            'retention_years_withdrawn', p_years_withdrawn,
            'status_at_anonymization', v_cand.status,
            'legal_basis', 'LGPD Lei 13.709/2018 Art. 16 / Art. 6 III — pre-member candidate retention limit reached',
            'source', 'cron:anonymize_premember_applications',
            'resume_objects_deleted', COALESCE((v_child->>'resume_objects_deleted')::int, 0),
            'video_screenings_deleted', COALESCE((v_child->>'video_screenings_deleted')::int, 0),
            'child_rows_deleted', COALESCE((v_child->>'child_rows_deleted')::int, 0),
            'calibration_runs_scrubbed', COALESCE((v_child->>'calibration_runs_scrubbed')::int, 0),
            'external_video_binaries', 'pending_manual_or_ef_purge'
          ));
      END IF;

      v_count := v_count + 1;
      v_ids := array_append(v_ids, v_cand.application_id);
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object('application_id', v_cand.application_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'retention_years', p_years,
    'retention_years_withdrawn', p_years_withdrawn,
    'processed', v_count,
    'skipped', v_skipped,
    'application_ids', to_jsonb(v_ids),
    'resume_objects_deleted_total', v_resume_deleted_total,
    'video_screenings_deleted_total', v_video_deleted_total,
    'child_rows_deleted_total', v_children_deleted_total,
    'calibration_runs_scrubbed_total', v_calib_scrubbed_total,
    'errors', v_errors,
    'executed_at', now()
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Member anonymizer — resolve the member's application(s) by email and run the SHARED helper on
--    each (was: a LIGHT mother-row scrub + separate resume-by-email delete, NO child-table erasure).
--    Everything else (license preservation #976, member/offboarding/notification/affiliation scrub)
--    is preserved verbatim. Signature/SECDEF/grants unchanged.
--    NOTE: p_limit DEFAULT stays 100 to preserve the live signature (#976); the live cron jobid 15
--    passes p_limit := 500 explicitly. (Keep this note OUT of the arg list — an inline comment there
--    breaks the body-drift parser's arg-key normalization -> false Phase C drift.)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.anonymize_inactive_members(
  p_dry_run boolean DEFAULT true,
  p_years integer DEFAULT 5,
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_candidate record;
  v_count int := 0;
  v_skipped int := 0;
  v_license_preserved int := 0;  -- #976 PR-4
  v_ids uuid[] := '{}';
  v_errors jsonb := '[]'::jsonb;
  v_aff_scrubbed int := 0;  -- #625
  -- #946 shared-helper aggregation
  v_app_ids uuid[];
  v_app_id uuid;
  v_child jsonb;
  v_resume_deleted_total int := 0;
  v_video_deleted_total int := 0;
  v_children_deleted_total int := 0;
  v_calib_scrubbed_total int := 0;
  v_c_resume int;
  v_c_video int;
  v_c_children int;
  v_c_calib int;
  v_c_apps int;
BEGIN
  FOR v_candidate IN
    SELECT * FROM public.list_anonymization_candidates(p_years) LIMIT p_limit
  LOOP
    BEGIN
      -- #976 PR-4 (15.4.5 / §9.1 Opção B): preserva quem detém licença viva (signature
      -- is_current). Um voluntário desligado por recusa/lapso de re-aceite mantém suas
      -- licenças; a linha de assinatura (que materializa a licença de PI) não pode ser
      -- anonimizada enquanto a licença vigorar.
      IF EXISTS (SELECT 1 FROM public.member_document_signatures mds
                 WHERE mds.member_id = v_candidate.member_id AND mds.is_current = true) THEN
        v_skipped := v_skipped + 1;
        v_license_preserved := v_license_preserved + 1;
        -- review (legal HIGH): visibilidade ao DPO — o deferimento por licença de PI não é silencioso;
        -- requisições LGPD Art.18(IV) desse titular roteiam ao DPO (Art.16(I) × Art.18(IV)).
        IF NOT p_dry_run THEN
          INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
          VALUES (NULL, 'lgpd.anonymization_deferred_ip_license', 'member', v_candidate.member_id,
            jsonb_build_object(
              'legal_basis', 'LGPD Art. 16(I) — IP license enforcement (Termo 15.4.5)',
              'art18_requests_require_dpo_review', true, 'signature_is_current', true,
              'source', 'cron:anonymize_inactive_members'));
        END IF;
        CONTINUE;
      END IF;

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

        -- #946: erase the member's prior selection application(s) uniformly via the shared helper.
        -- Resolve the application ids by the candidate's (pre-scrub) email — the SAME set the old
        -- light scrub reached — snapshotting the ids first (the helper mutates the mother-row email).
        -- The helper covers the resume binary, ALL child tables, the full mother-row scrub, and the
        -- ai_calibration_runs.sample_payload name scrub (previously the member path left all of these).
        v_c_resume := 0; v_c_video := 0; v_c_children := 0; v_c_calib := 0; v_c_apps := 0;
        SELECT array_agg(id) INTO v_app_ids
        FROM public.selection_applications WHERE email = v_candidate.email;
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
        v_resume_deleted_total   := v_resume_deleted_total   + v_c_resume;
        v_video_deleted_total    := v_video_deleted_total    + v_c_video;
        v_children_deleted_total := v_children_deleted_total  + v_c_children;
        v_calib_scrubbed_total   := v_calib_scrubbed_total   + v_c_calib;

        -- #625 F1: de-identifica a trilha de verificação de filiação do titular (subject).
        -- A linha de members já foi anonimizada acima (in-place), então member_id/verified_by
        -- de-referenciam para registro neutro; aqui só zera os campos livres/técnicos.
        UPDATE public.member_affiliation_verifications SET
          verification_obs = NULL,
          source_ref = CASE WHEN source_ref IS NOT NULL THEN md5(source_ref) ELSE NULL END,
          verified_by_member_id = NULL  -- #625: desreferencia o verificador (minimização Art. 6º III)
        WHERE member_id = v_candidate.member_id;
        GET DIAGNOSTICS v_aff_scrubbed = ROW_COUNT;

        -- #625: remove notificações de filiação SOBRE o titular enviadas a TERCEIROS (ex.: diretor),
        -- cujo body carrega o nome e não é limpo pela deleção das notificações do próprio titular acima.
        DELETE FROM public.notifications
        WHERE source_type = 'affiliation' AND source_id = v_candidate.member_id;

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
            'applications_erased', v_c_apps,
            'resume_objects_deleted', v_c_resume,
            'video_screenings_deleted', v_c_video,
            'child_rows_deleted', v_c_children,
            'calibration_runs_scrubbed', v_c_calib,
            'affiliation_rows_scrubbed', v_aff_scrubbed
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
    'license_preserved', v_license_preserved,  -- #976 PR-4
    'member_ids', to_jsonb(v_ids),
    'resume_objects_deleted_total', v_resume_deleted_total,
    'video_screenings_deleted_total', v_video_deleted_total,
    'child_rows_deleted_total', v_children_deleted_total,
    'calibration_runs_scrubbed_total', v_calib_scrubbed_total,
    'errors', v_errors,
    'executed_at', now()
  );
END;
$function$;

-- The member path now ALSO sets selection_applications.anonymized_at (via the helper), which cleanly
-- prevents the pre-member cron from re-touching an already-erased ex-member application.
COMMENT ON COLUMN public.selection_applications.anonymized_at IS
  '#905/#946 LGPD: when this selection application had its PII scrubbed by the shared _erase_application_pii helper (from either anonymize_premember_applications or anonymize_inactive_members). NULL = not anonymized.';

NOTIFY pgrst, 'reload schema';
