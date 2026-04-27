-- ============================================================
-- ADR-0047: 3 more #84 Onda 2 RPCs
-- - get_card_full_history(card_id) — 360° timeline join (read-only)
-- - convert_action_to_card(action_item_id, board_id, ...) — atomic flow
-- - register_decision(event_id, title, description, related_card_ids[])
-- Cross-references: ADR-0045 (schema), ADR-0046 (action item lifecycle), #84 (issue)
-- Rollback: DROP these 3 fns
-- ============================================================

-- ── 1. get_card_full_history ───────────────────────────────
CREATE OR REPLACE FUNCTION public.get_card_full_history(
  p_card_id uuid
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_card record;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  SELECT bi.id, bi.title, bi.description, bi.status, bi.curation_status,
         bi.board_id, bi.assignee_id, bi.created_at, bi.updated_at
  INTO v_card FROM public.board_items bi WHERE bi.id = p_card_id;
  IF v_card.id IS NULL THEN
    RETURN jsonb_build_object('error', 'card_not_found');
  END IF;

  v_result := jsonb_build_object(
    'card', jsonb_build_object(
      'id', v_card.id,
      'title', v_card.title,
      'description', v_card.description,
      'status', v_card.status,
      'curation_status', v_card.curation_status,
      'board_id', v_card.board_id,
      'assignee_id', v_card.assignee_id,
      'created_at', v_card.created_at,
      'updated_at', v_card.updated_at
    ),
    'lifecycle_events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ble.id,
        'action', ble.action,
        'reason', ble.reason,
        'actor_member_id', ble.actor_member_id,
        'actor_name', am.name,
        'created_at', ble.created_at,
        'review_round', ble.review_round,
        'review_score', ble.review_score
      ) ORDER BY ble.created_at DESC)
      FROM public.board_lifecycle_events ble
      LEFT JOIN public.members am ON am.id = ble.actor_member_id
      WHERE ble.item_id = p_card_id
    ), '[]'::jsonb),
    'meeting_links', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', biel.id,
        'event_id', biel.event_id,
        'event_title', e.title,
        'event_date', e.date,
        'link_type', biel.link_type,
        'note', biel.note,
        'author_id', biel.author_id,
        'author_name', am.name,
        'created_at', biel.created_at
      ) ORDER BY biel.created_at DESC)
      FROM public.board_item_event_links biel
      LEFT JOIN public.events e ON e.id = biel.event_id
      LEFT JOIN public.members am ON am.id = biel.author_id
      WHERE biel.board_item_id = p_card_id
    ), '[]'::jsonb),
    'action_items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', mai.id,
        'event_id', mai.event_id,
        'event_title', e.title,
        'event_date', e.date,
        'description', mai.description,
        'kind', mai.kind,
        'status', mai.status,
        'assignee_name', mai.assignee_name,
        'due_date', mai.due_date,
        'resolved_at', mai.resolved_at,
        'resolution_note', mai.resolution_note
      ) ORDER BY mai.created_at DESC)
      FROM public.meeting_action_items mai
      LEFT JOIN public.events e ON e.id = mai.event_id
      WHERE mai.board_item_id = p_card_id
    ), '[]'::jsonb),
    'showcases', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', es.id,
        'event_id', es.event_id,
        'event_title', e.title,
        'event_date', e.date,
        'member_id', es.member_id,
        'member_name', m.name,
        'showcase_type', es.showcase_type,
        'title', es.title,
        'notes', es.notes,
        'duration_min', es.duration_min,
        'xp_awarded', es.xp_awarded
      ) ORDER BY es.created_at DESC)
      FROM public.event_showcases es
      LEFT JOIN public.events e ON e.id = es.event_id
      LEFT JOIN public.members m ON m.id = es.member_id
      WHERE es.board_item_id = p_card_id
    ), '[]'::jsonb),
    'curation_reviews', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', crl.id,
        'curator_id', crl.curator_id,
        'curator_name', cm.name,
        'decision', crl.decision,
        'criteria_scores', crl.criteria_scores,
        'feedback_notes', crl.feedback_notes,
        'completed_at', crl.completed_at,
        'due_date', crl.due_date
      ) ORDER BY crl.completed_at DESC NULLS LAST)
      FROM public.curation_review_log crl
      LEFT JOIN public.members cm ON cm.id = crl.curator_id
      WHERE crl.board_item_id = p_card_id
    ), '[]'::jsonb),
    'generated_at', now()
  );

  RETURN v_result;
END;
$function$;

