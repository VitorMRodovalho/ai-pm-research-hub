-- Selection Journey V2: Mid-Cycle Recruitment + Full Pipeline
-- Schema changes + RPCs for VEP CSV import with dimensional membership tracking

-- 1. Add vep_opportunity_id to selection_applications
ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS vep_opportunity_id text;

-- 2. Partner chapters table (dynamic, not hardcoded)
CREATE TABLE IF NOT EXISTS partner_chapters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_code text NOT NULL UNIQUE,
  chapter_name text NOT NULL,
  is_active boolean DEFAULT true,
  partnership_start date,
  partnership_end date,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE partner_chapters ENABLE ROW LEVEL SECURITY;

INSERT INTO partner_chapters (chapter_code, chapter_name, partnership_start) VALUES
  ('PMI-GO', 'Goiás, Brazil Chapter', '2025-07-01'),
  ('PMI-CE', 'Ceará, Brazil Chapter', '2025-07-01'),
  ('PMI-MG', 'Minas Gerais, Brazil Chapter', '2025-07-01'),
  ('PMI-DF', 'Distrito Federal, Brazil Chapter', '2025-07-01'),
  ('PMI-RS', 'Rio Grande do Sul, Brazil Chapter', '2025-07-01')
ON CONFLICT (chapter_code) DO NOTHING;

-- 3. Membership snapshots table (temporal facts for audit + partner validation)
CREATE TABLE IF NOT EXISTS selection_membership_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id) ON DELETE CASCADE,
  snapshot_date timestamptz NOT NULL DEFAULT now(),
  membership_status text,
  chapter_affiliations text[],
  certifications text,
  is_partner_chapter boolean,
  source text DEFAULT 'csv_import',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE selection_membership_snapshots ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_membership_snap_app ON selection_membership_snapshots(application_id);

-- 4. Chapter parser helper (handles "State, Brazil Chapter" comma ambiguity)
CREATE OR REPLACE FUNCTION parse_vep_chapters(p_membership text)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_chapters text[] := '{}';
  v_match text;
BEGIN
  IF p_membership IS NULL OR p_membership = '' THEN RETURN v_chapters; END IF;

  FOR v_match IN
    SELECT m[1] FROM regexp_matches(p_membership, '([^,]+(?:,\s*Brazil)?\s+Chapter)', 'gi') AS m
  LOOP
    v_match := trim(v_match);
    v_chapters := v_chapters || CASE
      WHEN v_match ILIKE '%goiás%' OR v_match ILIKE '%goias%' THEN 'PMI-GO'
      WHEN v_match ILIKE '%ceará%' OR v_match ILIKE '%ceara%' THEN 'PMI-CE'
      WHEN v_match ILIKE '%minas gerais%' THEN 'PMI-MG'
      WHEN v_match ILIKE '%distrito federal%' THEN 'PMI-DF'
      WHEN v_match ILIKE '%rio grande do sul%' THEN 'PMI-RS'
      WHEN v_match ILIKE '%são paulo%' OR v_match ILIKE '%sao paulo%' THEN 'PMI-SP'
      WHEN v_match ILIKE '%rio de janeiro%' THEN 'PMI-RJ'
      WHEN v_match ILIKE '%pernambuco%' THEN 'PMI-PE'
      WHEN v_match ILIKE '%espírito santo%' OR v_match ILIKE '%espirito santo%' THEN 'PMI-ES'
      WHEN v_match ILIKE '%bahia%' THEN 'PMI-BA'
      WHEN v_match ILIKE '%paraná%' OR v_match ILIKE '%parana%' THEN 'PMI-PR'
      WHEN v_match ILIKE '%honduras%' THEN 'PMI-HN'
      ELSE 'PMI-' || regexp_replace(split_part(v_match, ',', 1), '[^A-Za-z ]', '', 'g')
    END;
  END LOOP;

  RETURN v_chapters;
END;
$$;

