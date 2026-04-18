-- ============================================================================
-- ADR-0015 Phase 1 — meeting_artifacts reader cutover (3rd C3 table)
--
-- Scope: 2 reader RPCs refactored to filter via initiatives (V4 primitive)
-- instead of tribes (V3 bridge). SETOF meeting_artifacts return shape
-- preserved (both tribe_id + initiative_id columns still in output).
--
-- Dual-write integrity: 12 rows total — 11 both + 1 neither (outlier, no
-- scope). 0 tribe_only + 0 init_only → lossless for tribe-bound rows.
--
-- Changed RPCs:
--   1. list_meeting_artifacts       — filter via initiatives.legacy_tribe_id
--   2. list_initiative_meeting_artifacts — filter by initiative_id directly
--      (no longer relies on resolve_tribe_id bridge — now V4-native)
--
-- NOT changed (writes still valid; triggers sync until Phase 2/3):
--   - save_presentation_snapshot — writes tribe_id, dual-write handles sync
--
-- Semantic note: filter expression preserved — "matching scope OR global"
--   OLD: tribe_id = p_tribe_id OR tribe_id IS NULL
--   NEW: i.legacy_tribe_id = p_tribe_id OR ma.initiative_id IS NULL
-- Equivalence holds given dual-write invariants.
--
-- ADR: ADR-0015 Phase 1, ADR-0005
-- Rollback: restore prior bodies (see bottom).
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. list_meeting_artifacts — JOIN initiatives for filter
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.list_meeting_artifacts(
  p_limit integer DEFAULT 100,
  p_tribe_id integer DEFAULT NULL
)
RETURNS SETOF meeting_artifacts
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
  SELECT ma.*
  FROM public.meeting_artifacts ma
  LEFT JOIN public.initiatives i ON i.id = ma.initiative_id  -- ADR-0015 Phase 1
  WHERE ma.is_published = true
    AND (
      p_tribe_id IS NULL
      OR i.legacy_tribe_id = p_tribe_id  -- ADR-0015 Phase 1: primitive-native filter
      OR ma.initiative_id IS NULL        -- global (unscoped) artifacts
    )
  ORDER BY ma.meeting_date DESC
  LIMIT p_limit;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. list_initiative_meeting_artifacts — direct initiative_id filter
-- (no longer routes through resolve_tribe_id bridge)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.list_initiative_meeting_artifacts(
  p_limit integer DEFAULT 100,
  p_initiative_id uuid DEFAULT NULL
)
RETURNS SETOF meeting_artifacts
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  IF p_initiative_id IS NOT NULL THEN
    PERFORM public.assert_initiative_capability(p_initiative_id, 'has_meeting_notes');
  END IF;

  RETURN QUERY
    SELECT *
    FROM public.meeting_artifacts ma
    WHERE ma.is_published = true
      AND (
        p_initiative_id IS NULL
        OR ma.initiative_id = p_initiative_id  -- ADR-0015 Phase 1: direct
        OR ma.initiative_id IS NULL            -- global (unscoped) artifacts
      )
    ORDER BY ma.meeting_date DESC
    LIMIT p_limit;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLLBACK: previous bodies used tribe_id filter directly.
--   list_meeting_artifacts:
--     SELECT * FROM public.meeting_artifacts
--     WHERE is_published = true
--       AND (p_tribe_id is null OR tribe_id = p_tribe_id OR tribe_id is null)
--     ORDER BY meeting_date DESC LIMIT p_limit;
--   list_initiative_meeting_artifacts:
--     PERFORM assert_initiative_capability(...)
--     RETURN QUERY SELECT * FROM list_meeting_artifacts(p_limit, resolve_tribe_id(p_initiative_id));
-- ═══════════════════════════════════════════════════════════════════════════
