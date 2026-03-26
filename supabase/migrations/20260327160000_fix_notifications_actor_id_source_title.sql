-- Fix P0: notifications table missing actor_id, RPCs referencing source_title
-- add actor_id column and fix create_notification + move_board_item RPCs

-- 1. Add actor_id column
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS actor_id uuid REFERENCES members(id);

-- 2. Fix the overloaded create_notification (source_title → title)
DROP FUNCTION IF EXISTS create_notification(uuid, text, text, uuid, text, uuid);

CREATE OR REPLACE FUNCTION create_notification(
  p_recipient_id uuid,
  p_type text,
  p_source_type text DEFAULT NULL,
  p_source_id uuid DEFAULT NULL,
  p_source_title text DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_notif_id uuid; v_prefs record;
BEGIN
  IF p_recipient_id = p_actor_id THEN RETURN NULL; END IF;
  SELECT * INTO v_prefs FROM notification_preferences WHERE member_id = p_recipient_id;
  IF FOUND THEN
    IF v_prefs.in_app = false THEN RETURN NULL; END IF;
    IF p_type = ANY(v_prefs.muted_types) THEN RETURN NULL; END IF;
  END IF;
  INSERT INTO notifications (recipient_id, type, source_type, source_id, title, actor_id)
  VALUES (p_recipient_id, p_type, p_source_type, p_source_id, p_source_title, p_actor_id)
  RETURNING id INTO v_notif_id;
  RETURN v_notif_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_notification(uuid, text, text, uuid, text, uuid) TO authenticated;

-- 3. Fix move_board_item notification INSERT (source_title → title)
CREATE OR REPLACE FUNCTION move_board_item(
  p_item_id uuid,
  p_new_status text,
  p_new_position integer DEFAULT 0,
  p_reason text DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_old_status text; v_board_id uuid; v_actor record; v_board record;
  v_is_gp boolean; v_is_leader boolean; v_is_card_owner boolean;
BEGIN
  SELECT status, board_id INTO v_old_status, v_board_id FROM board_items WHERE id = p_item_id;
  IF v_old_status IS NULL THEN RAISE EXCEPTION 'Item not found'; END IF;
  SELECT * INTO v_actor FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_board FROM project_boards WHERE id = v_board_id;

  v_is_gp := coalesce(v_actor.is_superadmin, false) OR v_actor.operational_role IN ('manager','deputy_manager') OR coalesce('co_gp' = ANY(v_actor.designations), false);
  v_is_leader := v_actor.operational_role = 'tribe_leader' AND v_actor.tribe_id = v_board.tribe_id;

  v_is_card_owner := EXISTS (SELECT 1 FROM board_items WHERE id = p_item_id AND (created_by = v_actor.id OR assignee_id = v_actor.id))
    OR EXISTS (SELECT 1 FROM board_item_assignments WHERE item_id = p_item_id AND member_id = v_actor.id);

  IF p_new_status = 'done' AND NOT v_is_gp AND NOT v_is_leader THEN
    RAISE EXCEPTION 'Only Leader or GP can mark as completed';
  END IF;

  IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_card_owner THEN
    RAISE EXCEPTION 'You can only move your own cards';
  END IF;

  UPDATE board_items SET position = position + 1
  WHERE board_id = v_board_id AND status = p_new_status AND position >= p_new_position AND id != p_item_id;

  UPDATE board_items SET status = p_new_status, position = p_new_position,
    actual_completion_date = CASE WHEN p_new_status = 'done' THEN CURRENT_DATE ELSE actual_completion_date END,
    updated_at = now()
  WHERE id = p_item_id;

  IF v_old_status != p_new_status THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'status_change', v_old_status, p_new_status, p_reason, v_actor.id);
    INSERT INTO notifications (recipient_id, type, source_type, source_id, title, actor_id)
    SELECT bia.member_id,
      CASE WHEN p_new_status = 'review' THEN 'review_requested' ELSE 'card_status_changed' END,
      'board_item', p_item_id, (SELECT title FROM board_items WHERE id = p_item_id), v_actor.id
    FROM board_item_assignments bia WHERE bia.item_id = p_item_id AND bia.member_id != v_actor.id;
  END IF;
END;
$$;

-- 4. Update get_my_notifications to include actor info
CREATE OR REPLACE FUNCTION get_my_notifications(
  p_limit int DEFAULT 20,
  p_unread_only boolean DEFAULT false
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_result
  FROM (
    SELECT n.id, n.type, n.title, n.body, n.link, n.source_type, n.source_id,
           n.actor_id, m.name AS actor_name, n.is_read, n.created_at
    FROM notifications n
    LEFT JOIN members m ON m.id = n.actor_id
    WHERE n.recipient_id = v_member_id
      AND (NOT p_unread_only OR n.is_read = false)
    ORDER BY n.created_at DESC
    LIMIT p_limit
  ) r;

  RETURN v_result;
END;
$$;
