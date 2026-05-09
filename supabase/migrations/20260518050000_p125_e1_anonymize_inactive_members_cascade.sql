-- p125 E1 Migration 5b/7 — anonymize_inactive_members CASCADE for new tables
-- Decision B3 (locked 2026-05-09): separate migration for cleaner diff/review/rollback
-- Risk 2 pre-mortem: ensure anonymize_inactive_members CASCADEs to p125 new tables
-- Wave 1 draft (council review pending Wave 2)
--
-- Changes from previous body (20260410160000):
--   1. Added PERFORM anonymize_pmi_cascade(v_person_id) before UPDATE members
--      → clears pmi_chapter_memberships + selection_application_service_history
--   2. Extended UPDATE selection_applications to clear Phase B fields too
--      (defense-in-depth even though anonymize_rejected_applicants is primary
--      gate for application-side cleanup)
--   3. Captures person_id of member into v_person_id local var
--
-- Rollback: restore body from 20260410160000.

BEGIN;

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
  v_person_id uuid;  -- p125: for CASCADE to new tables
  v_cascade_result jsonb;  -- p125
BEGIN
  FOR v_candidate IN
    SELECT * FROM public.list_anonymization_candidates(p_years) LIMIT p_limit
  LOOP
    BEGIN
      -- p125: capture person_id for CASCADE to pmi_chapter_memberships +
      -- selection_application_service_history (Risk 2 pre-mortem mitigation)
      SELECT person_id INTO v_person_id
      FROM public.members WHERE id = v_candidate.member_id;

      IF NOT p_dry_run THEN
        -- p125: CASCADE to new tables BEFORE the members UPDATE.
        -- Order matters: do CASCADE while person_id is still resolvable;
        -- the UPDATE doesn't change person_id but doing this first is defense
        -- in depth in case future iteration nullifies person_id during anonymize.
        IF v_person_id IS NOT NULL THEN
          v_cascade_result := public.anonymize_pmi_cascade(v_person_id);
        END IF;

        UPDATE public.members SET
          name           = 'Membro Anonimizado #' || SUBSTR(v_candidate.member_id::text, 1, 8),
          email          = 'anon_' || SUBSTR(v_candidate.member_id::text, 1, 8) || '@removed.local',
          phone          = NULL,
          phone_encrypted = NULL,
          pmi_id         = NULL,
          pmi_id_encrypted = NULL,
          linkedin_url   = NULL,
          photo_url      = NULL,
          credly_url     = NULL,
          credly_badges  = NULL,
          address        = NULL,
          city           = NULL,
          birth_date     = NULL,
          state          = NULL,
          country        = NULL,
          signature_url  = NULL,
          secondary_emails = NULL,
          last_active_pages = NULL,
          auth_id        = NULL,
          secondary_auth_ids = NULL,
          is_active      = false,
          member_status  = 'archived',
          anonymized_at  = now(),
          anonymized_by  = NULL,  -- NULL = automated
          updated_at     = now()
        WHERE id = v_candidate.member_id;

        DELETE FROM public.notifications WHERE member_id = v_candidate.member_id;
        DELETE FROM public.notification_preferences WHERE member_id = v_candidate.member_id;

        -- p125: extended UPDATE to clear Phase B fields too (defense-in-depth)
        -- Wave 2 fix: full PII coverage per ADR-0076 Princípio 6 (was missing 6 cols)
        UPDATE public.selection_applications SET
          applicant_name      = 'Candidato Anonimizado',
          email               = 'anon@removed.local',
          phone               = NULL,
          linkedin_url        = NULL,
          resume_url          = NULL,
          motivation_letter   = NULL,
          -- p125 Phase B fields
          applicant_city      = NULL,
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
          pmi_memberships     = NULL,
          service_history_chapters = NULL,
          service_history_count = NULL,
          service_first_start_date = NULL,
          service_latest_end_date = NULL,
          is_open_to_volunteer = NULL,
          pmi_data_fetched_at = NULL,
          consent_version     = NULL,
          updated_at          = now()
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
            -- p125: log CASCADE result for audit + Invariant I_LGPD_ERASURE_COMPLETENESS
            'p125_cascade', v_cascade_result,
            'p125_person_id', v_person_id
          ));
      END IF;

      v_count := v_count + 1;
      v_ids := array_append(v_ids, v_candidate.member_id);
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object(
        'member_id', v_candidate.member_id,
        'person_id', v_person_id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'years_threshold', p_years,
    'processed', v_count,
    'skipped', v_skipped,
    'member_ids', to_jsonb(v_ids),
    'errors', v_errors,
    'p125_cascade_enabled', true,
    'executed_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.anonymize_inactive_members(boolean, int, int) IS
  'p125 (2026-05-09): extended with CASCADE to pmi_chapter_memberships + selection_application_service_history via anonymize_pmi_cascade(person_id) helper. Risk 2 pre-mortem mitigation. ADR-0076 Princípio 6. Decision B3 (separate migration). UPDATE selection_applications also clears Phase B fields.';

COMMIT;

-- Post-apply checklist:
--   1. supabase migration repair --status applied 20260518050000
--   2. NOTIFY pgrst, 'reload schema'
--   3. Smoke test dry-run: SELECT public.anonymize_inactive_members(true, 5, 5);
--      Expect: dry_run=true, p125_cascade_enabled=true
--   4. Verify Invariant I_LGPD_ERASURE_COMPLETENESS após próximo cron run:
--      SELECT * FROM check_schema_invariants_p125()
--      WHERE invariant_name = 'I_LGPD_ERASURE_COMPLETENESS';
--      Expected: violation_count = 0
