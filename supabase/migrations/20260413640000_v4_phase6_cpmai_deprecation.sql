-- ============================================================================
-- V4 Phase 6 — Migration 5/5: CPMAI Tables Deprecation
-- ADR: ADR-0009 (Config-Driven Initiative Kinds)
-- Depends on: 20260413630000_v4_phase6_cpmai_migration.sql
-- Rollback: COMMENT ON TABLE cpmai_courses IS NULL;
--           (restore INSERT/UPDATE/DELETE grants via Phase 7 if needed)
-- ============================================================================

-- Mark all cpmai_* tables as deprecated. Data is now in initiatives + initiative_member_progress.
-- Tables remain read-only for backward compatibility during Fase 7 quiet window.

COMMENT ON TABLE public.cpmai_courses IS 'DEPRECATED (V4 Phase 6): Use initiatives WHERE kind=''study_group''. Will be dropped in Fase 7.';
COMMENT ON TABLE public.cpmai_domains IS 'DEPRECATED (V4 Phase 6): Domains stored in initiatives.metadata->''domains''. Will be dropped in Fase 7.';
COMMENT ON TABLE public.cpmai_modules IS 'DEPRECATED (V4 Phase 6): Modules stored in initiatives.metadata. Will be dropped in Fase 7.';
COMMENT ON TABLE public.cpmai_enrollments IS 'DEPRECATED (V4 Phase 6): Use engagements WHERE kind IN (''study_group_participant'',''study_group_owner''). Will be dropped in Fase 7.';
COMMENT ON TABLE public.cpmai_progress IS 'DEPRECATED (V4 Phase 6): Use initiative_member_progress WHERE progress_type=''module_completion''. Will be dropped in Fase 7.';
COMMENT ON TABLE public.cpmai_mock_scores IS 'DEPRECATED (V4 Phase 6): Use initiative_member_progress WHERE progress_type=''mock_score''. Will be dropped in Fase 7.';
COMMENT ON TABLE public.cpmai_sessions IS 'DEPRECATED (V4 Phase 6): Use events WHERE initiative_id = <study_group initiative>. Will be dropped in Fase 7.';

-- Revoke write access on deprecated tables (make truly read-only)
-- All 7 tables have rpc_only_deny_all RLS, but revoking DML as defense-in-depth.
REVOKE INSERT, UPDATE, DELETE ON public.cpmai_courses FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.cpmai_domains FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.cpmai_modules FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.cpmai_enrollments FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.cpmai_progress FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.cpmai_mock_scores FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.cpmai_sessions FROM authenticated;

NOTIFY pgrst, 'reload schema';
