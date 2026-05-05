-- p94 Phase C.2 Step 1: artia_*_id columns for bidirectional traceability
-- Trigger: PMO Audit 2026 — sync 7 blocks (TAP/Templates/Kick-off/Plano/Riscos/Status/KPIs) to Artia
-- Pattern: each platform entity that gets pushed to Artia stores artia_activity_id (or artia_folder_id) for idempotent re-sync

ALTER TABLE governance_documents
  ADD COLUMN IF NOT EXISTS artia_activity_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_synced_at TIMESTAMPTZ;

ALTER TABLE initiatives
  ADD COLUMN IF NOT EXISTS artia_activity_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_folder_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_synced_at TIMESTAMPTZ;

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS artia_activity_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_synced_at TIMESTAMPTZ;

ALTER TABLE board_items
  ADD COLUMN IF NOT EXISTS artia_activity_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_synced_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_govdocs_artia_stale
  ON governance_documents(artia_synced_at NULLS FIRST)
  WHERE artia_activity_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_initiatives_artia_stale
  ON initiatives(artia_synced_at NULLS FIRST)
  WHERE artia_activity_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_events_artia_stale
  ON events(artia_synced_at NULLS FIRST)
  WHERE artia_activity_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_board_items_artia_stale
  ON board_items(artia_synced_at NULLS FIRST)
  WHERE artia_activity_id IS NOT NULL;

COMMENT ON COLUMN governance_documents.artia_activity_id IS 'Artia activity ID where this governance doc is mirrored (folder 01.04 Templates). Set on first push. NULL = not synced.';
COMMENT ON COLUMN initiatives.artia_activity_id IS 'Artia activity ID for the initiative''s primary entry (typically in folder 02.0X Planejamento or 03 Execução).';
COMMENT ON COLUMN initiatives.artia_folder_id IS 'Artia folder ID if initiative has dedicated folder (large initiatives like CPMAI).';
COMMENT ON COLUMN events.artia_activity_id IS 'Artia activity ID for the event (kick-off → 01.03; webinars → 03 Execução; atas → 04.03/04.04).';
COMMENT ON COLUMN board_items.artia_activity_id IS 'Optional: Artia activity ID if board_item is materialized as discrete activity. Most board_items are aggregated in monitoring sync.';
