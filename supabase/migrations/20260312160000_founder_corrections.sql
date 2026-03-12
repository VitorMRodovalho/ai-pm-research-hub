-- ============================================================================
-- DATA SANITATION: Founder corrections
-- Antonio Marcos Costa = Marcos Moura Costa (governance manual)
-- Giovanni Oliveira Baroni Brandão = historical founder record
-- ============================================================================

-- Antonio Marcos Costa: add pilot-2024 to cycles
UPDATE members SET cycles = array_cat(
  COALESCE(cycles, '{}'::text[]), ARRAY['pilot-2024']::text[]
), updated_at = now()
WHERE name = 'Antonio Marcos Costa'
  AND NOT (COALESCE(cycles, '{}'::text[]) @> ARRAY['pilot-2024']);

-- Giovanni: historical founder (inactive, did not continue past pilot)
INSERT INTO members (name, email, operational_role, designations, cycles,
  is_active, current_cycle_active, chapter)
VALUES (
  'Giovanni Oliveira Baroni Brandão',
  'giovanni.brandao@historical.nucleo',
  'none', ARRAY['founder'], ARRAY['pilot-2024'],
  false, false, 'PMI-GO'
) ON CONFLICT DO NOTHING;
