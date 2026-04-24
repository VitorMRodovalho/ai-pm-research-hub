-- Migration: Card/Checklist CRUD RPCs — P0 from issue #83
-- 2026-05-08 p39
-- Feedback origem: Fabrício Costa (líder Tribo 6) — MCP coverage <40% de board/card/checklist CRUD
-- Context: fecha P0 do gap analysis (8 tools). 4 tools novos + 4 wrap existentes no MCP layer.
-- Authority (ADR-0011 V4 pattern):
--   * Primary gate: public.can_by_member(v_caller_id, 'write_board') — engagement-derived
--   * Fallbacks (for legacy UX): card_owner (board_items.assignee_id) + board_admin/editor (board_members)
-- Audit: todas as mutations emitem board_lifecycle_events.
-- Rollback: DROP FUNCTION das 4 RPCs. Sem DDL destrutivo.

BEGIN;

-- =========================================================================
-- 1. get_card_detail — rich payload para reduzir round-trips LLM
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_card_detail(p_card_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_card record;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  -- Anonymous: return NULL (no raise — auth-not-required read via RLS-parity pattern).
  IF v_caller_id IS NULL THEN RETURN NULL; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = p_card_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Card not found: %', p_card_id; END IF;

  RETURN jsonb_build_object(
    'card', to_jsonb(v_card),
    'board', (
      SELECT jsonb_build_object(
        'id', pb.id,
        'name', pb.board_name,
        'initiative_id', pb.initiative_id,
        'domain_key', pb.domain_key
      )
      FROM project_boards pb WHERE pb.id = v_card.board_id
    ),
    'assignee', (
      SELECT jsonb_build_object('id', m.id, 'name', m.name, 'operational_role', m.operational_role)
      FROM members m WHERE m.id = v_card.assignee_id
    ),
    'reviewer', (
      SELECT jsonb_build_object('id', m.id, 'name', m.name)
      FROM members m WHERE m.id = v_card.reviewer_id
    ),
    'checklist', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ci.id,
        'text', ci.text,
        'is_completed', ci.is_completed,
        'position', ci.position,
        'assigned_to', ci.assigned_to,
        'assigned_to_name', (SELECT m.name FROM members m WHERE m.id = ci.assigned_to),
        'target_date', ci.target_date,
        'completed_at', ci.completed_at,
        'completed_by', ci.completed_by,
        'assigned_at', ci.assigned_at
      ) ORDER BY ci.position, ci.created_at)
      FROM board_item_checklists ci WHERE ci.board_item_id = p_card_id
    ), '[]'::jsonb),
    'assignments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', ba.member_id,
        'member_name', (SELECT m.name FROM members m WHERE m.id = ba.member_id),
        'role', ba.role,
        'assigned_at', ba.assigned_at
      ))
      FROM board_item_assignments ba WHERE ba.item_id = p_card_id
    ), '[]'::jsonb),
    'timeline', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'action', ble.action,
        'reason', ble.reason,
        'actor_member_id', ble.actor_member_id,
        'actor_name', (SELECT m.name FROM members m WHERE m.id = ble.actor_member_id),
        'created_at', ble.created_at,
        'previous_status', ble.previous_status,
        'new_status', ble.new_status
      ) ORDER BY ble.created_at DESC)
      FROM (
        SELECT * FROM board_lifecycle_events
        WHERE item_id = p_card_id
        ORDER BY created_at DESC
        LIMIT 10
      ) ble
    ), '[]'::jsonb)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_card_detail(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_card_detail(uuid) IS
  'Issue #83 P0: rich payload (card + checklist + assignments + last 10 timeline events) para reduzir round-trips.';

-- =========================================================================
-- 2. add_checklist_item — INSERT no checklist
-- =========================================================================
CREATE OR REPLACE FUNCTION public.add_checklist_item(
  p_board_item_id uuid,
  p_text text,
  p_position smallint DEFAULT NULL,
  p_assigned_to uuid DEFAULT NULL,
  p_target_date date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_card record;
  v_board record;
  v_authorized boolean;
  v_new_id uuid;
  v_final_position smallint;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  IF coalesce(trim(p_text), '') = '' THEN
    RAISE EXCEPTION 'Checklist item text is required';
  END IF;

  SELECT * INTO v_card FROM board_items WHERE id = p_board_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Card not found: %', p_board_item_id; END IF;

  SELECT * INTO v_board FROM project_boards WHERE id = v_card.board_id;

  -- ADR-0011 V4 authority: can_by_member('write_board') primary + legacy fallbacks
  v_authorized := public.can_by_member(v_caller_id, 'write_board')
    OR v_card.assignee_id = v_caller_id
    OR EXISTS (
      SELECT 1 FROM board_members bm
      WHERE bm.board_id = v_board.id AND bm.member_id = v_caller_id
      AND bm.board_role IN ('admin', 'editor')
    );

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership, or board editor role';
  END IF;

  IF p_position IS NULL THEN
    SELECT COALESCE(MAX(position), 0) + 1 INTO v_final_position
    FROM board_item_checklists WHERE board_item_id = p_board_item_id;
  ELSE
    v_final_position := p_position;
  END IF;

  INSERT INTO board_item_checklists (
    board_item_id, text, position, assigned_to, target_date,
    assigned_at, assigned_by
  )
  VALUES (
    p_board_item_id, p_text, v_final_position, p_assigned_to, p_target_date,
    CASE WHEN p_assigned_to IS NOT NULL THEN now() ELSE NULL END,
    CASE WHEN p_assigned_to IS NOT NULL THEN v_caller_id ELSE NULL END
  )
  RETURNING id INTO v_new_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id, 'activity_added',
    p_text || CASE WHEN p_assigned_to IS NOT NULL
      THEN ' → ' || COALESCE((SELECT m.name FROM members m WHERE m.id = p_assigned_to), '?')
      ELSE '' END,
    v_caller_id);

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_checklist_item(uuid, text, smallint, uuid, date) TO authenticated, service_role;

COMMENT ON FUNCTION public.add_checklist_item(uuid, text, smallint, uuid, date) IS
  'Issue #83 P0: adiciona checklist item em board_item. V4 gate can_by_member(write_board). Audita via board_lifecycle_events.';

-- =========================================================================
-- 3. update_checklist_item — partial UPDATE (text / position / target_date)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.update_checklist_item(
  p_checklist_item_id uuid,
  p_text text DEFAULT NULL,
  p_position smallint DEFAULT NULL,
  p_target_date date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_item record;
  v_card record;
  v_board record;
  v_authorized boolean;
  v_old_text text;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  SELECT * INTO v_item FROM board_item_checklists WHERE id = p_checklist_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Checklist item not found'; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = v_item.board_item_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_card.board_id;

  -- ADR-0011 V4 authority: can_by_member('write_board') primary + legacy fallbacks
  v_authorized := public.can_by_member(v_caller_id, 'write_board')
    OR v_card.assignee_id = v_caller_id
    OR EXISTS (
      SELECT 1 FROM board_members bm
      WHERE bm.board_id = v_board.id AND bm.member_id = v_caller_id
      AND bm.board_role IN ('admin', 'editor')
    );

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership, or board editor role';
  END IF;

  IF p_text IS NOT NULL AND trim(p_text) = '' THEN
    RAISE EXCEPTION 'Text cannot be empty. Use delete_checklist_item to remove.';
  END IF;

  v_old_text := v_item.text;

  UPDATE board_item_checklists
  SET
    text = COALESCE(p_text, text),
    position = COALESCE(p_position, position),
    target_date = CASE WHEN p_target_date IS NOT NULL THEN p_target_date ELSE target_date END
  WHERE id = p_checklist_item_id;

  IF p_text IS NOT NULL AND p_text IS DISTINCT FROM v_old_text THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_card.board_id, v_card.id, 'activity_updated',
      v_old_text || ' → ' || p_text, v_caller_id);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_checklist_item(uuid, text, smallint, date) TO authenticated, service_role;

COMMENT ON FUNCTION public.update_checklist_item(uuid, text, smallint, date) IS
  'Issue #83 P0: partial update (text/position/target_date) de checklist item. V4 gate can_by_member(write_board).';

-- =========================================================================
-- 4. delete_checklist_item — permanent delete
-- =========================================================================
CREATE OR REPLACE FUNCTION public.delete_checklist_item(
  p_checklist_item_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_item record;
  v_card record;
  v_board record;
  v_authorized boolean;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  SELECT * INTO v_item FROM board_item_checklists WHERE id = p_checklist_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Checklist item not found'; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = v_item.board_item_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_card.board_id;

  -- ADR-0011 V4 authority: can_by_member('write_board') primary + legacy fallbacks
  v_authorized := public.can_by_member(v_caller_id, 'write_board')
    OR v_card.assignee_id = v_caller_id
    OR EXISTS (
      SELECT 1 FROM board_members bm
      WHERE bm.board_id = v_board.id AND bm.member_id = v_caller_id
      AND bm.board_role IN ('admin', 'editor')
    );

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership, or board editor role';
  END IF;

  DELETE FROM board_item_checklists WHERE id = p_checklist_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id, 'activity_deleted',
    v_item.text || COALESCE(' (motivo: ' || p_reason || ')', ''),
    v_caller_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_checklist_item(uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.delete_checklist_item(uuid, text) IS
  'Issue #83 P0: delete permanente de checklist item. V4 gate can_by_member(write_board). Audita via board_lifecycle_events com motivo opcional.';

-- =========================================================================
-- Reload PostgREST schema cache
-- =========================================================================
NOTIFY pgrst, 'reload schema';

COMMIT;
