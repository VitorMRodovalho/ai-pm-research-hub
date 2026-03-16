-- ═══════════════════════════════════════════════════════════════════════════
-- W108 — Financial Sustainability: CRUD RPCs + Projections + Seed
-- Date: 2026-03-16
-- Reference: docs/GOVERNANCE_CHANGELOG.md GC-066
--
-- New RPCs (all SECURITY DEFINER, applied via Supabase MCP):
--   1. get_cost_entries(category, date_from, date_to, limit) — list costs
--   2. get_revenue_entries(category, date_from, date_to, limit) — list revenue
--   3. delete_cost_entry(id) — manager/superadmin only
--   4. delete_revenue_entry(id) — manager/superadmin only
--   5. update_sustainability_kpi(id, target, current, notes) — edit targets
--   6. get_sustainability_projections(months_ahead) — 6-month forecast
--
-- Integrations:
--   - W104: infra_cost_monthly KPI auto_query = 'infra_cost_current'
--          (added to get_annual_kpis v_auto_values)
--   - W105: get_cycle_report now includes 'sustainability' section
--          via get_sustainability_dashboard(p_cycle)
--
-- Seed: 7 infrastructure items at R$0 documenting free tier usage
-- ═══════════════════════════════════════════════════════════════════════════

-- RPCs applied via Supabase MCP (CREATE OR REPLACE FUNCTION).
-- See deployed functions in database for canonical versions.

-- Seed data: 7 zero-cost infrastructure items
-- Applied via: INSERT INTO cost_entries ... CROSS JOIN VALUES ...
-- Items: Supabase, Cloudflare Pages, Resend, PostHog, Credly, GitHub, Claude Code

-- W104 integration:
-- UPDATE annual_kpi_targets SET auto_query = 'infra_cost_current'
-- WHERE kpi_key = 'infra_cost_monthly' AND cycle = 3;

-- W105 integration:
-- get_cycle_report now includes:
--   'sustainability', (SELECT get_sustainability_dashboard(p_cycle))
-- governance_decisions bumped to 66
