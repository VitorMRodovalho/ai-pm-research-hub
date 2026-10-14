-- #2697: convidado de evento de lideranca ve o evento; gravar convidados exige autoridade.
--
-- (1) set_event_invited_members: era SECURITY DEFINER sem portao e executavel por anon/PUBLIC
--     (o anon parava so no auth.uid()). Como (2) faz o convite conceder leitura, a gravacao passa
--     a exigir _manage_event_scope_ok sobre o evento. search_path preservado ('public','pg_temp'):
--     a captura antiga (20260314120003) nao o declarava e um CREATE OR REPLACE sem ele o zeraria.
-- (2) _caller_is_event_invitee + rls_can_see_event_tier de 3 argumentos: 'leadership' passa a
--     aceitar o convidado do proprio evento. 'gp_only' nao muda. A versao de 2 argumentos fica
--     intacta para os demais chamadores.
-- (3) get_event_detail, get_events_with_attendance e list_meetings_with_notes: corpos identicos
--     as capturas vigentes (md5 conferido contra o vivo em 14/10/2026), so com a troca acima.

CREATE OR REPLACE FUNCTION public._caller_is_event_invitee(p_event_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- #2697: o chamador esta na lista de convidados deste evento.
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.event_invited_members im
    JOIN public.members m ON m.id = im.member_id
    WHERE im.event_id = p_event_id
      AND m.auth_id = auth.uid()
  );
$function$;

