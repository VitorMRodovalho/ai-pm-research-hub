-- p150 hotfix6 (2026-05-12) — cron_run_log.organization_id constraint mismatch.
--
-- Bug: cron_run_log.organization_id is NOT NULL since Ω-E.1 financial RLS
-- hardening (p136), but the RPC log_cron_run_start does NOT populate it.
-- INSERT rejected with "null value in column 'organization_id' violates
-- not-null constraint". Worker /ingest wraps logRunStart in try/catch and
-- silences with console.error → cron_run_log stays empty even though
-- pmi-vep-sync /ingest ran multiple times today.
--
-- Symptom for PM: cron_run_log query returns 0 rows in 24h despite 3 apply
-- runs from the UI. Observability gap.
--
-- Fix: cron_run_log is system-level audit (worker, cron jobs) — NOT tenant
-- data. organization_id NULL is the correct state when the run is
-- system-level (worker as service_role, no auth_org context).
-- DROP NOT NULL — RLS policy cron_run_log_v4_org_scope already accepts
-- NULL rows ("organization_id = auth_org() OR organization_id IS NULL"),
-- so admins continue to see system-level rows.
--
-- This matches the pattern used in mcp_usage_log post-Ω-E.1.c (commit
-- 1de9996 p136): admin path for NULL org allowed.

ALTER TABLE public.cron_run_log ALTER COLUMN organization_id DROP NOT NULL;

COMMENT ON COLUMN public.cron_run_log.organization_id IS
  'NULL allowed for system-level worker runs (no auth_org context). Tenant-scoped runs populate explicitly. RLS accepts both via cron_run_log_v4_org_scope policy.';
