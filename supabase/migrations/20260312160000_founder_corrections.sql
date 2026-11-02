-- ============================================================================
-- DATA SANITATION: Founder corrections
-- member B = member C (governance manual)
-- member A = historical founder record
-- ============================================================================

-- member B: add pilot-2024 to cycles
UPDATE members SET cycles = array_cat(
  COALESCE(cycles, '{}'::text[]), ARRAY['pilot-2024']::text[]
), updated_at = now()
WHERE name = 'member B'
  AND NOT (COALESCE(cycles, '{}'::text[]) @> ARRAY['pilot-2024']);

-- member A: historical founder (inactive, did not continue past pilot)
INSERT INTO members (name, email, operational_role, designations, cycles,
  is_active, current_cycle_active, chapter)
VALUES (
  'member A',
  'redacted-032@example.com',
  'none', ARRAY['founder'], ARRAY['pilot-2024'],
  false, false, 'PMI-GO'
) ON CONFLICT DO NOTHING;

-- member A: set real contact info
UPDATE members SET
  email = 'redacted-032@example.com',
  phone = '+55 (00) 00000-0000',
  updated_at = now()
WHERE name = 'member A';
