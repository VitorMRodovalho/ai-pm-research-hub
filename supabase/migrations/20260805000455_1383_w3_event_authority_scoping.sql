-- #1383 Wave 3 — scope event-domain write authority to the event's initiative.
--
-- Extends the fix shipped in migration 444 (`_manage_event_scope_ok`) to five
-- event-domain RPCs the earlier pass did not cover. Each one gated on a
-- RESOURCELESS `can_by_member(caller, 'manage_event')`, so any holder of
-- manage_event on ANY initiative could write to EVERY initiative's meetings:
-- create/resolve action items, register decisions, reschedule and delete events.
--
-- Shape of the fix (identical in all five): the existing resourceless check stays
-- as the cheap pre-gate, preserving current error ordering and the
-- event-not-found semantics; the scope check is ADDED after the event is known.
-- `_manage_event_scope_ok` passes org/global-scope holders unconditionally and
-- restricts initiative-scoped holders to their own initiative, so this only ever
-- narrows authority — no legitimate caller loses access.
--
-- Also fixes `resolve_action_item`, which wrote status values ('carried_forward',
-- 'completed') that are not in the live CHECK constraint
-- (`meeting_action_items_status_check` = open|done|cancelled|carried_over), so
-- every carry-forward and every plain resolve raised a constraint violation.
--
-- Bodies below are the LIVE bodies (pg_get_functiondef) plus the gate/status
-- edits — not reconstructions from earlier migrations.

-- 1) create_action_item — scope after event existence check.
CREATE OR REPLACE FUNCTION public.create_action_item(p_event_id uuid, p_description text, p_assignee_id uuid DEFAULT NULL::uuid, p_due_date date DEFAULT NULL::date, p_board_item_id uuid DEFAULT NULL::uuid, p_checklist_item_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT 'action'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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

  -- V4 gate: manage_event (mirrors ADR-0045 RLS on board_item_event_links)
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  -- Validate event exists
  SELECT id, title INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN RETURN jsonb_build_object('error', 'event_not_found'); END IF;

  -- #1383 W3: scope manage_event to this event's initiative (was resourceless).
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Requires manage_event permission for this event';
  END IF;

  -- Validate kind
  IF p_kind NOT IN ('action','decision','followup','general') THEN
    RETURN jsonb_build_object('error', 'invalid_kind',
      'valid_kinds', jsonb_build_array('action','decision','followup','general'));
  END IF;

  -- Validate description
  IF p_description IS NULL OR length(trim(p_description)) = 0 THEN
    RETURN jsonb_build_object('error', 'description_required');
  END IF;

  -- Lookup assignee name (snapshot, even if assignee gets renamed later)
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
    CASE WHEN p_kind = 'decision' THEN 'done' ELSE 'open' END,
    v_caller_id
  )
  RETURNING id INTO v_action_id;

  -- If linked to a board_item, also create board_item_event_links entry
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

-- 2) register_decision — scope after event existence check.
CREATE OR REPLACE FUNCTION public.register_decision(p_event_id uuid, p_title text, p_description text DEFAULT NULL::text, p_related_card_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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

  -- #1383 W3: scope manage_event to this event's initiative (was resourceless).
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Requires manage_event permission for this event';
  END IF;

  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
    RETURN jsonb_build_object('error', 'title_required');
  END IF;

  v_full_text := trim(p_title) ||
    CASE WHEN p_description IS NOT NULL AND length(trim(p_description)) > 0
      THEN E'\n\n' || trim(p_description)
      ELSE ''
    END;

  -- Decision is an action item with kind='decision' (terminal status 'done')
  INSERT INTO public.meeting_action_items (
    event_id, description, kind, status, created_by
  ) VALUES (
    p_event_id, v_full_text, 'decision', 'done', v_caller_id
  )
  RETURNING id INTO v_action_id;

  -- Mark resolved with timestamp
  UPDATE public.meeting_action_items
  SET resolved_at = now(),
      resolved_by = v_caller_id,
      resolution_note = 'Decision registered',
      updated_at = now()
  WHERE id = v_action_id;

  -- Fanout: link decision to each related card via board_item_event_links
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

-- 3) resolve_action_item — scope on the action's own event AND on the
--    carry-forward target (carrying into another initiative's event is the same
--    cross-initiative write). Plus: status values now satisfy the live CHECK.
CREATE OR REPLACE FUNCTION public.resolve_action_item(p_action_item_id uuid, p_resolution_note text DEFAULT NULL::text, p_carry_to_event_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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

  -- #1383 W3: scope manage_event to the initiative owning this action's event.
  IF NOT public._manage_event_scope_ok(v_caller_id, v_action.event_id) THEN
    RAISE EXCEPTION 'Requires manage_event permission for this event';
  END IF;

  IF v_action.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_resolved',
      'resolved_at', v_action.resolved_at, 'resolved_by', v_action.resolved_by);
  END IF;

  -- Carry-forward: create new action_item in target event linked back to original
  IF p_carry_to_event_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.events WHERE id = p_carry_to_event_id) THEN
      RETURN jsonb_build_object('error', 'carry_to_event_not_found');
    END IF;

    -- #1383 W3: the carry target is a write too — scope it independently.
    IF NOT public._manage_event_scope_ok(v_caller_id, p_carry_to_event_id) THEN
      RAISE EXCEPTION 'Requires manage_event permission for the carry-forward target event';
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

  -- Mark resolved. Status must be one of meeting_action_items_status_check
  -- (open|done|cancelled|carried_over); the previous body wrote 'carried_forward'
  -- and 'completed', which the constraint rejected on every call.
  UPDATE public.meeting_action_items
  SET resolved_at = now(),
      resolved_by = v_caller_id,
      resolution_note = COALESCE(p_resolution_note,
        CASE WHEN p_carry_to_event_id IS NOT NULL THEN 'Carried forward to event ' || p_carry_to_event_id::text ELSE NULL END),
      status = CASE WHEN p_carry_to_event_id IS NOT NULL THEN 'carried_over' ELSE 'done' END,
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

