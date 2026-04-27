-- ADR-0035 (p66) defense-in-depth REVOKE
-- pg_policy precondition: zero RLS refs verified pre-apply.

REVOKE EXECUTE ON FUNCTION public.get_chapter_dashboard(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_diversity_dashboard(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_annual_kpis(integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_cycle_report(integer) FROM PUBLIC, anon;
