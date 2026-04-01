-- Phase 1: Essay import fix + RLS policies
-- Updates import_vep_applications to include academic_background and proposed_theme
-- Adds RLS policy for partner_chapters (read for authenticated)

-- RLS policy for partner_chapters
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'partner_chapters' AND policyname = 'partner_chapters_read_auth') THEN
    CREATE POLICY partner_chapters_read_auth ON partner_chapters FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- import_vep_applications updated to include academic_background and proposed_theme from CSV essays
-- (full function body in 20260401020000 migration, updated via CREATE OR REPLACE in DB)
