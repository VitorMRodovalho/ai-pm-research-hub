-- Mayanna report Item 01 (BUG ALTA): comentários no card.
-- Schema novo + 4 RPCs + RLS + MCP tools.
-- Habilita Item 06 (@menções) automaticamente.

CREATE TABLE IF NOT EXISTS public.board_item_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_item_id uuid NOT NULL REFERENCES public.board_items(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES public.members(id),
  body text NOT NULL,
  parent_comment_id uuid REFERENCES public.board_item_comments(id) ON DELETE SET NULL,
  mentioned_member_ids uuid[] DEFAULT '{}',
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_board_item_comments_board_item_id ON public.board_item_comments(board_item_id);
CREATE INDEX IF NOT EXISTS idx_board_item_comments_author_id ON public.board_item_comments(author_id);
CREATE INDEX IF NOT EXISTS idx_board_item_comments_created_at ON public.board_item_comments(created_at DESC);

ALTER TABLE public.board_item_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY board_item_comments_read_authenticated ON public.board_item_comments
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL
    AND EXISTS (
      SELECT 1 FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      WHERE bi.id = board_item_comments.board_item_id
    )
  );

ALTER TABLE public.board_lifecycle_events
  DROP CONSTRAINT board_lifecycle_events_action_check;

ALTER TABLE public.board_lifecycle_events
  ADD CONSTRAINT board_lifecycle_events_action_check CHECK (
    action = ANY (ARRAY[
      'board_archived', 'board_restored', 'item_archived', 'item_restored',
      'archived', 'deleted', 'created', 'status_change', 'forecast_update',
      'actual_completion', 'mirror_created', 'assigned', 'member_assigned',
      'member_unassigned', 'submitted_for_curation', 'reviewer_assigned',
      'curation_review', 'curation_approved', 'moved_out', 'moved_in',
      'baseline_set', 'baseline_locked', 'baseline_changed', 'forecast_changed',
      'title_changed', 'portfolio_flag_changed', 'activity_added',
      'activity_completed', 'activity_reopened', 'activity_assigned',
      'comment_added', 'comment_edited', 'comment_deleted'
    ])
  );

