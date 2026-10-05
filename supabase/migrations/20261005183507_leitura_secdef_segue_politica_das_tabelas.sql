-- Funções de leitura SECURITY DEFINER seguem a política de leitura das tabelas que leem.
--
-- Desde 20260805000246 (e 20260925183649 para colunas de events), as tabelas de cards, presença,
-- reuniões e submissões só deixam ler, pela API, membro com vínculo vigente
-- (rls_is_authoritative_member()), com as exceções de linha própria da própria política. Estas funções
-- são SECURITY DEFINER e não passavam por essas políticas. Passam a aplicar a mesma regra a quem
-- chama pela API (_request_is_rest_caller(), #684). Chamadas internas seguem iguais.
-- Exceções preservadas: o autor principal lê a própria submissão; cada pessoa lê os próprios eventos
-- próximos; membro sem vínculo vigente segue vendo a lista de eventos, sem ata, notas e convidados
-- externos.

CREATE OR REPLACE FUNCTION public.get_card_detail(p_card_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_card record;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN NULL; END IF;
  -- Leitura pela API segue a política de leitura de board_items.
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN NULL; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = p_card_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Card not found: %', p_card_id; END IF;

  -- #785 PR-3: confidential gate (board→initiative; same 'not found' to avoid leaking existence)
  IF NOT public.rls_can_see_board(v_card.board_id) THEN
    RAISE EXCEPTION 'Card not found: %', p_card_id;
  END IF;

  RETURN jsonb_build_object(
    'card', to_jsonb(v_card),
    'board', (
      SELECT jsonb_build_object(
        'id', pb.id,
        'name', pb.board_name,
        'initiative_id', pb.initiative_id,
        'domain_key', pb.domain_key
      )
      FROM project_boards pb WHERE pb.id = v_card.board_id
    ),
    'assignee', (
      SELECT jsonb_build_object('id', m.id, 'name', m.name, 'operational_role', m.operational_role)
      FROM members m WHERE m.id = v_card.assignee_id
    ),
    'reviewer', (
      SELECT jsonb_build_object('id', m.id, 'name', m.name)
      FROM members m WHERE m.id = v_card.reviewer_id
    ),
    'checklist', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ci.id,
        'text', ci.text,
        'is_completed', ci.is_completed,
        'position', ci.position,
        'assigned_to', ci.assigned_to,
        'assigned_to_name', (SELECT m.name FROM members m WHERE m.id = ci.assigned_to),
        'target_date', ci.target_date,
        'completed_at', ci.completed_at,
        'completed_by', ci.completed_by,
        'assigned_at', ci.assigned_at
      ) ORDER BY ci.position, ci.created_at)
      FROM board_item_checklists ci WHERE ci.board_item_id = p_card_id
    ), '[]'::jsonb),
    'assignments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', ba.member_id,
        'member_name', (SELECT m.name FROM members m WHERE m.id = ba.member_id),
        'role', ba.role,
        'assigned_at', ba.assigned_at
      ))
      FROM board_item_assignments ba WHERE ba.item_id = p_card_id
    ), '[]'::jsonb),
    'timeline', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'action', ble.action,
        'reason', ble.reason,
        'actor_member_id', ble.actor_member_id,
        'actor_name', (SELECT m.name FROM members m WHERE m.id = ble.actor_member_id),
        'created_at', ble.created_at,
        'previous_status', ble.previous_status,
        'new_status', ble.new_status
      ) ORDER BY ble.created_at DESC)
      FROM (
        SELECT * FROM board_lifecycle_events
        WHERE item_id = p_card_id
        ORDER BY created_at DESC
        LIMIT 10
      ) ble
    ), '[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_item_assignments(p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_has_junction boolean;
