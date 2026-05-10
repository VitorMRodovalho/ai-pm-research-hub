-- =====================================================================
-- p136 Ω-E.1.c — mcp_usage_log: admins see NULL organization_id rows
-- =====================================================================
-- Discovered post Ω-E.1.b smoke: sync-artia EF (and any service_role
-- INSERT path) creates mcp_usage_log rows with organization_id = NULL
-- because DEFAULT auth_org() returns NULL when auth.uid() is NULL
-- (service_role has no auth context).
--
-- Under Ω-E.1's policy `(rls_is_superadmin() OR (rls_can('manage_member')
-- AND organization_id = auth_org()))`, NULL org rows were invisible to
-- non-superadmin admins (NULL = uuid evaluates to NULL ≠ true).
--
-- This amendment treats NULL organization_id as "platform/system log"
-- visible to any manage_member admin. Aligns with V4 standard pattern
-- `OR organization_id IS NULL` already used in 30+ other tables.
--
-- NOT applied to financial tables (cost_entries, revenue_entries,
-- sustainability_kpi_targets) — those remain strict (NULL = unassigned,
-- superadmin-only) because financial data is inherently org-scoped and
-- shouldn't have a "platform/global" mode.
--
-- Rollback: re-apply Ω-E.1's original policy without the IS NULL clause.
-- =====================================================================

DROP POLICY IF EXISTS mcp_usage_log_select_admin_org ON public.mcp_usage_log;

CREATE POLICY mcp_usage_log_select_admin_org ON public.mcp_usage_log
  FOR SELECT TO authenticated
  USING (
    rls_is_superadmin()
    OR (
      rls_can('manage_member')
      AND (organization_id = auth_org() OR organization_id IS NULL)
    )
  );
