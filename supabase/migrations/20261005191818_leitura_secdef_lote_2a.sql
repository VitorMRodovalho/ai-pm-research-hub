-- Funções de leitura SECURITY DEFINER seguem a política de leitura das tabelas (lote 2a).
--
-- Mesma regra da migration 20261005183507: a quem chama pela API (_request_is_rest_caller(), #684),
-- a leitura segue a política da tabela, que desde 20260805000246 é membro com vínculo vigente
-- (rls_is_authoritative_member()). A recusa devolve o mesmo formato que cada função já usa para
-- quadro ou iniciativa confidencial. Chamadas internas seguem iguais.
-- As linhas do tempo de eventos seguem abertas a quem tem cadastro de membro (política de events),
-- sem a ata para quem não tem vínculo vigente; no radar, só as publicações exigem vínculo vigente.

CREATE OR REPLACE FUNCTION public.get_board_activities(p_board_id uuid, p_assignee_filter uuid DEFAULT NULL::uuid, p_status_filter text DEFAULT 'all'::text, p_period_filter text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_result jsonb;
  v_total bigint;
  v_completed bigint;
  v_pending bigint;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- #785 PR-3: confidential gate (board→initiative)
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('activities', '[]'::jsonb, 'total', 0, 'completed', 0, 'pending', 0);
  END IF;

  IF NOT public.rls_can_see_board(p_board_id) THEN
    RETURN jsonb_build_object('activities', '[]'::jsonb, 'total', 0, 'completed', 0, 'pending', 0);
  END IF;

  SELECT jsonb_agg(row_data ORDER BY card_title, position) INTO v_result
  FROM (
    SELECT
      jsonb_build_object(
        'id', c.id,
        'card_id', bi.id,
        'card_title', bi.title,
        'card_status', bi.status,
        'card_baseline', bi.baseline_date,
        'card_forecast', bi.forecast_date,
        'is_portfolio_item', bi.is_portfolio_item,
        'text', c.text,
        'done', c.is_completed,
        'assignee_id', c.assigned_to,
        'assignee_name', (SELECT name FROM members WHERE id = c.assigned_to),
        'target_date', c.target_date,
        'completed_at', c.completed_at,
        'completed_by_name', (SELECT name FROM members WHERE id = c.completed_by),
        'position', c.position
      ) as row_data,
      bi.title as card_title,
      c.position
    FROM board_item_checklists c
    JOIN board_items bi ON bi.id = c.board_item_id
    WHERE bi.board_id = p_board_id
      AND bi.status != 'archived'
      AND (p_assignee_filter IS NULL OR c.assigned_to = p_assignee_filter)
      AND (p_status_filter = 'all'
        OR (p_status_filter = 'pending' AND c.is_completed = false)
        OR (p_status_filter = 'completed' AND c.is_completed = true))
      AND (p_period_filter = 'all'
        OR (p_period_filter = 'overdue' AND c.target_date < CURRENT_DATE AND c.is_completed = false)
        OR (p_period_filter = 'week' AND c.target_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 7)
        OR (p_period_filter = 'month' AND c.target_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30))
  ) sub;

  SELECT count(*), count(*) FILTER (WHERE is_completed), count(*) FILTER (WHERE NOT is_completed)
  INTO v_total, v_completed, v_pending
  FROM board_item_checklists c
  JOIN board_items bi ON bi.id = c.board_item_id
  WHERE bi.board_id = p_board_id AND bi.status != 'archived';

  RETURN jsonb_build_object(
    'activities', COALESCE(v_result, '[]'::jsonb),
    'total', v_total,
    'completed', v_completed,
    'pending', v_pending
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_board_drive_links(p_board_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- #785: confidential initiative visibility gate
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('board_id', p_board_id, 'drive_links', '[]'::jsonb, 'fetched_at', now());
  END IF;

  IF NOT public.rls_can_see_board(p_board_id) THEN
    RETURN jsonb_build_object('board_id', p_board_id, 'drive_links', '[]'::jsonb, 'fetched_at', now());
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'linked_by_name', m.name,
    'linked_at', l.linked_at
  ) ORDER BY l.linked_at DESC), '[]'::jsonb)
  INTO v_result
  FROM public.board_drive_links l
  LEFT JOIN public.members m ON m.id = l.linked_by
  WHERE l.board_id = p_board_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object(
    'board_id', p_board_id,
    'drive_links', v_result,
    'fetched_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_board_lifecycle_log(p_board_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_result jsonb;
BEGIN
  SELECT id, tribe_id, is_superadmin, operational_role
  INTO v_member FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN jsonb_build_object('events', '[]'::jsonb, 'count', 0); END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(evt)::jsonb ORDER BY evt.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      ble.id,
      ble.action,
      ble.previous_status,
      ble.new_status,
      ble.reason,
      ble.created_at,
      ble.review_round,
      bi.title as item_title,
      m.name as actor_name
    FROM board_lifecycle_events ble
    JOIN board_items bi ON bi.id = ble.item_id
    LEFT JOIN members m ON m.id = ble.actor_member_id
    WHERE (p_board_id IS NULL OR ble.board_id = p_board_id)
      AND public.rls_can_see_board(bi.board_id)
    ORDER BY ble.created_at DESC
    LIMIT p_limit
  ) evt;

  RETURN jsonb_build_object(
    'events', v_result,
    'count', jsonb_array_length(v_result)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_board_tags(p_board_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN '[]'::jsonb; END IF;
  -- First try tags from this specific board
  SELECT jsonb_agg(DISTINCT tag ORDER BY tag) INTO v_result
  FROM (SELECT unnest(tags) as tag FROM board_items WHERE board_id = p_board_id AND public.rls_can_see_board(board_id) AND tags IS NOT NULL AND array_length(tags, 1) > 0) sub
  WHERE tag IS NOT NULL AND tag != '';
  
  -- If empty, fallback to tags from ALL active boards (global suggestions)
  IF v_result IS NULL OR jsonb_array_length(v_result) = 0 THEN
    SELECT jsonb_agg(DISTINCT tag ORDER BY tag) INTO v_result
    FROM (
      SELECT unnest(tags) as tag FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      WHERE pb.is_active = true AND public.rls_can_see_board(pb.id) AND bi.tags IS NOT NULL AND array_length(bi.tags, 1) > 0
    ) sub
    WHERE tag IS NOT NULL AND tag != '';
  END IF;
  
  RETURN COALESCE(v_result, '[]'::jsonb);
END; $function$;

CREATE OR REPLACE FUNCTION public.get_card_full_history(p_card_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN jsonb_build_object('error', 'card_not_found'); END IF;

  SELECT bi.id, bi.title, bi.description, bi.status, bi.curation_status,
         bi.board_id, bi.assignee_id, bi.created_at, bi.updated_at
  INTO v_card FROM public.board_items bi WHERE bi.id = p_card_id;
  IF v_card.id IS NULL THEN
    RETURN jsonb_build_object('error', 'card_not_found');
  END IF;

  -- #785: confidential gate (board->initiative; same not_found shape to avoid leaking existence)
  IF NOT public.rls_can_see_board(v_card.board_id) THEN
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

CREATE OR REPLACE FUNCTION public.get_cpmai_leaderboard(p_course_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; v_course_id uuid; v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN '[]'::jsonb; END IF;

  IF p_course_id IS NOT NULL THEN v_course_id := p_course_id;
  ELSE SELECT id INTO v_course_id FROM cpmai_courses WHERE status != 'cancelled' ORDER BY created_at DESC LIMIT 1;
  END IF;

  SELECT jsonb_agg(row_data ORDER BY (row_data->>'total_xp')::int DESC) INTO v_result FROM (
    SELECT jsonb_build_object(
      'member_id', m.id, 'name', m.name, 'photo_url', m.photo_url,
      'total_xp', COALESCE((SELECT sum(points) FROM gamification_points gp WHERE gp.member_id = m.id AND gp.category = 'cpmai_prep'), 0),
      'modules_completed', (SELECT count(*) FROM cpmai_progress p JOIN cpmai_enrollments e ON e.id = p.enrollment_id WHERE e.member_id = m.id AND e.course_id = v_course_id AND p.status = 'completed'),
      'best_mock_score', (SELECT max(ms.score_pct) FROM cpmai_mock_scores ms JOIN cpmai_enrollments e ON e.id = ms.enrollment_id WHERE e.member_id = m.id AND e.course_id = v_course_id),
      'enrollment_status', e.status
    ) as row_data
    FROM cpmai_enrollments e JOIN members m ON m.id = e.member_id
    WHERE e.course_id = v_course_id AND e.status IN ('active','completed')
  ) sub;

  RETURN COALESCE(v_result, '[]'::jsonb);
END; $function$;

CREATE OR REPLACE FUNCTION public.get_event_tags(p_event_id uuid)
 RETURNS TABLE(tag_id uuid, tag_name text, label_pt text, color text, tier tag_tier)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;
  RETURN QUERY
  SELECT t.id, t.name, t.label_pt, t.color, t.tier
  FROM public.tags t
  JOIN public.event_tag_assignments eta ON eta.tag_id = t.id
  WHERE eta.event_id = p_event_id
  ORDER BY t.display_order;
END; $function$;

CREATE OR REPLACE FUNCTION public.get_event_tags_batch(p_event_ids uuid[])
 RETURNS TABLE(event_id uuid, tag_id uuid, tag_name text, label_pt text, color text, tier tag_tier)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;
  RETURN QUERY
  SELECT eta.event_id, t.id, t.name, t.label_pt, t.color, t.tier
  FROM public.tags t
  JOIN public.event_tag_assignments eta ON eta.tag_id = t.id
  WHERE eta.event_id = ANY(p_event_ids)
  ORDER BY eta.event_id, t.display_order;
END; $function$;

CREATE OR REPLACE FUNCTION public.get_initiative_drive_links(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_initiative record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id, title, kind INTO v_initiative
  FROM public.initiatives WHERE id = p_initiative_id;
  IF v_initiative.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  -- #785 PR-3: confidential gate (same 'not found' response — do not leak existence)
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'link_purpose', l.link_purpose,
    'linked_by_name', m.name,
    'linked_at', l.linked_at
  ) ORDER BY
    CASE l.link_purpose
      WHEN 'workspace' THEN 1
      WHEN 'shared_resources' THEN 2
      WHEN 'minutes' THEN 3
      WHEN 'archive' THEN 4
      ELSE 5
    END,
    l.linked_at DESC
  ), '[]'::jsonb)
  INTO v_result
  FROM public.initiative_drive_links l
  LEFT JOIN public.members m ON m.id = l.linked_by
  WHERE l.initiative_id = p_initiative_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object(
    'initiative_id', p_initiative_id,
    'initiative_title', v_initiative.title,
    'initiative_kind', v_initiative.kind,
    'drive_links', v_result,
    'fetched_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_initiative_events_timeline(p_initiative_id uuid, p_upcoming_limit integer DEFAULT 5, p_past_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- A ata não tem leitura direta desde 20260925183649: pela API, só membro com vínculo vigente.
  v_full boolean := NOT public._request_is_rest_caller() OR public.rls_is_authoritative_member();
  v_caller record;
  v_upcoming jsonb;
  v_past jsonb;
  v_today date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_eligible int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN jsonb_build_object('upcoming', '[]'::jsonb, 'past', '[]'::jsonb);
  END IF;

  SELECT count(*) INTO v_eligible
  FROM engagements
  WHERE initiative_id = p_initiative_id AND status = 'active';

  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'date'), '[]'::jsonb)
  INTO v_upcoming
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'title_i18n', e.title_i18n,
      'date', e.date,
      'time_start', e.time_start,
      'type', e.type,
      'duration_minutes', COALESCE(e.duration_minutes, 60),
      'meeting_link', e.meeting_link,
      'agenda_text', e.agenda_text
    ) as row_data
    FROM events e
    WHERE e.initiative_id = p_initiative_id
      AND e.date >= v_today
    ORDER BY e.date ASC
    LIMIT p_upcoming_limit
  ) sub;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'date') DESC), '[]'::jsonb)
  INTO v_past
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'title_i18n', e.title_i18n,
      'date', e.date,
      'time_start', e.time_start,
      'type', e.type,
      'duration_minutes', COALESCE(e.duration_actual, e.duration_minutes, 60),
      'recording_url', e.recording_url,
      'youtube_url', e.youtube_url,
      'has_recording', (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL),
      'minutes_text', CASE WHEN v_full THEN e.minutes_text END,
      'has_minutes', (e.minutes_text IS NOT NULL AND e.minutes_text != ''),
      'agenda_text', e.agenda_text,
      'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true),
      'eligible_count', v_eligible
    ) as row_data
    FROM events e
    WHERE e.initiative_id = p_initiative_id
      AND e.date < v_today
    ORDER BY e.date DESC
    LIMIT p_past_limit
  ) sub;

  RETURN jsonb_build_object(
    'upcoming', v_upcoming,
    'past', v_past
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_item_curation_history(p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  -- #785: confidential gate (item->board->initiative)
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('reviews', '[]'::jsonb, 'assignments', '[]'::jsonb, 'sla_config', '{}'::jsonb);
  END IF;

  IF NOT public.rls_can_see_item(p_item_id) THEN
    RETURN jsonb_build_object('reviews', '[]'::jsonb, 'assignments', '[]'::jsonb, 'sla_config', '{}'::jsonb);
  END IF;
  SELECT jsonb_build_object(
    'reviews', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', crl.id,
        'curator_name', m.name,
        'curator_id', crl.curator_id,
        'decision', crl.decision,
        'criteria_scores', crl.criteria_scores,
        'feedback_notes', crl.feedback_notes,
        'completed_at', crl.completed_at
      ) ORDER BY crl.completed_at DESC)
      FROM curation_review_log crl
      LEFT JOIN members m ON m.id = crl.curator_id
      WHERE crl.board_item_id = p_item_id
    ), '[]'::jsonb),
    'assignments', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'reviewer_name', m.name,
        'reviewer_id', ble.actor_member_id,
        'round', ble.review_round,
        'assigned_at', ble.created_at,
        'sla_deadline', ble.sla_deadline
      ) ORDER BY ble.created_at DESC)
      FROM board_lifecycle_events ble
      LEFT JOIN members m ON m.id = ble.actor_member_id
      WHERE ble.item_id = p_item_id AND ble.action = 'reviewer_assigned'
    ), '[]'::jsonb),
    'sla_config', coalesce((
      SELECT jsonb_build_object(
        'sla_days', sc.sla_days,
        'reviewers_required', sc.reviewers_required,
        'max_review_rounds', sc.max_review_rounds,
        'rubric_criteria', sc.rubric_criteria
      )
      FROM board_sla_config sc
      JOIN board_items bi ON bi.board_id = sc.board_id
      WHERE bi.id = p_item_id
    ), '{}'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_mirror_target_boards(p_source_board_id uuid)
 RETURNS TABLE(board_id uuid, board_name text, board_scope text, item_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    pb.id,
    pb.board_name,
    pb.board_scope,
    (SELECT count(*) FROM public.board_items bi WHERE bi.board_id = pb.id AND bi.status != 'archived')
  FROM public.project_boards pb
  WHERE pb.id != p_source_board_id
    AND pb.is_active = true
    AND public.rls_can_see_board(pb.id)  -- #785
  ORDER BY pb.board_scope, pb.board_name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_tribe_events_timeline(p_tribe_id integer, p_upcoming_limit integer DEFAULT 3, p_past_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  -- A ata não tem leitura direta desde 20260925183649: pela API, só membro com vínculo vigente.
  v_full boolean := NOT public._request_is_rest_caller() OR public.rls_is_authoritative_member();
  v_caller record;
  v_upcoming jsonb;
  v_past jsonb;
  v_next_recurring jsonb;
  v_tribe_member_count int;
  v_tribe_initiative_id uuid;
  v_now_brt timestamptz := NOW() AT TIME ZONE 'America/Sao_Paulo';
  v_today_brt date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT id INTO v_tribe_initiative_id
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe'
  LIMIT 1;

  SELECT count(*) INTO v_tribe_member_count
  FROM public.v_tribe_active_members v
  WHERE v.initiative_id = v_tribe_initiative_id;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'date', row_data->>'title'), '[]'::jsonb)
  INTO v_upcoming
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'title_i18n', e.title_i18n,
      'date', e.date,
      'type', e.type,
      'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_minutes, 60),
      'meeting_link', e.meeting_link,
      'audience_level', e.audience_level,
      'tribe_id', i.legacy_tribe_id,
      'is_tribe_event', (i.legacy_tribe_id = p_tribe_id),
      'agenda_text', e.agenda_text,
      'eligible_count', CASE
        WHEN e.type IN ('geral', 'kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN i.legacy_tribe_id = p_tribe_id THEN v_tribe_member_count
        ELSE 0
      END
    ) as row_data
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff', 'lideranca'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
      AND (
        e.date > v_today_brt
        OR (
          e.date = v_today_brt
          AND (
            e.date::timestamp
            + COALESCE(
                (SELECT tms.time_start FROM tribe_meeting_slots tms
                 WHERE tms.tribe_id = i.legacy_tribe_id AND tms.is_active LIMIT 1),
                '19:30'::time
              )
            + (COALESCE(e.duration_minutes, 60) || ' minutes')::interval
          )::timestamp > v_now_brt::timestamp
        )
      )
    ORDER BY e.date ASC
    LIMIT p_upcoming_limit
  ) sub;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'date') DESC), '[]'::jsonb)
  INTO v_past
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'title_i18n', e.title_i18n,
      'date', e.date,
      'type', e.type,
      'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_actual, e.duration_minutes, 60),
      'tribe_id', i.legacy_tribe_id,
      'is_tribe_event', (i.legacy_tribe_id = p_tribe_id),
      'youtube_url', e.youtube_url,
      'recording_url', e.recording_url,
      'recording_type', e.recording_type,
      'has_recording', (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL),
      'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true),
      'eligible_count', CASE
        WHEN e.type IN ('geral', 'kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN i.legacy_tribe_id = p_tribe_id THEN v_tribe_member_count
        ELSE 0
      END,
      'agenda_text', e.agenda_text,
      'minutes_text', CASE WHEN v_full THEN e.minutes_text END
    ) as row_data
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date <= v_today_brt
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
    ORDER BY e.date DESC
    LIMIT p_past_limit
  ) sub;

  SELECT jsonb_build_object(
    'day_of_week', tms.day_of_week,
    'time_start', tms.time_start,
    'time_end', tms.time_end,
    'day_name_pt', CASE tms.day_of_week
      WHEN 0 THEN 'Domingo' WHEN 1 THEN 'Segunda' WHEN 2 THEN 'Terça'
      WHEN 3 THEN 'Quarta' WHEN 4 THEN 'Quinta' WHEN 5 THEN 'Sexta' WHEN 6 THEN 'Sábado'
    END,
    'day_name_en', CASE tms.day_of_week
      WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday'
      WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday' WHEN 6 THEN 'Saturday'
    END
  ) INTO v_next_recurring
  FROM tribe_meeting_slots tms
  WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true
  LIMIT 1;

  RETURN jsonb_build_object(
    'upcoming', v_upcoming,
    'past', v_past,
    'next_recurring', COALESCE(v_next_recurring, 'null'::jsonb),
    'tribe_member_count', v_tribe_member_count
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_tribe_housekeeping(p_initiative_id uuid DEFAULT NULL::uuid, p_legacy_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_initiative record;
  v_current_cycle text;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF p_initiative_id IS NOT NULL THEN
    SELECT id, title, kind, legacy_tribe_id
    INTO v_initiative FROM public.initiatives WHERE id = p_initiative_id;
  ELSIF p_legacy_tribe_id IS NOT NULL THEN
    SELECT id, title, kind, legacy_tribe_id
    INTO v_initiative FROM public.initiatives
    WHERE legacy_tribe_id = p_legacy_tribe_id
    LIMIT 1;
  END IF;

  IF v_initiative.id IS NULL THEN
    RETURN jsonb_build_object('error', 'initiative_not_found',
      'hint', 'Provide p_initiative_id or p_legacy_tribe_id');
  END IF;

  -- #785: confidential initiative visibility gate
  IF NOT public.rls_can_see_initiative(v_initiative.id) THEN
    RETURN jsonb_build_object('error', 'initiative_not_found',
      'hint', 'Provide p_initiative_id or p_legacy_tribe_id');
  END IF;

  SELECT cycle_code INTO v_current_cycle
  FROM public.tribe_deliverables
  WHERE initiative_id = v_initiative.id
    AND status NOT IN ('cancelled')
  ORDER BY created_at DESC LIMIT 1;
  v_current_cycle := COALESCE(v_current_cycle, 'cycle3-2026');

  v_result := jsonb_build_object(
    'initiative', jsonb_build_object(
      'id', v_initiative.id,
      'title', v_initiative.title,
      'kind', v_initiative.kind,
      'legacy_tribe_id', v_initiative.legacy_tribe_id
    ),
    'current_cycle', v_current_cycle,

    'kpis_contributed', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'kpi_target_id', akt.id,
        'kpi_key', akt.kpi_key,
        'kpi_label_pt', akt.kpi_label_pt,
        'category', akt.category,
        'target_value', akt.target_value,
        'current_value', akt.current_value,
        'baseline_value', akt.baseline_value,
        'attainment_pct', CASE WHEN akt.target_value IS NOT NULL AND akt.target_value <> 0
          THEN ROUND((COALESCE(akt.current_value, 0) / akt.target_value * 100)::numeric, 1)
          ELSE NULL END,
        'status_color', CASE
          WHEN akt.target_value IS NULL OR akt.target_value = 0 THEN 'gray'
          WHEN COALESCE(akt.current_value, 0) >= akt.target_value * 0.9 THEN 'green'
          WHEN COALESCE(akt.current_value, 0) >= akt.target_value * 0.7 THEN 'yellow'
          ELSE 'red' END,
        'weight', tkc.weight,
        'contribution_query', tkc.contribution_query,
        'icon', akt.icon
      ) ORDER BY akt.display_order)
      FROM public.tribe_kpi_contributions tkc
      JOIN public.annual_kpi_targets akt ON akt.id = tkc.kpi_target_id
      WHERE tkc.initiative_id = v_initiative.id
    ), '[]'::jsonb),

    'cards_linked_to_kpis', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'card_id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'assignee_id', bi.assignee_id,
        'assignee_name', am.name,
        'tags', bi.tags,
        'due_date', bi.due_date,
        'matched_kpi_keys', (
          SELECT COALESCE(jsonb_agg(akt.kpi_key), '[]'::jsonb)
          FROM public.tribe_kpi_contributions tkc2
          JOIN public.annual_kpi_targets akt ON akt.id = tkc2.kpi_target_id
          WHERE tkc2.initiative_id = v_initiative.id
            AND akt.kpi_key = ANY(COALESCE(bi.tags, ARRAY[]::text[]))
        )
      ) ORDER BY bi.updated_at DESC)
      FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.members am ON am.id = bi.assignee_id
      WHERE pb.initiative_id = v_initiative.id
        AND pb.is_active = true
        AND bi.status NOT IN ('archived')
        AND EXISTS (
          SELECT 1 FROM public.tribe_kpi_contributions tkc3
          JOIN public.annual_kpi_targets akt2 ON akt2.id = tkc3.kpi_target_id
          WHERE tkc3.initiative_id = v_initiative.id
            AND akt2.kpi_key = ANY(COALESCE(bi.tags, ARRAY[]::text[]))
        )
      LIMIT 100
    ), '[]'::jsonb),

    'cycle_deliverables', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', td.id,
        'title', td.title,
        'cycle_code', td.cycle_code,
        'status', td.status,
        'assigned_member_id', td.assigned_member_id,
        'assignee_name', tdm.name,
        'due_date', td.due_date,
        'days_to_due', CASE WHEN td.due_date IS NOT NULL
          THEN (td.due_date - CURRENT_DATE) ELSE NULL END,
        'has_artifact', td.artifact_id IS NOT NULL
      ) ORDER BY
        CASE WHEN td.status = 'done' THEN 1 ELSE 0 END,
        td.due_date NULLS LAST)
      FROM public.tribe_deliverables td
      LEFT JOIN public.members tdm ON tdm.id = td.assigned_member_id
      WHERE td.initiative_id = v_initiative.id
        AND td.cycle_code = v_current_cycle
    ), '[]'::jsonb),

    'rollup', jsonb_build_object(
      'kpis_total', (SELECT COUNT(*) FROM public.tribe_kpi_contributions WHERE initiative_id = v_initiative.id),
      'kpis_red', (SELECT COUNT(*) FROM public.tribe_kpi_contributions tkc4
        JOIN public.annual_kpi_targets akt3 ON akt3.id = tkc4.kpi_target_id
        WHERE tkc4.initiative_id = v_initiative.id
          AND akt3.target_value > 0
          AND COALESCE(akt3.current_value, 0) < akt3.target_value * 0.7),
      'kpis_yellow', (SELECT COUNT(*) FROM public.tribe_kpi_contributions tkc5
        JOIN public.annual_kpi_targets akt4 ON akt4.id = tkc5.kpi_target_id
        WHERE tkc5.initiative_id = v_initiative.id
          AND akt4.target_value > 0
          AND COALESCE(akt4.current_value, 0) >= akt4.target_value * 0.7
          AND COALESCE(akt4.current_value, 0) < akt4.target_value * 0.9),
      'cycle_deliverables_total', (SELECT COUNT(*) FROM public.tribe_deliverables
        WHERE initiative_id = v_initiative.id AND cycle_code = v_current_cycle),
      'cycle_deliverables_done', (SELECT COUNT(*) FROM public.tribe_deliverables
        WHERE initiative_id = v_initiative.id AND cycle_code = v_current_cycle AND status = 'done')
    ),

    'generated_at', now()
  );

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_webinar_lifecycle(p_webinar_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT wle.id, wle.action, wle.old_status, wle.new_status,
      wle.metadata, wle.created_at,
      m.name AS actor_name
    FROM webinar_lifecycle_events wle
    LEFT JOIN members m ON m.id = wle.actor_id
    WHERE wle.webinar_id = p_webinar_id
  ) r;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_active_boards()
 RETURNS TABLE(id uuid, board_name text, tribe_id integer, domain_key text, board_scope text, source text, item_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;
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
    AND public.rls_can_see_initiative(b.initiative_id)
  ORDER BY b.board_scope, public.resolve_tribe_id(b.initiative_id) NULLS FIRST, b.board_name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_card_drive_files(p_board_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_files jsonb;
  v_initiative_folders jsonb;
  v_board_folders jsonb;
  v_board_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  SELECT bi.board_id, pb.initiative_id
    INTO v_board_id, v_initiative_id
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.id = p_board_item_id;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  -- #785: confidential initiative visibility gate
  IF NOT public.rls_can_see_board(v_board_id) THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  -- Card-level files
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id,
    'drive_file_id', f.drive_file_id,
    'drive_file_url', f.drive_file_url,
    'filename', f.filename,
    'mime_type', f.mime_type,
    'size_bytes', f.size_bytes,
    'uploaded_by_name', m.name,
    'uploaded_via', f.uploaded_via,
    'created_at', f.created_at
  ) ORDER BY f.created_at DESC), '[]'::jsonb)
  INTO v_files
  FROM public.board_item_files f
  LEFT JOIN public.members m ON m.id = f.uploaded_by
  WHERE f.board_item_id = p_board_item_id AND f.deleted_at IS NULL;

  -- Initiative-level folder links (Hub de Comunicacao folder + Atas)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'link_purpose', l.link_purpose,
    'linked_at', l.linked_at
  ) ORDER BY l.link_purpose NULLS LAST, l.linked_at), '[]'::jsonb)
  INTO v_initiative_folders
  FROM public.initiative_drive_links l
  WHERE l.initiative_id = v_initiative_id AND l.unlinked_at IS NULL;

  -- Board-level folder links (rare but supported)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'linked_at', l.linked_at
  ) ORDER BY l.linked_at), '[]'::jsonb)
  INTO v_board_folders
  FROM public.board_drive_links l
  WHERE l.board_id = v_board_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object(
    'board_item_id', p_board_item_id,
    'files', v_files,
    'initiative_folders', v_initiative_folders,
    'board_folders', v_board_folders,
    'fetched_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_card_partners(p_board_item_id uuid)
 RETURNS TABLE(link_id uuid, link_role text, link_notes text, linked_at timestamp with time zone, linked_by_name text, partner_entity_id uuid, partner_name text, partner_entity_type text, partner_chapter text, partner_status text, partner_contact_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN RETURN; END IF;
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;

  -- #785: confidential initiative visibility gate (item->board->initiative)
  IF NOT public.rls_can_see_item(p_board_item_id) THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    pc.id, pc.link_role, pc.notes, pc.created_at, cm.name,
    pe.id, pe.name, pe.entity_type, pe.chapter, pe.status, pe.contact_name
  FROM public.partner_cards pc
  JOIN public.partner_entities pe ON pe.id = pc.partner_entity_id
  LEFT JOIN public.members cm ON cm.id = pc.created_by
  WHERE pc.board_item_id = p_board_item_id
  ORDER BY pc.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_meetings_with_notes(p_tribe_id integer DEFAULT NULL::integer, p_type text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_include_empty boolean DEFAULT false, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_total int;
  v_rows jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  -- Leitura pela API segue a política das colunas de ata (só membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('meetings', '[]'::jsonb, 'total', 0, 'limit', p_limit, 'offset', p_offset);
  END IF;

  SELECT count(*) INTO v_total
  FROM events e
  LEFT JOIN initiatives i ON i.id = e.initiative_id
  WHERE (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    AND public.rls_can_see_initiative(e.initiative_id)
    AND public.rls_can_see_event_tier(e.visibility, e.initiative_id)
    AND (p_type IS NULL OR e.type = p_type)
    AND (p_include_empty OR (e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20))
    AND (
      p_search IS NULL OR p_search = ''
      OR to_tsvector('portuguese',
           coalesce(e.title, '') || ' ' ||
           coalesce(e.minutes_text, '') || ' ' ||
           coalesce(e.agenda_text, '')
         ) @@ plainto_tsquery('portuguese', p_search)
    );

  SELECT COALESCE(jsonb_agg(row_to_json(sub) ORDER BY sub.date DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      e.id, e.title, e.date, e.type, i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      e.initiative_id,
      i.title AS initiative_name,
      e.youtube_url, e.recording_url,
      e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20 AS has_minutes,
      length(COALESCE(e.minutes_text, '')) AS minutes_length,
      e.agenda_text IS NOT NULL AS has_agenda,
      (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true) AS attendee_count
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND public.rls_can_see_initiative(e.initiative_id)
      AND public.rls_can_see_event_tier(e.visibility, e.initiative_id)
      AND (p_type IS NULL OR e.type = p_type)
      AND (p_include_empty OR (e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20))
      AND (
        p_search IS NULL OR p_search = ''
        OR to_tsvector('portuguese',
             coalesce(e.title, '') || ' ' ||
             coalesce(e.minutes_text, '') || ' ' ||
             coalesce(e.agenda_text, '')
           ) @@ plainto_tsquery('portuguese', p_search)
      )
    ORDER BY e.date DESC
    LIMIT p_limit
    OFFSET p_offset
  ) sub;

  RETURN jsonb_build_object(
    'meetings', v_rows,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_partner_cards(p_partner_entity_id uuid)
 RETURNS TABLE(link_id uuid, link_role text, link_notes text, linked_at timestamp with time zone, linked_by_name text, board_item_id uuid, board_item_title text, board_item_status text, board_item_due_date date, board_item_assignee_name text, board_id uuid, board_name text, partner_entity_id uuid, partner_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN RETURN; END IF;
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    pc.id,
    pc.link_role,
    pc.notes,
    pc.created_at,
    cm.name,
    bi.id,
    bi.title,
    bi.status,
    bi.due_date,
    am.name,
    bi.board_id,
    pb.board_name,
    pe.id,
    pe.name
  FROM public.partner_cards pc
  JOIN public.partner_entities pe ON pe.id = pc.partner_entity_id
  JOIN public.board_items bi ON bi.id = pc.board_item_id
  LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
  LEFT JOIN public.members am ON am.id = bi.assignee_id
  LEFT JOIN public.members cm ON cm.id = pc.created_by
  WHERE pc.partner_entity_id = p_partner_entity_id
    AND public.rls_can_see_board(bi.board_id)
  ORDER BY pc.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_project_boards(p_tribe_id integer DEFAULT NULL::integer)
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      pb.id, pb.board_name,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      pb.source, pb.columns, pb.is_active,
      pb.board_scope, pb.domain_key, pb.cycle_scope, pb.created_at,
      (SELECT count(*) FROM public.board_items bi WHERE bi.board_id = pb.id) AS item_count
    FROM public.project_boards pb
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    WHERE pb.is_active IS TRUE
      AND public.rls_can_see_initiative(pb.initiative_id)  -- #785 PR-3: confidential gate
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    ORDER BY
      CASE pb.board_scope WHEN 'global' THEN 0 WHEN 'operational' THEN 1 ELSE 2 END,
      pb.created_at DESC
  ) r;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_radar_global(p_webinars_limit integer DEFAULT 5, p_publications_limit integer DEFAULT 5)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_webinars json;
  v_publications json;
  v_today date := current_date;
BEGIN
  SELECT coalesce(json_agg(row_to_json(w)), '[]'::json) INTO v_webinars
  FROM (
    SELECT e.id, e.title, e.date, e.meeting_link, e.type
    FROM public.events e
    WHERE e.type = 'webinar'
      AND e.date >= v_today
      AND public.rls_can_see_initiative(e.initiative_id)
    ORDER BY e.date ASC
    LIMIT p_webinars_limit
  ) w;

  SELECT coalesce(json_agg(row_to_json(p)), '[]'::json) INTO v_publications
  FROM (
    SELECT bi.id, bi.title, bi.description, bi.updated_at
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    WHERE coalesce(pb.domain_key, '') = 'publications_submissions'
      AND bi.status = 'done'
      AND pb.is_active = true
      AND public.rls_can_see_initiative(pb.initiative_id)
      -- Publicações vêm de board_items: só membro com vínculo vigente, pela API.
      AND (NOT public._request_is_rest_caller() OR public.rls_is_authoritative_member())
    ORDER BY bi.updated_at DESC NULLS LAST
    LIMIT p_publications_limit
  ) p;

  RETURN json_build_object(
    'webinars', coalesce(v_webinars, '[]'::json),
    'publications', coalesce(v_publications, '[]'::json)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.search_partner_cards(p_link_role text DEFAULT NULL::text, p_card_status text DEFAULT NULL::text, p_chapter text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS TABLE(link_id uuid, link_role text, link_notes text, linked_at timestamp with time zone, linked_by_name text, partner_entity_id uuid, partner_name text, partner_chapter text, partner_status text, board_item_id uuid, board_item_title text, board_item_status text, board_item_due_date date, board_item_assignee_name text, board_id uuid, board_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_limit int;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN RETURN; END IF;
  -- Leitura pela API segue a política de leitura da tabela (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;

  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 100), 500));

  RETURN QUERY
  SELECT
    pc.id, pc.link_role, pc.notes, pc.created_at, cm.name,
    pe.id, pe.name, pe.chapter, pe.status,
    bi.id, bi.title, bi.status, bi.due_date, am.name,
    bi.board_id, pb.board_name
  FROM public.partner_cards pc
  JOIN public.partner_entities pe ON pe.id = pc.partner_entity_id
  JOIN public.board_items bi ON bi.id = pc.board_item_id
  LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
  LEFT JOIN public.members am ON am.id = bi.assignee_id
  LEFT JOIN public.members cm ON cm.id = pc.created_by
  WHERE (p_link_role IS NULL OR pc.link_role = p_link_role)
    AND (p_card_status IS NULL OR bi.status = p_card_status)
    AND (p_chapter IS NULL OR pe.chapter = p_chapter)
    AND public.rls_can_see_item(bi.id)
  ORDER BY pc.created_at DESC
  LIMIT v_limit;
END;
$function$;
