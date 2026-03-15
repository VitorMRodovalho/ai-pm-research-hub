-- ISSUE F: Tag T6 and T3 cycle-2 legacy items with unified ciclo_2 tag
-- T6 has 159 miro_import items, T3 has 24 miro_import items.
-- These are cycle-2 legacy items that should be preserved but filterable.

-- Tag all remaining miro_import items (T3 + T6) with ciclo_2
-- ciclo_2 tag was created in previous migration (b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e)
INSERT INTO board_item_tag_assignments (board_item_id, tag_id)
SELECT bi.id, 'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e'
FROM board_items bi
WHERE bi.source_board = 'miro_import'
  AND bi.board_id IN (
    '118b55be-9dcd-4b2d-82c7-5c457fb1fc1e',  -- T6
    '50474fd3-adbc-4980-ba2e-6dffec420321'    -- T3
  )
  AND NOT EXISTS (
    SELECT 1 FROM board_item_tag_assignments bita
    WHERE bita.board_item_id = bi.id
      AND bita.tag_id = 'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e'
  );
