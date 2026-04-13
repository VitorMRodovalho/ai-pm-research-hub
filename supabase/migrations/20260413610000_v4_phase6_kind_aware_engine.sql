-- ============================================================================
-- V4 Phase 6 — Migration 2/5: Kind-Aware Engine RPCs
-- ADR: ADR-0009 (Config-Driven Initiative Kinds)
-- Depends on: 20260413600000_v4_phase6_initiative_kinds_enrichment.sql
-- Rollback: DROP FUNCTION IF EXISTS public.assert_initiative_capability(uuid, text);
--           DROP FUNCTION IF EXISTS public.create_initiative(text, text, text, jsonb, uuid);
--           DROP FUNCTION IF EXISTS public.update_initiative(uuid, text, text, text, jsonb);
--           DROP FUNCTION IF EXISTS public.list_initiatives(text, text);
--           -- Then re-apply Phase 2 RPCs without guards (20260413240000)
-- ============================================================================

-- ── Guard function: NO "if kind == X" code ──────────────────────────────────
-- Dynamically checks the boolean flag column on initiative_kinds for any initiative.
-- Engine RPCs call this at entry to gate features by config.

CREATE OR REPLACE FUNCTION public.assert_initiative_capability(
  p_initiative_id uuid,
  p_capability text  -- 'has_board', 'has_meeting_notes', 'has_deliverables', 'has_attendance', 'has_certificate'
) RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_ok boolean;
  v_kind text;
BEGIN
  -- Validate capability name is a known boolean flag (prevent SQL injection via format)
  IF p_capability NOT IN ('has_board', 'has_meeting_notes', 'has_deliverables', 'has_attendance', 'has_certificate') THEN
    RAISE EXCEPTION 'Unknown capability: %', p_capability USING ERRCODE = 'P0001';
  END IF;

  SELECT i.kind INTO v_kind FROM public.initiatives i WHERE i.id = p_initiative_id;
  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'Initiative not found: %', p_initiative_id USING ERRCODE = 'P0002';
  END IF;

  EXECUTE format('SELECT ik.%I FROM public.initiative_kinds ik WHERE ik.slug = $1', p_capability)
    INTO v_ok USING v_kind;

  IF v_ok IS NOT TRUE THEN
    RAISE EXCEPTION 'Initiative kind "%" does not support "%"', v_kind, p_capability
      USING ERRCODE = 'P0003';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_initiative_capability(uuid, text) IS
  'V4 Phase 6: Dynamic capability guard — checks initiative_kinds boolean flag without hardcoding kind names';

GRANT EXECUTE ON FUNCTION public.assert_initiative_capability(uuid, text) TO authenticated;

-- ── Recreate _by_initiative RPCs with guards ────────────────────────────────

-- 1. exec_initiative_dashboard (no specific capability — dashboards always work)
-- Kept as-is: dashboards are universal, not gated by flags.