-- ── 2. convert_action_to_card ──────────────────────────────
CREATE OR REPLACE FUNCTION public.convert_action_to_card(
  p_action_item_id uuid,
  p_board_id uuid,
  p_title text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_status text DEFAULT 'todo',
  p_due_date date DEFAULT NULL
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action record;
  v_board record;
  v_new_card_id uuid;
  v_position int;
  v_final_title text;
  v_final_description text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'write_board') THEN
    RAISE EXCEPTION 'Requires write_board permission';
  END IF;

  SELECT * INTO v_action FROM public.meeting_action_items WHERE id = p_action_item_id;
  IF v_action.id IS NULL THEN
    RETURN jsonb_build_object('error', 'action_item_not_found');
  END IF;

  IF v_action.board_item_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'action_already_linked_to_card',
      'existing_board_item_id', v_action.board_item_id);
  END IF;

  SELECT pb.id, pb.organization_id, pb.is_active INTO v_board
  FROM public.project_boards pb WHERE pb.id = p_board_id;
  IF v_board.id IS NULL THEN
    RETURN jsonb_build_object('error', 'board_not_found');
  END IF;
  IF v_board.is_active = false THEN
    RETURN jsonb_build_object('error', 'board_inactive');
  END IF;

  SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
  FROM public.board_items WHERE board_id = p_board_id;

  v_final_title := COALESCE(NULLIF(trim(p_title), ''), substring(v_action.description from 1 for 80));
  v_final_description := COALESCE(p_description, v_action.description ||
    E'\n\n_Convertido de action item da reunião ' || v_action.event_id::text || '_');

  INSERT INTO public.board_items (
    board_id, title, description, status, assignee_id, due_date, position, created_at, updated_at
  ) VALUES (
    p_board_id, v_final_title, v_final_description, p_status,
    v_action.assignee_id, COALESCE(p_due_date, v_action.due_date), v_position, now(), now()
  )
  RETURNING id INTO v_new_card_id;

  INSERT INTO public.board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (p_board_id, v_new_card_id, 'created',
    'Created from action item ' || p_action_item_id::text, v_caller_id);

  UPDATE public.meeting_action_items
  SET board_item_id = v_new_card_id, updated_at = now()
  WHERE id = p_action_item_id;

  INSERT INTO public.board_item_event_links (
    organization_id, board_item_id, event_id, link_type, author_id, note
  ) VALUES (
    v_board.organization_id, v_new_card_id, v_action.event_id, 'action_emerged',
    v_caller_id, 'Card created from action item: ' || v_action.description
  )
  ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'action_item_id', p_action_item_id,
    'new_board_item_id', v_new_card_id,
    'board_id', p_board_id,
    'position', v_position,
    'created_at', now()
  );
END;
$function$;

-- ── 3. register_decision ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.register_decision(
  p_event_id uuid,
  p_title text,
  p_description text DEFAULT NULL,
  p_related_card_ids uuid[] DEFAULT NULL
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action_id uuid;
  v_event record;
  v_full_text text;
  v_card_id uuid;
  v_links_created int := 0;
  v_card_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  SELECT id INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
    RETURN jsonb_build_object('error', 'title_required');
  END IF;

  v_full_text := trim(p_title) ||
    CASE WHEN p_description IS NOT NULL AND length(trim(p_description)) > 0
      THEN E'\n\n' || trim(p_description)
      ELSE ''
    END;

  INSERT INTO public.meeting_action_items (
    event_id, description, kind, status, created_by
  ) VALUES (
    p_event_id, v_full_text, 'decision', 'completed', v_caller_id
  )
  RETURNING id INTO v_action_id;

  UPDATE public.meeting_action_items
  SET resolved_at = now(),
      resolved_by = v_caller_id,
      resolution_note = 'Decision registered',
      updated_at = now()
  WHERE id = v_action_id;

  IF p_related_card_ids IS NOT NULL AND array_length(p_related_card_ids, 1) > 0 THEN
    FOREACH v_card_id IN ARRAY p_related_card_ids
    LOOP
      SELECT organization_id INTO v_card_org FROM public.board_items WHERE id = v_card_id;
      IF v_card_org IS NOT NULL THEN
        INSERT INTO public.board_item_event_links (
          organization_id, board_item_id, event_id, link_type, author_id, note
        ) VALUES (
          v_card_org, v_card_id, p_event_id, 'decision', v_caller_id,
          'Decision: ' || trim(p_title)
        )
        ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;
        GET DIAGNOSTICS v_links_created = ROW_COUNT;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'decision_id', v_action_id,
    'event_id', p_event_id,
    'title', trim(p_title),
    'related_cards_linked', COALESCE(array_length(p_related_card_ids, 1), 0),
    'created_at', now()
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_card_full_history(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.convert_action_to_card(uuid, uuid, text, text, text, date) FROM anon;
REVOKE EXECUTE ON FUNCTION public.register_decision(uuid, text, text, uuid[]) FROM anon;

NOTIFY pgrst, 'reload schema';
