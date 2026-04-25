-- ADR-0011 V3→V4 writers batch 2 — replace hardcoded operational_role / is_superadmin
-- gates with `public.can_by_member()` actions, preserving residual tribe-scope and
-- self-access carve-outs.
--
-- Context: follow-up to 20260513010000 (admin readers batch 1, gated to manage_platform).
-- This batch is more complex because each RPC has a tribe-scoping or self-access
-- carve-out that must be preserved alongside the V4 baseline gate. The
-- `tests/contracts/rpc-v4-auth.test.mjs` parser explicitly allows the pattern
-- `can_by_member` + V3-style residual scope check.
--
-- Sub-groups (12 RPCs total):
--
--   Sub-group 2a — `manage_event` (5 RPCs):
--     1. bulk_mark_excused          (file: 20260428050000) — V3 admin/leader → V4 + tribe scope
--     2. update_event               (file: 20260428180000) — V3 admin/leader → V4 + tribe scope
--     3. generate_agenda_template   (file: 20260505030000) — V3 admin/leader → V4 + tribe scope
--     4. get_event_detail           (file: 20260428180000) — V3 visibility-based → V4 (`gp_only` → manage_platform; `leadership` → manage_event)
--     5. get_tribe_event_roster     (file: 20260428180000) — V3 admin/leader/co_gp → V4 + tribe scope
--
--   Sub-group 2b — `write_board` (5 RPCs):
--     6. assign_checklist_item      (file: 20260505010000) — V3 GP/leader/owner/board-admin → V4
--     7. complete_checklist_item    (file: 20260505010000) — same pattern
--     8. create_board_item          (file: 20260505010000) — same pattern
--     9. move_board_item            (file: 20260505010000) — same pattern (preserves done-status leader-only sub-check)
--    10. update_board_item          (file: 20260505010000) — same pattern (preserves baseline/forecast/assignee/portfolio sub-checks)
--
--   Sub-group 2c — special cases (2 RPCs):
--    11. exec_tribe_dashboard       (file: 20260428130000) — adds explicit cross-tribe = manage_platform; same-tribe = any member
--    12. get_member_attendance_hours (file: 20260428050000) — self-access carve-out + V4 view_pii
--
-- Behavior change docs:
--   * Sub-group 2a (manage_event): V3 accepted superadmin OR (manager|deputy_manager) OR
--     (tribe_leader same-tribe). Under V4 manage_event, the engagement_kind_permissions
--     table dictates who passes. The residual same-tribe check on tribe_leader is
--     PRESERVED (so a tribe_leader of tribe A still cannot manage events of tribe B).
--   * Sub-group 2b (write_board): V3 had a 4-way OR gate (GP, leader, card_owner, board_admin).
--     Under V4 write_board, the FINAL gate becomes `can_by_member('write_board')`. The
--     local var assignments (v_is_gp, v_is_leader, v_is_card_owner, v_is_board_admin) are
--     PRESERVED — they're still referenced in downstream sub-checks (e.g. `done` status
--     guard on move_board_item, baseline/forecast/assignee/portfolio guards on
--     update_board_item) which retain V3 shape because the parser only flags the
--     primary auth gate.
--   * Sub-group 2c special cases:
--     - exec_tribe_dashboard: V3 was complex (admin OR leader OR same-tribe member OR
--       sponsor/chapter_liaison-with-matching-chapter). V4 simplifies: any caller may
--       view their OWN tribe; cross-tribe view requires `manage_platform`. The
--       sponsor/chapter_liaison fast-path is dropped (those users must now have
--       manage_platform via engagement_kind_permissions to view cross-tribe).
--     - get_member_attendance_hours: V3 was self OR superadmin OR (manager|deputy_manager|
--       tribe_leader). V4 = self-access OR view_pii. tribe_leader cross-tribe view is
--       dropped (they can still view their own data; for cross-tribe attendance they
--       must have view_pii).
--
-- Pattern applied (canonical):
--   IF NOT public.can_by_member(v_caller_id, '<action>') THEN
--     RAISE EXCEPTION 'Unauthorized: requires <action> permission';
--   END IF;
--   IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
--     RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
--   END IF;
--
-- Body below the gate is preserved byte-for-byte from the latest definition of each
-- RPC across post-cutover migrations (latest CREATE OR REPLACE wins).

