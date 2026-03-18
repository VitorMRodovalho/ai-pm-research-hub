-- ============================================================
-- GC-089 / B8: Bulk-assign tribe leaders to orphan board_items
-- ============================================================
-- 91% of board_items have no assignee (legacy Trello import).
-- Assigns tribe leaders as default 'author' via the W91 junction table
-- (board_item_assignments), not the legacy assignee_id column.

INSERT INTO board_item_assignments (item_id, member_id, role)
SELECT bi.id, m.id, 'author'
FROM board_items bi
JOIN project_boards b ON b.id = bi.board_id
JOIN members m ON m.tribe_id = b.tribe_id
  AND m.operational_role = 'tribe_leader'
  AND m.is_active = true
WHERE b.is_active = true
  AND b.tribe_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM board_item_assignments bia
    WHERE bia.item_id = bi.id
  )
ON CONFLICT DO NOTHING;
