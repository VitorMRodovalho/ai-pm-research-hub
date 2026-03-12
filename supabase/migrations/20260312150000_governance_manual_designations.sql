-- ============================================================================
-- DATA SANITATION: Governance Manual R2 — designations and cycles
-- Source: DocuSign Manual de Governança R2 (GP-provided)
-- Applied to production 2026-03-12 via Management API.
-- ============================================================================

-- Ivan Lourenço: add ambassador designation
UPDATE members SET designations = array_cat(
  COALESCE(designations, '{}'::text[]), ARRAY['ambassador']::text[]
), updated_at = now()
WHERE name = 'Ivan Lourenço'
  AND NOT (designations @> ARRAY['ambassador']);

-- Founders: add pilot-2024 to cycles (text[] column)
UPDATE members SET cycles = array_cat(
  COALESCE(cycles, '{}'::text[]), ARRAY['pilot-2024']::text[]
), updated_at = now()
WHERE name IN (
  'Andressa Martins',
  'Carlos Magno do HUB Cerrado',
  'Fabricio Costa'
) AND NOT (COALESCE(cycles, '{}'::text[]) @> ARRAY['pilot-2024']);
