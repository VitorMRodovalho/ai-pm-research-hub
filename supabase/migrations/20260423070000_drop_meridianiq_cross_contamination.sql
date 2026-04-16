-- ═══════════════════════════════════════════════════════════════
-- Drop 16 ghost tables (Primavera P6 / DCMA schedule analyzer schema)
--
-- Confirmed by user (2026-04-16) as cross-contamination from
-- MeridianIQ project — unrelated to Núcleo IA. Created via Supabase
-- dashboard before this git repo existed (pre 2026-03-04). Zero rows,
-- zero autovacuum, zero application code references, zero ADR/doc
-- mentions. Closes 16 rls_enabled_no_policy INFO advisors.
--
-- Dropped cluster:
--   schedule_uploads (hub), activities, activity_codes, activity_code_types,
--   alerts, calendars, cost_accounts, float_snapshots, health_scores,
--   predecessors, reports, resource_assignments, resources,
--   udf_types, udf_values, wbs_elements
--
-- Dependencies: only own indexes (no views/FKs/functions). CASCADE is safe.
-- Rollback: not applicable — if MeridianIQ schema is needed again, it
-- should be recreated in a dedicated schema or project, not public.
-- ═══════════════════════════════════════════════════════════════

DROP TABLE IF EXISTS public.float_snapshots CASCADE;
DROP TABLE IF EXISTS public.alerts CASCADE;
DROP TABLE IF EXISTS public.health_scores CASCADE;
DROP TABLE IF EXISTS public.predecessors CASCADE;
DROP TABLE IF EXISTS public.resource_assignments CASCADE;
DROP TABLE IF EXISTS public.activities CASCADE;
DROP TABLE IF EXISTS public.wbs_elements CASCADE;
DROP TABLE IF EXISTS public.udf_values CASCADE;
DROP TABLE IF EXISTS public.udf_types CASCADE;
DROP TABLE IF EXISTS public.activity_codes CASCADE;
DROP TABLE IF EXISTS public.activity_code_types CASCADE;
DROP TABLE IF EXISTS public.cost_accounts CASCADE;
DROP TABLE IF EXISTS public.calendars CASCADE;
DROP TABLE IF EXISTS public.resources CASCADE;
DROP TABLE IF EXISTS public.reports CASCADE;
DROP TABLE IF EXISTS public.schedule_uploads CASCADE;
