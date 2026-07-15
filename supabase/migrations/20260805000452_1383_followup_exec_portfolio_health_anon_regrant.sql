-- #1383 follow-up: restore anon EXECUTE on exec_portfolio_health.
-- This SECURITY DEFINER function is the public home-page KPI feed: KpiSection and
-- TrailRankingSection on index.astro (pt-BR / en / es) call it client-side to
-- hydrate the live RAG progress bars + certification-trail %. It aggregates public
-- impact metrics and OKR / quarterly targets, with confidential initiatives and
-- boards excluded inline (NOT is_confidential_initiative / NOT is_confidential_board),
-- so anonymous access is by design for the marketing page. It is read-only (STABLE,
-- no INSERT/UPDATE/DELETE or http_post), so it stays outside the #965 anon-SECDEF
-- side-effect sweep. authenticated keeps EXECUTE (mig 20260805000443).
GRANT EXECUTE ON FUNCTION public.exec_portfolio_health(text) TO anon;
