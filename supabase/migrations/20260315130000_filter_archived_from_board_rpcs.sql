-- Fix: Filter archived items from get_board and get_curation_cross_board RPCs
-- Archived items should not appear in board views.

-- ─── 1. get_board — add archived filter ────────────────────────────────────

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
          'baseline_date', i.baseline_date,
          'forecast_date', i.forecast_date,
          'actual_completion_date', i.actual_completion_date,
          'mirror_source_id', i.mirror_source_id,
          'mirror_target_id', i.mirror_target_id,
          'is_mirror', i.is_mirror,
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
        AND i.status <> 'archived'
    )
  ) INTO v_result;
  RETURN v_result;
END;
$$;

-- ─── 2. get_curation_cross_board — add archived filter ─────────────────────

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
      AND i.status <> 'archived'
  ), '[]'::jsonb);
END;
$$;
