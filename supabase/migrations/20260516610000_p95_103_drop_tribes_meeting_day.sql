-- p95 #103 (PM decision 5C): DROP COLUMN tribes.meeting_day
-- ====================================================================
-- 0 active code readers verified (only types.ts derived auto + 1 historical migration mirror).
-- Tribos 1+7 conflict resolved at root: slot is canonical, text was stale legacy.
-- Future code MUST read from tribe_meeting_slots (UI already does).

ALTER TABLE public.tribes DROP COLUMN IF EXISTS meeting_day;

NOTIFY pgrst, 'reload schema';
