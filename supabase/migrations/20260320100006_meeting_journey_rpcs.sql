-- ============================================================
-- Phase 2: Meeting RPCs — agenda, minutes, actions, detail, template
-- ============================================================

-- Helper: check if caller can manage event content
CREATE OR REPLACE FUNCTION public._can_manage_event(p_event_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_caller record; v_event record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_caller.is_superadmin THEN RETURN true; END IF;
  IF v_caller.operational_role IN ('manager', 'deputy_manager') THEN RETURN true; END IF;
  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_caller.operational_role = 'tribe_leader' AND v_event.tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_event.created_by = v_caller.id THEN RETURN true; END IF;
  RETURN false;
END; $$;

-- 1. upsert_event_agenda
CREATE OR REPLACE FUNCTION public.upsert_event_agenda(p_event_id uuid, p_text text DEFAULT NULL, p_url text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT _can_manage_event(p_event_id) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  UPDATE events SET
    agenda_text = COALESCE(p_text, agenda_text),
    agenda_url = COALESCE(p_url, agenda_url),
    agenda_posted_at = now(),
    agenda_posted_by = (SELECT id FROM members WHERE auth_id = auth.uid()),
    updated_at = now()
  WHERE id = p_event_id;
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES ((SELECT id FROM members WHERE auth_id = auth.uid()), 'event.agenda_updated', 'event', p_event_id,
    jsonb_build_object('has_text', p_text IS NOT NULL, 'has_url', p_url IS NOT NULL));
  RETURN jsonb_build_object('success', true);
END; $$;

-- 2. upsert_event_minutes
CREATE OR REPLACE FUNCTION public.upsert_event_minutes(p_event_id uuid, p_text text DEFAULT NULL, p_url text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT _can_manage_event(p_event_id) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  UPDATE events SET
    minutes_text = COALESCE(p_text, minutes_text),
    minutes_url = COALESCE(p_url, minutes_url),
    minutes_posted_at = now(),
    minutes_posted_by = (SELECT id FROM members WHERE auth_id = auth.uid()),
    updated_at = now()
  WHERE id = p_event_id;
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES ((SELECT id FROM members WHERE auth_id = auth.uid()), 'event.minutes_updated', 'event', p_event_id,
    jsonb_build_object('has_text', p_text IS NOT NULL, 'has_url', p_url IS NOT NULL));
  RETURN jsonb_build_object('success', true);
END; $$;

-- 3. manage_action_items
CREATE OR REPLACE FUNCTION public.manage_action_items(p_event_id uuid, p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_caller_id uuid;
  v_item jsonb;
  v_item_id uuid;
BEGIN
  IF NOT _can_manage_event(p_event_id) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_item_id := (v_item->>'id')::uuid;
    IF v_item_id IS NOT NULL THEN
      UPDATE meeting_action_items SET
        description = COALESCE(v_item->>'description', description),
        assignee_id = CASE WHEN v_item ? 'assignee_id' THEN (v_item->>'assignee_id')::uuid ELSE assignee_id END,
        assignee_name = COALESCE(v_item->>'assignee_name', assignee_name),
        due_date = CASE WHEN v_item ? 'due_date' THEN (v_item->>'due_date')::date ELSE due_date END,
        status = COALESCE(v_item->>'status', status),
        updated_at = now()
      WHERE id = v_item_id AND event_id = p_event_id;
    ELSE
      INSERT INTO meeting_action_items (event_id, description, assignee_id, assignee_name, due_date, status, created_by)
      VALUES (p_event_id, v_item->>'description', (v_item->>'assignee_id')::uuid, v_item->>'assignee_name',
        (v_item->>'due_date')::date, COALESCE(v_item->>'status', 'open'), v_caller_id);
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', jsonb_array_length(p_items));
END; $$;

-- 4. get_event_detail
CREATE OR REPLACE FUNCTION public.get_event_detail(p_event_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_caller record;
  v_event record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Event not found'); END IF;

  -- Visibility enforcement
  IF v_event.visibility = 'gp_only' AND v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager') THEN
    RETURN jsonb_build_object('error', 'Restricted content');
  END IF;
  IF v_event.visibility = 'leadership' AND v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager', 'tribe_leader') THEN
    RETURN jsonb_build_object('error', 'Restricted content');
  END IF;

  SELECT jsonb_build_object(
    'event', jsonb_build_object(
      'id', v_event.id, 'title', v_event.title, 'date', v_event.date, 'type', v_event.type,
      'tribe_id', v_event.tribe_id, 'duration_minutes', v_event.duration_minutes,
      'duration_actual', v_event.duration_actual, 'meeting_link', v_event.meeting_link,
      'is_recorded', v_event.is_recorded, 'youtube_url', v_event.youtube_url,
      'recording_url', v_event.recording_url, 'recording_type', v_event.recording_type,
      'visibility', v_event.visibility
    ),
    'agenda', jsonb_build_object(
      'text', v_event.agenda_text, 'url', v_event.agenda_url,
      'posted_at', v_event.agenda_posted_at,
      'posted_by', (SELECT m.name FROM members m WHERE m.id = v_event.agenda_posted_by)
    ),
    'minutes', jsonb_build_object(
      'text', v_event.minutes_text, 'url', v_event.minutes_url,
      'posted_at', v_event.minutes_posted_at,
      'posted_by', (SELECT m.name FROM members m WHERE m.id = v_event.minutes_posted_by)
    ),
    'action_items', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', ai.id, 'description', ai.description,
        'assignee_id', ai.assignee_id, 'assignee_name', COALESCE(ai.assignee_name, am.name),
        'due_date', ai.due_date, 'status', ai.status,
        'carried_to_event_id', ai.carried_to_event_id
      ) ORDER BY ai.created_at), '[]'::jsonb)
      FROM meeting_action_items ai
      LEFT JOIN members am ON am.id = ai.assignee_id
      WHERE ai.event_id = p_event_id AND ai.status != 'cancelled'
    ),
    'attendance', jsonb_build_object(
      'total_eligible', (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id),
      'present_count', (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id),
      'members', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', a.member_id, 'name', m.name,
          'present', true, 'excused', COALESCE(a.excused, false)
        )), '[]'::jsonb)
        FROM attendance a JOIN members m ON m.id = a.member_id
        WHERE a.event_id = p_event_id
      )
    )
  ) INTO v_result;

  RETURN v_result;
