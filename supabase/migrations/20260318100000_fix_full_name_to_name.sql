-- ============================================================================
-- HOTFIX: Fix "column am.full_name does not exist" in BoardEngine RPCs
-- The members table uses column "name", not "full_name".
-- This migration re-creates all affected RPCs with the correct column name.
-- Safe to re-run (CREATE OR REPLACE).
-- ============================================================================

-- ─── 1. get_board ────────────────────────────────────────────────────────────

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

-- ─── 2. get_board_by_domain (calls get_board internally, no direct fix needed)
-- Included for completeness — no changes to SQL, just re-create to ensure consistency.

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

-- ─── 3. get_board_members ────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_board_members(uuid);

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
  SELECT m.id, m.name, m.avatar_url, m.operational_role
  FROM members m
  WHERE m.is_active = true
    AND (
      v_scope = 'global'
      OR (v_scope = 'tribe' AND m.tribe_id = v_tribe_id)
    )
  ORDER BY m.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_board_members(uuid) TO authenticated;

-- ─── 4. update_board_item (assignment log references members.name) ───────────

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

-- ─── 5. get_card_timeline ────────────────────────────────────────────────────

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

-- ─── 6. get_curation_cross_board ─────────────────────────────────────────────

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
