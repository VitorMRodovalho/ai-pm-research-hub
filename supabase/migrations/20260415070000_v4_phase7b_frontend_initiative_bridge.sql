-- ============================================================================
-- V4 Phase 7b — Frontend Initiative Bridge
-- ADR: ADR-0005 (Initiative como Primitivo do Domínio)
-- Purpose: Add p_initiative_id support to RPCs called by frontend that
--          don't yet have _by_initiative variants.
-- Rollback: Re-create functions without p_initiative_id parameter.
-- ============================================================================

-- ── 1. get_board_by_domain — add p_initiative_id parameter ──────────────────
-- project_boards already has initiative_id column (Phase 2).
-- Frontend will pass p_initiative_id instead of p_tribe_id.

DROP FUNCTION IF EXISTS public.get_board_by_domain(text, int);

CREATE OR REPLACE FUNCTION public.get_board_by_domain(
  p_domain_key text,
  p_tribe_id int DEFAULT NULL,
  p_initiative_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_board_id uuid;
  v_resolved_tribe_id int;
BEGIN
  -- Resolve initiative_id to tribe_id if provided
  IF p_initiative_id IS NOT NULL AND p_tribe_id IS NULL THEN
    v_resolved_tribe_id := public.resolve_tribe_id(p_initiative_id);
  ELSE
    v_resolved_tribe_id := p_tribe_id;
  END IF;

  SELECT id INTO v_board_id
  FROM project_boards
  WHERE domain_key = p_domain_key
    AND is_active = true
    AND (v_resolved_tribe_id IS NULL OR tribe_id = v_resolved_tribe_id)
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('board', null, 'items', '[]'::jsonb);
  END IF;

  RETURN public.get_board(v_board_id);
END;
$$;

COMMENT ON FUNCTION public.get_board_by_domain(text, int, uuid) IS
  'V4: Resolve board by domain_key + optional tribe_id or initiative_id';

GRANT EXECUTE ON FUNCTION public.get_board_by_domain(text, int, uuid) TO authenticated;

-- ── 2. get_initiative_member_contacts ────────────────────────────────────────
-- Wrapper around get_tribe_member_contacts for frontend migration.

CREATE OR REPLACE FUNCTION public.get_initiative_member_contacts(
  p_initiative_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN public.get_tribe_member_contacts(public.resolve_tribe_id(p_initiative_id));
END;
$$;

COMMENT ON FUNCTION public.get_initiative_member_contacts(uuid) IS
  'V4 wrapper: get member contacts by initiative UUID. Delegates to get_tribe_member_contacts.';

GRANT EXECUTE ON FUNCTION public.get_initiative_member_contacts(uuid) TO authenticated;

-- ── 3. broadcast_count_today — add p_initiative_id ──────────────────────────

-- First check current signature and recreate with initiative support
CREATE OR REPLACE FUNCTION public.broadcast_count_today_v4(
  p_initiative_id uuid
)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT public.broadcast_count_today(public.resolve_tribe_id(p_initiative_id));
$$;

COMMENT ON FUNCTION public.broadcast_count_today_v4(uuid) IS
  'V4 wrapper: broadcast count by initiative UUID.';

GRANT EXECUTE ON FUNCTION public.broadcast_count_today_v4(uuid) TO authenticated;

-- ── PostgREST reload ────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
