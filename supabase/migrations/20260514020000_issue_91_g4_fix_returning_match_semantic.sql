-- Issue #91 G4 — tighten is_returning_member predicate to match offboarded
-- members only (the data source the G4 panel actually queries).
--
-- Background:
--   * Migration 20260512040000 wired `get_application_returning_context` to read
--     `member_offboarding_records` and gate the panel on
--     `selection_applications.is_returning_member = true`.
--   * The live `import_vep_applications` body had drifted from
--     20260401020000_selection_journey_v2_schema.sql (no migration captured the
--     drift). Live logic flagged `is_returning_member = TRUE` whenever any
--     member matched by email (broad). Cycle3-2026 rows were imported earlier,
--     when an even older `EXISTS … is_active = true` predicate was active —
--     resulting in 0/9 returning candidates flagged in production.
--
-- This migration:
--   1. Captures the current live function body (closing the drift) AND tightens
--      the is_returning_member predicate to require an offboarding record on
--      the matched member (the exact data G4 surfaces).
--   2. Backfills cycle3-2026 (and any other historical rows) where the new
--      predicate would have flagged the application.
--
-- Rollback: revert to broad-match by replacing `v_is_returning_offboarded`
--           with `v_existing_member.id IS NOT NULL` in the INSERT and the
--           counter, then UPDATE … SET is_returning_member = false for any
--           rows where no offboarding record exists.

