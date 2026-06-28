-- #905 — LGPD retention/erasure path for PRE-MEMBER rejected/withdrawn selection applications.
--
-- Problem (grounded 2026-06-28): anonymize_inactive_members (the 5y LGPD cron) is MEMBER-anchored
-- (loops list_anonymization_candidates over members inactivity, scrubs selection_applications only
-- WHERE email = member.email). Candidates who NEVER became members (rejected/withdrawn pre-members)
-- are never reached -> their PII (name/email/phone/linkedin/resume/motivation + AI dossier + interview
-- notes + video/voice transcription + PMI membership snapshots) is retained indefinitely.
-- Latent LGPD minimization gap (Art. 6 III / Art. 16). Not a breach (RLS denies anon), but no
-- scheduled erasure path exists.
--
-- This migration adds an INDEPENDENT, member_id-agnostic erasure path anchored on the candidate's
-- end-of-purpose date (cycle_decision_date, falling back to created_at) + a NOT EXISTS member check.
--
-- Live grounding at build time (2026-06-28):
--   * 46 terminal rows (rejected 45 + withdrawn 1); 35 have NO member by email.
--   * Candidate pool = 29 (35 minus the 6 VEP-expired+cutoff-approved rows that belong to the #935
--     re-application track, which we EXCLUDE here to keep them actionable).
--   * Eligible TODAY under 5y/2y/1y window = 0/0/0 (all anchors in 2026). Build is risk-free.
--
-- POSTURE: the cron is registered DORMANT (active=false). Go-live = legal-counsel ratifies the
-- retention window(s) + flip the cron active. Until then this is a built-but-idle mechanism (no row
-- is eligible anyway). p_dry_run defaults to true.
--
-- Council review (legal-counsel + security-engineer + data-architect, 2026-06-28) incorporated:
--   * Anchor uses COALESCE(cycle_decision_date, created_at) — NOT updated_at (the pmi-vep-sync worker
--     bumps updated_at on rejected rows, which would silently extend the window with no legal basis).
--   * no-member guard covers primary email + member_emails table + members.secondary_emails array,
--     all trim(lower())-normalized (so a now-member who applied under a different primary email and
--     later added the application email as an alternate is NOT erased).
--   * Erasure follows PII into the PII-bearing CASCADE children, not just the mother row.
--   * Withdrawn (candidate opt-out) gets an OPTIONAL shorter window via p_years_withdrawn (forward-
--     ready; defaults to p_years until legal ratifies — recommendation: rejected 2y / withdrawn 1y).
--
-- RESIDUAL CLASSIFICATION (legal-counsel): after scrubbing identifiers + free-text, the row retains
-- scores/ranks/pert + demographic bands (gender/age_band/industry/sector/seniority) + coarse geo
-- (chapter/state/country) + cycle_id. In a small cohort this combination may be k=1 -> it is
-- PSEUDONYMIZED (restricted to service_role), NOT anonymized under Art. 5 III. Acceptable for
-- cohort/equity analytics under Art. 16 III, but classify it as pseudonymized in the RoPA and obtain
-- legal sign-off on k-anonymity + the retention window BEFORE activating the cron.
--
-- GO-LIVE CHECKLIST (from the legal parecer R1-R5; tracked, not blocking this dormant build):
--   R1 ratify windows (rejected 2y / withdrawn 1y) and set them on the cron command.
--   R2 time-bound the #935 exclusion to the active cycle (+grace) so those 6 don't stay excluded forever.
--   R3 map+purge external video binaries (Drive/YouTube) referenced by pmi_video_screenings before erasure.
--   R4 confirm the legal basis (Art. 11 I) for voice/video collection on the candidacy form.
--   R5 RoPA entries + record the dormant cron with a max activation deadline.
--   Follow-up: ai_calibration_runs.sample_payload retains applicant_name for historical runs (scrub
--   for anonymized application ids) — affects the member path too; track as its own issue.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. anonymized_at marker on the mother table
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS anonymized_at timestamptz;

COMMENT ON COLUMN public.selection_applications.anonymized_at IS
  '#905 LGPD: when this pre-member candidate row had its PII scrubbed by anonymize_premember_applications (retention-limit erasure). NULL = not anonymized. The member-anchored anonymize_inactive_members does NOT set this.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Candidate lister (PRIVACY-MINIMAL output: ids + dates only, no PII)