-- ============================================================================
-- Sub-group 2a — manage_event (5 RPCs)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. bulk_mark_excused  (latest: 20260428050000)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bulk_mark_excused(p_member_id uuid, p_date_from date, p_date_to date, p_reason text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid; v_caller_role text; v_is_admin boolean; v_caller_tribe int;
  v_member_tribe int;
  v_count int := 0;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT tribe_id INTO v_member_tribe FROM public.members WHERE id = p_member_id;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_member_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage members of own tribe';
  END IF;

  INSERT INTO public.attendance (event_id, member_id, excused, excuse_reason)
  SELECT e.id, p_member_id, true, p_reason
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.date >= p_date_from AND e.date <= p_date_to
    AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms')
    AND (
      e.type IN ('geral', 'kickoff')
      OR (e.type = 'tribo' AND i.legacy_tribe_id = v_member_tribe)
      OR (e.type = 'lideranca' AND EXISTS (SELECT 1 FROM members m WHERE m.id = p_member_id AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')))
    )
    AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.excused = false)
  ON CONFLICT (event_id, member_id) DO UPDATE SET excused = true, excuse_reason = p_reason, updated_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN json_build_object('success', true, 'events_marked', v_count, 'date_from', p_date_from, 'date_to', p_date_to);
END;
$function$;

-- ----------------------------------------------------------------------------
-- 2. update_event  (latest: 20260428180000)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_event(
  p_event_id uuid,
  p_title text DEFAULT NULL,
  p_date date DEFAULT NULL,
  p_time_start time without time zone DEFAULT NULL,
  p_duration_minutes integer DEFAULT NULL,
  p_meeting_link text DEFAULT NULL,
  p_youtube_url text DEFAULT NULL,
  p_is_recorded boolean DEFAULT NULL,
  p_recording_url text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_type text DEFAULT NULL,
  p_nature text DEFAULT NULL,
  p_audience_level text DEFAULT NULL,
  p_external_attendees text[] DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_event_tribe_id int;
  v_safe_type text;
  v_safe_nature text;
  v_safe_audience text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Event not found');
  END IF;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  -- Permission check (V4 baseline + residual tribe scope; preserves event-author
  -- carve-out so card creators can edit their own events).
  IF NOT public.can_by_member(v_caller.id, 'manage_event')
     AND v_event.created_by IS DISTINCT FROM auth.uid() THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;
  IF v_caller.operational_role = 'tribe_leader'
     AND v_event_tribe_id IS NOT NULL
     AND v_event_tribe_id IS DISTINCT FROM v_caller.tribe_id
     AND v_event.created_by IS DISTINCT FROM auth.uid() THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;

  v_safe_type := CASE
    WHEN p_type IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN p_type
    ELSE NULL END;
  v_safe_nature := CASE
    WHEN p_nature IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN p_nature
    ELSE NULL END;
  v_safe_audience := CASE
    WHEN p_audience_level IN ('all','leadership','tribe','curators') THEN p_audience_level
    ELSE NULL END;

  UPDATE public.events SET
    title              = COALESCE(p_title, title),
    date               = COALESCE(p_date, date),
    time_start         = COALESCE(p_time_start, time_start),
    duration_minutes   = COALESCE(p_duration_minutes, duration_minutes),
    meeting_link       = COALESCE(p_meeting_link, meeting_link),
    youtube_url        = COALESCE(p_youtube_url, youtube_url),
    is_recorded        = COALESCE(p_is_recorded, is_recorded),
    recording_url      = COALESCE(p_recording_url, recording_url),
    notes              = COALESCE(p_notes, notes),
    type               = COALESCE(v_safe_type, type),
    nature             = COALESCE(v_safe_nature, nature),
    audience_level     = COALESCE(v_safe_audience, audience_level),
    external_attendees = COALESCE(p_external_attendees, external_attendees),
    updated_at         = now()
  WHERE id = p_event_id;

  RETURN json_build_object('success', true);
END;
$function$;

-- ----------------------------------------------------------------------------
-- 3. generate_agenda_template  (latest: 20260505030000)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_agenda_template(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_last_event record;
  v_template text;
  v_actions text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF v_caller.operational_role = 'tribe_leader'
     AND v_caller.tribe_id IS DISTINCT FROM p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT e.* INTO v_last_event
  FROM public.events e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id
    AND e.date < CURRENT_DATE
    AND e.type IN ('tribo', 'kickoff')
  ORDER BY e.date DESC
  LIMIT 1;

  SELECT string_agg(
    '- [ ] ' || ai.description
      || COALESCE(' (@' || ai.assignee_name || ')', '')
      || COALESCE(' — prazo: ' || ai.due_date::text, ''),
    E'\n'
  ) INTO v_actions
  FROM public.meeting_action_items ai
  WHERE ai.event_id = v_last_event.id AND ai.status = 'open';

  v_template := '## Pauta da Reunião' || E'\n\n' || '### 1. Abertura e check-in' || E'\n\n';
  IF v_actions IS NOT NULL THEN
    v_template := v_template || '### 2. Revisão de ações pendentes' || E'\n' || v_actions || E'\n\n';
  ELSE
    v_template := v_template || '### 2. Revisão da reunião anterior' || E'\n\n';
  END IF;
  v_template := v_template
    || '### 3. Tópicos da semana' || E'\n- ' || E'\n\n'
    || '### 4. Próximos passos e ações' || E'\n- [ ] ' || E'\n\n'
    || '### 5. Encerramento' || E'\n';

  RETURN jsonb_build_object(
    'success', true,
    'template', v_template,
    'last_event_title', v_last_event.title,
    'last_event_date', v_last_event.date,
    'open_actions_count', COALESCE(array_length(string_to_array(v_actions, E'\n'), 1), 0)
  );
END;
$function$;

-- ----------------------------------------------------------------------------
-- 4. get_event_detail  (latest: 20260428180000)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_event_detail(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_event_tribe_id int;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Event not found'); END IF;

  IF v_event.visibility = 'gp_only'
     AND NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Restricted content');
  END IF;
  IF v_event.visibility = 'leadership'
     AND NOT public.can_by_member(v_caller.id, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'Restricted content');
  END IF;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  SELECT jsonb_build_object(
    'event', jsonb_build_object(
      'id', v_event.id, 'title', v_event.title, 'date', v_event.date,
      'type', v_event.type, 'tribe_id', v_event_tribe_id,
      'duration_minutes', v_event.duration_minutes, 'duration_actual', v_event.duration_actual,
      'meeting_link', v_event.meeting_link, 'is_recorded', v_event.is_recorded,
      'youtube_url', v_event.youtube_url, 'recording_url', v_event.recording_url,
      'recording_type', v_event.recording_type, 'visibility', v_event.visibility
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
        'id', ai.id, 'description', ai.description, 'assignee_id', ai.assignee_id,
        'assignee_name', COALESCE(ai.assignee_name, am.name),
        'due_date', ai.due_date, 'status', ai.status,
        'carried_to_event_id', ai.carried_to_event_id
      ) ORDER BY ai.created_at), '[]'::jsonb)
      FROM meeting_action_items ai
      LEFT JOIN members am ON am.id = ai.assignee_id
      WHERE ai.event_id = p_event_id AND ai.status != 'cancelled'
    ),
    'attendance', jsonb_build_object(
      'present_count', (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id),
      'members', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', a.member_id, 'name', m.name, 'present', true,
          'excused', COALESCE(a.excused, false)
        )), '[]'::jsonb)
        FROM attendance a JOIN members m ON m.id = a.member_id
        WHERE a.event_id = p_event_id
      )
    ),
    'showcases', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', es.id, 'member_id', es.member_id, 'member_name', m.name,
        'showcase_type', es.showcase_type, 'title', es.title, 'duration_min', es.duration_min
      ) ORDER BY es.created_at), '[]'::jsonb)
      FROM event_showcases es JOIN members m ON m.id = es.member_id
      WHERE es.event_id = p_event_id
    )
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 5. get_tribe_event_roster  (latest: 20260428180000)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_tribe_event_roster(p_event_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller RECORD;
  v_event  RECORD;
  v_event_tribe_id int;
  v_result JSON;
  v_has_attendance boolean;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  -- Access control: V4 baseline manage_event + residual tribe scope for tribe_leader
  IF NOT public.can_by_member(v_caller.id, 'manage_event') THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;
  IF v_caller.operational_role = 'tribe_leader'
     AND v_event_tribe_id IS NOT NULL
     AND v_event_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;

  SELECT EXISTS(SELECT 1 FROM attendance WHERE event_id = p_event_id) INTO v_has_attendance;

  SELECT json_agg(row_to_json(q) ORDER BY q.name) INTO v_result
  FROM (
    SELECT
      m.id, m.name, m.photo_url, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations) AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter,
      COALESCE(a.present, false) AS present,
      a.corrected_by IS NOT NULL AS was_corrected
    FROM public.members m
    LEFT JOIN public.attendance a
      ON a.event_id = p_event_id AND a.member_id = m.id
    WHERE
      m.operational_role != 'guest'
      AND (
        -- 1) Initiative events: scope to initiative members
        CASE WHEN v_event.initiative_id IS NOT NULL AND v_event_tribe_id IS NULL THEN
          m.id IN (
            SELECT mm.id FROM members mm
            JOIN engagements eng ON eng.person_id = mm.person_id
            WHERE eng.initiative_id = v_event.initiative_id AND eng.status = 'active'
          )
          OR a.id IS NOT NULL

        -- 2) Small event types with existing attendance: show only attendees
        WHEN v_event.type IN ('1on1', 'entrevista', 'parceria') AND v_has_attendance THEN
          a.id IS NOT NULL

        -- 3) Standard audience-based filtering
        ELSE
          CASE COALESCE(v_event.audience_level, 'all')
            WHEN 'tribe' THEN
              m.current_cycle_active = true
              AND m.tribe_id = v_event_tribe_id
            WHEN 'leadership' THEN
              m.operational_role IN ('manager')
              OR 'sponsor'    = ANY(COALESCE(m.designations, '{}'))
              OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
              OR 'founder'    = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp'      = ANY(COALESCE(m.designations, '{}'))
            WHEN 'curators' THEN
              'curator' = ANY(COALESCE(m.designations, '{}'))
            ELSE
              m.current_cycle_active = true
              OR m.operational_role = 'manager'
              OR 'sponsor'    = ANY(COALESCE(m.designations, '{}'))
              OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
              OR 'curator'    = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp'      = ANY(COALESCE(m.designations, '{}'))
          END
        END
      )
  ) q;

  RETURN COALESCE(v_result, '[]'::json);
