-- ============================================================================
-- p201 BUG-201.C — get_tribe_attendance_grid marks empty same-day tribe event as N/A
--
-- Runtime evidence (2026-05-19):
-- - Marcos Klemz reported that today's Tribe 7 meeting showed dashes for all
--   participants, while the global/admin view showed absences.
-- - Event `4b31e97d-2b63-4548-91af-65adbec6fb46`
--   ("Governança & Trustworthy AI — Reunião Semanal") is scheduled for
--   2026-05-19, type `tribo`, initiative legacy_tribe_id=7.
-- - Marcos and other active Tribe 7 members are eligible and have no attendance
--   rows yet.
-- - `get_tribe_attendance_grid(7, NULL)` returned `na` for the event because
--   `cell_status` had `WHEN COALESCE(erc.row_count, 0) = 0 THEN 'na'`.
--
-- Root cause:
-- The tribe-specific RPC treated fully-empty attendance events as not applicable.
-- For past/same-day eligible events, an empty attendance table means "not marked
-- yet" and should show `absent` until someone registers presence. Future events
-- remain `scheduled`; cancelled events remain `na`.
--
-- Fix:
-- Remove the empty-event `na` branch from `get_tribe_attendance_grid`. The
-- existing ordered CASE still preserves:
-- - cancelled -> `na`
-- - not eligible -> `na`
-- - future active member -> `scheduled`
-- - explicit attendance row -> `present` / `absent` / `excused`
-- - same-day/past eligible no-row -> `absent`
--
-- ROLLBACK:
-- Reinsert `WHEN COALESCE(erc.row_count, 0) = 0 THEN 'na'` immediately before
-- the final `ELSE CASE` in `cell_status` of `get_tribe_attendance_grid`.
-- ============================================================================

DO $$
DECLARE
  v_def text;
BEGIN
  SELECT pg_get_functiondef('public.get_tribe_attendance_grid(integer,text)'::regprocedure)
    INTO v_def;

  IF v_def NOT LIKE '%WHEN COALESCE(erc.row_count, 0) = 0 THEN ''na''%' THEN
    RAISE NOTICE 'get_tribe_attendance_grid already patched; no-op';
    RETURN;
  END IF;

  v_def := replace(
    v_def,
    E'        WHEN COALESCE(erc.row_count, 0) = 0 THEN ''na''\n        ELSE CASE',
    E'        ELSE CASE'
  );

  EXECUTE v_def;
END $$;