CREATE OR REPLACE FUNCTION public.create_card_comment(
  p_board_item_id uuid,
  p_body text,
  p_parent_comment_id uuid DEFAULT NULL,
  p_mentioned_member_ids uuid[] DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller record;
  v_card record;
  v_board record;
  v_authorized boolean;
  v_new_id uuid;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF coalesce(trim(p_body), '') = '' THEN
    RETURN jsonb_build_object('error', 'Comment body required');
  END IF;

  SELECT * INTO v_card FROM public.board_items WHERE id = p_board_item_id;
  IF v_card.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  SELECT * INTO v_board FROM public.project_boards WHERE id = v_card.board_id;

  v_authorized := public.rls_is_member()
    OR public.can_by_member(v_caller.id, 'write_board')
    OR (coalesce(v_board.domain_key, '') = 'communication' AND (
      v_caller.operational_role = 'communicator'
      OR coalesce('comms_team' = ANY(v_caller.designations), false)
      OR coalesce('comms_leader' = ANY(v_caller.designations), false)
      OR coalesce('comms_member' = ANY(v_caller.designations), false)
    ));

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized: must be a member or have write_board to comment');
  END IF;

  IF p_parent_comment_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.board_item_comments
      WHERE id = p_parent_comment_id AND board_item_id = p_board_item_id AND deleted_at IS NULL
    ) THEN
      RETURN jsonb_build_object('error', 'Parent comment not found or deleted');
    END IF;
  END IF;

  INSERT INTO public.board_item_comments (
    board_item_id, author_id, body, parent_comment_id, mentioned_member_ids
  )
  VALUES (
    p_board_item_id, v_caller.id, p_body, p_parent_comment_id, COALESCE(p_mentioned_member_ids, '{}'::uuid[])
  )
  RETURNING id INTO v_new_id;

  INSERT INTO public.board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id, 'comment_added',
    substring(p_body from 1 for 100) || CASE WHEN length(p_body) > 100 THEN '...' ELSE '' END,
    v_caller.id);

  IF p_mentioned_member_ids IS NOT NULL AND array_length(p_mentioned_member_ids, 1) > 0 THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, link, actor_id, delivery_mode)
    SELECT
      mid,
      'card_comment_mention',
      v_caller.name || ' mencionou você em ' || coalesce(v_card.title, 'um card'),
      p_body,
      'board_item',
      v_card.id,
      '/boards/' || v_board.id || '/items/' || v_card.id,
      v_caller.id,
      'transactional_immediate'
    FROM unnest(p_mentioned_member_ids) AS mid
    WHERE mid != v_caller.id;
  END IF;

  IF v_card.assignee_id IS NOT NULL
     AND v_card.assignee_id != v_caller.id
     AND NOT (v_card.assignee_id = ANY(coalesce(p_mentioned_member_ids, '{}'::uuid[]))) THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, link, actor_id, delivery_mode)
    VALUES (
      v_card.assignee_id,
      'card_comment_new',
      v_caller.name || ' comentou em ' || coalesce(v_card.title, 'um card'),
      p_body,
      'board_item',
      v_card.id,
      '/boards/' || v_board.id || '/items/' || v_card.id,
      v_caller.id,
      'digest_weekly'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'comment_id', v_new_id,
    'author_id', v_caller.id,
    'mentioned_count', array_length(coalesce(p_mentioned_member_ids, '{}'::uuid[]), 1)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_card_comment(uuid, text, uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_card_comment(uuid, text, uuid, uuid[]) TO authenticated;

COMMENT ON FUNCTION public.create_card_comment(uuid, text, uuid, uuid[]) IS
'Mayanna Item 01: comentário em board_item. Suporta thread (parent_comment_id) + @menções (notification immediate). Authority: rls_is_member OR write_board OR comms in communication domain.';

CREATE OR REPLACE FUNCTION public.list_card_comments(p_board_item_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.board_items WHERE id = p_board_item_id) THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'author_id', c.author_id,
    'author_name', m.name,
    'author_photo_url', m.photo_url,
    'body', c.body,
    'parent_comment_id', c.parent_comment_id,
    'mentioned_member_ids', c.mentioned_member_ids,
    'edited_at', c.edited_at,
    'created_at', c.created_at
  ) ORDER BY c.created_at ASC), '[]'::jsonb)
  INTO v_result
  FROM public.board_item_comments c
  LEFT JOIN public.members m ON m.id = c.author_id
  WHERE c.board_item_id = p_board_item_id
    AND c.deleted_at IS NULL;

  RETURN jsonb_build_object('card_id', p_board_item_id, 'comments', v_result);
END;
$$;

REVOKE ALL ON FUNCTION public.list_card_comments(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_card_comments(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_card_comment(p_comment_id uuid, p_new_body text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_comment record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_comment FROM public.board_item_comments WHERE id = p_comment_id;
  IF v_comment.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Comment not found');
  END IF;

  IF v_comment.author_id != v_caller_id THEN
    RETURN jsonb_build_object('error', 'Only author can edit own comment');
  END IF;

  IF v_comment.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Cannot edit deleted comment');
  END IF;

  IF coalesce(trim(p_new_body), '') = '' THEN
    RETURN jsonb_build_object('error', 'Body required');
  END IF;

  UPDATE public.board_item_comments
  SET body = p_new_body, edited_at = now(), updated_at = now()
  WHERE id = p_comment_id;

  RETURN jsonb_build_object('success', true, 'comment_id', p_comment_id);
END;
$$;

REVOKE ALL ON FUNCTION public.update_card_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_card_comment(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_card_comment(p_comment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_comment record;
  v_authorized boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_comment FROM public.board_item_comments WHERE id = p_comment_id;
  IF v_comment.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Comment not found');
  END IF;

  v_authorized := v_comment.author_id = v_caller_id
    OR public.can_by_member(v_caller_id, 'write_board')
    OR public.can_by_member(v_caller_id, 'manage_member');

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE public.board_item_comments
  SET deleted_at = now(), updated_at = now()
  WHERE id = p_comment_id;

  RETURN jsonb_build_object('success', true, 'comment_id', p_comment_id);
END;
$$;

REVOKE ALL ON FUNCTION public.delete_card_comment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_card_comment(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