END;
$function$;

-- ============================================================================
-- Sub-group 2b — write_board (5 RPCs)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 6. assign_checklist_item  (latest: 20260505010000)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assign_checklist_item(p_checklist_item_id uuid, p_assigned_to uuid, p_target_date date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_item record;
  v_card record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_card_owner boolean;
  v_is_board_admin boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM board_item_checklists WHERE id = p_checklist_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Checklist item not found'; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = v_item.board_item_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_card.board_id;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false);

  v_is_leader := v_caller.operational_role = 'tribe_leader'
    AND v_caller.tribe_id = v_board_legacy_tribe_id;

  v_is_card_owner := v_card.assignee_id = v_caller.id;

  v_is_board_admin := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id
    AND bm.board_role = 'admin'
  );

  IF NOT public.can_by_member(v_caller.id, 'write_board') AND NOT v_is_card_owner AND NOT v_is_board_admin THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or card-owner/board-admin role';
  END IF;

  UPDATE board_item_checklists
  SET assigned_to = p_assigned_to,
      target_date = COALESCE(p_target_date, target_date),
      assigned_at = now(),
      assigned_by = v_caller.id
  WHERE id = p_checklist_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id, 'activity_assigned',
    v_item.text || ' → ' || coalesce((SELECT m.name FROM members m WHERE m.id = p_assigned_to), '?'),
    v_caller.id);
END;
$function$;

