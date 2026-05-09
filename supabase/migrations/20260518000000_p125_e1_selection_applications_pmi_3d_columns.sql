-- p125 E1 Migration 1/7 — selection_applications PMI 3-dimensional columns + RPC update
-- ADR-0076: PMI 3-dimensional volunteer model + Phase B base legal
-- Decision B1 (locked 2026-05-09): include CREATE OR REPLACE FUNCTION
-- import_vep_applications atomically with column adds (atomicity protocol)
-- Wave 1 draft (council review pending Wave 2)
--
-- Atomicity (Princípio 10 ADR-0076):
--   - All columns NULL-allowed (no fabricated defaults)
--   - import_vep_applications RPC body updated INCLUDING new columns
--     (atomic in this migration — Decision B1)
--   - E2 worker MUST deploy BEFORE this migration applied to prod
--     (worker tolera columns ausentes; migration cobre pos-deploy gap)
--
-- Rollback: ALTER TABLE selection_applications DROP COLUMN ... (each new col)
--          + restore prior import_vep_applications body from 20260514020000

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1 — selection_applications new columns
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Phase B / VEP profile geographic (Decision 5 + Princípio 1) ────────────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS applicant_city text,
  ADD COLUMN IF NOT EXISTS profile_location text,
  ADD COLUMN IF NOT EXISTS profile_state text,
  ADD COLUMN IF NOT EXISTS profile_city text,
  ADD COLUMN IF NOT EXISTS profile_country text;

COMMENT ON COLUMN public.selection_applications.applicant_city IS
  'Cidade derivada de profileLocation (Phase B Community) ou VEP profile. Preenchida apenas se community_profile_private=false. Source of truth para selection geographic context (não para identity — usar persons.city).';

COMMENT ON COLUMN public.selection_applications.profile_location IS
  'Raw text "Cidade, Estado, País" do PMI Community profile. Snapshot at submission. NÃO normalized — see profile_city/state/country for parsed.';

-- ─── Phase B multi-chapter snapshot (Decision 2 — híbrido) ──────────────────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS pmi_memberships jsonb;

COMMENT ON COLUMN public.selection_applications.pmi_memberships IS
  'Point-in-time submission snapshot of candidate''s multi-chapter PMI membership. Format: [{"chapterName":"Goiás","expiryDate":"2026-12-31"}]. IMUTÁVEL após import. NÃO é canonical — para queries live (cron compliance) usar pmi_chapter_memberships table. ADR-0076 Princípio 1.';

-- ─── Phase B professional fields (Princípio 2 — base legal Art. 7 IX) ───────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS profile_industry text,
  ADD COLUMN IF NOT EXISTS profile_company text,
  ADD COLUMN IF NOT EXISTS profile_designation text,
  ADD COLUMN IF NOT EXISTS profile_certifications text,
  ADD COLUMN IF NOT EXISTS profile_volunteer_interest text,
  ADD COLUMN IF NOT EXISTS profile_specialties text,
  ADD COLUMN IF NOT EXISTS profile_linkedin_url text;

-- Wave 3 synth (legal-counsel E3 + data-architect D3): COMMENTs for audit traceability
COMMENT ON COLUMN public.selection_applications.profile_industry IS
  'Phase B Community snapshot. Base legal: Art. 7 IX LIA — ADR-0076 Princípio 2. Snapshot at pmi_data_fetched_at.';
COMMENT ON COLUMN public.selection_applications.profile_company IS
  'Phase B Community snapshot. Base legal: Art. 7 IX LIA — ADR-0076 Princípio 2. Snapshot at pmi_data_fetched_at.';
COMMENT ON COLUMN public.selection_applications.profile_designation IS
  'Phase B Community snapshot. Base legal: Art. 7 IX LIA — ADR-0076 Princípio 2. Snapshot at pmi_data_fetched_at.';
COMMENT ON COLUMN public.selection_applications.profile_certifications IS
  'Phase B Community snapshot — raw text PMP/PMI-ACP/etc. Base legal: Art. 7 IX LIA. AI triage signal V2 (Cycle 4+).';
