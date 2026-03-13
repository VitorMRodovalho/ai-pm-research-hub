-- ═══════════════════════════════════════════════════════════════
-- Fix cycle_3 start date: was 2026-01-01, should be 2026-03-01
-- Cycle 3 started in March 2026, not January.
-- This fixes KPI filtering (e.g., articles showing 4 instead of 0).
-- ═══════════════════════════════════════════════════════════════

UPDATE public.cycles
SET cycle_start = '2026-03-01'
WHERE cycle_code = 'cycle_3';
