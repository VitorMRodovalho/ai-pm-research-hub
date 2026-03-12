-- ============================================================================
-- BoardEngine RPCs — Sprint 1 Foundation
-- 12 RPCs for the generic board engine component.
-- Uses CREATE OR REPLACE; safe to re-run.
-- Depends on: project_boards, board_items, board_lifecycle_events, members
-- ============================================================================

-- ─── 1. get_board: Fetch board config + all items in one call ───────────────

CREATE OR REPLACE FUNCTION public.get_board(p_board_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'board', (
      SELECT jsonb_build_object(
        'id', b.id,
        'board_name', b.board_name,
        'tribe_id', b.tribe_id,
        'source', b.source,
        'columns', b.columns,
        'is_active', b.is_active,
        'domain_key', b.domain_key,
        'board_scope', b.board_scope,
        'cycle_scope', b.cycle_scope
      )
      FROM project_boards b WHERE b.id = p_board_id
    ),
    'items', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'title', i.title,
          'description', i.description,
          'status', i.status,
          'assignee_id', i.assignee_id,
          'assignee_name', am.name,
          'reviewer_id', i.reviewer_id,
          'reviewer_name', rm.name,
          'tags', i.tags,
          'labels', i.labels,
          'due_date', i.due_date,
          'position', i.position,
          'attachments', i.attachments,
          'checklist', i.checklist,
          'curation_status', i.curation_status,
          'curation_due_at', i.curation_due_at,
          'cycle', i.cycle,
          'source_card_id', i.source_card_id,
          'source_board', i.source_board,
          'created_at', i.created_at,
          'updated_at', i.updated_at
        ) ORDER BY i.position
      ), '[]'::jsonb)
      FROM board_items i
      LEFT JOIN members am ON am.id = i.assignee_id
      LEFT JOIN members rm ON rm.id = i.reviewer_id
      WHERE i.board_id = p_board_id
    )
  ) INTO v_result;
  RETURN v_result;
END;
$$;

-- ─── 2. get_board_by_domain: Resolve board by domain_key + optional tribe ───

