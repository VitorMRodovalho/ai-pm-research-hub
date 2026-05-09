-- p125 E1 Migration 5/5 — Bifurcated retention + CASCADE extension to new tables
-- ADR-0076 Princípio 6 (retention bifurcated) + Risk 2 pre-mortem (CASCADE coverage)
-- Decision 7: 5y active members / 12m applicants rejected / 90d free-text bio
-- Wave 1 draft (council review pending Wave 2)
--
-- Adds:
--   1. Helper anonymize_pmi_cascade(p_person_id) — clears new tables for given person
--   2. New function anonymize_rejected_applicants(p_dry_run, p_months, p_limit)
--      — bifurcated retention 12 months for status IN ('declined','withdrawn','removed','expired')
--   3. New function anonymize_free_text_bios(p_dry_run, p_days, p_limit)
--      — 90 days clearing of profile_about_me, non_pmi_experience, motivation_letter
--   4. pg_cron schedule additions for new functions
--
-- DOES NOT modify base anonymize_inactive_members yet (Wave 2 council reviews
-- whether to splice helper call here or in separate migration). Wave 1 provides
-- helper + new functions; integration into existing cron is Wave 2 task.
--
-- Rollback: DROP FUNCTION ... + remove pg_cron schedules.

BEGIN;

-- ─── Helper 1: CASCADE coverage for new tables (Risk 2 pre-mortem) ──────────
DROP FUNCTION IF EXISTS public.anonymize_pmi_cascade(uuid);

CREATE FUNCTION public.anonymize_pmi_cascade(p_person_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pcm_deleted integer := 0;
  v_sh_deleted integer := 0;
  v_member_ids uuid[];
BEGIN
  -- DELETE pmi_chapter_memberships for this person
  DELETE FROM public.pmi_chapter_memberships
  WHERE person_id = p_person_id;
  GET DIAGNOSTICS v_pcm_deleted = ROW_COUNT;

  -- For each member of this person, find their applications + delete service_history
  SELECT array_agg(id) INTO v_member_ids
  FROM public.members WHERE person_id = p_person_id;

  IF v_member_ids IS NOT NULL THEN
    DELETE FROM public.selection_application_service_history sh
    WHERE sh.application_id IN (
      SELECT sa.id FROM public.selection_applications sa
      WHERE sa.email IN (
        SELECT email FROM public.members WHERE id = ANY(v_member_ids)
      )
    );
    GET DIAGNOSTICS v_sh_deleted = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'person_id', p_person_id,
    'pmi_chapter_memberships_deleted', v_pcm_deleted,
    'service_history_deleted', v_sh_deleted
  );
END;
$$;

COMMENT ON FUNCTION public.anonymize_pmi_cascade(uuid) IS
  'CASCADE coverage for p125 new tables (pmi_chapter_memberships, selection_application_service_history) when persons anonymized via UPDATE pattern (não DELETE). Called by anonymize_inactive_members. ADR-0076 Princípio 6 + Risk 2 pre-mortem.';