BEGIN
  -- #785: confidential gate (item->board->initiative)
  IF NOT public.rls_can_see_item(p_item_id) THEN RETURN '[]'::jsonb; END IF;
  -- Leitura pela API segue a política de leitura de board_item_assignments.
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN '[]'::jsonb; END IF;
  SELECT EXISTS(SELECT 1 FROM board_item_assignments WHERE item_id = p_item_id)
  INTO v_has_junction;

  IF v_has_junction THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', bia.id,
      'member_id', bia.member_id,
      'name', m.name,
      'avatar_url', m.photo_url,
      'role', bia.role,
      'assigned_at', bia.assigned_at
    ) ORDER BY
      CASE bia.role
        WHEN 'author' THEN 0
        WHEN 'reviewer' THEN 1
        WHEN 'curation_reviewer' THEN 2
        WHEN 'contributor' THEN 3
      END,
      bia.assigned_at
    ), '[]'::jsonb) INTO v_result
    FROM board_item_assignments bia
    JOIN members m ON m.id = bia.member_id
    WHERE bia.item_id = p_item_id;
  ELSE
    -- Fallback: read from legacy assignee_id / reviewer_id
    SELECT coalesce(jsonb_agg(x ORDER BY x->>'role'), '[]'::jsonb) INTO v_result
    FROM (
      SELECT jsonb_build_object(
        'id', null,
        'member_id', bi.assignee_id,
        'name', am.name,
        'avatar_url', am.photo_url,
        'role', 'author',
        'assigned_at', bi.updated_at
      ) AS x
      FROM board_items bi
      LEFT JOIN members am ON am.id = bi.assignee_id
      WHERE bi.id = p_item_id AND bi.assignee_id IS NOT NULL
      UNION ALL
      SELECT jsonb_build_object(
        'id', null,
        'member_id', bi.reviewer_id,
        'name', rm.name,
        'avatar_url', rm.photo_url,
        'role', 'reviewer',
        'assigned_at', bi.updated_at
      )
      FROM board_items bi
      LEFT JOIN members rm ON rm.id = bi.reviewer_id
      WHERE bi.id = p_item_id AND bi.reviewer_id IS NOT NULL
    ) sub;
  END IF;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_card_comments(p_board_item_id uuid)
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

  -- Leitura pela API segue a política de leitura de board_items.
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  -- Anyone authenticated who can SELECT board_items can read comments
  IF NOT EXISTS (SELECT 1 FROM public.board_items WHERE id = p_board_item_id) THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  -- #785: confidential initiative visibility gate
  IF NOT public.rls_can_see_item(p_board_item_id) THEN
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
$function$;

