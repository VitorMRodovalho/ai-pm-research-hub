-- ============================================================
-- GC-089 / B7: Populate board_sla_config with default SLAs
-- ============================================================
-- board_sla_config has 0 rows for most boards.
-- Insert sensible defaults for all active boards that lack config.

INSERT INTO board_sla_config (board_id, sla_days, reviewers_required)
SELECT b.id, 7, 2
FROM project_boards b
WHERE b.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM board_sla_config bsc WHERE bsc.board_id = b.id
  )
ON CONFLICT (board_id) DO NOTHING;
