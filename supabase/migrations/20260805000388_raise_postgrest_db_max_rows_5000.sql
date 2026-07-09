-- Raise PostgREST db-max-rows from the Supabase default (1000) to 5000.
--
-- WHY: the public schema holds 1121 functions and grows every session. PostgREST caps
-- API/RPC responses at 1000 rows (Supabase "Max Rows" default), so the Phase C body-drift
-- audit RPC public._audit_list_public_function_bodies() (ORDER BY proname) has been SILENTLY
-- truncating its ~121 alphabetically-last functions — the drift gate was blind to them. The
-- boundary surfaced when #1224 PR2 added get_my_entry_chapter_diagnosis + nudge_entry_chapter_cohort
-- (both alphabetically before 's'), shifting submit_interview_scores from position ~999 to >1000
-- and breaking its p241 live checks (tests/contracts/p241-watch-240-a-submit-interview-scores-relax).
--
-- FIX: set pgrst.db_max_rows on the authenticator role (PostgREST's in-database config channel)
-- + reload. 5000 restores full visibility for the ~1121 functions with multi-year headroom.
-- RLS still gates every row (PII protection is unchanged); the app paginates its own large reads,
-- so the higher ceiling only affects intentionally-large admin/audit responses.
--
-- ROLLBACK:
--   ALTER ROLE authenticator RESET pgrst.db_max_rows;
--   NOTIFY pgrst, 'reload config';

ALTER ROLE authenticator SET pgrst.db_max_rows = '5000';

NOTIFY pgrst, 'reload config';
