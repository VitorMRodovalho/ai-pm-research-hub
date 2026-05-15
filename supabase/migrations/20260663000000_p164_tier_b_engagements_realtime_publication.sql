-- p164 Tier B — Add engagements to supabase_realtime publication
-- Refs: ADR-0083 (capability cache); Tier B realtime invalidation for canFor scoped UI gates.
--
-- Why: capability cache (window.__nucleoCapabilities) is bootstrap-time. Engagement
-- INSERT/UPDATE/DELETE during a session does NOT trigger re-fetch — user sees stale
-- capabilities until page refresh. Adding engagements to the realtime publication lets
-- the frontend subscribe to postgres_changes filtered by person_id and re-fetch
-- get_caller_capabilities() on event.
--
-- Privacy: existing RLS `engagements_select_authenticated` (qual=true) already permits any
-- authenticated user to SELECT all engagement rows; Supabase Realtime applies SELECT RLS
-- as filter for postgres_changes broadcasts, so this publication doesn't expose more than
-- already exposed. Filtering at broker by `person_id=eq.<self>` keeps client-side traffic
-- minimal.
--
-- Rollback: ALTER PUBLICATION supabase_realtime DROP TABLE public.engagements;
ALTER PUBLICATION supabase_realtime ADD TABLE public.engagements;

NOTIFY pgrst, 'reload schema';
