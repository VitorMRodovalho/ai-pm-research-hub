-- p223 audit MED #10 close — formalize accepted advisor risk per ADR-0096.
-- COMMENT ON VIEW: preserves p170 BUG-HOI canonical formula rationale
-- and adds ADR-0096 cross-reference for the security_definer_view advisor finding.
--
-- Rollback: revert this COMMENT to the prior p170 BUG-HOI text:
--   COMMENT ON VIEW public.impact_hours_total IS
--     'p170 BUG-HOI — refactored to canonical formula (COALESCE duration_actual + excused filter). Match get_impact_hours_canonical() exactly. Antes p170: SUM(duration_minutes) only.';
COMMENT ON VIEW public.impact_hours_total IS
  'Platform-wide YTD impact hours aggregate. SECURITY DEFINER view — accepted advisor risk per ADR-0096.
   anon REVOKE''d (only authenticated/service_role); content is scalar aggregates (no PII per row).
   Canonical formula (p170 BUG-HOI): SUM(COALESCE(duration_actual, duration_minutes)/60) FILTER (present=true AND excused IS NOT TRUE).
   Consumed by: attendance.astro + kpi_summary RPC + w104_kpi_targets_health + w105_cycle_report + analytics_v2 internal readonly.';