-- 2. get_initiative_attendance_grid — gated by has_attendance
CREATE OR REPLACE FUNCTION public.get_initiative_attendance_grid(
  p_initiative_id uuid,
  p_event_type text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM public.assert_initiative_capability(p_initiative_id, 'has_attendance');
  RETURN public.get_tribe_attendance_grid(public.resolve_tribe_id(p_initiative_id), p_event_type);
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_initiative_attendance_grid(uuid, text) TO authenticated;

-- 3. list_initiative_deliverables — gated by has_deliverables
CREATE OR REPLACE FUNCTION public.list_initiative_deliverables(
  p_initiative_id uuid,
  p_cycle_code text DEFAULT NULL
) RETURNS SETOF public.tribe_deliverables LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM public.assert_initiative_capability(p_initiative_id, 'has_deliverables');
  RETURN QUERY SELECT * FROM public.list_tribe_deliverables(public.resolve_tribe_id(p_initiative_id), p_cycle_code);
END;
$$;
GRANT EXECUTE ON FUNCTION public.list_initiative_deliverables(uuid, text) TO authenticated;

-- 4. list_initiative_meeting_artifacts — gated by has_meeting_notes
CREATE OR REPLACE FUNCTION public.list_initiative_meeting_artifacts(
  p_limit integer DEFAULT 20,
  p_initiative_id uuid DEFAULT NULL
) RETURNS SETOF public.meeting_artifacts LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF p_initiative_id IS NOT NULL THEN
    PERFORM public.assert_initiative_capability(p_initiative_id, 'has_meeting_notes');
  END IF;
  RETURN QUERY SELECT * FROM public.list_meeting_artifacts(p_limit, public.resolve_tribe_id(p_initiative_id));
END;
$$;
GRANT EXECUTE ON FUNCTION public.list_initiative_meeting_artifacts(integer, uuid) TO authenticated;

-- 7. list_initiative_boards — gated by has_board
CREATE OR REPLACE FUNCTION public.list_initiative_boards(
  p_initiative_id uuid DEFAULT NULL
) RETURNS SETOF json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF p_initiative_id IS NOT NULL THEN
    PERFORM public.assert_initiative_capability(p_initiative_id, 'has_board');
  END IF;
  RETURN QUERY SELECT * FROM public.list_project_boards(public.resolve_tribe_id(p_initiative_id));
END;
$$;
GRANT EXECUTE ON FUNCTION public.list_initiative_boards(uuid) TO authenticated;

-- 8. search_initiative_board_items — gated by has_board
CREATE OR REPLACE FUNCTION public.search_initiative_board_items(
  p_query text,
  p_initiative_id uuid DEFAULT NULL
) RETURNS SETOF json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF p_initiative_id IS NOT NULL THEN
    PERFORM public.assert_initiative_capability(p_initiative_id, 'has_board');
  END IF;
  RETURN QUERY SELECT * FROM public.search_board_items(p_query, public.resolve_tribe_id(p_initiative_id));
END;
$$;
GRANT EXECUTE ON FUNCTION public.search_initiative_board_items(text, uuid) TO authenticated;

-- 9. get_initiative_gamification — no gate (gamification is universal)
-- Kept as-is.

-- ── CRUD RPCs for initiatives ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_initiative(
  p_kind text,
  p_title text,
  p_description text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_parent_initiative_id uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_kind_row record;
  v_count integer;
  v_new_id uuid;
BEGIN
  -- Validate kind exists
  SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = p_kind;
  IF v_kind_row IS NULL THEN
    RAISE EXCEPTION 'Unknown initiative kind: %', p_kind USING ERRCODE = 'P0004';
  END IF;

  -- Check max_concurrent_per_org constraint
  IF v_kind_row.max_concurrent_per_org IS NOT NULL THEN
    SELECT count(*) INTO v_count
    FROM public.initiatives
    WHERE kind = p_kind
      AND organization_id = public.auth_org()
      AND status IN ('draft', 'active');

    IF v_count >= v_kind_row.max_concurrent_per_org THEN
      RAISE EXCEPTION 'Maximum concurrent initiatives of kind "%" reached (limit: %)',
        p_kind, v_kind_row.max_concurrent_per_org USING ERRCODE = 'P0005';
    END IF;
  END IF;

  -- Insert initiative
  INSERT INTO public.initiatives (kind, title, description, metadata, parent_initiative_id, organization_id)
  VALUES (p_kind, p_title, p_description, p_metadata, p_parent_initiative_id, public.auth_org())
  RETURNING id INTO v_new_id;

  -- Auto-create board if kind has_board
  IF v_kind_row.has_board THEN
    INSERT INTO public.project_boards (board_name, initiative_id, source, is_active, organization_id)
    VALUES (p_title, v_new_id, 'manual', true, public.auth_org());
  END IF;

  RETURN v_new_id;
END;
$$;

COMMENT ON FUNCTION public.create_initiative(text, text, text, jsonb, uuid) IS
  'V4 Phase 6: Create initiative with kind validation, concurrency check, and auto-board creation';

GRANT EXECUTE ON FUNCTION public.create_initiative(text, text, text, jsonb, uuid) TO authenticated;

-- ── update_initiative ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_initiative(
  p_initiative_id uuid,
  p_title text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_metadata jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_initiative record;
  v_kind_row record;
BEGIN
  SELECT * INTO v_initiative FROM public.initiatives WHERE id = p_initiative_id;
  IF v_initiative IS NULL THEN
    RAISE EXCEPTION 'Initiative not found: %', p_initiative_id USING ERRCODE = 'P0002';
  END IF;

  -- Validate status against kind's lifecycle_states
  IF p_status IS NOT NULL THEN
    SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = v_initiative.kind;
    IF NOT (p_status = ANY(v_kind_row.lifecycle_states)) THEN
      RAISE EXCEPTION 'Invalid status "%" for kind "%". Allowed: %',
        p_status, v_initiative.kind, v_kind_row.lifecycle_states USING ERRCODE = 'P0006';
    END IF;
  END IF;

  UPDATE public.initiatives SET
    title = COALESCE(p_title, title),
    description = COALESCE(p_description, description),
    status = COALESCE(p_status, status),
    metadata = COALESCE(p_metadata, metadata),
    updated_at = now()
  WHERE id = p_initiative_id;

  RETURN jsonb_build_object('id', p_initiative_id, 'updated', true);
END;
$$;

COMMENT ON FUNCTION public.update_initiative(uuid, text, text, text, jsonb) IS
  'V4 Phase 6: Update initiative with lifecycle state validation';

GRANT EXECUTE ON FUNCTION public.update_initiative(uuid, text, text, text, jsonb) TO authenticated;

-- ── list_initiatives ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.list_initiatives(
  p_kind text DEFAULT NULL,
  p_status text DEFAULT NULL
) RETURNS SETOF jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT jsonb_build_object(
    'id', i.id,
    'kind', i.kind,
    'title', i.title,
    'description', i.description,
    'status', i.status,
    'metadata', i.metadata,
    'parent_initiative_id', i.parent_initiative_id,
    'legacy_tribe_id', i.legacy_tribe_id,
    'created_at', i.created_at,
    'kind_config', jsonb_build_object(
      'display_name', ik.display_name,
      'icon', ik.icon,
      'has_board', ik.has_board,
      'has_meeting_notes', ik.has_meeting_notes,
      'has_deliverables', ik.has_deliverables,
      'has_attendance', ik.has_attendance,
      'has_certificate', ik.has_certificate
    )
  )
  FROM public.initiatives i
  JOIN public.initiative_kinds ik ON ik.slug = i.kind
  WHERE i.organization_id = public.auth_org()
    AND (p_kind IS NULL OR i.kind = p_kind)
    AND (p_status IS NULL OR i.status = p_status)
  ORDER BY i.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.list_initiatives(text, text) IS
  'V4 Phase 6: List initiatives with kind config, filtered by kind/status';

GRANT EXECUTE ON FUNCTION public.list_initiatives(text, text) TO authenticated;

-- ── RLS for initiative_kinds writes (admin) ─────────────────────────────────
-- Phase 2 only had SELECT for authenticated. Add write policy for managers.

CREATE POLICY "initiative_kinds_write_admin"
  ON public.initiative_kinds FOR INSERT TO authenticated
  WITH CHECK (
    public.can_by_member(
      (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()),
      'write'
    )
  );

CREATE POLICY "initiative_kinds_update_admin"
  ON public.initiative_kinds FOR UPDATE TO authenticated
  USING (
    public.can_by_member(
      (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()),
      'write'
    )
  )
  WITH CHECK (
    public.can_by_member(
      (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()),
      'write'
    )
  );

CREATE POLICY "initiative_kinds_delete_admin"
  ON public.initiative_kinds FOR DELETE TO authenticated
  USING (
    public.can_by_member(
      (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()),
      'write'
    )
  );

-- PostgREST reload
NOTIFY pgrst, 'reload schema';
