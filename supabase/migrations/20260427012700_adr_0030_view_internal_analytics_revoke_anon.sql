-- ADR-0030 (p66) defense-in-depth REVOKE
-- Matches ADR-0026 batch 1 + extension precedent.
-- pg_policy precondition verified pre-apply (zero refs in RLS).

REVOKE EXECUTE ON FUNCTION public.exec_chapter_dashboard(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.exec_role_transitions(text, integer, text) FROM PUBLIC, anon;
-- Note: can_read_internal_analytics is helper called from exec_role_transitions
-- body via SECDEF chain. Authenticated callers reach it indirectly only via
-- exec_role_transitions; direct call return false for anon (no auth.uid()).
-- Keep authenticated EXECUTE for SECDEF chain to work; REVOKE from anon.
REVOKE EXECUTE ON FUNCTION public.can_read_internal_analytics() FROM PUBLIC, anon;
