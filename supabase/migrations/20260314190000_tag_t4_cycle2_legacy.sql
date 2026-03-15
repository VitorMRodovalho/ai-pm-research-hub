-- ISSUE E: Tag T4 cycle-2 legacy items with unified ciclo_2 tag
-- These 52 miro_import items from cycle 2 should NOT be deleted, just tagged for filtering.

-- 1. Create ciclo_2 tag (system tier, all domain) if not exists
INSERT INTO tags (id, name, label_pt, label_en, label_es, color, tier, domain, description, display_order)
VALUES (
  'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e',
  'ciclo_2',
  'Ciclo 2',
  'Cycle 2',
  'Ciclo 2',
  '#6B7280',
  'system',
  'all',
  'Items from Cycle 2 (legacy)',
  3
) ON CONFLICT (id) DO NOTHING;

-- 2. Tag all T4 cycle-2 legacy items (source_board = 'miro_import')
INSERT INTO board_item_tag_assignments (board_item_id, tag_id)
SELECT bi.id, 'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e'
FROM board_items bi
WHERE bi.board_id = 'e62bf41c-a762-4e07-8a18-4f8fff23c2f7'  -- T4 board
  AND bi.source_board = 'miro_import'
  AND NOT EXISTS (
    SELECT 1 FROM board_item_tag_assignments bita
    WHERE bita.board_item_id = bi.id
      AND bita.tag_id = 'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e'
  );