CREATE OR REPLACE FUNCTION public.import_vep_applications(
  p_cycle_id uuid,
  p_rows jsonb,
  p_opportunity_id text DEFAULT NULL::text,
  p_role text DEFAULT 'researcher'::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_row jsonb; v_imported int := 0; v_skipped_dedup int := 0;
  v_skipped_declined int := 0; v_skipped_active int := 0;
  v_flagged_review int := 0; v_updated_snapshots int := 0; v_returning int := 0;
  v_app_id uuid; v_vep_app_id text; v_vep_status text; v_email text;
  v_membership text; v_chapters text[]; v_has_partner boolean;
  v_existing_app_id uuid; v_existing_member record;
  v_prev_cycles text[]; v_app_count int; v_partner_codes text[];
  v_primary_chapter text; v_cycle record; v_essay_mapping jsonb;
  v_opp record; v_app_date date;
  v_motivation text; v_areas text; v_availability text;
  v_academic text; v_proposed text; v_leadership text; v_chapter_aff text;
  v_field text; v_essay_val text;
  v_is_returning_offboarded boolean;
BEGIN
  SELECT array_agg(chapter_code) INTO v_partner_codes FROM partner_chapters WHERE is_active = true;
  SELECT * INTO v_cycle FROM selection_cycles WHERE id = p_cycle_id;
  SELECT * INTO v_opp FROM vep_opportunities WHERE opportunity_id = p_opportunity_id;
  v_essay_mapping := coalesce(v_opp.essay_mapping, '{"1":"essay_q1","2":"essay_q2","3":"essay_q3","4":"essay_q4","5":"essay_q5"}'::jsonb);
  IF v_opp.role_default IS NOT NULL THEN p_role := v_opp.role_default; END IF;

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_vep_app_id := v_row->>'application_id';
    v_vep_status := v_row->>'app_status';
    v_email := lower(trim(v_row->>'email'));
    v_membership := v_row->>'membership_status';

    IF v_vep_status IN ('OfferNotExtended', 'Declined', 'Withdrawn') THEN
      v_skipped_declined := v_skipped_declined + 1; CONTINUE;
    END IF;

    v_chapters := parse_vep_chapters(v_membership);
    v_has_partner := v_chapters && v_partner_codes;

    IF v_vep_status IN ('Active', 'Complete') THEN
      SELECT id INTO v_existing_app_id FROM selection_applications WHERE lower(email) = v_email LIMIT 1;
      IF v_existing_app_id IS NOT NULL THEN
        INSERT INTO selection_membership_snapshots (application_id, membership_status, chapter_affiliations, certifications, is_partner_chapter, source)
        VALUES (v_existing_app_id, v_membership, v_chapters, v_row->>'certifications', v_has_partner, 'csv_active_snapshot');
        v_updated_snapshots := v_updated_snapshots + 1;
      END IF;
      v_skipped_active := v_skipped_active + 1; CONTINUE;
    END IF;

    SELECT id INTO v_existing_app_id FROM selection_applications WHERE vep_application_id = v_vep_app_id;
    IF v_existing_app_id IS NOT NULL THEN
      INSERT INTO selection_membership_snapshots (application_id, membership_status, chapter_affiliations, certifications, is_partner_chapter, source)
      VALUES (v_existing_app_id, v_membership, v_chapters, v_row->>'certifications', v_has_partner, 'csv_reimport');
      v_updated_snapshots := v_updated_snapshots + 1;
      v_skipped_dedup := v_skipped_dedup + 1; CONTINUE;
    END IF;

    SELECT id, is_active, operational_role, offboarded_at, chapter INTO v_existing_member
    FROM members WHERE lower(email) = v_email LIMIT 1;

    -- p49: is_returning_member is true iff the matched member has an
    -- offboarding record. Matches the data source `get_application_returning_context`
    -- queries, so the G4 panel never renders for candidates without context.
    v_is_returning_offboarded := v_existing_member.id IS NOT NULL AND EXISTS (
      SELECT 1 FROM member_offboarding_records mor WHERE mor.member_id = v_existing_member.id
    );

    IF v_existing_member.id IS NOT NULL AND v_existing_member.is_active = false THEN
      IF v_existing_member.offboarded_at IS NOT NULL
         AND v_existing_member.offboarded_at >= coalesce(v_cycle.open_date, '2026-01-01')::timestamptz THEN
        INSERT INTO data_anomaly_log (anomaly_type, severity, message, details)
        VALUES ('selection_import_flagged_current_cycle', 'high',
          'Candidato inativado no ciclo corrente: ' || (v_row->>'first_name') || ' ' || (v_row->>'last_name'),
          jsonb_build_object('email', v_email, 'member_id', v_existing_member.id,
            'offboarded_at', v_existing_member.offboarded_at, 'vep_app_id', v_vep_app_id));
        v_flagged_review := v_flagged_review + 1; CONTINUE;
      END IF;
    END IF;

    v_primary_chapter := NULL;
    IF v_existing_member.id IS NOT NULL AND v_existing_member.chapter IS NOT NULL THEN
      v_primary_chapter := v_existing_member.chapter;
    ELSIF array_length(v_chapters, 1) > 0 THEN
      SELECT unnest INTO v_primary_chapter FROM unnest(v_chapters)
      WHERE unnest = ANY(v_partner_codes) LIMIT 1;
      IF v_primary_chapter IS NULL THEN v_primary_chapter := v_chapters[1]; END IF;
    END IF;

    SELECT count(*), array_agg(DISTINCT sc.cycle_code)
    INTO v_app_count, v_prev_cycles
    FROM selection_applications sa JOIN selection_cycles sc ON sc.id = sa.cycle_id
    WHERE lower(sa.email) = v_email;
    v_app_count := coalesce(v_app_count, 0) + 1;

    BEGIN
      v_app_date := NULLIF(trim(v_row->>'application_date'), '')::date;
    EXCEPTION WHEN OTHERS THEN v_app_date := NULL; END;

    v_motivation := NULL; v_areas := NULL; v_availability := NULL;
    v_academic := NULL; v_proposed := NULL; v_leadership := NULL; v_chapter_aff := NULL;

    FOR i IN 1..5 LOOP
      v_field := get_essay_field(v_essay_mapping, i::text);
      v_essay_val := v_row->>('essay_q' || i::text);
      IF v_field IS NOT NULL AND v_essay_val IS NOT NULL AND v_essay_val != '' THEN
        CASE v_field
          WHEN 'motivation_letter' THEN v_motivation := v_essay_val;
          WHEN 'chapter_affiliation' THEN v_chapter_aff := v_essay_val;
          WHEN 'areas_of_interest' THEN v_areas := v_essay_val;
          WHEN 'availability_declared' THEN v_availability := v_essay_val;
          WHEN 'academic_background' THEN v_academic := v_essay_val;
          WHEN 'proposed_theme' THEN v_proposed := v_essay_val;
          WHEN 'leadership_experience' THEN v_leadership := v_essay_val;
          ELSE NULL;
        END CASE;
      END IF;
    END LOOP;

    IF v_motivation IS NULL THEN v_motivation := v_row->>'reason_for_applying'; END IF;
    IF v_areas IS NULL THEN v_areas := v_row->>'areas_of_interest'; END IF;

    INSERT INTO selection_applications (
      cycle_id, vep_application_id, vep_opportunity_id,
      applicant_name, first_name, last_name, email, pmi_id,
      chapter, state, country, membership_status, certifications,
      resume_url, role_applied,
      motivation_letter, reason_for_applying, chapter_affiliation,
      areas_of_interest, availability_declared,
      academic_background, proposed_theme, leadership_experience,
      industry, application_date,
      is_returning_member, previous_cycles, application_count,
      imported_at, status
    ) VALUES (
      p_cycle_id, v_vep_app_id, p_opportunity_id,
      trim(coalesce(v_row->>'first_name', '')) || ' ' || trim(coalesce(v_row->>'last_name', '')),
      v_row->>'first_name', v_row->>'last_name', v_email, v_row->>'pmi_id',
      v_primary_chapter, v_row->>'state', v_row->>'country',
      v_membership, v_row->>'certifications',
      v_row->>'resume_url', p_role,
      v_motivation, v_row->>'reason_for_applying', v_chapter_aff,
      v_areas, v_availability,
      v_academic, v_proposed, v_leadership,
      v_row->>'industry', v_app_date,
      v_is_returning_offboarded,
      v_prev_cycles, v_app_count,
      now(), 'submitted'
    ) RETURNING id INTO v_app_id;

    INSERT INTO selection_membership_snapshots (application_id, membership_status, chapter_affiliations, certifications, is_partner_chapter, source)
    VALUES (v_app_id, v_membership, v_chapters, v_row->>'certifications', v_has_partner, 'csv_import');

    v_imported := v_imported + 1;
    IF v_is_returning_offboarded THEN v_returning := v_returning + 1; END IF;
  END LOOP;

  RETURN json_build_object(
    'imported', v_imported, 'skipped_dedup', v_skipped_dedup,
    'skipped_declined', v_skipped_declined, 'skipped_active', v_skipped_active,
    'flagged_review', v_flagged_review,
    'updated_snapshots', v_updated_snapshots, 'returning_members', v_returning,
    'cycle_id', p_cycle_id, 'opportunity_id', p_opportunity_id
  );
END;
$function$;

COMMENT ON FUNCTION public.import_vep_applications(uuid, jsonb, text, text) IS
  '#91 G4 (p49) — is_returning_member is set TRUE iff the matched member has a member_offboarding_records row. Mirrors the data source `get_application_returning_context` queries, so the G4 panel never renders for candidates without offboarding context.';

-- Backfill historical rows where the new predicate would have flagged the
-- application. For cycle3-2026 (closed) this catches the 9 offboarded-then-
-- reapplied candidates the panel could not render before.
UPDATE selection_applications sa
SET is_returning_member = true
WHERE sa.is_returning_member = false
  AND EXISTS (
    SELECT 1
    FROM member_offboarding_records mor
    JOIN members m ON m.id = mor.member_id
    WHERE lower(trim(m.email)) = lower(trim(sa.email))
  );
