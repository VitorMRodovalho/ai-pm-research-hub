-- ============================================================================
-- P0 regression fix: ADR-0015 Phase 3 stragglers
-- Smoke test em prod (19/Abr p29) detectou funções ainda referenciando
-- events.tribe_id / project_boards.tribe_id após DROP COLUMN em Phase 3d/3e.
-- Phase 3 migrations (commit 4d2a10d + precedentes) não refatoraram essas 7.
--
-- Erros observados:
--   get_tribe_event_roster → "record v_event has no field tribe_id"
--   list_active_boards     → "column b.tribe_id does not exist"
--   + 400 em get_board, get_board_by_domain, get_member_detail, etc.
--
-- Pattern aplicado: derivar tribe_id via initiatives.legacy_tribe_id usando
-- public.resolve_tribe_id(initiative_id). Preserva output shape (frontend não muda).
--
-- Rollback: reapply migrations 20260428030000 (Phase 3d) e 20260428050000 (Phase 3e)
--           se precisar voltar — mas isso não recupera a coluna dropped.
-- ============================================================================

-- ───────────────────────────────────────────────────────────
-- EVENTS: 4 funções afetadas (_can_manage_event, get_event_detail,
--         get_tribe_event_roster, update_event)
-- ───────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._can_manage_event(p_event_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_event_tribe_id int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_caller.is_superadmin THEN RETURN true; END IF;
  IF v_caller.operational_role IN ('manager', 'deputy_manager') THEN RETURN true; END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN false; END IF;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  IF v_caller.operational_role = 'tribe_leader' AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_caller.operational_role = 'researcher'   AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_event.created_by = v_caller.id THEN RETURN true; END IF;
  RETURN false;
END;
$function$;


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
     AND v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager') THEN
    RETURN jsonb_build_object('error', 'Restricted content');
  END IF;
  IF v_event.visibility = 'leadership'
     AND v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager', 'tribe_leader') THEN
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

  -- Access control
  IF NOT COALESCE(v_caller.is_superadmin, false) THEN
    IF v_caller.operational_role IN ('manager', 'deputy_manager') THEN
      NULL;
    ELSIF v_caller.operational_role = 'tribe_leader' OR 'co_gp' = ANY(COALESCE(v_caller.designations, '{}')) THEN
      IF v_event_tribe_id IS NOT NULL AND v_event_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
        RETURN json_build_object('error', 'Access denied');
      END IF;
    ELSE
      RETURN json_build_object('error', 'Access denied');
    END IF;
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
  v_allowed boolean := false;
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

  -- Permission check
  IF v_caller.is_superadmin THEN v_allowed := true;
  ELSIF v_caller.operational_role IN ('manager', 'deputy_manager') THEN v_allowed := true;
  ELSIF v_caller.designations && ARRAY['deputy_manager', 'co_gp'] THEN v_allowed := true;
  ELSIF v_caller.operational_role = 'tribe_leader'
    AND v_event_tribe_id IS NOT NULL
    AND v_event_tribe_id = v_caller.tribe_id THEN v_allowed := true;
  ELSIF v_event.created_by = auth.uid() THEN v_allowed := true;
  END IF;

  IF NOT v_allowed THEN
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


-- ───────────────────────────────────────────────────────────
-- PROJECT_BOARDS: 3 funções afetadas (get_board, get_curation_cross_board,
--                 list_active_boards)
-- ───────────────────────────────────────────────────────────

-- list_active_boards: assinatura mantida (tribe_id integer derivado)
CREATE OR REPLACE FUNCTION public.list_active_boards()
RETURNS TABLE(id uuid, board_name text, tribe_id integer, domain_key text, board_scope text, source text, item_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    b.id,
    b.board_name,
    public.resolve_tribe_id(b.initiative_id) AS tribe_id,
    b.domain_key,
    b.board_scope,
    b.source,
    (SELECT count(*) FROM board_items bi WHERE bi.board_id = b.id) AS item_count
  FROM project_boards b
  WHERE b.is_active = true
  ORDER BY b.board_scope, public.resolve_tribe_id(b.initiative_id) NULLS FIRST, b.board_name;
END;
$function$;


CREATE OR REPLACE FUNCTION public.get_board(p_board_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'board', (
      SELECT jsonb_build_object(
        'id', b.id,
        'board_name', b.board_name,
        'tribe_id', public.resolve_tribe_id(b.initiative_id),
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
$function$;


CREATE OR REPLACE FUNCTION public.get_curation_cross_board()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN coalesce((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'board_id', i.board_id,
        'board_name', b.board_name,
        'tribe_id', public.resolve_tribe_id(b.initiative_id),
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
$function$;


-- get_board_by_domain: filtra por tribe_id derivado via initiative_id
CREATE OR REPLACE FUNCTION public.get_board_by_domain(
  p_domain_key text,
  p_tribe_id integer DEFAULT NULL,
  p_initiative_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_board_id uuid;
  v_resolved_tribe_id int;
BEGIN
  IF p_initiative_id IS NOT NULL AND p_tribe_id IS NULL THEN
    v_resolved_tribe_id := public.resolve_tribe_id(p_initiative_id);
  ELSE
    v_resolved_tribe_id := p_tribe_id;
  END IF;

  SELECT b.id INTO v_board_id
  FROM project_boards b
  WHERE b.domain_key = p_domain_key
    AND b.is_active = true
    AND (v_resolved_tribe_id IS NULL OR public.resolve_tribe_id(b.initiative_id) = v_resolved_tribe_id)
  ORDER BY b.created_at DESC
  LIMIT 1;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('board', null, 'items', '[]'::jsonb);
  END IF;

  RETURN public.get_board(v_board_id);
END;
$function$;

NOTIFY pgrst, 'reload schema';
