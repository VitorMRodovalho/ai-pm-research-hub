-- p125 E2 Migration 7/8 — selection_application_service_history idempotency UNIQUE
-- Wave 2 BLOCKER (code-reviewer + senior-software-engineer + ai-engineer convergent)
-- Wave 3 synth fix: re-ingest must NOT produce duplicate rows
--
-- Issue: original Migration 3 (20260518020000) created service_history table
-- without UNIQUE constraint. Worker E2 INSERT produces duplicates if PM re-runs
-- extract_pmi_volunteer.js + /ingest. AI triage signal V2 (Cycle 4+) would
-- count duplicates → corrupted scoring.
--
-- Fix: UNIQUE constraint (application_id, chapter_name, COALESCE(start_date, '1900-01-01'))
-- handles NULL start_date (some PMI rows have role start unknown).
-- Worker E2 db.ts changed to UPSERT with onConflict ignore_duplicates=true.
--
-- Atomicity: this migration MUST apply BEFORE worker E2 deployed in prod
-- (or worker tolerates failure on duplicate insert per Wave 1 design).
--
-- Rollback: ALTER TABLE selection_application_service_history
--   DROP CONSTRAINT service_history_idempotency_unique;

BEGIN;

-- ─── Add UNIQUE constraint with COALESCE for NULL start_date ────────────────
-- Functional UNIQUE INDEX (não constraint) porque PostgreSQL UNIQUE constraint
-- não suporta expressões — só columns. Functional unique index serves the
-- same purpose for upsert ON CONFLICT.
CREATE UNIQUE INDEX IF NOT EXISTS service_history_idempotency_unique
  ON public.selection_application_service_history (
    application_id,
    chapter_name,
    COALESCE(start_date, DATE '1900-01-01')
  );

COMMENT ON INDEX public.service_history_idempotency_unique IS
  'Idempotency guard for /ingest re-runs. Prevents duplicate row on (application, chapter, start_date) tuple. NULL start_date treated as 1900-01-01 (sentinel) to enable UPSERT ON CONFLICT. Wave 3 synth fix Wave 2 BLOCKER 2026-05-09.';

COMMIT;

-- Post-apply checklist:
--   1. supabase migration repair --status applied 20260518070000
--   2. Verify: SELECT indexname, indexdef FROM pg_indexes
--      WHERE tablename='selection_application_service_history';
--   3. Worker E2 db.ts insertServiceHistory must use .upsert() not .insert()
--      with onConflict: 'application_id,chapter_name,COALESCE(start_date, \'1900-01-01\')'
--      OR fallback to ignoreDuplicates: true (cleaner for append-snapshot)
