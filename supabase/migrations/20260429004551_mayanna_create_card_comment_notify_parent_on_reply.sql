-- Mayanna report (28/Abr p79 round 3): "Opção de menção quando comentário é respondido não".
-- Root cause: create_card_comment já notifica @mentions e card assignee, mas não notifica
-- o autor do parent_comment quando alguém responde. Sem isso, replies viram silent.
--
-- Fix: estender create_card_comment com notification para parent author quando p_parent_comment_id
-- é fornecido. Type: 'card_comment_reply'. Delivery: transactional_immediate (urgent).
-- Skip se parent_author == caller (auto-reply) ou parent_author já em mentioned_member_ids
-- (evita double-notify). Card assignee notify também ganha skip se igual ao parent_author.
--
-- Sobre "aprovado": board comments não tem approval workflow ainda. Reply é o caso real.

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
  v_parent_author_id uuid;
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
    SELECT author_id INTO v_parent_author_id
    FROM public.board_item_comments
    WHERE id = p_parent_comment_id AND board_item_id = p_board_item_id AND deleted_at IS NULL;
    IF v_parent_author_id IS NULL THEN
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

  IF v_parent_author_id IS NOT NULL
     AND v_parent_author_id != v_caller.id
     AND NOT (v_parent_author_id = ANY(coalesce(p_mentioned_member_ids, '{}'::uuid[]))) THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, link, actor_id, delivery_mode)
    VALUES (
      v_parent_author_id,
      'card_comment_reply',
      v_caller.name || ' respondeu seu comentário em ' || coalesce(v_card.title, 'um card'),
      p_body,
      'board_item',
      v_card.id,
      '/boards/' || v_board.id || '/items/' || v_card.id,
      v_caller.id,
      'transactional_immediate'
    );
  END IF;

  IF v_card.assignee_id IS NOT NULL
     AND v_card.assignee_id != v_caller.id
     AND NOT (v_card.assignee_id = ANY(coalesce(p_mentioned_member_ids, '{}'::uuid[])))
     AND v_card.assignee_id IS DISTINCT FROM v_parent_author_id THEN
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
    'mentioned_count', array_length(coalesce(p_mentioned_member_ids, '{}'::uuid[]), 1),
    'replied_to_author', v_parent_author_id IS NOT NULL AND v_parent_author_id != v_caller.id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_card_comment(uuid, text, uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_card_comment(uuid, text, uuid, uuid[]) TO authenticated;

COMMENT ON FUNCTION public.create_card_comment(uuid, text, uuid, uuid[]) IS
'Mayanna Items 01+06+round-3: comentário em board_item. Notifica (immediate) @menções + parent comment author (em replies); notifica (digest) card assignee.';

NOTIFY pgrst, 'reload schema';
