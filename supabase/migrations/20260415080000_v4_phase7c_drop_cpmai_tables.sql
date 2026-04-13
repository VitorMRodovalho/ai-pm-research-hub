-- ============================================================================
-- V4 Phase 7c — Drop deprecated cpmai_* tables
-- ADR: ADR-0009 (Config-Driven Initiative Kinds)
-- Context: 7 tables deprecated in Fase 6 (migration 20260413640000) with
--          REVOKE writes + COMMENT ON TABLE. Data migrated to
--          initiatives/initiative_member_progress in Fase 6.
-- Backup: JSON snapshot taken via execute_sql before drop (2026-04-13).
--         1 course + 5 domains preserved. 0 enrollments/progress/sessions.
-- Rollback: Restore from backup JSON + recreate tables from
--           migrations 20260321052333 and 20260413630000.
-- ============================================================================

-- Drop in dependency order (children first)
DROP TABLE IF EXISTS public.cpmai_mock_scores CASCADE;
DROP TABLE IF EXISTS public.cpmai_progress CASCADE;
DROP TABLE IF EXISTS public.cpmai_sessions CASCADE;
DROP TABLE IF EXISTS public.cpmai_modules CASCADE;
DROP TABLE IF EXISTS public.cpmai_enrollments CASCADE;
DROP TABLE IF EXISTS public.cpmai_domains CASCADE;
DROP TABLE IF EXISTS public.cpmai_courses CASCADE;

-- NOTE: get_cpmai_course_dashboard(uuid) is KEPT — it was rewritten in
-- Fase 6 (migration 20260413630000) to read from initiatives +
-- initiative_member_progress. CpmaiLanding.tsx still calls it.

NOTIFY pgrst, 'reload schema';
