-- ADR-0032 Group W: convert 3 board admin writers to V4 manage_board_admin (resource-scoped)
-- See docs/adr/ADR-0032-board-admin-v4-conversion.md

-- ============================================================
-- 1. admin_archive_project_board
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_archive_project_board(
  p_board_id uuid,
  p_reason text DEFAULT NULL::text,
  p_archive_items boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_board record;
  v_archived_items integer := 0;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Auth required';
  END IF;

  SELECT * INTO v_board FROM public.project_boards WHERE id = p_board_id;
  IF v_board IS NULL THEN
    RAISE EXCEPTION 'Board not found: %', p_board_id;
  END IF;

  -- V4 gate: org-wide manage_board_admin OR initiative-scoped
  IF NOT public.can_by_member(v_caller_id, 'manage_board_admin', 'initiative', v_board.initiative_id) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  UPDATE public.project_boards
  SET is_active = false, updated_at = now()
  WHERE id = p_board_id;

  IF p_archive_items THEN
    UPDATE public.board_items
    SET status = 'archived', updated_at = now()
    WHERE board_id = p_board_id AND status <> 'archived';
    GET DIAGNOSTICS v_archived_items = ROW_COUNT;
  END IF;

  INSERT INTO public.board_lifecycle_events (board_id, action, reason, actor_member_id)
  VALUES (p_board_id, 'board_archived', NULLIF(TRIM(COALESCE(p_reason, '')), ''), v_caller_id);

  RETURN jsonb_build_object('success', true, 'board_id', p_board_id, 'archived_items', v_archived_items);
END;
$$;
COMMENT ON FUNCTION public.admin_archive_project_board(uuid, text, boolean) IS
  'Phase B'' V4 conversion (ADR-0032, p66): manage_board_admin resource-scoped via can_by_member. Was V3 (SA OR manager/deputy_manager OR co_gp OR tribe_leader own-tribe).';

-- ============================================================
-- 2. admin_restore_project_board
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_restore_project_board(
  p_board_id uuid,
  p_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_board record;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Auth required';
  END IF;

  SELECT * INTO v_board FROM public.project_boards WHERE id = p_board_id;
  IF v_board IS NULL THEN
    RAISE EXCEPTION 'Board not found: %', p_board_id;
  END IF;

  -- V4 gate: org-wide manage_board_admin OR initiative-scoped
  IF NOT public.can_by_member(v_caller_id, 'manage_board_admin', 'initiative', v_board.initiative_id) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  UPDATE public.project_boards
  SET is_active = true, updated_at = now()
  WHERE id = p_board_id;

  INSERT INTO public.board_lifecycle_events (board_id, action, reason, actor_member_id)
  VALUES (p_board_id, 'board_restored', NULLIF(TRIM(COALESCE(p_reason, '')), ''), v_caller_id);

  RETURN jsonb_build_object('success', true, 'board_id', p_board_id);
END;
$$;
COMMENT ON FUNCTION public.admin_restore_project_board(uuid, text) IS
  'Phase B'' V4 conversion (ADR-0032, p66): manage_board_admin resource-scoped via can_by_member. Was V3 (SA OR manager/deputy_manager OR co_gp OR tribe_leader own-tribe).';

-- ============================================================
-- 3. admin_update_board_columns
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_update_board_columns(
  p_board_id uuid,
  p_columns jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_board record;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'authentication_required');
  END IF;

  SELECT * INTO v_board FROM public.project_boards WHERE id = p_board_id;
  IF v_board IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'board_not_found');
  END IF;

  -- V4 gate: org-wide manage_board_admin OR initiative-scoped
  IF NOT public.can_by_member(v_caller_id, 'manage_board_admin', 'initiative', v_board.initiative_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
  END IF;

  IF jsonb_array_length(p_columns) < 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'minimum_2_columns');
  END IF;
  IF jsonb_array_length(p_columns) > 8 THEN
    RETURN jsonb_build_object('success', false, 'error', 'maximum_8_columns');
  END IF;

  UPDATE public.project_boards
  SET columns = p_columns, updated_at = now()
  WHERE id = p_board_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
COMMENT ON FUNCTION public.admin_update_board_columns(uuid, jsonb) IS
  'Phase B'' V4 conversion (ADR-0032, p66): manage_board_admin resource-scoped via can_by_member. Was V3 (SA OR manager/deputy_manager OR tribe_leader own-tribe — note: V3 sem co_gp). p66 expansion: co_gp + initiative-leader gain access (intentional, per ADR-0032 Q2 ratify).';

NOTIFY pgrst, 'reload schema';