-- ----------------------------------------------------------------------------
-- 7. complete_checklist_item  (latest: 20260505010000)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.complete_checklist_item(p_checklist_item_id uuid, p_completed boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_item record;
  v_card record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_card_owner boolean;
  v_is_activity_owner boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM board_item_checklists WHERE id = p_checklist_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Checklist item not found'; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = v_item.board_item_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_card.board_id;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false);

  v_is_leader := v_caller.operational_role = 'tribe_leader'
    AND v_caller.tribe_id = v_board_legacy_tribe_id;

  v_is_card_owner := v_card.assignee_id = v_caller.id;
  v_is_activity_owner := v_item.assigned_to = v_caller.id OR v_item.assigned_to IS NULL;

  IF NOT public.can_by_member(v_caller.id, 'write_board') AND NOT v_is_card_owner AND NOT v_is_activity_owner THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or card/activity ownership';
  END IF;

  UPDATE board_item_checklists
  SET is_completed = p_completed,
      completed_at = CASE WHEN p_completed THEN now() ELSE NULL END,
      completed_by = CASE WHEN p_completed THEN v_caller.id ELSE NULL END
  WHERE id = p_checklist_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_card.board_id, v_card.id,
    CASE WHEN p_completed THEN 'activity_completed' ELSE 'activity_reopened' END,
    v_item.text || CASE WHEN p_completed THEN ' (concluída por ' || v_caller.name || ')' ELSE ' (reaberta)' END,
    v_caller.id);
END;
$function$;

