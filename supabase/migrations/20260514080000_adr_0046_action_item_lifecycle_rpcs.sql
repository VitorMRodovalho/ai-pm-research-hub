-- ============================================================
-- ADR-0046: Action item lifecycle RPCs (#84 Onda 2 partial)
-- Builds on ADR-0045 schema (meeting_action_items new columns).
-- 3 RPCs: create_action_item, resolve_action_item, list_meeting_action_items
-- Cross-references: ADR-0045 (schema), #84 (issue), ADR-0042 (manage_event audience)
-- Rollback: DROP these 3 fns; data in meeting_action_items remains intact.
-- ============================================================

-- ── 1. create_action_item ──────────────────────────────────
-- Structured INSERT replacing markdown-string action items.
-- V4 gate: manage_event (event organizers; matches Onda 1 RLS pattern)
CREATE OR REPLACE FUNCTION public.create_action_item(
  p_event_id uuid,
  p_description text,
  p_assignee_id uuid DEFAULT NULL,
  p_due_date date DEFAULT NULL,
  p_board_item_id uuid DEFAULT NULL,
  p_checklist_item_id uuid DEFAULT NULL,
  p_kind text DEFAULT 'action'
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action_id uuid;
  v_assignee_name text;
  v_event record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  SELECT id, title INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN RETURN jsonb_build_object('error', 'event_not_found'); END IF;

  IF p_kind NOT IN ('action','decision','followup','general') THEN
    RETURN jsonb_build_object('error', 'invalid_kind',
      'valid_kinds', jsonb_build_array('action','decision','followup','general'));
  END IF;

  IF p_description IS NULL OR length(trim(p_description)) = 0 THEN
    RETURN jsonb_build_object('error', 'description_required');
  END IF;

  IF p_assignee_id IS NOT NULL THEN
    SELECT name INTO v_assignee_name FROM public.members WHERE id = p_assignee_id;
    IF v_assignee_name IS NULL THEN
      RETURN jsonb_build_object('error', 'assignee_not_found', 'assignee_id', p_assignee_id);
    END IF;
  END IF;

  INSERT INTO public.meeting_action_items (
    event_id, description, assignee_id, assignee_name, due_date,
    board_item_id, checklist_item_id, kind, status, created_by
  ) VALUES (
    p_event_id, trim(p_description), p_assignee_id, v_assignee_name, p_due_date,
    p_board_item_id, p_checklist_item_id, p_kind,
    CASE WHEN p_kind = 'decision' THEN 'completed' ELSE 'open' END,
    v_caller_id
  )
  RETURNING id INTO v_action_id;

  IF p_board_item_id IS NOT NULL THEN
    INSERT INTO public.board_item_event_links (
      organization_id, board_item_id, event_id, link_type, author_id, note
    )
    SELECT bi.organization_id, p_board_item_id, p_event_id,
      CASE p_kind
        WHEN 'decision' THEN 'decision'
        WHEN 'action' THEN 'action_emerged'
        ELSE 'discussed'
      END,
      v_caller_id, trim(p_description)
    FROM public.board_items bi
    WHERE bi.id = p_board_item_id
    ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'action_item_id', v_action_id,
    'event_id', p_event_id,
    'kind', p_kind,
    'created_at', now()
  );
END;
$function$;

-- ── 2. resolve_action_item ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.resolve_action_item(
  p_action_item_id uuid,
  p_resolution_note text DEFAULT NULL,
  p_carry_to_event_id uuid DEFAULT NULL
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action record;
  v_carried_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  SELECT * INTO v_action FROM public.meeting_action_items WHERE id = p_action_item_id;
  IF v_action.id IS NULL THEN
    RETURN jsonb_build_object('error', 'action_item_not_found');
  END IF;

  IF v_action.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_resolved',
      'resolved_at', v_action.resolved_at, 'resolved_by', v_action.resolved_by);
  END IF;

  IF p_carry_to_event_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.events WHERE id = p_carry_to_event_id) THEN
      RETURN jsonb_build_object('error', 'carry_to_event_not_found');
    END IF;

    INSERT INTO public.meeting_action_items (
      event_id, description, assignee_id, assignee_name, due_date,
      board_item_id, checklist_item_id, kind, status, created_by
    ) VALUES (
      p_carry_to_event_id,
      v_action.description || ' (carried from prior meeting)',
      v_action.assignee_id, v_action.assignee_name, v_action.due_date,
      v_action.board_item_id, v_action.checklist_item_id, v_action.kind,
      'open', v_caller_id
    )
    RETURNING id INTO v_carried_id;

    UPDATE public.meeting_action_items
    SET carried_to_event_id = p_carry_to_event_id, updated_at = now()
    WHERE id = p_action_item_id;
  END IF;

  UPDATE public.meeting_action_items
  SET resolved_at = now(),
      resolved_by = v_caller_id,
      resolution_note = COALESCE(p_resolution_note,
        CASE WHEN p_carry_to_event_id IS NOT NULL THEN 'Carried forward to event ' || p_carry_to_event_id::text ELSE NULL END),
      status = CASE WHEN p_carry_to_event_id IS NOT NULL THEN 'carried_forward' ELSE 'completed' END,
      updated_at = now()
  WHERE id = p_action_item_id;

  RETURN jsonb_build_object(
    'success', true,
    'action_item_id', p_action_item_id,
    'resolved_at', now(),
    'carried_to_action_item_id', v_carried_id
  );
END;
$function$;

-- ── 3. list_meeting_action_items ───────────────────────────
CREATE OR REPLACE FUNCTION public.list_meeting_action_items(
  p_event_id uuid DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_assignee_id uuid DEFAULT NULL,
  p_kind text DEFAULT NULL,
  p_unresolved_only boolean DEFAULT false
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', mai.id,
    'event_id', mai.event_id,
    'event_title', e.title,
    'event_date', e.date,
    'description', mai.description,
    'assignee_id', mai.assignee_id,
    'assignee_name', mai.assignee_name,
    'due_date', mai.due_date,
    'kind', mai.kind,
    'status', mai.status,
    'board_item_id', mai.board_item_id,
    'board_item_title', bi.title,
    'checklist_item_id', mai.checklist_item_id,
    'carried_to_event_id', mai.carried_to_event_id,
    'resolved_at', mai.resolved_at,
    'resolved_by', mai.resolved_by,
    'resolved_by_name', rm.name,
    'resolution_note', mai.resolution_note,
    'created_by', mai.created_by,
    'created_at', mai.created_at
  ) ORDER BY
    CASE WHEN mai.resolved_at IS NULL THEN 0 ELSE 1 END,
    mai.due_date NULLS LAST, mai.created_at DESC), '[]'::jsonb) INTO v_result
  FROM public.meeting_action_items mai
  LEFT JOIN public.events e ON e.id = mai.event_id
  LEFT JOIN public.board_items bi ON bi.id = mai.board_item_id
  LEFT JOIN public.members rm ON rm.id = mai.resolved_by
  WHERE (p_event_id IS NULL OR mai.event_id = p_event_id)
    AND (p_status IS NULL OR mai.status = p_status)
    AND (p_assignee_id IS NULL OR mai.assignee_id = p_assignee_id)
    AND (p_kind IS NULL OR mai.kind = p_kind)
    AND (NOT p_unresolved_only OR mai.resolved_at IS NULL)
  LIMIT 200;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_action_item(uuid, text, uuid, date, uuid, uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.resolve_action_item(uuid, text, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_meeting_action_items(uuid, text, uuid, text, boolean) FROM anon;

NOTIFY pgrst, 'reload schema';
