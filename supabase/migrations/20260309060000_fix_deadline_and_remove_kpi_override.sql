-- Fix BUG 1: Restore correct tribe selection deadline
-- The deadline was incorrectly extended to 2026-03-14 in a previous migration.
-- Correct deadline: 2026-03-09T15:00:00Z (tomorrow 12:00 PM BRT = UTC-3)
UPDATE public.home_schedule
SET selection_deadline_at = '2026-03-09T15:00:00+00:00'::timestamptz,
    updated_at = now()
WHERE id = 1;
