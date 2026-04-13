-- ============================================================================
-- V4 Phase 2 — Migration 5/5: _by_initiative RPC variants
-- ADR: ADR-0005 (Initiative como Primitivo do Domínio)
-- Depends on: 20260413230000_v4_phase2_dual_write_triggers.sql
-- Rollback: DROP FUNCTION public.resolve_tribe_id(uuid);
--           DROP FUNCTION public.exec_initiative_dashboard(uuid, text);
--           DROP FUNCTION public.get_initiative_attendance_grid(uuid, text);
--           DROP FUNCTION public.list_initiative_deliverables(uuid, text);
--           DROP FUNCTION public.list_initiative_meeting_artifacts(integer, uuid);
--           DROP FUNCTION public.get_initiative_stats(uuid);
--           DROP FUNCTION public.get_initiative_events_timeline(uuid, integer, integer);
--           DROP FUNCTION public.list_initiative_boards(uuid);
--           DROP FUNCTION public.search_initiative_board_items(text, uuid);
--           DROP FUNCTION public.get_initiative_gamification(uuid);
-- ============================================================================

-- Shared helper: resolve initiative_id → legacy tribe_id
-- Used by all wrapper RPCs to delegate to existing tribe-based RPCs.
CREATE OR REPLACE FUNCTION public.resolve_tribe_id(p_initiative_id uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT legacy_tribe_id FROM public.initiatives WHERE id = p_initiative_id;
$$;

COMMENT ON FUNCTION public.resolve_tribe_id(uuid) IS 'V4 bridge: resolve initiative UUID to legacy integer tribe_id';

-- ── 1. exec_initiative_dashboard ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.exec_initiative_dashboard(
  p_initiative_id uuid,
  p_cycle text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN public.exec_tribe_dashboard(public.resolve_tribe_id(p_initiative_id), p_cycle);
END;
$$;
GRANT EXECUTE ON FUNCTION public.exec_initiative_dashboard(uuid, text) TO authenticated;

-- ── 2. get_initiative_attendance_grid ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_initiative_attendance_grid(
  p_initiative_id uuid,
  p_event_type text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN public.get_tribe_attendance_grid(public.resolve_tribe_id(p_initiative_id), p_event_type);
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_initiative_attendance_grid(uuid, text) TO authenticated;

-- ── 3. list_initiative_deliverables ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_initiative_deliverables(
  p_initiative_id uuid,
  p_cycle_code text DEFAULT NULL
) RETURNS SETOF public.tribe_deliverables LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY SELECT * FROM public.list_tribe_deliverables(public.resolve_tribe_id(p_initiative_id), p_cycle_code);
END;
$$;
GRANT EXECUTE ON FUNCTION public.list_initiative_deliverables(uuid, text) TO authenticated;

-- ── 4. list_initiative_meeting_artifacts ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_initiative_meeting_artifacts(
  p_limit integer DEFAULT 20,
  p_initiative_id uuid DEFAULT NULL
) RETURNS SETOF public.meeting_artifacts LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY SELECT * FROM public.list_meeting_artifacts(p_limit, public.resolve_tribe_id(p_initiative_id));
END;
$$;
GRANT EXECUTE ON FUNCTION public.list_initiative_meeting_artifacts(integer, uuid) TO authenticated;

-- ── 5. get_initiative_stats ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_initiative_stats(
  p_initiative_id uuid
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN public.get_tribe_stats(public.resolve_tribe_id(p_initiative_id));
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_initiative_stats(uuid) TO authenticated;

-- ── 6. get_initiative_events_timeline ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_initiative_events_timeline(
  p_initiative_id uuid,
  p_upcoming_limit integer DEFAULT 3,
  p_past_limit integer DEFAULT 5
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN public.get_tribe_events_timeline(public.resolve_tribe_id(p_initiative_id), p_upcoming_limit, p_past_limit);
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_initiative_events_timeline(uuid, integer, integer) TO authenticated;

-- ── 7. list_initiative_boards ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_initiative_boards(
  p_initiative_id uuid DEFAULT NULL
) RETURNS SETOF json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY SELECT * FROM public.list_project_boards(public.resolve_tribe_id(p_initiative_id));
END;
$$;
GRANT EXECUTE ON FUNCTION public.list_initiative_boards(uuid) TO authenticated;

-- ── 8. search_initiative_board_items ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.search_initiative_board_items(
  p_query text,
  p_initiative_id uuid DEFAULT NULL
) RETURNS SETOF json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY SELECT * FROM public.search_board_items(p_query, public.resolve_tribe_id(p_initiative_id));
END;
$$;
GRANT EXECUTE ON FUNCTION public.search_initiative_board_items(text, uuid) TO authenticated;

-- ── 9. get_initiative_gamification ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_initiative_gamification(
  p_initiative_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN public.get_tribe_gamification(public.resolve_tribe_id(p_initiative_id));
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_initiative_gamification(uuid) TO authenticated;

-- PostgREST reload
NOTIFY pgrst, 'reload schema';
