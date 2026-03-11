-- Migration: Consolidate duplicate/scattered boards per tribe
-- Context: Tribe assignments changed across cycles (e.g. tribe_id=6 was
-- Débora in cycle 2, Fabrício in cycle 3; tribe_id=3 was Fabrício in
-- cycles 1-2). This left board_items scattered across multiple boards
-- for the same tribe_id.
--
-- Strategy: For each tribe with multiple boards, move all board_items
-- into the most recent active board and deactivate older boards.

BEGIN;

-- Nullify source_board on items being moved to avoid trigger conflicts
-- with enforce_board_item_source_tribe_integrity.

-- === Tribe 6 (ROI & Portfolio — Fabrício, cycle 3) ===
WITH target_board_t6 AS (
  SELECT id FROM project_boards
  WHERE tribe_id = 6 AND is_active = true
  ORDER BY created_at DESC LIMIT 1
)
UPDATE board_items
SET board_id = (SELECT id FROM target_board_t6),
    source_board = NULL,
    updated_at = now()
WHERE board_id IN (
  SELECT id FROM project_boards WHERE tribe_id = 6
)
AND board_id != (SELECT id FROM target_board_t6);

-- Deactivate old boards for tribe 6
WITH target_board_t6 AS (
  SELECT id FROM project_boards
  WHERE tribe_id = 6 AND is_active = true
  ORDER BY created_at DESC LIMIT 1
)
UPDATE project_boards
SET is_active = false, updated_at = now()
WHERE tribe_id = 6
  AND id != (SELECT id FROM target_board_t6)
  AND is_active = true;

-- === Tribe 3 (legacy Fabrício boards from cycles 1-2) ===
WITH target_board_t3 AS (
  SELECT id FROM project_boards
  WHERE tribe_id = 3 AND is_active = true
  ORDER BY created_at DESC LIMIT 1
)
UPDATE board_items
SET board_id = (SELECT id FROM target_board_t3),
    source_board = NULL,
    updated_at = now()
WHERE board_id IN (
  SELECT id FROM project_boards WHERE tribe_id = 3
)
AND board_id != (SELECT id FROM target_board_t3)
AND EXISTS (SELECT 1 FROM target_board_t3);

WITH target_board_t3 AS (
  SELECT id FROM project_boards
  WHERE tribe_id = 3 AND is_active = true
  ORDER BY created_at DESC LIMIT 1
)
UPDATE project_boards
SET is_active = false, updated_at = now()
WHERE tribe_id = 3
  AND id != (SELECT id FROM target_board_t3)
  AND is_active = true
  AND EXISTS (SELECT 1 FROM target_board_t3);

-- === Tribe 2 (Agentes Autônomos — Débora, cycle 3) ===
WITH target_board_t2 AS (
  SELECT id FROM project_boards
  WHERE tribe_id = 2 AND is_active = true
  ORDER BY created_at DESC LIMIT 1
)
UPDATE board_items
SET board_id = (SELECT id FROM target_board_t2),
    source_board = NULL,
    updated_at = now()
WHERE board_id IN (
  SELECT id FROM project_boards WHERE tribe_id = 2
)
AND board_id != (SELECT id FROM target_board_t2)
AND EXISTS (SELECT 1 FROM target_board_t2);

WITH target_board_t2 AS (
  SELECT id FROM project_boards
  WHERE tribe_id = 2 AND is_active = true
  ORDER BY created_at DESC LIMIT 1
)
UPDATE project_boards
SET is_active = false, updated_at = now()
WHERE tribe_id = 2
  AND id != (SELECT id FROM target_board_t2)
  AND is_active = true
  AND EXISTS (SELECT 1 FROM target_board_t2);

-- === Tribe 4 (Cultura & Change — Fernando) ===
WITH target_board_t4 AS (
  SELECT id FROM project_boards
  WHERE tribe_id = 4 AND is_active = true
  ORDER BY created_at DESC LIMIT 1
)
UPDATE board_items
SET board_id = (SELECT id FROM target_board_t4),
    source_board = NULL,
    updated_at = now()
WHERE board_id IN (
  SELECT id FROM project_boards WHERE tribe_id = 4
)
AND board_id != (SELECT id FROM target_board_t4)
AND EXISTS (SELECT 1 FROM target_board_t4);

WITH target_board_t4 AS (
  SELECT id FROM project_boards
  WHERE tribe_id = 4 AND is_active = true
  ORDER BY created_at DESC LIMIT 1
)
UPDATE project_boards
SET is_active = false, updated_at = now()
WHERE tribe_id = 4
  AND id != (SELECT id FROM target_board_t4)
  AND is_active = true
  AND EXISTS (SELECT 1 FROM target_board_t4);

COMMIT;