-- 4) update_event_instance — scope after the existing role check. The
--    operational_role = 'tribe_leader' branch stays: it is a lazily-maintained
--    cache and covers a different population than the V4 catalog.
CREATE OR REPLACE FUNCTION public.update_event_instance(p_event_id uuid, p_new_date date DEFAULT NULL::date, p_new_time_start time without time zone DEFAULT NULL::time without time zone, p_new_duration_minutes integer DEFAULT NULL::integer, p_meeting_link text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_agenda_text text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_exists boolean;
  v_updated text[] := '{}';
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT true, i.legacy_tribe_id
    INTO v_event_exists, v_event_tribe
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_exists IS NOT TRUE THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  -- #1383 W3: scope manage_event to this event's initiative (was resourceless —
  -- the role check above only constrains callers whose cached operational_role is
  -- literally 'tribe_leader').
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission for this event';
  END IF;

  IF p_new_date IS NOT NULL THEN
    IF v_event_tribe IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.events e2
      JOIN public.initiatives i2 ON i2.id = e2.initiative_id
      WHERE i2.legacy_tribe_id = v_event_tribe
        AND e2.date = p_new_date
        AND e2.id <> p_event_id
    ) THEN
      RAISE EXCEPTION 'Ja existe um evento desta tribo na data %', p_new_date;
    END IF;
    UPDATE public.events SET date = p_new_date, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'date');
  END IF;
  IF p_new_time_start IS NOT NULL THEN
    UPDATE public.events SET time_start = p_new_time_start, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'time_start');
  END IF;
  IF p_new_duration_minutes IS NOT NULL THEN
    UPDATE public.events SET duration_minutes = p_new_duration_minutes, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'duration_minutes');
  END IF;
  IF p_meeting_link IS NOT NULL THEN
    UPDATE public.events SET meeting_link = p_meeting_link, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'meeting_link');
  END IF;
  IF p_notes IS NOT NULL THEN
    UPDATE public.events SET notes = p_notes, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'notes');
  END IF;
  IF p_agenda_text IS NOT NULL THEN
    UPDATE public.events SET agenda_text = p_agenda_text, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'agenda_text');
  END IF;

  RETURN json_build_object('success', true, 'event_id', p_event_id, 'updated_fields', to_json(v_updated));
END;
$function$;

-- 5) drop_event_instance — same shape. This one DELETEs, so the unscoped gate
--    let an initiative-scoped leader delete another initiative's event (and,
--    with p_force_delete_attendance, its attendance records).
CREATE OR REPLACE FUNCTION public.drop_event_instance(p_event_id uuid, p_force_delete_attendance boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_date date;
  v_event_title text;
  v_att_count int;
  v_blocker text;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT i.legacy_tribe_id, e.date, e.title
    INTO v_event_tribe, v_event_date, v_event_title
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  -- #1383 W3: scope manage_event to this event's initiative (was resourceless).
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission for this event';
  END IF;

  SELECT count(*) INTO v_att_count FROM public.attendance WHERE event_id = p_event_id;
  IF v_att_count > 0 AND NOT p_force_delete_attendance THEN
    RAISE EXCEPTION 'attendance_exists:%', v_att_count USING HINT = 'Evento possui ' || v_att_count || ' presença(s) registrada(s). Re-chame com p_force_delete_attendance=true para remover.';
  END IF;

  v_blocker := '';
  IF EXISTS (SELECT 1 FROM public.meeting_artifacts WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'meeting_artifacts, '; END IF;
  IF EXISTS (SELECT 1 FROM public.cost_entries WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'cost_entries, '; END IF;
  -- REMOVED: cpmai_sessions check (table never existed — Item 2 fix)
  IF EXISTS (SELECT 1 FROM public.webinars WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'webinars, '; END IF;
  IF EXISTS (SELECT 1 FROM public.event_showcases WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'event_showcases, '; END IF;
  IF EXISTS (SELECT 1 FROM public.meeting_action_items WHERE carried_to_event_id = p_event_id) THEN v_blocker := v_blocker || 'meeting_action_items (carried_to), '; END IF;
  IF v_blocker <> '' THEN
    v_blocker := rtrim(v_blocker, ', ');
    RAISE EXCEPTION 'Evento possui dependencias que impedem a exclusao: %', v_blocker;
  END IF;

  IF v_att_count > 0 AND p_force_delete_attendance THEN
    DELETE FROM public.attendance WHERE event_id = p_event_id;
  END IF;
  DELETE FROM public.events WHERE id = p_event_id;

  RETURN json_build_object('success', true, 'deleted_event_id', p_event_id, 'deleted_date', v_event_date, 'deleted_title', v_event_title, 'deleted_attendance_count', COALESCE(v_att_count, 0), 'force_used', p_force_delete_attendance);
END;
$function$;
