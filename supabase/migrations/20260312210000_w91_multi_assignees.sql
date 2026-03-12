-- ============================================================================
-- W91: Multiple Assignees per Card (Junction Table)
-- Creates board_item_assignments, backfills from legacy fields,
-- and adds RPCs for managing assignments.
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Junction table for multiple assignees with roles
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS board_item_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid REFERENCES board_items(id) ON DELETE CASCADE NOT NULL,
  member_id uuid REFERENCES members(id) NOT NULL,
  role text NOT NULL DEFAULT 'contributor',
  assigned_at timestamptz DEFAULT now(),
  assigned_by uuid REFERENCES members(id),
  UNIQUE(item_id, member_id, role)
);

COMMENT ON TABLE board_item_assignments IS 'Multiple assignees per card with differentiated roles';
COMMENT ON COLUMN board_item_assignments.role IS 'author | reviewer | contributor | curation_reviewer';

CREATE INDEX IF NOT EXISTS idx_bia_item ON board_item_assignments(item_id);
CREATE INDEX IF NOT EXISTS idx_bia_member ON board_item_assignments(member_id);

-- RLS
ALTER TABLE board_item_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read assignments" ON board_item_assignments
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Board members can manage assignments" ON board_item_assignments
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Backfill from legacy assignee_id / reviewer_id fields
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO board_item_assignments (item_id, member_id, role, assigned_at)
SELECT id, assignee_id, 'author', updated_at
FROM board_items
WHERE assignee_id IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO board_item_assignments (item_id, member_id, role, assigned_at)
SELECT id, reviewer_id, 'reviewer', updated_at
FROM board_items
WHERE reviewer_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. RPC: assign_member_to_item
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.assign_member_to_item(
  p_item_id uuid,
  p_member_id uuid,
  p_role text DEFAULT 'contributor'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_member members%rowtype;
  v_assignment_id uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT (
    v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')
    OR (p_role = 'curation_reviewer' AND 'curator' = ANY(coalesce(v_caller.designations, array[]::text[])))
  ) THEN
    RAISE EXCEPTION 'Requires tribe_leader, manager, or curator role';
  END IF;

  IF p_role NOT IN ('author', 'reviewer', 'contributor', 'curation_reviewer') THEN
    RAISE EXCEPTION 'Invalid role: %. Must be author|reviewer|contributor|curation_reviewer', p_role;
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  SELECT * INTO v_member FROM members WHERE id = p_member_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Member not found'; END IF;

  INSERT INTO board_item_assignments (item_id, member_id, role, assigned_by)
  VALUES (p_item_id, p_member_id, p_role, v_caller.id)
  ON CONFLICT (item_id, member_id, role) DO NOTHING
  RETURNING id INTO v_assignment_id;

  IF v_assignment_id IS NOT NULL THEN
    INSERT INTO board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES
      (v_item.board_id, p_item_id, 'member_assigned',
       v_member.name || ' como ' || p_role,
       v_caller.id);
  END IF;

  RETURN coalesce(v_assignment_id, (
    SELECT id FROM board_item_assignments
    WHERE item_id = p_item_id AND member_id = p_member_id AND role = p_role
  ));
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_member_to_item(uuid, uuid, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RPC: unassign_member_from_item
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.unassign_member_from_item(
  p_item_id uuid,
  p_member_id uuid,
  p_role text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_member_name text;
  v_deleted int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT (
    v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')
  ) THEN
    RAISE EXCEPTION 'Requires tribe_leader or manager role';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  SELECT name INTO v_member_name FROM members WHERE id = p_member_id;

  DELETE FROM board_item_assignments
  WHERE item_id = p_item_id AND member_id = p_member_id AND role = p_role;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  IF v_deleted > 0 THEN
    INSERT INTO board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES
      (v_item.board_id, p_item_id, 'member_unassigned',
       coalesce(v_member_name, 'membro') || ' removido de ' || p_role,
       v_caller.id);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.unassign_member_from_item(uuid, uuid, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. RPC: get_item_assignments (with fallback to legacy fields)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_item_assignments(p_item_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result jsonb;
  v_has_junction boolean;
BEGIN
  SELECT EXISTS(SELECT 1 FROM board_item_assignments WHERE item_id = p_item_id)
  INTO v_has_junction;

  IF v_has_junction THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', bia.id,
      'member_id', bia.member_id,
      'name', m.name,
      'avatar_url', m.photo_url,
      'role', bia.role,
      'assigned_at', bia.assigned_at
    ) ORDER BY
      CASE bia.role
        WHEN 'author' THEN 0
        WHEN 'reviewer' THEN 1
        WHEN 'curation_reviewer' THEN 2
        WHEN 'contributor' THEN 3
      END,
      bia.assigned_at
    ), '[]'::jsonb) INTO v_result
    FROM board_item_assignments bia
    JOIN members m ON m.id = bia.member_id
    WHERE bia.item_id = p_item_id;
  ELSE
    -- Fallback: read from legacy assignee_id / reviewer_id
    SELECT coalesce(jsonb_agg(x ORDER BY x->>'role'), '[]'::jsonb) INTO v_result
    FROM (
      SELECT jsonb_build_object(
        'id', null,
        'member_id', bi.assignee_id,
        'name', am.name,
        'avatar_url', am.photo_url,
        'role', 'author',
        'assigned_at', bi.updated_at
      ) AS x
      FROM board_items bi
      LEFT JOIN members am ON am.id = bi.assignee_id
      WHERE bi.id = p_item_id AND bi.assignee_id IS NOT NULL
      UNION ALL
      SELECT jsonb_build_object(
        'id', null,
        'member_id', bi.reviewer_id,
        'name', rm.name,
        'avatar_url', rm.photo_url,
        'role', 'reviewer',
        'assigned_at', bi.updated_at
      )
      FROM board_items bi
      LEFT JOIN members rm ON rm.id = bi.reviewer_id
      WHERE bi.id = p_item_id AND bi.reviewer_id IS NOT NULL
    ) sub;
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_item_assignments(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Update get_board to include assignments array per item
-- ═══════════════════════════════════════════════════════════════════════════

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
          'updated_at', i.updated_at,
          'assignments', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
              'member_id', bia.member_id,
              'name', bm.name,
              'avatar_url', bm.photo_url,
              'role', bia.role
            ) ORDER BY
              CASE bia.role WHEN 'author' THEN 0 WHEN 'reviewer' THEN 1 WHEN 'curation_reviewer' THEN 2 ELSE 3 END,
              bia.assigned_at
            )
            FROM board_item_assignments bia
            JOIN members bm ON bm.id = bia.member_id
            WHERE bia.item_id = i.id
          ), '[]'::jsonb)
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