-- ----------------------------------------------------------------------------
-- 8. create_board_item  (latest: 20260505010000)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_board_item(p_board_id uuid, p_title text, p_description text DEFAULT NULL::text, p_assignee_id uuid DEFAULT NULL::uuid, p_tags text[] DEFAULT '{}'::text[], p_due_date date DEFAULT NULL::date, p_status text DEFAULT 'backlog'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_max_pos int;
  v_caller record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_tribe_member boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_board FROM project_boards WHERE id = p_board_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Board not found'; END IF;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false);
  v_is_leader := v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = v_board_legacy_tribe_id;
  v_is_tribe_member := v_caller.is_active AND v_caller.tribe_id = v_board_legacy_tribe_id;

  IF NOT public.can_by_member(v_caller.id, 'write_board') AND NOT v_is_tribe_member AND NOT (
    (coalesce(v_board.domain_key, '') = 'communication' AND (
      v_caller.operational_role = 'communicator'
      OR coalesce('comms_team' = ANY(v_caller.designations), false)
      OR coalesce('comms_leader' = ANY(v_caller.designations), false)
      OR coalesce('comms_member' = ANY(v_caller.designations), false)
    ))
    OR (coalesce(v_board.domain_key, '') = 'publications_submissions' AND (
      v_caller.operational_role IN ('tribe_leader', 'communicator')
      OR coalesce('curator' = ANY(v_caller.designations), false)
    ))
  ) THEN RAISE EXCEPTION 'Unauthorized to create cards on this board'; END IF;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos FROM board_items WHERE board_id = p_board_id AND status = p_status;

  INSERT INTO board_items (board_id, title, description, assignee_id, tags, due_date, position, status, cycle, created_by)
  VALUES (p_board_id, p_title, p_description, COALESCE(p_assignee_id, v_caller.id), p_tags, p_due_date, v_max_pos, p_status, 3, v_caller.id)
  RETURNING id INTO v_id;

  INSERT INTO board_item_assignments (item_id, member_id, role, assigned_by)
  VALUES (v_id, v_caller.id, 'author', v_caller.id)
  ON CONFLICT DO NOTHING;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, new_status, actor_member_id)
  VALUES (p_board_id, v_id, 'created', p_status, v_caller.id);

  RETURN v_id;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 9. move_board_item  (latest: 20260505010000)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.move_board_item(p_item_id uuid, p_new_status text, p_new_position integer DEFAULT 0, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old_status text;
  v_board_id uuid;
  v_actor record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_card_owner boolean;
BEGIN
  SELECT status, board_id INTO v_old_status, v_board_id FROM board_items WHERE id = p_item_id;
  IF v_old_status IS NULL THEN RAISE EXCEPTION 'Item not found'; END IF;
  SELECT * INTO v_actor FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_board FROM project_boards WHERE id = v_board_id;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_actor.is_superadmin, false) OR v_actor.operational_role IN ('manager','deputy_manager') OR coalesce('co_gp' = ANY(v_actor.designations), false);
  v_is_leader := v_actor.operational_role = 'tribe_leader' AND v_actor.tribe_id = v_board_legacy_tribe_id;

  v_is_card_owner := EXISTS (SELECT 1 FROM board_items WHERE id = p_item_id AND (created_by = v_actor.id OR assignee_id = v_actor.id))
    OR EXISTS (SELECT 1 FROM board_item_assignments WHERE item_id = p_item_id AND member_id = v_actor.id);

  IF p_new_status = 'done' AND NOT v_is_gp AND NOT v_is_leader THEN
    RAISE EXCEPTION 'Only Leader or GP can mark as completed';
  END IF;

  IF NOT public.can_by_member(v_actor.id, 'write_board') AND NOT v_is_card_owner THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or card ownership';
  END IF;

  UPDATE board_items SET position = position + 1
  WHERE board_id = v_board_id AND status = p_new_status AND position >= p_new_position AND id != p_item_id;

  UPDATE board_items SET status = p_new_status, position = p_new_position,
    actual_completion_date = CASE WHEN p_new_status = 'done' THEN CURRENT_DATE ELSE actual_completion_date END,
    updated_at = now()
  WHERE id = p_item_id;

  IF v_old_status != p_new_status THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'status_change', v_old_status, p_new_status, p_reason, v_actor.id);
    INSERT INTO notifications (recipient_id, type, source_type, source_id, title, actor_id)
    SELECT bia.member_id,
      CASE WHEN p_new_status = 'review' THEN 'review_requested' ELSE 'card_status_changed' END,
      'board_item', p_item_id, (SELECT title FROM board_items WHERE id = p_item_id), v_actor.id
    FROM board_item_assignments bia WHERE bia.item_id = p_item_id AND bia.member_id != v_actor.id;
  END IF;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 10. update_board_item  (latest: 20260505010000)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_board_item(p_item_id uuid, p_fields jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_board_id uuid;
  v_old record;
  v_caller record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_card_owner boolean;
  v_is_board_admin boolean;
  v_is_board_editor boolean;
  v_new_assignee uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_old FROM board_items WHERE id = p_item_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

  v_board_id := v_old.board_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_board_id;

  -- ADR-0015 Phase 3d: project_boards.tribe_id dropado; derivar via initiative
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false);

  v_is_leader := v_caller.operational_role = 'tribe_leader'
    AND v_caller.tribe_id = v_board_legacy_tribe_id;

  v_is_card_owner := v_old.assignee_id = v_caller.id;

  v_is_board_admin := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id
    AND bm.board_role = 'admin'
  );
  v_is_board_editor := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id
    AND bm.board_role IN ('admin', 'editor')
  );

  IF NOT public.can_by_member(v_caller.id, 'write_board')
     AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor THEN
    IF NOT (
      (coalesce(v_board.domain_key, '') = 'communication' AND (
        v_caller.operational_role = 'communicator'
        OR coalesce('comms_team' = ANY(v_caller.designations), false)
        OR coalesce('comms_leader' = ANY(v_caller.designations), false)
        OR coalesce('comms_member' = ANY(v_caller.designations), false)
      ))
      OR (coalesce(v_board.domain_key, '') = 'publications_submissions' AND (
        v_caller.operational_role IN ('tribe_leader', 'communicator')
        OR coalesce('curator' = ANY(v_caller.designations), false)
        OR coalesce('co_gp' = ANY(v_caller.designations), false)
        OR coalesce('comms_leader' = ANY(v_caller.designations), false)
        OR coalesce('comms_member' = ANY(v_caller.designations), false)
      ))
    ) THEN
      RAISE EXCEPTION 'Insufficient permissions to edit this card';
    END IF;
  END IF;

  IF p_fields ? 'baseline_date' THEN
    IF v_old.baseline_locked_at IS NOT NULL AND NOT v_is_gp THEN
      RAISE EXCEPTION 'Baseline is locked. Only GP can change it.';
    END IF;
    IF v_old.baseline_locked_at IS NOT NULL AND v_is_gp AND NOT (p_fields ? 'reason') THEN
      RAISE EXCEPTION 'Reason required to change locked baseline';
    END IF;
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin THEN
      RAISE EXCEPTION 'Only Leader or GP can change baseline';
    END IF;
  END IF;

  IF p_fields ? 'forecast_date' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_card_owner AND NOT v_is_board_editor THEN
      RAISE EXCEPTION 'Only Leader, GP, or card owner can change forecast';
    END IF;
  END IF;

  IF p_fields ? 'assignee_id' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin THEN
      RAISE EXCEPTION 'Only Leader or GP can change assignee';
    END IF;
  END IF;

  IF p_fields ? 'is_portfolio_item' THEN
    IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin THEN
      RAISE EXCEPTION 'Only Leader or GP can change portfolio flag';
    END IF;
  END IF;

  IF v_old.baseline_date IS NOT NULL
    AND v_old.baseline_locked_at IS NULL
    AND v_old.baseline_date <= CURRENT_DATE - 7
  THEN
    UPDATE board_items SET baseline_locked_at = now() WHERE id = p_item_id;
    v_old.baseline_locked_at := now();
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'baseline_locked', 'Auto-lock após 7 dias de grace period', v_caller.id);
  END IF;

  UPDATE board_items SET
    title = coalesce(p_fields->>'title', title),
    description = CASE WHEN p_fields ? 'description' THEN p_fields->>'description' ELSE description END,
    assignee_id = CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                       THEN (p_fields->>'assignee_id')::uuid
                       WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NULL THEN NULL
                       ELSE assignee_id END,
    reviewer_id = CASE WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NOT NULL
                       THEN (p_fields->>'reviewer_id')::uuid
                       WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NULL THEN NULL
                       ELSE reviewer_id END,
    tags = CASE WHEN p_fields ? 'tags' THEN ARRAY(SELECT jsonb_array_elements_text(p_fields->'tags')) ELSE tags END,
    labels = CASE WHEN p_fields ? 'labels' THEN p_fields->'labels' ELSE labels END,
    due_date = CASE WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NOT NULL THEN (p_fields->>'due_date')::date
                    WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NULL THEN NULL ELSE due_date END,
    baseline_date = CASE WHEN p_fields ? 'baseline_date' AND p_fields->>'baseline_date' IS NOT NULL THEN (p_fields->>'baseline_date')::date
                         WHEN p_fields ? 'baseline_date' AND p_fields->>'baseline_date' IS NULL THEN NULL ELSE baseline_date END,
    forecast_date = CASE WHEN p_fields ? 'forecast_date' AND p_fields->>'forecast_date' IS NOT NULL THEN (p_fields->>'forecast_date')::date
                         WHEN p_fields ? 'forecast_date' AND p_fields->>'forecast_date' IS NULL THEN NULL ELSE forecast_date END,
    is_portfolio_item = CASE WHEN p_fields ? 'is_portfolio_item' THEN (p_fields->>'is_portfolio_item')::boolean ELSE is_portfolio_item END,
    baseline_locked_at = CASE WHEN p_fields ? 'baseline_locked_at' AND p_fields->>'baseline_locked_at' IS NOT NULL
                               THEN (p_fields->>'baseline_locked_at')::timestamptz ELSE baseline_locked_at END,
    checklist = CASE WHEN p_fields ? 'checklist' THEN p_fields->'checklist' ELSE checklist END,
    attachments = CASE WHEN p_fields ? 'attachments' THEN p_fields->'attachments' ELSE attachments END,
    curation_status = coalesce(p_fields->>'curation_status', curation_status),
    curation_due_at = CASE WHEN p_fields ? 'curation_due_at' AND p_fields->>'curation_due_at' IS NOT NULL
                           THEN (p_fields->>'curation_due_at')::timestamptz ELSE curation_due_at END,
    updated_at = now()
  WHERE id = p_item_id;

  IF p_fields ? 'baseline_date' THEN
    IF v_old.baseline_date IS NULL AND p_fields->>'baseline_date' IS NOT NULL THEN
      INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
      VALUES (v_board_id, p_item_id, 'baseline_set', 'Baseline definida: ' || (p_fields->>'baseline_date'), v_caller.id);
    ELSIF v_old.baseline_date IS NOT NULL AND p_fields->>'baseline_date' IS NOT NULL
      AND v_old.baseline_date::text != p_fields->>'baseline_date' THEN
      INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
      VALUES (v_board_id, p_item_id, 'baseline_changed',
        v_old.baseline_date::text || ' → ' || (p_fields->>'baseline_date')
        || CASE WHEN p_fields ? 'reason' THEN ' | Razão: ' || (p_fields->>'reason') ELSE '' END, v_caller.id);
    END IF;
  END IF;

  IF p_fields ? 'forecast_date' AND p_fields->>'forecast_date' IS DISTINCT FROM v_old.forecast_date::text THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'forecast_changed',
      coalesce(v_old.forecast_date::text, 'null') || ' → ' || coalesce(p_fields->>'forecast_date', 'null'), v_caller.id);
  END IF;

  IF p_fields ? 'title' AND p_fields->>'title' IS DISTINCT FROM v_old.title THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'title_changed', 'Título alterado', v_caller.id);
  END IF;

  v_new_assignee := CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                         THEN (p_fields->>'assignee_id')::uuid
                         WHEN p_fields ? 'assignee_id' THEN NULL ELSE v_old.assignee_id END;
  IF v_new_assignee IS DISTINCT FROM v_old.assignee_id THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'assigned',
      'Atribuído a ' || coalesce((SELECT name FROM members WHERE id = v_new_assignee), 'ninguém'), v_caller.id);
  END IF;

  IF p_fields ? 'is_portfolio_item'
    AND (p_fields->>'is_portfolio_item')::boolean IS DISTINCT FROM v_old.is_portfolio_item THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'portfolio_flag_changed',
      CASE WHEN (p_fields->>'is_portfolio_item')::boolean THEN 'Marcado como entregável' ELSE 'Removido de entregáveis' END, v_caller.id);
  END IF;
