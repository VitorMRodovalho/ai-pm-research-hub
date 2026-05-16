-- p171 #9 followup — drop old meeting_close(uuid, text) overload
--
-- 20260675700000 CREATE OR REPLACE added third arg (p_suggested_champion_ids)
-- which created an overload instead of replacing (CLAUDE.md GC-097 rule:
-- "DROP + CREATE when changing parameter count"). PostgREST routes by
-- matching args so backward compat works, but old 2-arg version is dead
-- weight + could confuse future callers.
--
-- Rollback: re-CREATE the 2-arg version (body from 20260645000000 + p168
-- modifications, NOT recommended).

DROP FUNCTION IF EXISTS public.meeting_close(uuid, text);

NOTIFY pgrst, 'reload schema';
