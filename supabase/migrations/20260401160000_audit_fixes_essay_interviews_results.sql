-- Audit fixes: essay mapping, interview records, results grouping
-- =================================================================
-- Fix 1: chapter_affiliation column — Q1 was chapter filiation, not motivation
ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS chapter_affiliation text;
-- Data migration: motivation_letter → chapter_affiliation, reason_for_applying → motivation_letter
-- (Applied via execute_sql for both kickoff and batch2 cycles)

-- Fix 2: 34 selection_interviews records created for historical interviews
-- (Applied via import_historical_interviews RPC)

-- Fix 3: Frontend results view now groups by evaluation_type
-- Shows separate tables: Quantitativa (Pesquisador), Qualitativa (Entrevista), Quantitativa (Líder)
-- Each table shows PERT per criterion + subtotal ponderado
-- Calculation explanation visible at bottom
