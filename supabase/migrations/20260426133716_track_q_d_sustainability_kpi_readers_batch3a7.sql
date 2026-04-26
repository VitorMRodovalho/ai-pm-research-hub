-- Track Q-D — sustainability/KPI readers hardening (batch 3a.7)
--
-- Discovery (p58 continuation, post 3a.6):
-- 17 SECDEF readers/writers in sustainability/KPI bucket. Per-fn body
-- + callsite analysis classified into 3 buckets:
--
-- (a) Live with authenticated callers — REVOKE-from-anon (12 fns):
-- - exec_portfolio_board_summary(boolean) — caller admin/portfolio.astro.
-- - get_annual_kpis(integer, integer) — annual KPI dashboard. Caller
--   admin/portfolio.astro + MCP. Body uses operational_role for
--   member filtering (display, not gate).
-- - get_cost_entries(text, date, date, integer) — cost entries listing.
--   Caller admin/sustainability.astro.
-- - get_cycle_evolution() — cycle evolution trend. Caller
--   admin/cycle-report.astro.
-- - get_cycle_report(integer) — full cycle report. Caller ReportPage.tsx.
--   Body uses operational_role for by_role aggregation (display, not gate).
-- - get_kpi_dashboard(date, date) — KPI dashboard for cycle window.
--   Caller workspace/KpiDashboard.tsx.
-- - get_pilot_metrics(uuid) — single pilot metrics. Caller usePilots.ts +
--   admin/pilots.astro.
-- - get_pilots_summary() — pilots overview. Caller usePilots.ts +
--   admin/pilots.astro.
-- - get_portfolio_dashboard(integer) — portfolio dashboard for cycle.
--   Caller usePortfolio.ts + MCP.
-- - get_revenue_entries(text, date, date, integer) — revenue entries.
--   Caller admin/sustainability.astro.
-- - get_sustainability_dashboard(integer) — sustainability dashboard.
--   Caller admin/sustainability.astro.
-- - get_sustainability_projections(integer) — projections. Caller
--   admin/sustainability.astro.
--
-- (b) Verified public-by-design — no change (1 fn):
-- - exec_portfolio_health(text) — annual KPI portfolio health metrics
--   (chapters_participating, partner_entities, certification_trail %,
--   cpmai_certified, articles_published, webinars_completed,
--   ia_pilots, meeting_hours, impact_hours + quarter targets).
--   Body returns aggregate counts/percentages/sums only — NO PII.
--   Callers: src/components/sections/TrailSection.astro:214 +
--   src/components/sections/KpiSection.astro:84. Both sections
--   imported by src/pages/index.astro (and en/, es/) — homepage
--   public pages. Both call via getSupabase() (anon key) without
--   any !member bail check. Documented as verified public-by-design
--   (Q-D batch 2 pattern extended).
--
-- Out-of-scope — Phase B'' V3 admin writers (4 fns documented):
-- - delete_cost_entry(uuid) — V3 gate (is_sa + op_role).
-- - delete_revenue_entry(uuid) — V3 gate (is_sa + op_role).
-- - update_kpi_target(...) — V3 gate (is_sa + op_role).
-- - update_sustainability_kpi(...) — V3 gate (is_sa + op_role).
--
-- Total: 13 fns triaged in batch 3a.7 (12 live REVOKE-from-anon +
-- 1 verified public-by-design). 4 V3 fns out-of-scope (Phase B'').
--
-- Risk: low. Authenticated callers via admin pages and MCP preserved
-- on the 12 live fns. exec_portfolio_health stays public-by-design
-- (homepage hydration). Postgres + service_role retained.

-- ============================================================
-- (a) Live with authenticated callers — REVOKE-from-anon
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.exec_portfolio_board_summary(boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_annual_kpis(integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_cost_entries(text, date, date, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_cycle_evolution() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_cycle_report(integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_kpi_dashboard(date, date) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_pilot_metrics(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_pilots_summary() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_portfolio_dashboard(integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_revenue_entries(text, date, date, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_sustainability_dashboard(integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_sustainability_projections(integer) FROM PUBLIC, anon;

-- (b) exec_portfolio_health: NO CHANGE — verified public-by-design
-- (homepage hydration, aggregate-only metrics, no PII).

NOTIFY pgrst, 'reload schema';