COMMENT ON COLUMN public.selection_applications.profile_volunteer_interest IS
  'Phase B Community snapshot. Base legal: Art. 7 IX LIA. Display + human context only.';
COMMENT ON COLUMN public.selection_applications.profile_specialties IS
  'Phase B Community snapshot. Base legal: Art. 7 IX LIA. Display + human context only.';
COMMENT ON COLUMN public.selection_applications.profile_linkedin_url IS
  'Phase B Community snapshot. Base legal: Art. 7 IX LIA — ADR-0076 Princípio 2. Snapshot at pmi_data_fetched_at — não tratar como canonical identity. URL pode resolver a conteúdo diferente over time (LinkedIn squatting) ou expirar.';

-- ─── Phase B free-text bio (Decision 3 — store only, NOT in LLM Cycle 3) ────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS profile_about_me text;

COMMENT ON COLUMN public.selection_applications.profile_about_me IS
  'Free-text bio do PMI Community profile. EXCLUSIVO para human review. NÃO incluído em AI triage prompt (Cycle 3 + Cycle 4 V2 initial — ADR-0076 Princípio 4 + Decision 3). Risk Art. 11 (sensitive data latente). Retenção 90d via anonymize cron (Princípio 6). Cycle 5+ avaliação Option B (3 preconditions tracked em memory project_p125_cycle5_profileaboutme_track).';

-- ─── Service history denormalized counters (Princípio 1 — for AI triage) ────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS service_history_count integer,
  ADD COLUMN IF NOT EXISTS service_history_chapters text,
  ADD COLUMN IF NOT EXISTS service_first_start_date date,
  ADD COLUMN IF NOT EXISTS service_latest_end_date date;

COMMENT ON COLUMN public.selection_applications.service_history_count IS
  'Denormalized count from selection_application_service_history. **SNAPSHOT-ONLY at import time**, NOT live cache (Wave 3 synth Decision S5: ADR-0012 Principle 2 cache-with-trigger does NOT apply — this is point-in-time aggregate, immutable post-import). Do NOT query for live accuracy. AI triage signal V2 (Cycle 4+ — target deploy 2026-09-01 ou 30 dias pós Cycle 3 closure, whichever later). Cycle 3 NOT in prompt (frozen Decision 4).';

COMMENT ON COLUMN public.selection_applications.service_history_chapters IS
  'Denormalized distinct chapter list from service history. **SNAPSHOT-ONLY at import time**, NOT live cache. Do NOT query for live accuracy.';

COMMENT ON COLUMN public.selection_applications.service_first_start_date IS
  'Earliest service start date across all roles. **SNAPSHOT-ONLY at import time**, NOT live cache.';

COMMENT ON COLUMN public.selection_applications.service_latest_end_date IS
  'Latest service end date across all roles. **SNAPSHOT-ONLY at import time**, NOT live cache.';

-- ─── isOpenToVolunteer ternary (Decision P3 stored, Princípio 4 NOT in LLM) ─
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS is_open_to_volunteer boolean;

COMMENT ON COLUMN public.selection_applications.is_open_to_volunteer IS
  'Ternary: true=open / false=not / NULL=unknown (private profile or not surfaced). NUNCA incluído em AI triage prompt — security-engineer R7 (78T/0F/19U distribution sugere blacklist-by-silence vector). Display + human context only (admin UI policy: never auto-filter ou sort).';

-- ─── profilePrivate flag (Decision 5) ───────────────────────────────────────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS community_profile_private boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.selection_applications.community_profile_private IS
  'true se PMI Community API retornou HTTP 400 (user disabled public profile). When true, all profile_* fields são NULL (mapper omite). Decision 5: VEP-only scoring policy — NÃO é penalidade per declared selection criteria. Policy declaration em ADR-0076 Princípio 3.';

-- ─── PMI data fetch timestamp (snapshot semantic) ───────────────────────────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS pmi_data_fetched_at timestamptz;

