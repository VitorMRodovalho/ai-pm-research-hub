-- Fix: essay key concatenation bug in import + enrichment RPCs
-- Bug: v_row->>'essay_q' || i  evaluated as  (v_row->>'essay_q') || i = NULL
-- Fix: v_row->>('essay_q' || i::text)  correctly reads 'essay_q1', 'essay_q2', etc.
-- Both RPCs recreated in DB via execute_sql (not in this migration file)
-- This migration documents the fix for history tracking.

-- Also adds reason_for_applying column and enrich_applications_from_csv RPC
ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS reason_for_applying text;