REVOKE ALL ON FUNCTION public.anonymize_pmi_cascade(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymize_pmi_cascade(uuid) TO service_role;

-- ─── New cron 1: 12-month retention for rejected applicants (Decision 7) ────
DROP FUNCTION IF EXISTS public.anonymize_rejected_applicants(boolean, int, int);

CREATE FUNCTION public.anonymize_rejected_applicants(
  p_dry_run boolean DEFAULT true,
  p_months int DEFAULT 12,
  p_limit int DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_candidate record;
  v_count int := 0;
  v_skipped int := 0;
  v_ids uuid[] := '{}';
BEGIN
  FOR v_candidate IN
    SELECT id, email, applicant_name, status, cycle_decision_date
    FROM public.selection_applications
    WHERE status IN ('declined','withdrawn','removed','expired')
      AND cycle_decision_date IS NOT NULL
      AND cycle_decision_date <= now() - (p_months || ' months')::interval
      AND (applicant_name IS NULL OR applicant_name NOT LIKE 'Applicant Anonimizado #%')
    LIMIT p_limit
  LOOP
    BEGIN
      IF NOT p_dry_run THEN
        UPDATE public.selection_applications SET
          applicant_name      = 'Applicant Anonimizado #' || SUBSTR(v_candidate.id::text, 1, 8),
          email               = 'anon_' || SUBSTR(v_candidate.id::text, 1, 8) || '@removed.local',
          first_name          = NULL,
          last_name           = NULL,
          phone               = NULL,
          pmi_id              = NULL,
          linkedin_url        = NULL,
          resume_url          = NULL,
          motivation_letter   = NULL,
          non_pmi_experience  = NULL,
          academic_background = NULL,
          leadership_experience = NULL,
          areas_of_interest   = NULL,
          proposed_theme      = NULL,
          chapter_affiliation = NULL,
          referral_source     = NULL,
          utm_data            = NULL,
          cv_extracted_text   = NULL,
          ai_analysis         = NULL,
          ai_triage_reasoning = NULL,
          last_briefing_jsonb = NULL,
          -- Phase B fields cleared (Wave 2 fix: full PII coverage per ADR-0076 Princípio 6)
          profile_location    = NULL,
          profile_state       = NULL,
          profile_city        = NULL,
          profile_country     = NULL,
          profile_industry    = NULL,
          profile_company     = NULL,
          profile_designation = NULL,
          profile_certifications = NULL,
          profile_volunteer_interest = NULL,
          profile_specialties = NULL,
          profile_linkedin_url = NULL,
          profile_about_me    = NULL,
          applicant_city      = NULL,
          pmi_memberships     = NULL,
          service_history_chapters = NULL,
          service_history_count = NULL,
          service_first_start_date = NULL,
          service_latest_end_date = NULL,
          is_open_to_volunteer = NULL,
          pmi_data_fetched_at = NULL,
          consent_version     = NULL,
          updated_at          = now()
        WHERE id = v_candidate.id;

        -- DELETE child service_history rows
        DELETE FROM public.selection_application_service_history
        WHERE application_id = v_candidate.id;
      END IF;

      v_count := v_count + 1;
      v_ids := v_ids || v_candidate.id;
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      -- Wave 2 fix (security-engineer B2): log skipped rows to data_anomaly_log
      -- Silent skips would constitute LGPD Art. 18 §VI violation (right-to-erasure incomplete)
      INSERT INTO public.data_anomaly_log (anomaly_type, severity, message, details)
      VALUES (
        'lgpd_anonymize_rejected_skipped',
        'high',
        'Failed to anonymize rejected applicant: ' || SQLERRM,
        jsonb_build_object(
          'application_id', v_candidate.id,
          'cycle_decision_date', v_candidate.cycle_decision_date,
          'sqlerrm', SQLERRM,
          'sqlstate', SQLSTATE,
          'function', 'anonymize_rejected_applicants',
          'months_threshold', p_months
        )
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'processed', v_count,
    'skipped', v_skipped,
    'ids', v_ids,
    'months', p_months,
    'finished_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.anonymize_rejected_applicants(boolean, int, int) IS
  'p125 ADR-0076 Princípio 6: bifurcated retention 12 months para applicants rejected/declined/withdrawn/removed/expired. CALL via pg_cron weekly. Decision 7.';

REVOKE ALL ON FUNCTION public.anonymize_rejected_applicants(boolean, int, int) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymize_rejected_applicants(boolean, int, int) TO service_role;

-- ─── New cron 2: 90-day clearing of free-text bios (Decision 7 + Princípio 4) ─
DROP FUNCTION IF EXISTS public.anonymize_free_text_bios(boolean, int, int);

CREATE FUNCTION public.anonymize_free_text_bios(
  p_dry_run boolean DEFAULT true,
  p_days int DEFAULT 90,
  p_limit int DEFAULT 500
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_candidate record;
  v_count int := 0;
  v_ids uuid[] := '{}';
BEGIN
  FOR v_candidate IN
    -- Wave 2 fix (legal-counsel B1): use COALESCE(pmi_data_fetched_at, imported_at, created_at)
    -- as retention anchor. created_at is row-creation in our DB (= import time);
    -- LGPD-correct anchor is when Núcleo OBTAINED the data (Phase B fetch ou import).
    -- Wave 3 synth (Decision S8): exclude apps still within 60-day appeal window
    -- per ADR-0067 D4 (30-day appeal post-cycle-close + 30-day buffer).
    SELECT id, COALESCE(pmi_data_fetched_at, imported_at, created_at) AS retention_anchor
    FROM public.selection_applications sa
    WHERE COALESCE(pmi_data_fetched_at, imported_at, created_at) <= now() - (p_days || ' days')::interval
      AND (
        profile_about_me IS NOT NULL OR
        non_pmi_experience IS NOT NULL OR
        motivation_letter IS NOT NULL
      )
      -- Appeal window protection: skip if cycle closed within last 60 days
      -- (preserves motivation_letter etc. for committee review during appeal window)
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_cycles sc
        WHERE sc.id = sa.cycle_id
          AND sc.status = 'closed'
          AND sc.close_date IS NOT NULL
          AND sc.close_date > now() - interval '60 days'
      )
    LIMIT p_limit
  LOOP
    IF NOT p_dry_run THEN
      UPDATE public.selection_applications SET
        profile_about_me   = NULL,
        non_pmi_experience = NULL,
        motivation_letter  = NULL,
        updated_at         = now()
      WHERE id = v_candidate.id;
    END IF;

    v_count := v_count + 1;
    v_ids := v_ids || v_candidate.id;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'processed', v_count,
    'ids', v_ids,
    'days', p_days,
    'finished_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.anonymize_free_text_bios(boolean, int, int) IS
  'p125 ADR-0076 Princípio 6: 90-day clearing of profile_about_me + non_pmi_experience + motivation_letter regardless of selection status. Art. 11 priority (sensitive data latente em texto livre). Decision 7. CALL via pg_cron weekly.';

REVOKE ALL ON FUNCTION public.anonymize_free_text_bios(boolean, int, int) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymize_free_text_bios(boolean, int, int) TO service_role;

-- ─── pg_cron schedules ──────────────────────────────────────────────────────
-- Weekly cleanup runs (Wave 2 council reviews schedule timing)
-- Sunday 03:00 UTC = Sunday 00:00 BRT = low-traffic
DO $$
BEGIN
  -- Schedule rejected applicants cleanup (12-month retention)
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'anonymize_rejected_applicants_weekly') THEN
    PERFORM cron.schedule(
      'anonymize_rejected_applicants_weekly',
      '0 3 * * 0',  -- Sunday 03:00 UTC
      $cron$SELECT public.anonymize_rejected_applicants(false, 12, 200);$cron$
    );
  END IF;

  -- Schedule free-text bios cleanup (90-day retention)
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'anonymize_free_text_bios_weekly') THEN
    PERFORM cron.schedule(
      'anonymize_free_text_bios_weekly',
      '30 3 * * 0',  -- Sunday 03:30 UTC
      $cron$SELECT public.anonymize_free_text_bios(false, 90, 500);$cron$
    );
  END IF;
END $$;

-- ─── Wave 2 TODO: integrate anonymize_pmi_cascade into anonymize_inactive_members ──
-- The existing anonymize_inactive_members (in 20260410160000) does
-- UPDATE public.members SET email='anon_...' but does NOT touch persons NOR
-- new tables. Risk 2 pre-mortem materializa se não integrarmos:
--
-- Decision needed at Wave 2:
--   Option A: CREATE OR REPLACE FUNCTION anonymize_inactive_members in this migration,
--             splicing in `PERFORM public.anonymize_pmi_cascade(v_candidate.person_id)`
--             before/after the UPDATE members. Complete but copies large body.
--   Option B: Separate migration 20260518050000 that does CREATE OR REPLACE only
--             for that purpose. Cleaner separation, smaller diff.
--   Option C: Add AFTER UPDATE trigger on members.anonymized_at column that calls
--             anonymize_pmi_cascade automatically. Decoupled, idiomatic, but adds
--             trigger surface.
--
-- Recommend Wave 2: Option B for clarity + reversibility.

COMMIT;

-- Post-apply checklist:
--   1. supabase migration repair --status applied 20260518040000
--   2. NOTIFY pgrst, 'reload schema'
--   3. Test dry-run: SELECT * FROM anonymize_rejected_applicants(true, 12, 10);
--      Expect: jsonb with processed count, dry_run=true
--   4. Test dry-run: SELECT * FROM anonymize_free_text_bios(true, 90, 10);
--   5. Verify cron schedules: SELECT jobname, schedule, command FROM cron.job
--      WHERE jobname LIKE 'anonymize_%'
--   6. Wave 2 council: choose Option A/B/C for anonymize_inactive_members integration
