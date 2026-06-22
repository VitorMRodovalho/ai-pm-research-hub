-- #785 follow-up — close confidential-initiative gate gaps on event / roster / stats read RPCs.
--
-- PR-3 (20260805000233) gated the initiative/board/artifact read RPCs, but THREE
-- member-callable SECURITY DEFINER read paths were missed and leaked a confidential
-- initiative's data to ANY authenticated member (verified live, non-engaged identity):
--   * get_initiative_members          -> leaked the full roster (names + photos)
--   * get_initiative_stats            -> leaked card counts + contributor names
--   * get_initiative_events_timeline  -> leaked events (titles/dates/minutes) once linked
--
-- This migration adds public.rls_can_see_initiative(...) to those three (behavior-neutral
-- for standard / null-initiative cases -- the helper returns true there), and hardens
-- get_event_detail with the same gate PLUS an engaged-member bypass so members engaged in
-- a CONFIDENTIAL initiative can open that committee's own meetings (incl. gp_only 1:1s).
--
-- See ADR-0105 (#785) + docs/reference/V4_AUTHORITY_MODEL.md (decision #5: any SECDEF read
-- RPC over initiative-linked tables MUST apply the gate).
--
-- NOTE: function bodies below are byte-equivalent (modulo whitespace) to what was applied
-- via apply_migration -- inline comments are intentionally omitted from the bodies because
-- the Phase-C body-hash drift gate counts comments inside prosrc.

CREATE OR REPLACE FUNCTION public.get_initiative_members(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(m) ORDER BY m.role_order, m.name), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      e.id as engagement_id,
      e.kind,
      e.role,
      e.status,
      e.start_date,
      p.id as person_id,
      COALESCE(p.name, mb.name) as name,
      COALESCE(p.photo_url, mb.photo_url) as photo_url,
      mb.id as member_id,
      ek.display_name as kind_display,
      CASE e.role
        WHEN 'leader' THEN 0
        WHEN 'coordinator' THEN 1
        WHEN 'participant' THEN 2
        WHEN 'observer' THEN 3
        ELSE 4
      END as role_order
    FROM engagements e
    JOIN persons p ON p.id = e.person_id
    LEFT JOIN members mb ON mb.id = p.legacy_member_id
    LEFT JOIN engagement_kinds ek ON ek.slug = e.kind
    WHERE e.initiative_id = p_initiative_id
      AND e.status = 'active'
  ) m;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_initiative_stats(p_initiative_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_tribe_id int;
BEGIN
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
      ) FROM att a),
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
$$;

CREATE OR REPLACE FUNCTION public.get_initiative_events_timeline(p_initiative_id uuid, p_upcoming_limit integer DEFAULT 5, p_past_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
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
      'minutes_text', e.minutes_text,
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
$$;

CREATE OR REPLACE FUNCTION public.get_event_detail(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
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
  IF v_event.visibility = 'leadership'
     AND NOT public.can_by_member(v_caller.id, 'manage_event')
     AND NOT v_engaged_confidential THEN
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
$$;

NOTIFY pgrst, 'reload schema';