CREATE OR REPLACE FUNCTION public.get_board_by_domain(
  p_domain_key text,
  p_tribe_id int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_board_id uuid;
BEGIN
  SELECT id INTO v_board_id
  FROM project_boards
  WHERE domain_key = p_domain_key
    AND is_active = true
    AND (p_tribe_id IS NULL OR tribe_id = p_tribe_id)
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('board', null, 'items', '[]'::jsonb);
  END IF;

  RETURN public.get_board(v_board_id);
END;
$$;

-- ─── 3. get_board_members: Members for MemberPicker ─────────────────────────

CREATE OR REPLACE FUNCTION public.get_board_members(p_board_id uuid)
RETURNS TABLE(id uuid, name text, avatar_url text, operational_role text)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_scope text;
  v_tribe_id int;
BEGIN
  SELECT board_scope, pb.tribe_id INTO v_scope, v_tribe_id
  FROM project_boards pb WHERE pb.id = p_board_id;

  RETURN QUERY
  SELECT m.id, m.name, m.photo_url AS avatar_url, m.operational_role
  FROM members m
  WHERE m.is_active = true
    AND (
      v_scope = 'global'
      OR (v_scope = 'tribe' AND m.tribe_id = v_tribe_id)
    )
  ORDER BY m.name;
END;
$$;

-- ─── 4. create_board_item: Create a new card ────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_board_item(
  p_board_id uuid,
  p_title text,
  p_description text DEFAULT NULL,
  p_assignee_id uuid DEFAULT NULL,
  p_tags text[] DEFAULT '{}',
  p_due_date date DEFAULT NULL,
  p_status text DEFAULT 'backlog'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
  v_max_pos int;
  v_actor uuid;
BEGIN
  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = p_board_id AND status = p_status;

  INSERT INTO board_items (
    board_id, title, description, assignee_id, tags, due_date, position, status, cycle
  ) VALUES (
    p_board_id, p_title, p_description, p_assignee_id, p_tags, p_due_date, v_max_pos, p_status, 3
  ) RETURNING id INTO v_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, new_status, actor_member_id)
  VALUES (p_board_id, v_id, 'created', p_status, v_actor);

  RETURN v_id;
END;
$$;

-- ─── 5. Evolve move_board_item: add p_reason param ──────────────────────────
-- The existing function has signature (uuid, text, integer).
-- We drop and recreate with (uuid, text, integer, text) to add audit reason.

DROP FUNCTION IF EXISTS public.move_board_item(uuid, text, integer);

CREATE OR REPLACE FUNCTION public.move_board_item(
  p_item_id uuid,
  p_new_status text,
  p_new_position int DEFAULT 0,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_old_status text;
  v_board_id uuid;
  v_actor uuid;
BEGIN
  SELECT status, board_id INTO v_old_status, v_board_id
  FROM board_items WHERE id = p_item_id;

  IF v_old_status IS NULL THEN
    RAISE EXCEPTION 'Item not found: %', p_item_id;
  END IF;

  UPDATE board_items
  SET position = position + 1
  WHERE board_id = v_board_id AND status = p_new_status
    AND position >= p_new_position AND id != p_item_id;

  UPDATE board_items
  SET status = p_new_status, position = p_new_position, updated_at = now()
  WHERE id = p_item_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  IF v_old_status != p_new_status THEN
    INSERT INTO board_lifecycle_events
      (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
    VALUES
      (v_board_id, p_item_id, 'status_change', v_old_status, p_new_status, p_reason, v_actor);
  END IF;
END;
$$;

-- ─── 6. update_board_item: Generic field updater ────────────────────────────

CREATE OR REPLACE FUNCTION public.update_board_item(
  p_item_id uuid,
  p_fields jsonb
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_board_id uuid;
  v_old_assignee uuid;
  v_new_assignee uuid;
  v_actor uuid;
BEGIN
  SELECT board_id, assignee_id INTO v_board_id, v_old_assignee
  FROM board_items WHERE id = p_item_id;

  IF v_board_id IS NULL THEN
    RAISE EXCEPTION 'Item not found: %', p_item_id;
  END IF;

  UPDATE board_items SET
    title = coalesce(p_fields->>'title', title),
    description = CASE WHEN p_fields ? 'description' THEN p_fields->>'description' ELSE description END,
    assignee_id = CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                       THEN (p_fields->>'assignee_id')::uuid
                       WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NULL
                       THEN NULL
                       ELSE assignee_id END,
    reviewer_id = CASE WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NOT NULL
                       THEN (p_fields->>'reviewer_id')::uuid
                       WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NULL
                       THEN NULL
                       ELSE reviewer_id END,
    tags = CASE WHEN p_fields ? 'tags'
                THEN ARRAY(SELECT jsonb_array_elements_text(p_fields->'tags'))
                ELSE tags END,
    labels = CASE WHEN p_fields ? 'labels' THEN p_fields->'labels' ELSE labels END,
    due_date = CASE WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NOT NULL
                    THEN (p_fields->>'due_date')::date
                    WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NULL
                    THEN NULL
                    ELSE due_date END,
    checklist = CASE WHEN p_fields ? 'checklist' THEN p_fields->'checklist' ELSE checklist END,
    attachments = CASE WHEN p_fields ? 'attachments' THEN p_fields->'attachments' ELSE attachments END,
    curation_status = coalesce(p_fields->>'curation_status', curation_status),
    curation_due_at = CASE WHEN p_fields ? 'curation_due_at' AND p_fields->>'curation_due_at' IS NOT NULL
                           THEN (p_fields->>'curation_due_at')::timestamptz
                           ELSE curation_due_at END,
    updated_at = now()
  WHERE id = p_item_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  v_new_assignee := CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                         THEN (p_fields->>'assignee_id')::uuid
                         ELSE v_old_assignee END;

  IF v_new_assignee IS DISTINCT FROM v_old_assignee THEN
    INSERT INTO board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES
      (v_board_id, p_item_id, 'assigned',
       'Atribuído a ' || coalesce((SELECT name FROM members WHERE id = v_new_assignee), 'ninguém'),
       v_actor);
  END IF;
END;
$$;

-- ─── 7. delete_board_item: Soft delete (archive) ───────────────────────────

CREATE OR REPLACE FUNCTION public.delete_board_item(
  p_item_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_board_id uuid;
  v_old_status text;
  v_actor uuid;
BEGIN
  SELECT board_id, status INTO v_board_id, v_old_status
  FROM board_items WHERE id = p_item_id;

  UPDATE board_items
  SET status = 'archived', updated_at = now()
  WHERE id = p_item_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  INSERT INTO board_lifecycle_events
    (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
  VALUES
    (v_board_id, p_item_id, 'archived', v_old_status, 'archived', p_reason, v_actor);
END;
$$;

-- ─── 8. duplicate_board_item: Clone card ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.duplicate_board_item(
  p_item_id uuid,
  p_target_board_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_new_id uuid;
  v_board_id uuid;
  v_max_pos int;
  v_actor uuid;
BEGIN
  SELECT coalesce(p_target_board_id, board_id) INTO v_board_id
  FROM board_items WHERE id = p_item_id;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = v_board_id AND status = 'backlog';

  INSERT INTO board_items (
    board_id, title, description, tags, labels, checklist, attachments, cycle, position, status
  )
  SELECT v_board_id, title || ' (cópia)', description, tags, labels, checklist, attachments, cycle, v_max_pos, 'backlog'
  FROM board_items WHERE id = p_item_id
  RETURNING id INTO v_new_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_board_id, v_new_id, 'created', 'Duplicado de ' || p_item_id::text, v_actor);

  RETURN v_new_id;
END;
$$;

-- ─── 9. move_item_to_board: Transfer card between boards ────────────────────

CREATE OR REPLACE FUNCTION public.move_item_to_board(
  p_item_id uuid,
  p_target_board_id uuid
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_old_board_id uuid;
  v_max_pos int;
  v_actor uuid;
BEGIN
  SELECT board_id INTO v_old_board_id FROM board_items WHERE id = p_item_id;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = p_target_board_id AND status = 'backlog';

  UPDATE board_items
  SET board_id = p_target_board_id, status = 'backlog', position = v_max_pos, updated_at = now()
  WHERE id = p_item_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES
    (v_old_board_id, p_item_id, 'moved_out', 'Movido para outro board', v_actor),
    (p_target_board_id, p_item_id, 'moved_in', 'Recebido de outro board', v_actor);
END;
$$;

-- ─── 10. get_card_timeline: Audit trail for a card ──────────────────────────

CREATE OR REPLACE FUNCTION public.get_card_timeline(p_item_id uuid)
RETURNS TABLE(
  id bigint,
  action text,
  previous_status text,
  new_status text,
  reason text,
  actor_name text,
  created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.action,
    e.previous_status,
    e.new_status,
    e.reason,
    m.name AS actor_name,
    e.created_at
  FROM board_lifecycle_events e
  LEFT JOIN members m ON m.id = e.actor_member_id
  WHERE e.item_id = p_item_id
  ORDER BY e.created_at DESC;
END;
$$;

-- ─── 11. get_curation_cross_board: Items across ALL boards ──────────────────

CREATE OR REPLACE FUNCTION public.get_curation_cross_board()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN coalesce((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'board_id', i.board_id,
        'board_name', b.board_name,
        'tribe_id', b.tribe_id,
        'domain_key', b.domain_key,
        'title', i.title,
        'description', i.description,
        'status', i.status,
        'assignee_id', i.assignee_id,
        'assignee_name', am.name,
        'reviewer_id', i.reviewer_id,
        'reviewer_name', rm.name,
        'tags', i.tags,
        'labels', i.labels,
        'due_date', i.due_date,
        'attachments', i.attachments,
        'checklist', i.checklist,
        'curation_status', i.curation_status,
        'curation_due_at', i.curation_due_at,
        'cycle', i.cycle,
        'created_at', i.created_at,
        'updated_at', i.updated_at
      ) ORDER BY
        CASE i.curation_status
          WHEN 'draft' THEN 0
          WHEN 'review' THEN 1
          WHEN 'approved' THEN 2
          WHEN 'rejected' THEN 3
        END,
        i.updated_at DESC
    )
    FROM board_items i
    JOIN project_boards b ON b.id = i.board_id
    LEFT JOIN members am ON am.id = i.assignee_id
    LEFT JOIN members rm ON rm.id = i.reviewer_id
    WHERE b.is_active = true
  ), '[]'::jsonb);
END;
$$;

-- ─── 12. list_active_boards: For board selector / navigation ────────────────

CREATE OR REPLACE FUNCTION public.list_active_boards()
RETURNS TABLE(
  id uuid,
  board_name text,
  tribe_id int,
  domain_key text,
  board_scope text,
  source text,
  item_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    b.id,
    b.board_name,
    b.tribe_id,
    b.domain_key,
    b.board_scope,
    b.source,
    (SELECT count(*) FROM board_items bi WHERE bi.board_id = b.id) AS item_count
  FROM project_boards b
  WHERE b.is_active = true
  ORDER BY b.board_scope, b.tribe_id NULLS FIRST, b.board_name;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANT EXECUTE to authenticated users
-- ═══════════════════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION public.get_board(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_board_by_domain(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_board_members(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_board_item(uuid, text, text, uuid, text[], date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_board_item(uuid, text, int, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_board_item(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_board_item(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.duplicate_board_item(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_item_to_board(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_card_timeline(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_curation_cross_board() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_active_boards() TO authenticated;