END; $$;

-- 5. generate_agenda_template
CREATE OR REPLACE FUNCTION public.generate_agenda_template(p_tribe_id integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_caller record;
  v_last_event record;
  v_template text;
  v_actions text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
     AND NOT (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = p_tribe_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Find most recent past event for this tribe
  SELECT * INTO v_last_event FROM events
  WHERE tribe_id = p_tribe_id AND date < CURRENT_DATE AND type IN ('tribo', 'kickoff')
  ORDER BY date DESC LIMIT 1;

  -- Get open action items from last event
  SELECT string_agg('- [ ] ' || ai.description || COALESCE(' (@' || ai.assignee_name || ')', '') || COALESCE(' — prazo: ' || ai.due_date::text, ''), E'\n')
  INTO v_actions
  FROM meeting_action_items ai
  WHERE ai.event_id = v_last_event.id AND ai.status = 'open';

  v_template := '## Pauta da Reunião' || E'\n\n';
  v_template := v_template || '### 1. Abertura e check-in' || E'\n\n';

  IF v_actions IS NOT NULL THEN
    v_template := v_template || '### 2. Revisão de ações pendentes' || E'\n' || v_actions || E'\n\n';
  ELSE
    v_template := v_template || '### 2. Revisão da reunião anterior' || E'\n\n';
  END IF;

  v_template := v_template || '### 3. Tópicos da semana' || E'\n- ' || E'\n\n';
  v_template := v_template || '### 4. Próximos passos e ações' || E'\n- [ ] ' || E'\n\n';
  v_template := v_template || '### 5. Encerramento' || E'\n';

  RETURN jsonb_build_object('success', true, 'template', v_template,
    'last_event_title', v_last_event.title, 'last_event_date', v_last_event.date,
    'open_actions_count', COALESCE(array_length(string_to_array(v_actions, E'\n'), 1), 0));
END; $$;
