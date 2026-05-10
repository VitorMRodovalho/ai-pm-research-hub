-- =====================================================================
-- p136 Ω-E.1 — RLS RF-1 fix + organization_id retrofit (financial tables)
-- =====================================================================
-- Context: 3 of 4 financial/audit tables had RLS policy USING(true) for
-- authenticated SELECT, exposing cost/revenue/KPI data to ANY authenticated
-- user (including ghost auths pre-member). This migration:
--   1. Adds organization_id (V4 multi-tenant compliance, ADR-0009)
--   2. Backfills with single seeded org (Nucleo IA, 2b4f58ab-…)
--   3. Replaces USING(true) policies with hardened SELECT-only,
--      org-scoped + superadmin pattern (writes blocked → RPC-only)
--   4. Tightens mcp_usage_log to admin+org combined gate
--
-- Hardening deviates from V4 standard `FOR ALL` cmd='*' pattern: financial
-- data uses `FOR SELECT only`. Writes already blocked today (no policy
-- existed for INSERT/UPDATE/DELETE) — keeping that posture forces RPC-only
-- writes where can() gates can be added later (Ω-E.2 RPC hardening sweep).
--
-- Out of scope (deferred to Ω-E.2):
--   - NOT NULL constraint on organization_id (defer post-monitor)
--   - can() gate inside SECDEF RPCs (e.g. get_sustainability_dashboard)
--   - sync-artia EF explicit organization_id on mcp_usage_log inserts
--
-- Rollback (if needed):
--   DROP POLICY <names>; DROP COLUMN organization_id; recreate USING(true)
--   policies as they were. NOT idempotent — but there's only 1 org today
--   so backfill direction is unambiguous.
-- =====================================================================

-- Step 1: Add organization_id column with FK to organizations
ALTER TABLE public.cost_entries
  ADD COLUMN organization_id UUID REFERENCES public.organizations(id) ON DELETE RESTRICT;

ALTER TABLE public.revenue_entries
  ADD COLUMN organization_id UUID REFERENCES public.organizations(id) ON DELETE RESTRICT;

ALTER TABLE public.sustainability_kpi_targets
  ADD COLUMN organization_id UUID REFERENCES public.organizations(id) ON DELETE RESTRICT;

ALTER TABLE public.mcp_usage_log
  ADD COLUMN organization_id UUID REFERENCES public.organizations(id) ON DELETE RESTRICT;

-- Step 2: Backfill with single seeded org (Nucleo IA & GP — 2b4f58ab-…)
UPDATE public.cost_entries
  SET organization_id = '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
  WHERE organization_id IS NULL;

UPDATE public.revenue_entries
  SET organization_id = '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
  WHERE organization_id IS NULL;

UPDATE public.sustainability_kpi_targets
  SET organization_id = '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
  WHERE organization_id IS NULL;

UPDATE public.mcp_usage_log
  SET organization_id = '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
  WHERE organization_id IS NULL;

-- Step 3: DEFAULT auth_org() — future INSERTs auto-fill from caller's org
ALTER TABLE public.cost_entries
  ALTER COLUMN organization_id SET DEFAULT auth_org();

ALTER TABLE public.revenue_entries
  ALTER COLUMN organization_id SET DEFAULT auth_org();

ALTER TABLE public.sustainability_kpi_targets
  ALTER COLUMN organization_id SET DEFAULT auth_org();

ALTER TABLE public.mcp_usage_log
  ALTER COLUMN organization_id SET DEFAULT auth_org();

-- Step 4: Indexes for org-scoped queries
CREATE INDEX IF NOT EXISTS cost_entries_org_idx
  ON public.cost_entries(organization_id);

CREATE INDEX IF NOT EXISTS revenue_entries_org_idx
  ON public.revenue_entries(organization_id);

CREATE INDEX IF NOT EXISTS sustainability_kpi_targets_org_idx
  ON public.sustainability_kpi_targets(organization_id);

CREATE INDEX IF NOT EXISTS mcp_usage_log_org_idx
  ON public.mcp_usage_log(organization_id);

-- Step 5: Drop legacy permissive policies
DROP POLICY IF EXISTS "Authenticated can view costs" ON public.cost_entries;
DROP POLICY IF EXISTS "Authenticated can view revenue" ON public.revenue_entries;
DROP POLICY IF EXISTS "Authenticated can view KPIs" ON public.sustainability_kpi_targets;
DROP POLICY IF EXISTS "mcp_usage_log_select_admin" ON public.mcp_usage_log;

-- Step 6: New hardened policies
-- Financial tables: SELECT-only, superadmin OR org match. Writes blocked
-- (no policy for INSERT/UPDATE/DELETE) → SECDEF RPCs only.
CREATE POLICY cost_entries_select_org ON public.cost_entries
  FOR SELECT TO authenticated
  USING (rls_is_superadmin() OR organization_id = auth_org());

CREATE POLICY revenue_entries_select_org ON public.revenue_entries
  FOR SELECT TO authenticated
  USING (rls_is_superadmin() OR organization_id = auth_org());

CREATE POLICY sustainability_kpi_targets_select_org ON public.sustainability_kpi_targets
  FOR SELECT TO authenticated
  USING (rls_is_superadmin() OR organization_id = auth_org());

-- mcp_usage_log: admin gate + org scope (superadmin sees all orgs)
CREATE POLICY mcp_usage_log_select_admin_org ON public.mcp_usage_log
  FOR SELECT TO authenticated
  USING (
    rls_is_superadmin()
    OR (rls_can('manage_member') AND organization_id = auth_org())
  );

-- Step 7: Comments documenting the hardening
COMMENT ON COLUMN public.cost_entries.organization_id IS
  'V4 multi-tenant scoping (ADR-0009). DEFAULT auth_org() auto-fills from caller. RLS hardened to SELECT-only org match (writes RPC-only).';
COMMENT ON COLUMN public.revenue_entries.organization_id IS
  'V4 multi-tenant scoping (ADR-0009). DEFAULT auth_org() auto-fills from caller. RLS hardened to SELECT-only org match (writes RPC-only).';
COMMENT ON COLUMN public.sustainability_kpi_targets.organization_id IS
  'V4 multi-tenant scoping (ADR-0009). DEFAULT auth_org() auto-fills from caller. RLS hardened to SELECT-only org match (writes RPC-only).';
COMMENT ON COLUMN public.mcp_usage_log.organization_id IS
  'V4 multi-tenant scoping (ADR-0009). DEFAULT auth_org() auto-fills from caller. RLS = admin gate (manage_member) AND org match; superadmin bypass.';
