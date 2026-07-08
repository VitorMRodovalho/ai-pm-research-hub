-- #1175 Wave 4 follow-up: service-history backfill still inserted 0 rows on the live re-upload
-- (2026-07-08 03:45 UTC, run d263ef2e): every insert failed with 42P10
-- "there is no unique or exclusion constraint matching the ON CONFLICT specification".
--
-- Root cause: uq_service_history_app_chapter_start is an EXPRESSION index
-- (application_id, chapter_name, COALESCE(start_date,'1900-01-01')) while the worker's
-- supabase-js upsert targets onConflict:'application_id,chapter_name,start_date' — a plain
-- column tuple. ON CONFLICT column-list inference cannot match an expression index, so the
-- idempotency guard added by the Wave 3 blocker fix has NEVER worked against this schema.
--
-- Fix: replace the expression index with a plain-column UNIQUE index using NULLS NOT DISTINCT
-- (PG 17), preserving the intended semantics (rows with NULL start_date dedupe too).
-- Live table has 0 duplicate key groups on the plain tuple (checked pre-apply).

DROP INDEX IF EXISTS public.uq_service_history_app_chapter_start;

CREATE UNIQUE INDEX uq_service_history_app_chapter_start
  ON public.selection_application_service_history (application_id, chapter_name, start_date)
  NULLS NOT DISTINCT;

-- Sanity: the ON CONFLICT tuple the worker sends must now be inferable.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE tablename = 'selection_application_service_history'
      AND indexname = 'uq_service_history_app_chapter_start'
      AND indexdef LIKE '%(application_id, chapter_name, start_date) NULLS NOT DISTINCT%'
  ) THEN
    RAISE EXCEPTION 'uq_service_history_app_chapter_start not rebuilt as plain-column NULLS NOT DISTINCT';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
