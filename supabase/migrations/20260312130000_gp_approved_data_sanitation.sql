-- ============================================================================
-- DATA SANITATION: GP-approved fixes (2026-03-12)
-- Applied to production via Supabase Management API.
-- This migration file ensures local state matches production.
-- ============================================================================

-- ─── Bloco 1: member H tribe_id correction ────────────────────────────
UPDATE members SET tribe_id = 2, updated_at = now()
WHERE name = 'member H' AND tribe_id = 8;

-- ─── Bloco 2: operational_role for liaisons and sponsors ──────────────────────
UPDATE members SET operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'member D' AND operational_role = 'none';

UPDATE members SET operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'member J' AND operational_role = 'none';

UPDATE members SET operational_role = 'sponsor', updated_at = now()
WHERE name IN (
  'member G',
  'member A',
  'member E',
  'member C'
) AND operational_role = 'none';

-- ─── Bloco 3a: Deactivate departed members ───────────────────────────────────
UPDATE members SET current_cycle_active = false, updated_at = now()
WHERE is_active = false AND current_cycle_active = true
  AND name IN ('member K', 'member F');

-- ─── Bloco 3b: Reactivate founders ───────────────────────────────────────────
UPDATE members SET is_active = true, operational_role = 'sponsor', updated_at = now()
WHERE name = 'member L';

UPDATE members SET is_active = true, operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'member I';

UPDATE members SET is_active = true, updated_at = now()
WHERE name = 'member B' AND is_active = false;
