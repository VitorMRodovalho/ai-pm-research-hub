-- ============================================================================
-- DATA SANITATION: Sync members.tribe_id from tribe_selections
--
-- Problem: 32 members have a tribe_selections record but members.tribe_id = NULL.
-- This causes MemberPicker and tribe-scoped boards to not show these members.
--
-- Fix 1: Backfill NULL tribe_id from tribe_selections (32 rows)
-- Fix 2: Create trigger to keep them in sync going forward
--
-- Safe: only fills NULL values, never overwrites existing tribe_id.
-- ============================================================================

-- ─── Fix 1: Backfill tribe_id ──────────────────────────────────────────────────

UPDATE members m
SET tribe_id = ts.tribe_id, updated_at = now()
FROM tribe_selections ts
WHERE ts.member_id = m.id
  AND m.tribe_id IS NULL;

-- ─── Fix 2: Sync trigger ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.sync_tribe_id_from_selection()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  UPDATE members SET tribe_id = NEW.tribe_id, updated_at = now()
  WHERE id = NEW.member_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_tribe_id ON tribe_selections;
CREATE TRIGGER trg_sync_tribe_id
  AFTER INSERT OR UPDATE ON tribe_selections
  FOR EACH ROW
  EXECUTE FUNCTION sync_tribe_id_from_selection();
