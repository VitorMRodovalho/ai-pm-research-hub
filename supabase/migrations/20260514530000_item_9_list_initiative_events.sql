-- Item 9 (handoff 2026-04-25): list_initiative_events RPC.
-- Bloqueia 8+ workflows do líder (handoff Tabela). Hoje nenhuma rota lista
-- eventos passados de tribo/iniciativa com event_ids. Sintoma de design:
-- sistema construído com viés "presente + futuro", passado virou cego.
--
-- Spec: handoff Item 9. Permission tiering preserved.
-- Tribe derivation: events.initiative_id → initiatives.legacy_tribe_id (V4 path).

CREATE OR REPLACE FUNCTION public.list_initiative_events(
  p_tribe_id integer DEFAULT NULL,
  p_initiative_id uuid DEFAULT NULL,
  p_types text[] DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL,
  p_has_minutes boolean DEFAULT NULL,
  p_has_recording boolean DEFAULT NULL,
  p_has_attendance boolean DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_clamped_limit int;
  v_resolved_from date;
  v_resolved_to date;
  v_total int;
  v_result jsonb;
  v_target_tribe int;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_caller_id, 'manage_partner');

  IF p_initiative_id IS NOT NULL THEN
    SELECT legacy_tribe_id INTO v_target_tribe
    FROM public.initiatives WHERE id = p_initiative_id;
  ELSE
    v_target_tribe := p_tribe_id;
  END IF;

  IF v_is_admin THEN
    NULL;
  ELSIF v_is_stakeholder AND v_target_tribe IS NULL THEN
    NULL;
  ELSIF v_caller_role = 'tribe_leader' AND (v_target_tribe IS NULL OR v_target_tribe = v_caller_tribe) THEN
    NULL;
  ELSIF v_caller_role IN ('researcher', 'chapter_board') AND v_target_tribe = v_caller_tribe THEN
    NULL;
  ELSE
    RETURN jsonb_build_object('error', 'Unauthorized: insufficient access to requested events');
  END IF;

  v_clamped_limit := greatest(1, least(200, coalesce(p_limit, 50)));
  v_resolved_from := coalesce(p_date_from, current_date - interval '90 days');
  v_resolved_to := coalesce(p_date_to, current_date);

  WITH base AS (
    SELECT
      e.id, e.date, e.time_start, e.type, e.title,
      e.duration_minutes, e.duration_actual, e.meeting_link,
      e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) > 0 AS has_minutes,
      e.minutes_posted_at,
      e.youtube_url, e.recording_url, e.is_recorded, e.recording_type,
      e.nature, e.created_at,
      i.legacy_tribe_id AS tribe_id,
      i.id AS initiative_id,
      i.title AS initiative_title,
      (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id) AS attendance_count,
      (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id AND a.present = true) AS attendance_present_count,
      (SELECT count(*) FROM public.event_showcases s WHERE s.event_id = e.id) AS showcase_count,
      (SELECT count(*) FROM public.meeting_action_items m WHERE m.event_id = e.id AND m.status NOT IN ('done', 'cancelled')) AS action_items_open
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_resolved_from
      AND e.date <= v_resolved_to
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND (p_initiative_id IS NULL OR i.id = p_initiative_id)
      AND (p_types IS NULL OR e.type = ANY(p_types))
      AND (NOT (v_is_stakeholder AND NOT v_is_admin) OR e.type IN ('geral', 'kickoff', 'lideranca'))
  ),
  filtered AS (
    SELECT * FROM base
    WHERE
      (p_has_minutes IS NULL OR base.has_minutes = p_has_minutes)
      AND (p_has_recording IS NULL OR (base.youtube_url IS NOT NULL OR base.recording_url IS NOT NULL) = p_has_recording)
      AND (p_has_attendance IS NULL OR (base.attendance_count > 0) = p_has_attendance)
  )
  SELECT
    count(*)::int,
    coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id,
      'date', f.date,
      'time_start', f.time_start,
      'type', f.type,
      'title', f.title,
      'duration_minutes', f.duration_minutes,
      'duration_actual', f.duration_actual,
      'meeting_link', f.meeting_link,
      'minutes_text_present', f.has_minutes,
      'minutes_posted_at', f.minutes_posted_at,
      'youtube_url', f.youtube_url,
      'recording_url', f.recording_url,
      'is_recorded', f.is_recorded,
      'recording_type', f.recording_type,
      'tribe_id', f.tribe_id,
      'initiative_id', f.initiative_id,
      'initiative_title', f.initiative_title,
      'attendance_count', f.attendance_count,
      'attendance_present_count', f.attendance_present_count,
      'showcase_count', f.showcase_count,
      'action_items_open', f.action_items_open,
      'nature', f.nature
    ) ORDER BY f.date DESC, f.time_start DESC NULLS LAST), '[]'::jsonb)
  INTO v_total, v_result
  FROM (
    SELECT * FROM filtered
    ORDER BY date DESC, time_start DESC NULLS LAST
    OFFSET p_offset
    LIMIT v_clamped_limit
  ) f;

  RETURN jsonb_build_object(
    'total_count', v_total,
    'limit', v_clamped_limit,
    'offset', p_offset,
    'date_from', v_resolved_from,
    'date_to', v_resolved_to,
    'events', v_result
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_initiative_events(integer, uuid, text[], date, date, boolean, boolean, boolean, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_initiative_events(integer, uuid, text[], date, date, boolean, boolean, boolean, integer, integer) TO authenticated;

COMMENT ON FUNCTION public.list_initiative_events(integer, uuid, text[], date, date, boolean, boolean, boolean, integer, integer) IS
'Item 9 (handoff 2026-04-25): lista eventos passados/futuros de tribo ou iniciativa. Bloqueia 8+ workflows do líder. Filtros: tribe_id|initiative_id, types[], date_from/to (default últimos 90d), has_minutes/recording/attendance. Permission: admin (all), TL (own tribe + general), researcher (own tribe), sponsor/liaison (general only).';

NOTIFY pgrst, 'reload schema';
