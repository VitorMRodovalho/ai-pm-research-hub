-- ============================================================================
-- V4 Phase 7b — Deprecate tribe-based RPCs in favor of _by_initiative
-- ADR: ADR-0005 (Initiative como Primitivo do Domínio)
-- Depends on: 20260413240000_v4_phase2_initiative_rpcs.sql (wrappers exist)
-- Rollback: Re-run original COMMENT ON FUNCTION statements (or remove comments)
-- ============================================================================
-- These 9 RPCs accept integer tribe_id and are the legacy API.
-- The canonical API is the _by_initiative variants (UUID initiative_id).
-- Callers should migrate to _by_initiative RPCs.
-- These functions will be dropped after all callers are migrated (Fase 7c+).
-- ============================================================================

-- 1. exec_tribe_dashboard → exec_initiative_dashboard
COMMENT ON FUNCTION public.exec_tribe_dashboard(integer, text) IS
  'DEPRECATED (V4 Phase 7): Use exec_initiative_dashboard(uuid, text) instead. Will be removed after migration complete.';

-- 2. get_tribe_attendance_grid → get_initiative_attendance_grid
COMMENT ON FUNCTION public.get_tribe_attendance_grid(integer, text) IS
  'DEPRECATED (V4 Phase 7): Use get_initiative_attendance_grid(uuid, text) instead. Will be removed after migration complete.';

-- 3. list_tribe_deliverables → list_initiative_deliverables
COMMENT ON FUNCTION public.list_tribe_deliverables(integer, text) IS
  'DEPRECATED (V4 Phase 7): Use list_initiative_deliverables(uuid, text) instead. Will be removed after migration complete.';

-- 4. get_tribe_stats → get_initiative_stats
COMMENT ON FUNCTION public.get_tribe_stats(integer) IS
  'DEPRECATED (V4 Phase 7): Use get_initiative_stats(uuid) instead. Will be removed after migration complete.';

-- 5. get_tribe_events_timeline → get_initiative_events_timeline
COMMENT ON FUNCTION public.get_tribe_events_timeline(integer, integer, integer) IS
  'DEPRECATED (V4 Phase 7): Use get_initiative_events_timeline(uuid, integer, integer) instead. Will be removed after migration complete.';

-- 6. get_tribe_gamification → get_initiative_gamification
COMMENT ON FUNCTION public.get_tribe_gamification(integer) IS
  'DEPRECATED (V4 Phase 7): Use get_initiative_gamification(uuid) instead. Will be removed after migration complete.';

-- 7. list_meeting_artifacts (takes p_tribe_id) → list_initiative_meeting_artifacts
COMMENT ON FUNCTION public.list_meeting_artifacts(integer, integer) IS
  'DEPRECATED (V4 Phase 7): Use list_initiative_meeting_artifacts(integer, uuid) instead. Will be removed after migration complete.';

-- 8. list_project_boards (takes p_tribe_id) → list_initiative_boards
COMMENT ON FUNCTION public.list_project_boards(integer) IS
  'DEPRECATED (V4 Phase 7): Use list_initiative_boards(uuid) instead. Will be removed after migration complete.';

-- 9. search_board_items (takes p_tribe_id) → search_initiative_board_items
COMMENT ON FUNCTION public.search_board_items(text, integer) IS
  'DEPRECATED (V4 Phase 7): Use search_initiative_board_items(text, uuid) instead. Will be removed after migration complete.';

-- Also create a reverse helper: resolve initiative_id FROM tribe_id
-- (resolve_tribe_id goes initiative→tribe; this goes tribe→initiative)
CREATE OR REPLACE FUNCTION public.resolve_initiative_id(p_tribe_id integer)
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM public.initiatives WHERE legacy_tribe_id = p_tribe_id;
$$;

COMMENT ON FUNCTION public.resolve_initiative_id(integer) IS
  'V4 bridge: resolve legacy integer tribe_id to initiative UUID. Used during migration.';

GRANT EXECUTE ON FUNCTION public.resolve_initiative_id(integer) TO authenticated;

-- PostgREST reload
NOTIFY pgrst, 'reload schema';