CREATE OR REPLACE FUNCTION public.rls_can_see_event_tier(p_visibility text, p_initiative_id uuid, p_event_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- #2697: a regra de 2 argumentos, mais o convidado do proprio evento para 'leadership'.
  SELECT public.rls_can_see_event_tier(p_visibility, p_initiative_id)
    OR (p_visibility = 'leadership'
        AND p_event_id IS NOT NULL
        AND public._caller_is_event_invitee(p_event_id));
$function$;

CREATE OR REPLACE FUNCTION public.set_event_invited_members(p_event_id uuid, p_members jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_m jsonb;
  v_caller_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.events WHERE id = p_event_id) THEN
    RAISE EXCEPTION 'Event not found';
  END IF;
  -- #2697: a lista de convidados passa a conceder leitura de evento de lideranca,
  -- entao grava-la exige autoridade sobre ESTE evento.
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Requires manage_event permission for this event';
  END IF;
  DELETE FROM public.event_invited_members WHERE event_id = p_event_id;
  FOR v_m IN SELECT * FROM jsonb_array_elements(p_members) LOOP
    INSERT INTO public.event_invited_members (event_id, member_id, attendance_type, notes)
    VALUES (p_event_id, (v_m->>'member_id')::uuid, COALESCE(v_m->>'attendance_type','mandatory'), v_m->>'notes');
  END LOOP;
END; $$;

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
  v_engaged_confidential boolean;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Event not found'); END IF;

  IF NOT public.rls_can_see_initiative(v_event.initiative_id) THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  v_engaged_confidential := (v_event.initiative_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.initiatives i
    JOIN public.auth_engagements ae ON ae.initiative_id = i.id
    WHERE i.id = v_event.initiative_id
      AND i.visibility = 'confidential'
      AND ae.auth_id = auth.uid()
      AND ae.is_authoritative = true
  ));

  IF v_event.visibility = 'gp_only'
     AND NOT public.can_by_member(v_caller.id, 'manage_platform')
     AND NOT v_engaged_confidential THEN
    RETURN jsonb_build_object('error', 'Restricted content');
  END IF;

  -- #2697: o convidado do proprio evento (event_invited_members) ve o evento de lideranca.
  -- So 'leadership'; 'gp_only' acima nao muda.
  IF v_event.visibility = 'leadership'
     AND NOT public.can_by_member(v_caller.id, 'manage_event')
     AND NOT v_engaged_confidential
     AND NOT public._caller_is_event_invitee(p_event_id) THEN
    RETURN jsonb_build_object('error', 'Restricted content');
  END IF;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  SELECT jsonb_build_object(
    'event', jsonb_build_object(
      'id', v_event.id,
      'title', v_event.title,
      'date', v_event.date,
      'type', v_event.type,
      'tribe_id', v_event_tribe_id,
      'duration_minutes', v_event.duration_minutes,
      'duration_actual', v_event.duration_actual,
      'meeting_link', v_event.meeting_link,
      'is_recorded', v_event.is_recorded,
      'youtube_url', v_event.youtube_url,
      'recording_url', v_event.recording_url,
      'recording_type', v_event.recording_type,
      'visibility', v_event.visibility
    ),
    'agenda', jsonb_build_object(
      'text', v_event.agenda_text,
      'url', v_event.agenda_url,
      'posted_at', v_event.agenda_posted_at,
      'posted_by', (SELECT m.name FROM members m WHERE m.id = v_event.agenda_posted_by)
    ),
    'minutes', jsonb_build_object(
      'text', v_event.minutes_text,
      'url', v_event.minutes_url,
      'posted_at', v_event.minutes_posted_at,
      'posted_by', (SELECT m.name FROM members m WHERE m.id = v_event.minutes_posted_by)
    ),
    'action_items', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', ai.id,
        'description', ai.description,
        'assignee_id', ai.assignee_id,
        'assignee_name', COALESCE(ai.assignee_name, am.name),
        'due_date', ai.due_date,
        'status', ai.status,
        'carried_to_event_id', ai.carried_to_event_id
      ) ORDER BY ai.created_at), '[]'::jsonb)
      FROM meeting_action_items ai
      LEFT JOIN members am ON am.id = ai.assignee_id
      WHERE ai.event_id = p_event_id AND ai.status != 'cancelled'
    ),
    'attendance', jsonb_build_object(
      -- #2278: conta PRESENTES, nao linhas. `COUNT(*)` respondia 43 onde havia 37.
      'present_count', (SELECT COUNT(*) FROM attendance
                         WHERE event_id = p_event_id AND present IS TRUE),
      -- #2278: explicito, para que ninguem precise inferir ausencia por subtracao.
      'absent_count',  (SELECT COUNT(*) FROM attendance
                         WHERE event_id = p_event_id AND present IS NOT TRUE),
      'excused_count', (SELECT COUNT(*) FROM attendance
                         WHERE event_id = p_event_id AND excused IS TRUE),
      'record_count',  (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id),
      'members', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', a.member_id,
          'name', m.name,
          -- #2278: A CORRECAO. Era o literal `true`.
          'present', COALESCE(a.present, false),
          'excused', COALESCE(a.excused, false)
        ) ORDER BY m.name), '[]'::jsonb)
        FROM attendance a
        JOIN members m ON m.id = a.member_id
        WHERE a.event_id = p_event_id
      )
    ),
    'showcases', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', es.id,
        'member_id', es.member_id,
        'member_name', m.name,
        'showcase_type', es.showcase_type,
        'title', es.title,
        'duration_min', es.duration_min
      ) ORDER BY es.created_at), '[]'::jsonb)
      FROM event_showcases es
      JOIN members m ON m.id = es.member_id
      WHERE es.event_id = p_event_id
    )
  ) INTO v_result;

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
    AND public.rls_can_see_event_tier(e.visibility, e.initiative_id, e.id)
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
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
    AND public.rls_can_see_event_tier(e.visibility, e.initiative_id, e.id)
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
      AND public.rls_can_see_event_tier(e.visibility, e.initiative_id, e.id)
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

REVOKE ALL ON FUNCTION public.set_event_invited_members(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_event_invited_members(uuid, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public._caller_is_event_invitee(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._caller_is_event_invitee(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rls_can_see_event_tier(text, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rls_can_see_event_tier(text, uuid, uuid) TO anon, authenticated;