END;
$function$;

-- ============================================================================
-- Sub-group 2c — special cases (2 RPCs)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 11. exec_tribe_dashboard  (latest: 20260428130000)
--
-- V4 simplification: any caller may view their OWN tribe; cross-tribe view
-- requires `manage_platform`. The V3 sponsor/chapter_liaison fast-path is
-- dropped (those users must now have manage_platform via engagement_kind_permissions
-- to view cross-tribe).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.exec_tribe_dashboard(p_tribe_id integer, p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record; v_caller_tribe_id integer;
  v_tribe record; v_leader record; v_cycle_start date; v_result jsonb;
  v_tribe_initiative_id uuid;
  v_members_total int; v_members_active int; v_members_by_role jsonb; v_members_by_chapter jsonb; v_members_list jsonb;
  v_board record; v_prod_total int := 0; v_prod_by_status jsonb := '{}'::jsonb;
  v_articles_submitted int := 0; v_articles_approved int := 0; v_articles_published int := 0;
  v_curation_pending int := 0; v_avg_days_to_approval numeric := 0;
  v_attendance_rate numeric := 0; v_total_meetings int := 0; v_total_hours numeric := 0;
  v_avg_attendance numeric := 0; v_members_with_streak int := 0; v_members_inactive_30d int := 0;
  v_last_meeting_date date; v_next_meeting jsonb := '{}'::jsonb;
  v_tribe_total_xp int := 0; v_tribe_avg_xp numeric := 0;
  v_top_contributors jsonb := '[]'::jsonb; v_cpmai_certified int := 0;
  v_attendance_by_month jsonb := '[]'::jsonb; v_production_by_month jsonb := '[]'::jsonb;
  v_meeting_slots jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;
  v_caller_tribe_id := public.get_member_tribe(v_caller.id);

  -- Caller may view their OWN tribe; cross-tribe view requires manage_platform.
  IF v_caller_tribe_id IS DISTINCT FROM p_tribe_id
     AND NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: cross-tribe view requires manage_platform permission';
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found'; END IF;

  -- Cache initiative_id for efficient engagement lookups
  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  v_cycle_start := COALESCE(
    (SELECT MIN(date) FROM public.events WHERE title ILIKE '%kick%off%' AND date >= '2026-01-01'),
    '2026-03-05'::date
  );
  SELECT id, name, photo_url INTO v_leader FROM public.members WHERE id = v_tribe.leader_member_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('day_of_week', tms.day_of_week, 'time_start', tms.time_start, 'time_end', tms.time_end)), '[]'::jsonb)
  INTO v_meeting_slots
  FROM public.tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true;

  SELECT COUNT(*) INTO v_members_total
  FROM public.members m
  WHERE m.is_active = true
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    );

  SELECT COUNT(*) INTO v_members_active
  FROM public.members m
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    );

  SELECT COALESCE(jsonb_object_agg(role, cnt), '{}'::jsonb) INTO v_members_by_role
  FROM (
    SELECT m.operational_role AS role, COUNT(*) AS cnt
    FROM public.members m
    WHERE m.is_active = true
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id
          AND e.kind = 'volunteer' AND e.status = 'active'
          AND e.initiative_id = v_tribe_initiative_id
      )
    GROUP BY m.operational_role
  ) sub;

  SELECT COALESCE(jsonb_object_agg(ch, cnt), '{}'::jsonb) INTO v_members_by_chapter
  FROM (
    SELECT COALESCE(m.chapter, 'N/A') AS ch, COUNT(*) AS cnt
    FROM public.members m
    WHERE m.is_active = true
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id
          AND e.kind = 'volunteer' AND e.status = 'active'
          AND e.initiative_id = v_tribe_initiative_id
      )
    GROUP BY m.chapter
  ) sub;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id, 'name', m.name, 'chapter', m.chapter, 'operational_role', m.operational_role,
      'xp_total', COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0),
      'attendance_rate', COALESCE(
        (SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(COUNT(*), 0), 2)
         FROM public.attendance a
         JOIN public.events e ON e.id = a.event_id
         JOIN public.initiatives i ON i.id = e.initiative_id
         WHERE a.member_id = m.id AND i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE), 0),
      'cpmai_certified', COALESCE(m.cpmai_certified, false),
      'last_activity_at', GREATEST(m.updated_at, (SELECT MAX(a2.created_at) FROM public.attendance a2 WHERE a2.member_id = m.id))
    ) ORDER BY COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0) DESC
  ), '[]'::jsonb) INTO v_members_list
  FROM public.members m
  WHERE m.is_active = true
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    );

  SELECT pb.* INTO v_board
  FROM public.project_boards pb
  JOIN public.initiatives i ON i.id = pb.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND pb.domain_key = 'research_delivery' AND pb.is_active = true
  LIMIT 1;

  IF v_board.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_prod_total FROM public.board_items WHERE board_id = v_board.id;
    SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb) INTO v_prod_by_status
    FROM (SELECT status, COUNT(*) AS cnt FROM public.board_items WHERE board_id = v_board.id GROUP BY status) sub;
    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review', 'approved', 'published')) INTO v_articles_submitted
    FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status = 'approved') INTO v_articles_approved FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status = 'published') INTO v_articles_published FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review')) INTO v_curation_pending FROM public.board_items WHERE board_id = v_board.id;
  END IF;

  SELECT COUNT(DISTINCT e.id), COALESCE(SUM(COALESCE(e.duration_actual, e.duration_minutes, 60)) / 60.0, 0)
  INTO v_total_meetings, v_total_hours
  FROM public.events e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;

  IF v_total_meetings > 0 AND v_members_active > 0 THEN
    SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(v_members_active * v_total_meetings, 0), 2)
    INTO v_attendance_rate
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;

    SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(v_total_meetings, 0), 1)
    INTO v_avg_attendance
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;
  END IF;

  SELECT MAX(e.date) INTO v_last_meeting_date
  FROM public.events e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND e.date <= CURRENT_DATE;

  SELECT COUNT(*) INTO v_members_inactive_30d
  FROM public.members m
  WHERE m.is_active = true
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.attendance a JOIN public.events e2 ON e2.id = a.event_id
      WHERE a.member_id = m.id AND a.present = true AND e2.date >= (CURRENT_DATE - INTERVAL '30 days')
    );

  SELECT jsonb_build_object('day_of_week', tms.day_of_week, 'time_start', tms.time_start) INTO v_next_meeting
  FROM public.tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true LIMIT 1;

  SELECT COALESCE(SUM(gp.points), 0) INTO v_tribe_total_xp
  FROM public.gamification_points gp
  WHERE gp.member_id IN (
    SELECT m.id FROM public.members m
    WHERE m.is_active = true
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id
          AND e.kind = 'volunteer' AND e.status = 'active'
          AND e.initiative_id = v_tribe_initiative_id
      )
  );

  v_tribe_avg_xp := CASE WHEN v_members_active > 0 THEN ROUND(v_tribe_total_xp::numeric / v_members_active, 1) ELSE 0 END;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', sub.name, 'xp', sub.xp, 'rank', sub.rn)), '[]'::jsonb) INTO v_top_contributors
  FROM (
    SELECT m.name, SUM(gp.points) AS xp, ROW_NUMBER() OVER (ORDER BY SUM(gp.points) DESC) AS rn
    FROM public.gamification_points gp
    JOIN public.members m ON m.id = gp.member_id
    WHERE m.is_active = true
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id
          AND e.kind = 'volunteer' AND e.status = 'active'
          AND e.initiative_id = v_tribe_initiative_id
      )
    GROUP BY m.id, m.name
    ORDER BY xp DESC LIMIT 5
  ) sub;

  SELECT COUNT(*) INTO v_cpmai_certified
  FROM public.members m
  WHERE m.is_active = true AND m.cpmai_certified = true
    AND EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = m.person_id
        AND e.kind = 'volunteer' AND e.status = 'active'
        AND e.initiative_id = v_tribe_initiative_id
    );

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', sub.month, 'rate', sub.rate) ORDER BY sub.month), '[]'::jsonb) INTO v_attendance_by_month
  FROM (SELECT TO_CHAR(e.date, 'YYYY-MM') AS month,
      ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(COUNT(*), 0), 2) AS rate
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
    GROUP BY TO_CHAR(e.date, 'YYYY-MM')) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', sub.month, 'cards_created', sub.created, 'cards_completed', sub.completed) ORDER BY sub.month), '[]'::jsonb) INTO v_production_by_month
  FROM (SELECT TO_CHAR(bi.created_at, 'YYYY-MM') AS month, COUNT(*) AS created,
      COUNT(*) FILTER (WHERE bi.status = 'done') AS completed
    FROM public.board_items bi WHERE bi.board_id = v_board.id AND bi.created_at >= v_cycle_start
    GROUP BY TO_CHAR(bi.created_at, 'YYYY-MM')) sub;

  v_result := jsonb_build_object(
    'tribe', jsonb_build_object('id', v_tribe.id, 'name', v_tribe.name,
      'quadrant', v_tribe.quadrant, 'quadrant_name', v_tribe.quadrant_name,
      'leader', CASE WHEN v_leader.id IS NOT NULL THEN jsonb_build_object('id', v_leader.id, 'name', v_leader.name, 'avatar_url', v_leader.photo_url) ELSE NULL END,
      'meeting_slots', v_meeting_slots, 'whatsapp_url', v_tribe.whatsapp_url, 'drive_url', v_tribe.drive_url),
    'members', jsonb_build_object('total', v_members_total, 'active', v_members_active,
      'by_role', v_members_by_role, 'by_chapter', v_members_by_chapter, 'list', v_members_list),
    'production', jsonb_build_object('total_cards', v_prod_total, 'by_status', v_prod_by_status,
      'articles_submitted', v_articles_submitted, 'articles_approved', v_articles_approved,
      'articles_published', v_articles_published, 'curation_pending', v_curation_pending,
      'avg_days_to_approval', v_avg_days_to_approval),
    'engagement', jsonb_build_object('attendance_rate', v_attendance_rate, 'total_meetings', v_total_meetings,
      'total_hours', ROUND(v_total_hours, 1), 'avg_attendance_per_meeting', v_avg_attendance,
      'members_inactive_30d', v_members_inactive_30d, 'last_meeting_date', v_last_meeting_date, 'next_meeting', v_next_meeting),
    'gamification', jsonb_build_object('tribe_total_xp', v_tribe_total_xp, 'tribe_avg_xp', v_tribe_avg_xp,
      'top_contributors', v_top_contributors,
      'certification_progress', jsonb_build_object('cpmai_certified', v_cpmai_certified)),
    'trends', jsonb_build_object('attendance_by_month', v_attendance_by_month, 'production_by_month', v_production_by_month)
  );
  RETURN v_result;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 12. get_member_attendance_hours  (latest: 20260428050000)
