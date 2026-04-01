-- Selection Import R1-R5 Fixes
-- R1: Cycle-aware skip logic (only block current-cycle offboarded)
-- R2: vep_opportunities table with essay_mapping
-- R3: application_date field
-- R4: (data cleanup — done via SQL, not migration)
-- R5: Chapter merge (members table as primary source)

-- R2: VEP Opportunities table
CREATE TABLE IF NOT EXISTS vep_opportunities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opportunity_id text NOT NULL UNIQUE,
  title text NOT NULL,
  chapter_posted text,
  role_default text DEFAULT 'researcher',
  essay_mapping jsonb NOT NULL DEFAULT '{}',
  vep_url text,
  start_date date,
  end_date date,
  positions_available int,
  time_commitment text,
  requirements text,
  eligibility text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE vep_opportunities ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'vep_opportunities' AND policyname = 'vep_opportunities_read_auth') THEN
    CREATE POLICY vep_opportunities_read_auth ON vep_opportunities FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

INSERT INTO vep_opportunities (opportunity_id, title, chapter_posted, role_default, essay_mapping, vep_url, start_date, end_date, positions_available, time_commitment, eligibility) VALUES
  ('64967', 'Pesquisador e multiplicador de conhecimento em IA - Núcleo IA & GP (Nível 4) - 2026', 'PMI-GO', 'researcher',
   '{"1":"motivation_letter","2":"areas_of_interest","3":"academic_background","4":"availability_declared"}'::jsonb,
   'https://volunteer.pmi.org/recruiter-dashboard/manage-applications/opportunity/64967',
   '2026-01-20', '2026-12-19', 42, '21-30 hours per month',
   'Filiado ativo a capitulo parceiro ou disposto a se filiar.'),
  ('64966', 'Líder de tribo e Pesquisador chefe - Núcleo IA & GP - 2026', 'PMI-GO', 'leader',
   '{"1":"motivation_letter","2":"leadership_experience","3":"academic_background","4":"availability_declared","5":"proposed_theme"}'::jsonb,
   'https://volunteer.pmi.org/recruiter-dashboard/manage-applications/opportunity/64966',
   '2026-01-20', '2026-12-19', 42, '21-30 hours per month',
   'Filiado ativo a capitulo parceiro. Experiencia em lideranca.')
ON CONFLICT (opportunity_id) DO NOTHING;

-- R3: Application date
ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS application_date date;