--    p_years        = retention window for rejected candidates (years)
--    p_years_withdrawn = optional shorter window for withdrawn (opt-out) candidates; NULL = use p_years
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_premember_anonymization_candidates(
  p_years integer DEFAULT 5,
  p_years_withdrawn integer DEFAULT NULL
)
RETURNS TABLE(
  application_id uuid,
  cycle_id uuid,
  status text,
  vep_status_raw text,
  retention_anchor timestamptz,
  years_since_anchor numeric,
  has_resume boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    sa.id,
    sa.cycle_id,
    sa.status,
    sa.vep_status_raw,
    COALESCE(sa.cycle_decision_date, sa.created_at) AS retention_anchor,
    ROUND(
      (EXTRACT(EPOCH FROM (now() - COALESCE(sa.cycle_decision_date, sa.created_at))) / 31557600.0)::numeric
    , 2) AS years_since_anchor,
    (sa.resume_storage_path IS NOT NULL) AS has_resume
  FROM public.selection_applications sa
  WHERE sa.anonymized_at IS NULL
    -- terminal pre-member statuses only
    AND sa.status IN ('rejected','withdrawn')
    -- pre-member: the application email is not tied to ANY member (primary, alternate table, or array)
    AND NOT EXISTS (
      SELECT 1 FROM public.members m WHERE trim(lower(m.email)) = trim(lower(sa.email))
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.member_emails me WHERE trim(lower(me.email)) = trim(lower(sa.email))
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.members m2
      WHERE m2.secondary_emails IS NOT NULL
        AND EXISTS (SELECT 1 FROM unnest(m2.secondary_emails) se WHERE trim(lower(se)) = trim(lower(sa.email)))
    )
    -- protect the #935 VEP-expired re-application cohort (administrative lapse, still actionable):
    -- cutoff-approved + VEP terminal-by-expiry must NOT be erased here.
    AND NOT (
      sa.cutoff_approved_email_sent_at IS NOT NULL
      AND sa.vep_status_raw IN ('Expired','OfferExpired','OfferNotExtended')
    )
    -- retention window elapsed (withdrawn may get a shorter window)
    AND COALESCE(sa.cycle_decision_date, sa.created_at)
        < (now() - make_interval(years =>
             CASE WHEN sa.status = 'withdrawn' THEN COALESCE(p_years_withdrawn, p_years)
                  ELSE p_years END))
  ORDER BY retention_anchor ASC;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Anonymizer (dry-run by default; per-application loop with error isolation)
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
  v_resume_path text;
  v_resume_deleted int;
  v_resume_deleted_total int := 0;
  v_video_deleted int;
  v_video_deleted_total int := 0;
  v_children_deleted int;
  v_children_deleted_total int := 0;
BEGIN
  FOR v_cand IN
    SELECT * FROM public.list_premember_anonymization_candidates(p_years, p_years_withdrawn) LIMIT p_limit
  LOOP
    BEGIN
      IF NOT p_dry_run THEN
        -- (a) delete the resume binary from storage (path lives on the mother row)
        v_resume_deleted := 0;
        SELECT sa.resume_storage_path INTO v_resume_path
        FROM public.selection_applications sa WHERE sa.id = v_cand.application_id;
        IF v_resume_path IS NOT NULL THEN
          DELETE FROM storage.objects
          WHERE bucket_id = 'selection-resumes' AND name = v_resume_path;
          GET DIAGNOSTICS v_resume_deleted = ROW_COUNT;
          v_resume_deleted_total := v_resume_deleted_total + v_resume_deleted;
        END IF;

        -- (b) DELETE biometric-adjacent video screenings (transcription + Drive/YouTube links).
        --     External binaries (Drive/YouTube) are not reachable from SQL -> follow-up cleanup (R3).
        DELETE FROM public.pmi_video_screenings WHERE application_id = v_cand.application_id;
        GET DIAGNOSTICS v_video_deleted = ROW_COUNT;
        v_video_deleted_total := v_video_deleted_total + v_video_deleted;

        -- (c) DELETE pure candidate-derived child content (no aggregate value once subject erased).
        --     selection_dispatch_url_log + onboarding_progress have NO ON DELETE CASCADE -> explicit.
        v_children_deleted := 0;
        DELETE FROM public.ai_analysis_runs                     WHERE application_id = v_cand.application_id;
        GET DIAGNOSTICS v_children_deleted = ROW_COUNT; v_children_deleted_total := v_children_deleted_total + v_children_deleted;
        DELETE FROM public.ai_processing_log                    WHERE application_id = v_cand.application_id;
        GET DIAGNOSTICS v_children_deleted = ROW_COUNT; v_children_deleted_total := v_children_deleted_total + v_children_deleted;
        DELETE FROM public.ai_score_validations                 WHERE application_id = v_cand.application_id;
        GET DIAGNOSTICS v_children_deleted = ROW_COUNT; v_children_deleted_total := v_children_deleted_total + v_children_deleted;
        DELETE FROM public.selection_evaluation_ai_suggestions  WHERE application_id = v_cand.application_id;
        GET DIAGNOSTICS v_children_deleted = ROW_COUNT; v_children_deleted_total := v_children_deleted_total + v_children_deleted;
        DELETE FROM public.selection_membership_snapshots       WHERE application_id = v_cand.application_id;
        GET DIAGNOSTICS v_children_deleted = ROW_COUNT; v_children_deleted_total := v_children_deleted_total + v_children_deleted;
        DELETE FROM public.selection_application_service_history WHERE application_id = v_cand.application_id;
        GET DIAGNOSTICS v_children_deleted = ROW_COUNT; v_children_deleted_total := v_children_deleted_total + v_children_deleted;
        DELETE FROM public.selection_topic_views                WHERE application_id = v_cand.application_id;
        GET DIAGNOSTICS v_children_deleted = ROW_COUNT; v_children_deleted_total := v_children_deleted_total + v_children_deleted;
        DELETE FROM public.selection_dispatch_url_log           WHERE application_id = v_cand.application_id;
        GET DIAGNOSTICS v_children_deleted = ROW_COUNT; v_children_deleted_total := v_children_deleted_total + v_children_deleted;
        DELETE FROM public.onboarding_progress                  WHERE application_id = v_cand.application_id;
        GET DIAGNOSTICS v_children_deleted = ROW_COUNT; v_children_deleted_total := v_children_deleted_total + v_children_deleted;

        -- (d) SCRUB free-text but KEEP structured scores (de-identified cohort/fairness analytics)
        UPDATE public.selection_evaluations
           SET notes = NULL, criterion_notes = NULL
         WHERE application_id = v_cand.application_id;
        UPDATE public.selection_interviews
           SET notes = NULL, theme_of_interest = NULL, calendar_event_id = NULL
         WHERE application_id = v_cand.application_id;
        UPDATE public.gate_attempts
           SET payload = NULL, gate_failed_reason = NULL
         WHERE application_id = v_cand.application_id;
        UPDATE public.selection_evaluation_anomalies
           SET payload = NULL
         WHERE application_id = v_cand.application_id;

        -- (e) SCRUB the mother row: direct identifiers + free-text + AI (incl. triage + scraped
        --     LinkedIn) + external VEP ids + voice evidence. Mirrors the consent-revocation purge
        --     (linkedin_relevant_posts / ai_pm_focus_tags / ai_triage_*). KEEP: human scores/ranks/
        --     pert/cohort_n, gender/age_band/industry/sector/seniority, coarse geo, cycle_id, status,
        --     tags (categorical), referral_source/referrer_member_id, consent_* ledger fields.
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
        WHERE id = v_cand.application_id;

        -- (f) audit (NO PII in the audit row: ids, anchors, counts only)
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
            'resume_objects_deleted', v_resume_deleted,
            'video_screenings_deleted', v_video_deleted,
            'child_rows_deleted', v_children_deleted_total,
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
    'errors', v_errors,
    'executed_at', now()
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Grants — mirror the member anonymizer: service_role only (revoke anon/authenticated/PUBLIC)
-- ─────────────────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.list_premember_anonymization_candidates(integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_premember_anonymization_candidates(integer, integer) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.anonymize_premember_applications(boolean, integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.anonymize_premember_applications(boolean, integer, integer, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_premember_anonymization_candidates(integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.anonymize_premember_applications(boolean, integer, integer, integer) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Cron (registered DORMANT: active=false until legal-counsel ratifies the retention window).
--    Go-live = set the ratified windows + SELECT cron.alter_job(jobid, active := true).
-- ─────────────────────────────────────────────────────────────────────────────
-- Use the cron.* function API only (the migration role cannot DML cron.job directly).
DO $cronsetup$
DECLARE
  v_jobid bigint;
BEGIN
  v_jobid := cron.schedule(
    'lgpd-anonymize-premember-monthly',
    '15 4 1 * *',
    $cron$SELECT public.anonymize_premember_applications(p_dry_run := false, p_years := 5, p_years_withdrawn := NULL, p_limit := 500)$cron$
  );
  PERFORM cron.alter_job(v_jobid, active := false);
END
$cronsetup$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Surface in get_lgpd_cron_health (informational + pending counter + dormant-aware health).
--    Behavior-neutral while the premember cron is dormant (active=false): the existing 3-job
--    red/green logic over the original jobs is preserved unchanged.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_lgpd_cron_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_inactive_pending integer;
  v_jobs jsonb;
  v_health text;
  v_max_days_since integer;
  v_premember_pending integer;
  v_premember_active boolean;
  v_premember_registered boolean;
  v_premember_days_since numeric;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  SELECT count(*) INTO v_inactive_pending
  FROM public.members
  WHERE member_status IN ('alumni','observer','inactive')
    AND updated_at < now() - interval '5 years'
    AND (name IS NULL OR name NOT ILIKE 'Anonymous%');

  -- #905 pre-member pending (eligible NOW under a conservative 5y default window; 0 until 2031)
  SELECT count(*) INTO v_premember_pending
  FROM public.list_premember_anonymization_candidates(5);

  SELECT coalesce(bool_or(active), false), count(*) > 0
  INTO v_premember_active, v_premember_registered
  FROM cron.job WHERE jobname = 'lgpd-anonymize-premember-monthly';

  SELECT extract(epoch FROM (now() - max(d.start_time))) / 86400
  INTO v_premember_days_since
  FROM cron.job j
  LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
  WHERE j.jobname = 'lgpd-anonymize-premember-monthly';

  SELECT jsonb_object_agg(jobname, snapshot)
  INTO v_jobs
  FROM (
    SELECT
      j.jobname,
      jsonb_build_object(
        'jobid', j.jobid,
        'schedule', j.schedule,
        'active', j.active,
        'last_run_at', (SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid),
        'last_status', (SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1),
        'last_message', (SELECT return_message FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1),
        'days_since_last_run', (
          SELECT extract(epoch FROM (now() - max(start_time))) / 86400
          FROM cron.job_run_details d WHERE d.jobid = j.jobid
        ),
        'failed_runs_last_90d', (
          SELECT count(*) FROM cron.job_run_details d
          WHERE d.jobid = j.jobid AND d.status = 'failed' AND d.start_time >= now() - interval '90 days'
        )
      ) AS snapshot
    FROM cron.job j
    WHERE j.jobname IN ('lgpd-anonymize-inactive-monthly', 'v4-anonymize-by-kind-monthly', 'log-retention-monthly', 'lgpd-anonymize-premember-monthly')
  ) sub;

  -- Worst days-since across the original 3 retention jobs (NULL counted as 999 — never ran).
  -- The premember job is intentionally excluded from this red/green driver while dormant.
  SELECT max(coalesce(days, 999))::integer INTO v_max_days_since
  FROM (
    SELECT extract(epoch FROM (now() - max(d.start_time))) / 86400 AS days
    FROM cron.job j
    LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
    WHERE j.jobname IN ('lgpd-anonymize-inactive-monthly', 'v4-anonymize-by-kind-monthly', 'log-retention-monthly')
    GROUP BY j.jobid
  ) t;

  -- Health: red if any original job is overdue with pending work, OR the premember job is ACTIVE
  -- (i.e. legal has gone live) yet overdue with pending pre-member work. Dormant premember -> neutral.
  v_health := CASE
    WHEN v_premember_active AND v_premember_pending > 0 AND coalesce(v_premember_days_since, 999) > 35 THEN 'red'
    WHEN v_max_days_since <= 35 THEN 'green'
    WHEN v_max_days_since = 999 AND v_inactive_pending = 0 THEN 'yellow'
    WHEN v_inactive_pending > 0 AND v_max_days_since > 35 THEN 'red'
    ELSE 'yellow'
  END;

  RETURN jsonb_build_object(
    'pending_anonymization_inactive_5y', v_inactive_pending,
    'pending_premember_anonymization', v_premember_pending,
    'premember_anonymization', jsonb_build_object(
      'registered', v_premember_registered,
      'active', v_premember_active,
      'pending', v_premember_pending,
      'note', 'Dormant until legal-counsel ratifies the pre-member retention window (#905). Go-live = set windows + activate cron.'
    ),
    'cron_jobs', coalesce(v_jobs, '{}'::jsonb),
    'max_days_since_any_job_ran', v_max_days_since,
    'health_signal', v_health,
    'note', 'Monthly crons fire on 1st of month at 03:30/03:45/04:00/04:15 UTC. days_since=999 means never ran (newly registered).',
    'fetched_at', now()
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
