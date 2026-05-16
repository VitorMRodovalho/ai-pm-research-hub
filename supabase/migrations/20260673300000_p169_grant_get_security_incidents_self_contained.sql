-- p169 — re-state GRANT EXECUTE for get_security_incidents (self-contained pattern)
-- Code-review finding LOW: hotfix migration 20260673100000 omitted GRANT EXECUTE
-- statement, relying on CREATE OR REPLACE preserving prior grants from p168 mig
-- 20260670. Functionally OK but violates self-contained-migration pattern.
-- This migration re-states the grants explicitly so future fresh rebuilds work.
-- Idempotent — GRANT is no-op if already granted.

GRANT EXECUTE ON FUNCTION public.get_security_incidents(text, text, int)
  TO authenticated, service_role;
