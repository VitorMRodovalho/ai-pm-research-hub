-- ═══════════════════════════════════════════════════════════════
-- W132 — Database Audit & Sanitation
-- Phase 3: Archive 22 empty speculative tables to z_archive schema
-- Phase 2: Bulk-assign tribe leaders as default assignee for unassigned items
-- ═══════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────
-- 1. Create z_archive schema for unused tables
-- ───────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS z_archive;

-- ───────────────────────────────────────────────
-- 2. Move 22 empty speculative tables to z_archive
--    (reversible: ALTER TABLE z_archive.x SET SCHEMA public)
-- ───────────────────────────────────────────────

-- Ingestion pipeline (never used, 0 rows each)
ALTER TABLE IF EXISTS public.ingestion_alert_events SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.ingestion_alert_remediation_rules SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.ingestion_alert_remediation_runs SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.ingestion_alerts SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.ingestion_apply_locks SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.ingestion_batch_files SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.ingestion_batches SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.ingestion_provenance_signatures SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.ingestion_rollback_plans SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.ingestion_run_ledger SET SCHEMA z_archive;

-- Rollback/readiness (never used)
ALTER TABLE IF EXISTS public.rollback_audit_events SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.readiness_slo_alerts SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.release_readiness_history SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.governance_bundle_snapshots SET SCHEMA z_archive;

-- Legacy/import (never used)
ALTER TABLE IF EXISTS public.legacy_member_links SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.legacy_tribe_board_links SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.notion_import_staging SET SCHEMA z_archive;

-- Publication/presentation (never used)
ALTER TABLE IF EXISTS public.publication_submission_events SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.presentations SET SCHEMA z_archive;

-- Misc (never used)
ALTER TABLE IF EXISTS public.member_chapter_affiliations SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.comms_token_alerts SET SCHEMA z_archive;
ALTER TABLE IF EXISTS public.portfolio_data_sanity_runs SET SCHEMA z_archive;

-- ───────────────────────────────────────────────
-- 3. Bulk-assign tribe_leaders as default assignee
--    for imported board_items that have no assignee
-- ───────────────────────────────────────────────
UPDATE board_items bi
SET assignee_id = (
  SELECT m.id FROM members m
  WHERE m.tribe_id = pb.tribe_id
    AND m.operational_role = 'tribe_leader'
    AND m.is_active = true
  LIMIT 1
)
FROM project_boards pb
WHERE bi.board_id = pb.id
  AND bi.assignee_id IS NULL
  AND pb.tribe_id IS NOT NULL
  AND pb.is_active = true;