--
-- V4: self-access OR view_pii. tribe_leader cross-tribe view is dropped (they
-- can still view their own data; for cross-tribe attendance they must have
-- view_pii via engagement_kind_permissions).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_member_attendance_hours(p_member_id uuid, p_cycle_code text DEFAULT 'cycle_3'::text)
 RETURNS TABLE(total_hours numeric, total_events integer, avg_hours_per_event numeric, current_streak integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_start date;
  v_streak int := 0;
  v_rec record;
  v_target_tribe int;
BEGIN
  SELECT id INTO v_caller_id
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (v_caller_id = p_member_id OR public.can_by_member(v_caller_id, 'view_pii')) THEN
    RAISE EXCEPTION 'Unauthorized: can only view own attendance or requires view_pii permission';
  END IF;

  SELECT cycle_start INTO v_cycle_start
  FROM public.cycles WHERE cycle_code = p_cycle_code;

  IF v_cycle_start IS NULL THEN
    RETURN QUERY SELECT 0::numeric, 0::int, 0::numeric, 0::int;
    RETURN;
  END IF;

  SELECT tribe_id INTO v_target_tribe FROM public.members WHERE id = p_member_id;

  FOR v_rec IN
    SELECT e.id,
           EXISTS(SELECT 1 FROM public.attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id) AS was_present
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND e.date <= current_date
      AND (e.initiative_id IS NULL
           OR i.legacy_tribe_id = v_target_tribe)
    ORDER BY e.date DESC
  LOOP
    IF v_rec.was_present THEN
      v_streak := v_streak + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;

  RETURN QUERY
  SELECT
    COALESCE(SUM(e.duration_minutes / 60.0), 0)::numeric          AS total_hours,
    COUNT(DISTINCT a.event_id)::int                                AS total_events,
    CASE WHEN COUNT(DISTINCT a.event_id) > 0
      THEN (COALESCE(SUM(e.duration_minutes / 60.0), 0) / COUNT(DISTINCT a.event_id))::numeric
      ELSE 0::numeric
    END                                                            AS avg_hours_per_event,
    v_streak                                                       AS current_streak
  FROM public.attendance a
  JOIN public.events e ON e.id = a.event_id
  WHERE a.member_id = p_member_id
    AND e.date >= v_cycle_start;
END;
$function$;

NOTIFY pgrst, 'reload schema';
