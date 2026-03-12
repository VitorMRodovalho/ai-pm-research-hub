-- ============================================================================
-- DATA SANITATION: GP-approved fixes (2026-03-12)
-- Applied to production via Supabase Management API.
-- This migration file ensures local state matches production.
-- ============================================================================

-- ─── Bloco 1: Andressa Martins tribe_id correction ────────────────────────────
UPDATE members SET tribe_id = 2, updated_at = now()
WHERE name = 'Andressa Martins' AND tribe_id = 8;

-- ─── Bloco 2: operational_role for liaisons and sponsors ──────────────────────
UPDATE members SET operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'Ana Cristina Fernandes Lima' AND operational_role = 'none';

UPDATE members SET operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'Rogério Peixoto' AND operational_role = 'none';

UPDATE members SET operational_role = 'sponsor', updated_at = now()
WHERE name IN (
  'Felipe Moraes Borges',
  'Matheus Frederico Rosa Rocha',
  'Márcio Silva dos Santos',
  'Francisca Jessica de Sousa de Alcântara'
) AND operational_role = 'none';

-- ─── Bloco 3a: Deactivate departed members ───────────────────────────────────
UPDATE members SET current_cycle_active = false, updated_at = now()
WHERE is_active = false AND current_cycle_active = true
  AND name IN ('Cristiano Oliveira', 'Herlon Alves de Sousa');

-- ─── Bloco 3b: Reactivate founders ───────────────────────────────────────────
UPDATE members SET is_active = true, operational_role = 'sponsor', updated_at = now()
WHERE name = 'Ivan Lourenço';

UPDATE members SET is_active = true, operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'Roberto Macêdo';

UPDATE members SET is_active = true, updated_at = now()
WHERE name = 'Sarah Faria Alcantara Macedo' AND is_active = false;