CREATE OR REPLACE FUNCTION public.get_portfolio_dashboard(p_cycle integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_artifacts jsonb;
  v_summary jsonb;
  v_by_tribe jsonb;
  v_by_type jsonb;
  v_by_month jsonb;
BEGIN
  -- Leitura pela API segue a política de leitura de board_items.
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_agg(row_to_json(sub.*) ORDER BY sub.tribe_id, sub.baseline_date NULLS LAST)
  INTO v_artifacts
  FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.baseline_date, bi.forecast_date, bi.actual_completion_date,
      CASE
        WHEN bi.baseline_date IS NOT NULL AND bi.forecast_date IS NOT NULL
        THEN (bi.forecast_date - bi.baseline_date) ELSE NULL
      END AS variance_days,
      CASE
        WHEN bi.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN bi.baseline_date IS NULL OR bi.forecast_date IS NULL THEN 'no_baseline'
        WHEN CURRENT_DATE > bi.forecast_date THEN 'delayed'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END AS health,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      i.id AS initiative_id,
      i.kind AS initiative_kind,
      m.name AS leader_name,
      bi.tags AS legacy_tags,
      (SELECT jsonb_agg(jsonb_build_object('name', tg.name, 'label', tg.label_pt, 'color', tg.color))
       FROM board_item_tag_assignments bita JOIN tags tg ON tg.id = bita.tag_id
       WHERE bita.board_item_id = bi.id AND tg.name NOT IN ('entregavel_lider', 'ciclo_3')) AS unified_tags,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) AS checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) AS checklist_done,
      CASE WHEN bi.baseline_date IS NOT NULL THEN 'Q' || EXTRACT(QUARTER FROM bi.baseline_date)::text ELSE 'TBD' END AS quarter,
      CASE WHEN bi.baseline_date IS NOT NULL THEN to_char(bi.baseline_date, 'YYYY-MM') ELSE 'TBD' END AS baseline_month
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    LEFT JOIN members m ON m.id = bi.assignee_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle AND bi.is_portfolio_item = true
  ) sub;

  SELECT jsonb_build_object(
    'total_artifacts', count(*),
    'completed', count(*) FILTER (WHERE sub.health = 'completed'),
    'on_track', count(*) FILTER (WHERE sub.health = 'on_track'),
    'at_risk', count(*) FILTER (WHERE sub.health = 'at_risk'),
    'delayed', count(*) FILTER (WHERE sub.health = 'delayed'),
    'no_baseline', count(*) FILTER (WHERE sub.health = 'no_baseline'),
    'avg_variance_days', ROUND(AVG(sub.variance_days) FILTER (WHERE sub.variance_days IS NOT NULL), 1),
    'checklist_total', SUM(sub.checklist_total),
    'checklist_done', SUM(sub.checklist_done),
    'pct_with_baseline', ROUND(count(*) FILTER (WHERE sub.baseline_date IS NOT NULL)::numeric / NULLIF(count(*), 0) * 100, 1)
  )
  INTO v_summary
  FROM (
    SELECT bi.baseline_date, bi.forecast_date, bi.actual_completion_date,
      CASE
        WHEN bi.actual_completion_date IS NOT NULL THEN 'completed'
        WHEN bi.baseline_date IS NULL OR bi.forecast_date IS NULL THEN 'no_baseline'
        WHEN CURRENT_DATE > bi.forecast_date THEN 'delayed'
        WHEN bi.forecast_date <= bi.baseline_date THEN 'on_track'
        WHEN (bi.forecast_date - bi.baseline_date) <= 7 THEN 'at_risk'
        ELSE 'delayed'
      END AS health,
      (bi.forecast_date - bi.baseline_date) AS variance_days,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id) AS checklist_total,
      (SELECT count(*) FROM board_item_checklists bic WHERE bic.board_item_id = bi.id AND bic.is_completed = true) AS checklist_done
    FROM board_items bi
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle AND bi.is_portfolio_item = true
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'tribe_id', sub.tribe_id, 'tribe_name', sub.tribe_name,
    'initiative_id', sub.initiative_id, 'initiative_kind', sub.initiative_kind,
    'leader', sub.leader_name, 'total', sub.total,
    'completed', sub.completed, 'on_track', sub.on_track,
    'at_risk', sub.at_risk, 'delayed', sub.delayed,
    'no_baseline', sub.no_baseline, 'next_deadline', sub.next_deadline,
    'checklist_pct', sub.checklist_pct
  ) ORDER BY sub.tribe_id NULLS LAST, sub.tribe_name)
  INTO v_by_tribe
  FROM (
    SELECT
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      i.id AS initiative_id,
      i.kind AS initiative_kind,
      m.name AS leader_name,
      count(*) AS total,
      count(*) FILTER (WHERE bi.actual_completion_date IS NOT NULL) AS completed,
      count(*) FILTER (
        WHERE bi.actual_completion_date IS NULL
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND bi.forecast_date <= bi.baseline_date
          AND CURRENT_DATE <= bi.forecast_date
      ) AS on_track,
      count(*) FILTER (
        WHERE bi.actual_completion_date IS NULL
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND (bi.forecast_date - bi.baseline_date) BETWEEN 1 AND 7
          AND CURRENT_DATE <= bi.forecast_date
      ) AS at_risk,
      count(*) FILTER (
        WHERE bi.actual_completion_date IS NULL
          AND bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
          AND ((bi.forecast_date - bi.baseline_date) > 7 OR CURRENT_DATE > bi.forecast_date)
      ) AS delayed,
      count(*) FILTER (WHERE bi.baseline_date IS NULL) AS no_baseline,
      MIN(bi.forecast_date) FILTER (WHERE bi.actual_completion_date IS NULL AND bi.forecast_date >= CURRENT_DATE) AS next_deadline,
      CASE WHEN SUM(chk.total) > 0 THEN ROUND(SUM(chk.done)::numeric / SUM(chk.total) * 100, 1) ELSE 0 END AS checklist_pct
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    LEFT JOIN members m ON m.id = bi.assignee_id
    LEFT JOIN LATERAL (
      SELECT count(*) AS total, count(*) FILTER (WHERE is_completed) AS done
      FROM board_item_checklists WHERE board_item_id = bi.id
    ) chk ON true
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle AND bi.is_portfolio_item = true
    GROUP BY i.legacy_tribe_id, i.title, i.id, i.kind, m.name
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'type', sub.tag_name, 'label', sub.tag_label, 'color', sub.tag_color, 'count', sub.cnt
  ) ORDER BY sub.cnt DESC)
  INTO v_by_type
  FROM (
    SELECT tg.name AS tag_name, tg.label_pt AS tag_label, tg.color AS tag_color, count(DISTINCT bi.id) AS cnt
    FROM board_items bi
    JOIN board_item_tag_assignments bita ON bita.board_item_id = bi.id
    JOIN tags tg ON tg.id = bita.tag_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND tg.name NOT IN ('entregavel_lider', 'ciclo_3')
      AND tg.tier = 'system' AND bi.is_portfolio_item = true
    GROUP BY tg.name, tg.label_pt, tg.color
  ) sub;

  SELECT jsonb_agg(jsonb_build_object(
    'month', sub.month, 'count', sub.cnt, 'tribes', sub.tribes
  ) ORDER BY sub.month)
  INTO v_by_month
  FROM (
    SELECT
      to_char(bi.baseline_date, 'YYYY-MM') AS month,
      count(*) AS cnt,
      jsonb_agg(DISTINCT i.legacy_tribe_id) AS tribes
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    LEFT JOIN initiatives i ON i.id = pb.initiative_id
    WHERE bi.status <> 'archived' AND bi.cycle = p_cycle
      AND bi.baseline_date IS NOT NULL AND bi.is_portfolio_item = true
    GROUP BY to_char(bi.baseline_date, 'YYYY-MM')
  ) sub;

  v_result := jsonb_build_object(
    'cycle', p_cycle,
    'generated_at', now(),
    'summary', COALESCE(v_summary, '{}'::jsonb),
    'artifacts', COALESCE(v_artifacts, '[]'::jsonb),
    'by_tribe', COALESCE(v_by_tribe, '[]'::jsonb),
    'by_type', COALESCE(v_by_type, '[]'::jsonb),
    'by_month', COALESCE(v_by_month, '[]'::jsonb)
  );

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_meeting_detail(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Leitura pela API segue a política de leitura das tabelas de reunião e presença.
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  -- #785 PR-3: confidential gate (event→initiative; SECDEF bypasses RLS so this subquery is safe)
  IF NOT public.rls_can_see_initiative((SELECT e.initiative_id FROM events e WHERE e.id = p_event_id)) THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  SELECT jsonb_build_object(
    'event', jsonb_build_object(
      'id', e.id, 'title', e.title, 'date', e.date, 'type', e.type,
      'tribe_id', i.legacy_tribe_id,
      'tribe_name', i.title,
      'duration_minutes', e.duration_minutes, 'time_start', e.time_start,
      'meeting_link', e.meeting_link,
      'youtube_url', e.youtube_url, 'recording_url', e.recording_url,
      'agenda_text', e.agenda_text,
      'minutes_text', e.minutes_text,
      'notes', e.notes
    ),
    'attendance', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', a.member_id, 'member_name', m.name,
        'present', a.present, 'excused', a.excused
      ) ORDER BY m.name)
      FROM attendance a JOIN members m ON m.id = a.member_id
      WHERE a.event_id = e.id
    ), '[]'::jsonb),
    'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true)
  ) INTO v_result
  FROM events e
  LEFT JOIN initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_events_with_attendance(p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, title text, date date, type text, nature text, duration_minutes integer, time_start time without time zone, timezone text, meeting_link text, youtube_url text, is_recorded boolean, audience_level text, tribe_id integer, attendee_count bigint, agenda_text text, agenda_url text, minutes_text text, minutes_url text, recording_url text, recording_type text, notes text, visibility text, external_attendees text[], recurrence_group uuid, initiative_id uuid, initiative_name text, status text, cancelled_at timestamp with time zone, cancellation_reason text, i_attended boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- Leitura pela API segue a política de events: sem cadastro de membro, nada; ata, notas e convidados
  -- externos (colunas sem leitura direta desde 20260925183649) só para membro com vínculo vigente.
  WITH g AS (
    SELECT (NOT public._request_is_rest_caller() OR public.rls_is_authoritative_member()) AS full_read,
           (NOT public._request_is_rest_caller() OR public.rls_is_member()) AS any_member
  )
  SELECT
    e.id, e.title, e.date, e.type, e.nature,
    e.duration_minutes, e.time_start, e.timezone, e.meeting_link,
    e.youtube_url, e.is_recorded, e.audience_level,
    i.legacy_tribe_id AS tribe_id,
    (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id AND a.present = true) AS attendee_count,
    e.agenda_text, e.agenda_url,
    CASE WHEN g.full_read THEN e.minutes_text END, e.minutes_url,
    e.recording_url, e.recording_type,
    CASE WHEN g.full_read THEN e.notes END, e.visibility,
    CASE WHEN g.full_read THEN e.external_attendees END, e.recurrence_group,
    e.initiative_id,
    i.title AS initiative_name,
    e.status, e.cancelled_at, e.cancellation_reason,
    -- #1321: did the CURRENT caller mark present for this event? (anon -> false)
    EXISTS (
      SELECT 1 FROM public.attendance a
      WHERE a.event_id = e.id
        AND a.present = true
        AND a.member_id = (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid())
    ) AS i_attended
  FROM public.events e
  CROSS JOIN g
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE g.any_member
    AND (public.rls_can_see_initiative(e.initiative_id) OR auth.uid() IS NULL)
    AND public.rls_can_see_event_tier(e.visibility, e.initiative_id)
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
$function$;

CREATE OR REPLACE FUNCTION public.get_tribe_stats(p_tribe_id integer)
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- Leitura pela API segue a política de leitura de presença e membros (nomes e taxas por pessoa).
  WITH gate AS (SELECT (NOT public._request_is_rest_caller() OR public.rls_is_authoritative_member()) AS ok),
  cycle AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1),
  tribe_members AS (
    SELECT DISTINCT vir.member_id AS id
    FROM v_initiative_roster vir
    WHERE vir.legacy_tribe_id = p_tribe_id AND vir.member_id IS NOT NULL
  ),
  tribe_events AS (
    SELECT e.id, e.duration_minutes
    FROM events e
    JOIN initiatives i ON i.id = e.initiative_id
    CROSS JOIN cycle c
    WHERE i.legacy_tribe_id = p_tribe_id AND e.type = 'tribo'
      AND e.date >= c.cycle_start AND e.date <= current_date
  ),
  att AS (
    SELECT a.event_id, a.member_id FROM attendance a
    JOIN tribe_events te ON te.id = a.event_id
    WHERE a.excused IS NOT TRUE
  ),
  tribe_boards AS (
    SELECT bi.id, bi.status FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    JOIN initiatives i ON i.id = pb.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id
  )
  SELECT json_build_object(
    'member_count', public.get_initiative_roster_count(public.resolve_initiative_id(p_tribe_id)),
    'events_held', (SELECT count(*) FROM tribe_events),
    'attendance_rate', ROUND((public.get_attendance_engagement_summary('tribe', p_tribe_id) ->> 'avg_rate')::numeric * 100, 1),
    -- #1656: mesmo valor sob o nome que declara a escala. 'attendance_rate' aqui SEMPRE foi 0-100,
    -- contra a convencao; e o par que sustentava o coalesce 'rate <= 1' no front.
    'attendance_pct', ROUND((public.get_attendance_engagement_summary('tribe', p_tribe_id) ->> 'avg_rate')::numeric * 100, 1),
    'impact_hours', (SELECT coalesce(round(sum(te.duration_minutes * sub.c)::numeric / 60, 1), 0)
      FROM tribe_events te JOIN (SELECT event_id, count(*) c FROM att GROUP BY event_id) sub ON sub.event_id = te.id),
    'cards_backlog', (SELECT count(*) FROM tribe_boards WHERE status = 'backlog'),
    'cards_in_progress', (SELECT count(*) FROM tribe_boards WHERE status = 'in_progress'),
    'cards_review', (SELECT count(*) FROM tribe_boards WHERE status = 'review'),
    'cards_done', (SELECT count(*) FROM tribe_boards WHERE status = 'done'),
    'top_contributors', (SELECT coalesce(json_agg(row_to_json(r) ORDER BY r.att_count DESC), '[]')
      FROM (
        SELECT m.name, count(a2.event_id) as att_count,
          round(count(a2.event_id)::numeric / NULLIF((SELECT count(*) FROM tribe_events), 0) * 100, 0) as rate
        FROM tribe_members tm
        JOIN members m ON m.id = tm.id
        LEFT JOIN att a2 ON a2.member_id = tm.id
        GROUP BY m.name
      ) r
    )
  )
  FROM gate WHERE gate.ok;