COMMENT ON COLUMN public.selection_applications.pmi_data_fetched_at IS
  'Timestamp Phase B fetch. profile_* fields são snapshot at this time. profileLinkedinUrl + profileDesignation podem evoluir externalmente — não tratar como canonical identity, apenas as point-in-time.';

-- ─── consent_version audit trail (Decision 4 — Cycle 3 freeze) ──────────────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS consent_version text;

COMMENT ON COLUMN public.selection_applications.consent_version IS
  'Versão do consent text/scope no momento da submission. Pattern: "termo-v2-cycle3" ou "termo-v3-cycle4". Audit trail para Art. 8 §6 LGPD — qual scope foi consented at submission. Cycle 4 enriched prompt requires consent_version >= termo-v3.';

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2 — import_vep_applications RPC body update (Decision B1 atomicity)
-- ═══════════════════════════════════════════════════════════════════════════
-- Updated to read 17 new fields from p_rows JSONB and INSERT into new columns.
-- Backwards-compatible: missing keys default to NULL via v_row->>'key' returning NULL.
-- E2 worker (mapper) populates these keys in p_rows when Phase B data available;
-- old callers continue working (NULL fields).

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
  -- p125: Phase B fields
  v_applicant_city text; v_profile_location text;
  v_profile_state text; v_profile_city text; v_profile_country text;
  v_profile_industry text; v_profile_company text;
  v_profile_designation text; v_profile_certifications text;
  v_profile_volunteer_interest text; v_profile_specialties text;
  v_profile_linkedin_url text; v_profile_about_me text;
  v_pmi_memberships jsonb;
  v_service_history_count integer; v_service_history_chapters text;
  v_service_first_start_date date; v_service_latest_end_date date;
  v_is_open_to_volunteer boolean;
  v_community_profile_private boolean;
  v_pmi_data_fetched_at timestamptz;
  v_consent_version text;
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
    -- p125 Issue C E3 will extend this to also check active engagements.
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

    -- p125: read Phase B fields from JSONB row (Decision B1 atomic update)
    -- All keys optional; missing → NULL. Worker E2 popula quando Phase B data available.
    v_applicant_city := v_row->>'applicant_city';
    v_profile_location := v_row->>'profile_location';
    v_profile_state := v_row->>'profile_state';
    v_profile_city := v_row->>'profile_city';
    v_profile_country := v_row->>'profile_country';
    v_profile_industry := v_row->>'profile_industry';
    v_profile_company := v_row->>'profile_company';
    v_profile_designation := v_row->>'profile_designation';
    v_profile_certifications := v_row->>'profile_certifications';
    v_profile_volunteer_interest := v_row->>'profile_volunteer_interest';
    v_profile_specialties := v_row->>'profile_specialties';
    v_profile_linkedin_url := v_row->>'profile_linkedin_url';
    v_profile_about_me := v_row->>'profile_about_me';
    v_pmi_memberships := v_row->'pmi_memberships';  -- JSONB array
    BEGIN
      v_service_history_count := NULLIF(v_row->>'service_history_count','')::integer;
    EXCEPTION WHEN OTHERS THEN v_service_history_count := NULL; END;
    v_service_history_chapters := v_row->>'service_history_chapters';
    BEGIN
      v_service_first_start_date := NULLIF(v_row->>'service_first_start_date','')::date;
    EXCEPTION WHEN OTHERS THEN v_service_first_start_date := NULL; END;
    BEGIN
      v_service_latest_end_date := NULLIF(v_row->>'service_latest_end_date','')::date;
    EXCEPTION WHEN OTHERS THEN v_service_latest_end_date := NULL; END;
    BEGIN
      v_is_open_to_volunteer := NULLIF(v_row->>'is_open_to_volunteer','')::boolean;
    EXCEPTION WHEN OTHERS THEN v_is_open_to_volunteer := NULL; END;
    v_community_profile_private := COALESCE((v_row->>'community_profile_private')::boolean, false);
    BEGIN
      v_pmi_data_fetched_at := NULLIF(v_row->>'pmi_data_fetched_at','')::timestamptz;
    EXCEPTION WHEN OTHERS THEN v_pmi_data_fetched_at := NULL; END;
    v_consent_version := COALESCE(v_row->>'consent_version', 'termo-v2-' || v_cycle.cycle_code);

    -- p125 Decision 5: profilePrivate posture — if community_profile_private=true,
    -- omit ALL profile_* fields (worker should already have NULL'd them, but defense in depth)
    IF v_community_profile_private THEN
      v_profile_location := NULL; v_profile_state := NULL; v_profile_city := NULL; v_profile_country := NULL;
      v_profile_industry := NULL; v_profile_company := NULL; v_profile_designation := NULL;
      v_profile_certifications := NULL; v_profile_volunteer_interest := NULL; v_profile_specialties := NULL;
      v_profile_linkedin_url := NULL; v_profile_about_me := NULL;
      v_pmi_memberships := NULL; v_is_open_to_volunteer := NULL;
      v_service_history_count := NULL; v_service_history_chapters := NULL;
      v_service_first_start_date := NULL; v_service_latest_end_date := NULL;
      -- Wave 2 fix (data-architect D5): v_row->>'state' was wrong fallback (state is US-style code, not city)
      -- Leave applicant_city NULL when profilePrivate; admin UI will fall back to selection_applications.state if needed
    END IF;

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
      imported_at, status,
      -- p125 Phase B fields (Decision B1 atomic addition)
      applicant_city, profile_location, profile_state, profile_city, profile_country,
      profile_industry, profile_company, profile_designation, profile_certifications,
      profile_volunteer_interest, profile_specialties, profile_linkedin_url, profile_about_me,
      pmi_memberships,
      service_history_count, service_history_chapters,
      service_first_start_date, service_latest_end_date,
      is_open_to_volunteer, community_profile_private,
      pmi_data_fetched_at, consent_version
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
      now(), 'submitted',
      -- p125 values
      v_applicant_city, v_profile_location, v_profile_state, v_profile_city, v_profile_country,
      v_profile_industry, v_profile_company, v_profile_designation, v_profile_certifications,
      v_profile_volunteer_interest, v_profile_specialties, v_profile_linkedin_url, v_profile_about_me,
      v_pmi_memberships,
      v_service_history_count, v_service_history_chapters,
      v_service_first_start_date, v_service_latest_end_date,
      v_is_open_to_volunteer, v_community_profile_private,
      v_pmi_data_fetched_at, v_consent_version
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
    'cycle_id', p_cycle_id, 'opportunity_id', p_opportunity_id,
    'p125_phase_b_atomic', true
  );