-- 5. VEP CSV Import RPC
CREATE OR REPLACE FUNCTION import_vep_applications(
  p_cycle_id uuid,
  p_opportunity_id text,
  p_rows jsonb,
  p_role text DEFAULT 'researcher'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row jsonb;
  v_imported int := 0;
  v_skipped_dedup int := 0;
  v_skipped_declined int := 0;
  v_updated_snapshots int := 0;
  v_returning int := 0;
  v_app_id uuid;
  v_vep_app_id text;
  v_vep_status text;
  v_email text;
  v_membership text;
  v_chapters text[];
  v_has_partner boolean;
  v_existing_app_id uuid;
  v_is_returning boolean;
  v_prev_cycles text[];
  v_app_count int;
  v_partner_codes text[];
  v_primary_chapter text;
BEGIN
  SELECT array_agg(chapter_code) INTO v_partner_codes
  FROM partner_chapters WHERE is_active = true;

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_vep_app_id := v_row->>'application_id';
    v_vep_status := v_row->>'app_status';
    v_email := lower(trim(v_row->>'email'));
    v_membership := v_row->>'membership_status';

    IF v_vep_status IN ('OfferNotExtended', 'Declined', 'Withdrawn') THEN
      v_skipped_declined := v_skipped_declined + 1;
      CONTINUE;
    END IF;

    v_chapters := parse_vep_chapters(v_membership);
    v_has_partner := v_chapters && v_partner_codes;

    SELECT id INTO v_existing_app_id
    FROM selection_applications WHERE vep_application_id = v_vep_app_id;

    IF v_existing_app_id IS NOT NULL THEN
      INSERT INTO selection_membership_snapshots (
        application_id, membership_status, chapter_affiliations,
        certifications, is_partner_chapter, source
      ) VALUES (
        v_existing_app_id, v_membership, v_chapters,
        v_row->>'certifications', v_has_partner, 'csv_reimport'
      );
      v_updated_snapshots := v_updated_snapshots + 1;
      v_skipped_dedup := v_skipped_dedup + 1;
      CONTINUE;
    END IF;

    v_is_returning := EXISTS (SELECT 1 FROM members WHERE email = v_email AND is_active = true);

    SELECT count(*), array_agg(DISTINCT sc.cycle_code)
    INTO v_app_count, v_prev_cycles
    FROM selection_applications sa
    JOIN selection_cycles sc ON sc.id = sa.cycle_id
    WHERE lower(sa.email) = v_email;
    v_app_count := coalesce(v_app_count, 0) + 1;

    v_primary_chapter := NULL;
    IF array_length(v_chapters, 1) > 0 THEN
      SELECT unnest INTO v_primary_chapter FROM unnest(v_chapters)
      WHERE unnest = ANY(v_partner_codes) LIMIT 1;
      IF v_primary_chapter IS NULL THEN v_primary_chapter := v_chapters[1]; END IF;
    END IF;

    INSERT INTO selection_applications (
      cycle_id, vep_application_id, vep_opportunity_id,
      applicant_name, first_name, last_name, email, pmi_id,
      chapter, state, country, membership_status, certifications,
      resume_url, role_applied,
      motivation_letter, areas_of_interest, availability_declared,
      industry,
      is_returning_member, previous_cycles, application_count,
      imported_at, status
    ) VALUES (
      p_cycle_id, v_vep_app_id, p_opportunity_id,
      trim(coalesce(v_row->>'first_name', '')) || ' ' || trim(coalesce(v_row->>'last_name', '')),
      v_row->>'first_name', v_row->>'last_name', v_email, v_row->>'pmi_id',
      v_primary_chapter, v_row->>'state', v_row->>'country',
      v_membership, v_row->>'certifications',
      v_row->>'resume_url', p_role,
      v_row->>'reason_for_applying', v_row->>'areas_of_interest',
      v_row->>'availability',
      v_row->>'industry',
      v_is_returning, v_prev_cycles, v_app_count,
      now(), 'submitted'
    ) RETURNING id INTO v_app_id;

    INSERT INTO selection_membership_snapshots (
      application_id, membership_status, chapter_affiliations,
      certifications, is_partner_chapter, source
    ) VALUES (
      v_app_id, v_membership, v_chapters,
      v_row->>'certifications', v_has_partner, 'csv_import'
    );

    v_imported := v_imported + 1;
    IF v_is_returning THEN v_returning := v_returning + 1; END IF;
  END LOOP;

  RETURN json_build_object(
    'imported', v_imported,
    'skipped_dedup', v_skipped_dedup,
    'skipped_declined', v_skipped_declined,
    'updated_snapshots', v_updated_snapshots,
    'returning_members', v_returning,
    'cycle_id', p_cycle_id,
    'opportunity_id', p_opportunity_id
  );
END;
$$;