$function$;

CREATE OR REPLACE FUNCTION public.get_initiative_stats(p_initiative_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tribe_id int;
BEGIN
  -- Leitura pela API segue a política de leitura de presença e membros.
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN NULL;
  END IF;

  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN json_build_object('error', 'Initiative not found');
  END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_stats(v_tribe_id);
  END IF;

  RETURN (
    WITH cycle AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1),
    init_members AS (
      SELECT DISTINCT vir.member_id AS id, vir.name
      FROM v_initiative_roster vir
      WHERE vir.initiative_id = p_initiative_id AND vir.member_id IS NOT NULL
    ),
    init_events AS (
      SELECT e.id, COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes
      FROM events e, cycle c
      WHERE e.initiative_id = p_initiative_id AND e.date >= c.cycle_start AND e.date <= current_date
    ),
    att AS (
      SELECT a.event_id, a.member_id FROM attendance a
      JOIN init_events ie ON ie.id = a.event_id
      WHERE a.present = true AND a.excused IS NOT TRUE
    ),
    -- #2461: a taxa divide por roster x eventos, entao o numerador so conta quem esta no roster.
    -- Quem esteve presente sem estar no roster continua nas horas de impacto (att), nao na taxa.
    att_roster AS (
      SELECT a.event_id, a.member_id FROM att a
      WHERE a.member_id IN (SELECT im.id FROM init_members im)
    ),
    init_boards AS (
      SELECT bi.id, bi.status FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      WHERE pb.initiative_id = p_initiative_id
    )
    SELECT json_build_object(
      'member_count', public.get_initiative_roster_count(p_initiative_id),
      'events_held', (SELECT count(*) FROM init_events),
      'attendance_rate', (SELECT round(
        count(a.*)::numeric / NULLIF((SELECT count(*) FROM init_members) * (SELECT count(*) FROM init_events), 0) * 100, 0
      ) FROM att_roster a),
      -- #1656: mesmo valor sob o nome que declara a escala (ja era 0-100).
      'attendance_pct', (SELECT round(
        count(a.*)::numeric / NULLIF((SELECT count(*) FROM init_members) * (SELECT count(*) FROM init_events), 0) * 100, 0
      ) FROM att_roster a),
      'impact_hours', (SELECT coalesce(round(sum(ie.duration_minutes * sub.c)::numeric / 60, 1), 0)
        FROM init_events ie JOIN (SELECT event_id, count(*) c FROM att GROUP BY event_id) sub ON sub.event_id = ie.id),
      'cards_backlog', (SELECT count(*) FROM init_boards WHERE status = 'backlog'),
      'cards_in_progress', (SELECT count(*) FROM init_boards WHERE status = 'in_progress'),
      'cards_review', (SELECT count(*) FROM init_boards WHERE status = 'review'),
      'cards_done', (SELECT count(*) FROM init_boards WHERE status = 'done'),
      'top_contributors', (SELECT coalesce(json_agg(row_to_json(r) ORDER BY r.att_count DESC), '[]')
        FROM (
          SELECT im.name, count(a2.event_id) as att_count,
            round(count(a2.event_id)::numeric / NULLIF((SELECT count(*) FROM init_events), 0) * 100, 0) as rate
          FROM init_members im
          LEFT JOIN att a2 ON a2.member_id = im.id
          GROUP BY im.name
        ) r
      )
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_near_events(p_member_id uuid, p_window_hours integer DEFAULT 2)
 RETURNS TABLE(event_id uuid, event_title text, event_date date, event_type text, duration_minutes integer, already_checked_in boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tribe_id int;
  v_caller uuid;
BEGIN
  -- Pela API, cada pessoa vê os próprios eventos próximos; quem gere membros vê de qualquer um.
  IF public._request_is_rest_caller() THEN
    SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;
    IF v_caller IS NULL OR (p_member_id IS DISTINCT FROM v_caller AND NOT public.can_by_member(v_caller, 'manage_member')) THEN
      RETURN;
    END IF;
  END IF;

  SELECT m.tribe_id INTO v_tribe_id
  FROM public.members m WHERE m.id = p_member_id;

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.date,
    e.type,
    e.duration_minutes,
    EXISTS(
      SELECT 1 FROM public.attendance a
      WHERE a.event_id = e.id AND a.member_id = p_member_id
    )
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.date::timestamptz BETWEEN
        now() - (p_window_hours || ' hours')::interval
    AND now() + (p_window_hours || ' hours')::interval
    AND (e.initiative_id IS NULL OR i.legacy_tribe_id = v_tribe_id)
    AND public.rls_can_see_initiative(e.initiative_id)  -- #785 PR-3: confidential gate
  ORDER BY e.date ASC
  LIMIT 3;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_publication_submissions(p_status submission_status DEFAULT NULL::submission_status, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS TABLE(id uuid, title text, abstract text, target_type submission_target_type, target_name text, status submission_status, submission_date date, presentation_date date, primary_author_name text, tribe_name text, estimated_cost_brl numeric, actual_cost_brl numeric, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    ps.id, ps.title, ps.abstract, ps.target_type, ps.target_name,
    ps.status, ps.submission_date, ps.presentation_date,
    m.name AS primary_author_name,
    i.title AS tribe_name,
    ps.estimated_cost_brl, ps.actual_cost_brl, ps.created_at
  FROM public.publication_submissions ps
  LEFT JOIN public.members m ON m.id = ps.primary_author_id
  LEFT JOIN public.initiatives i ON i.id = ps.initiative_id
  WHERE (p_status IS NULL OR ps.status = p_status)
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    -- Leitura pela API segue a política de publication_submissions: vínculo vigente ou autor principal.
    AND (NOT public._request_is_rest_caller() OR public.rls_is_authoritative_member()
         OR ps.primary_author_id IN (SELECT m2.id FROM public.members m2 WHERE m2.auth_id = auth.uid()))
  ORDER BY ps.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_publication_submission_detail(p_submission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  -- Leitura pela API segue a política de publication_submissions: vínculo vigente ou autor principal.
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member()
     AND NOT EXISTS (
       SELECT 1 FROM public.publication_submissions ps0
       JOIN public.members m0 ON m0.id = ps0.primary_author_id
       WHERE ps0.id = p_submission_id AND m0.auth_id = auth.uid()
     ) THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'submission', jsonb_build_object(
      'id', ps.id, 'title', ps.title, 'abstract', ps.abstract,
      'target_type', ps.target_type::text, 'target_name', ps.target_name,
      'target_url', ps.target_url, 'status', ps.status::text,
      'submission_date', ps.submission_date, 'review_deadline', ps.review_deadline,
      'acceptance_date', ps.acceptance_date, 'presentation_date', ps.presentation_date,
      'primary_author_id', ps.primary_author_id, 'primary_author_name', m.name,
      'estimated_cost_brl', ps.estimated_cost_brl, 'actual_cost_brl', ps.actual_cost_brl,
      'cost_paid_by', ps.cost_paid_by, 'reviewer_feedback', ps.reviewer_feedback,
      'doi_or_url', ps.doi_or_url,
      'tribe_id', i.legacy_tribe_id, 'tribe_name', i.title,
      'board_item_id', ps.board_item_id, 'created_by', ps.created_by,
      'created_at', ps.created_at, 'updated_at', ps.updated_at
    ),
    'authors', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', psa.id, 'member_id', psa.member_id, 'member_name', am.name,
        'author_order', psa.author_order, 'is_corresponding', psa.is_corresponding
      ) ORDER BY psa.author_order), '[]'::jsonb)
      FROM public.publication_submission_authors psa
      JOIN public.members am ON am.id = psa.member_id
      WHERE psa.submission_id = ps.id
    )
  )
  INTO v_result
  FROM public.publication_submissions ps
  LEFT JOIN public.members m ON m.id = ps.primary_author_id
  LEFT JOIN public.initiatives i ON i.id = ps.initiative_id
  WHERE ps.id = p_submission_id
    AND public.rls_can_see_initiative(ps.initiative_id)  -- #785
  ;
  RETURN v_result;
END; $function$;