END;
$function$;

COMMENT ON FUNCTION public.import_vep_applications(uuid, jsonb, text, text) IS
  'p125 (2026-05-09): updated to support Phase B PMI Community fields atomically with column adds (Decision B1). Reads 22 new optional keys from p_rows JSONB; missing → NULL. Backwards-compatible. Decision 5 (profilePrivate VEP-only) enforced via community_profile_private flag — defense in depth. ADR-0076 Princípio 1 + Princípio 10 (atomicity).';

COMMIT;

-- Post-apply checklist (CLAUDE.md GC-097):
--   1. supabase migration repair --status applied 20260518000000
--   2. NOTIFY pgrst, 'reload schema'
--   3. Verify columns: SELECT column_name FROM information_schema.columns
--             WHERE table_name='selection_applications' AND column_name IN
--             ('applicant_city','pmi_memberships','community_profile_private',
--              'profile_about_me','consent_version','pmi_data_fetched_at')
--   4. Verify RPC body: SELECT proname FROM pg_proc WHERE proname='import_vep_applications'
--   5. Smoke test: SELECT public.import_vep_applications(
--        '<cycle_id>'::uuid, '[]'::jsonb, NULL, 'researcher'
--      ); should return JSON without error
--   6. Tests: tests/contracts/rpc-migration-coverage.test.mjs deve passar
