-- Migration: initiative feature parity + events fix + WhatsApp links
-- Rollback: UPDATE initiative_kinds SET has_attendance=false, has_certificate=false WHERE slug IN ('workgroup','committee');
--           -- Revert get_initiative_events_timeline to bridge version
--           -- Remove whatsapp_url from initiatives.metadata

-- 1. Enable attendance + certificate for workgroup and committee
UPDATE initiative_kinds
SET has_attendance = true, has_certificate = true
WHERE slug IN ('workgroup', 'committee');

-- 2. Store WhatsApp links in initiative metadata
UPDATE initiatives
SET metadata = metadata || '{"whatsapp_url": "https://chat.whatsapp.com/Je41n66sNYD0kv9mWrpZzK"}'::jsonb
WHERE id = '9ea82b09-55c6-4cc3-ab7f-178518d0ab47';

UPDATE initiatives
SET metadata = metadata || '{"whatsapp_url": "https://chat.whatsapp.com/I4rEk1Koz7TIhc77rS3cTr", "whatsapp_note": "Grupo administrativo do preparatório. Estudantes terão board e grupo próprios."}'::jsonb
WHERE id = '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19';

-- 3. Fix get_initiative_events_timeline: query by initiative_id directly (not tribe bridge)
CREATE OR REPLACE FUNCTION public.get_initiative_events_timeline(
  p_initiative_id uuid,
  p_upcoming_limit integer DEFAULT 3,
  p_past_limit integer DEFAULT 5
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_upcoming jsonb;
  v_past jsonb;
  v_today date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'date'), '[]'::jsonb)
  INTO v_upcoming
  FROM (
    SELECT jsonb_build_object(
      'id', e.id, 'title', e.title, 'date', e.date, 'type', e.type,
      'duration_minutes', COALESCE(e.duration_minutes, 60),
      'meeting_link', e.meeting_link, 'agenda_text', e.agenda_text
    ) as row_data
    FROM events e
    WHERE e.initiative_id = p_initiative_id AND e.date >= v_today
    ORDER BY e.date ASC LIMIT p_upcoming_limit
  ) sub;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'date') DESC), '[]'::jsonb)
  INTO v_past
  FROM (
    SELECT jsonb_build_object(
      'id', e.id, 'title', e.title, 'date', e.date, 'type', e.type,
      'duration_minutes', COALESCE(e.duration_actual, e.duration_minutes, 60),
      'recording_url', e.recording_url, 'youtube_url', e.youtube_url,
      'has_recording', (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL),
      'minutes_text', e.minutes_text,
      'has_minutes', (e.minutes_text IS NOT NULL AND e.minutes_text != ''),
      'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true)
    ) as row_data
    FROM events e
    WHERE e.initiative_id = p_initiative_id AND e.date < v_today
    ORDER BY e.date DESC LIMIT p_past_limit
  ) sub;

  RETURN jsonb_build_object('upcoming', v_upcoming, 'past', v_past);
END;
$function$;

-- 4. Add metadata to get_initiative_detail response
CREATE OR REPLACE FUNCTION public.get_initiative_detail(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_initiative record;
  v_kind_config jsonb;
  v_board_id uuid;
  v_leader jsonb;
  v_member_count integer;
  v_engagement_summary jsonb;
  v_user_engagement jsonb;
  v_caller_person_id uuid;
BEGIN
  SELECT p.id INTO v_caller_person_id
  FROM persons p WHERE p.auth_id = auth.uid();

  SELECT i.id, i.title, i.kind, i.status, i.description,
         i.legacy_tribe_id, i.metadata, i.created_at
  INTO v_initiative
  FROM initiatives i WHERE i.id = p_initiative_id;

  IF v_initiative IS NULL THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  SELECT jsonb_build_object(
    'slug', ik.slug, 'display_name', ik.display_name, 'icon', ik.icon,
    'has_board', ik.has_board, 'has_meeting_notes', ik.has_meeting_notes,
    'has_deliverables', ik.has_deliverables, 'has_attendance', ik.has_attendance,
    'has_certificate', ik.has_certificate,
    'allowed_engagement_kinds', ik.allowed_engagement_kinds
  ) INTO v_kind_config
  FROM initiative_kinds ik WHERE ik.slug = v_initiative.kind;

  SELECT pb.id INTO v_board_id
  FROM project_boards pb
  WHERE pb.initiative_id = p_initiative_id AND pb.is_active = true LIMIT 1;

  SELECT jsonb_build_object(
    'person_id', p.id, 'name', COALESCE(p.name, m.name),
    'photo_url', COALESCE(p.photo_url, m.photo_url), 'role', e.role
  ) INTO v_leader
  FROM engagements e
  JOIN persons p ON p.id = e.person_id
  LEFT JOIN members m ON m.id = p.legacy_member_id
  WHERE e.initiative_id = p_initiative_id AND e.status = 'active' AND e.role = 'leader'
  LIMIT 1;

  SELECT count(*) INTO v_member_count
  FROM engagements e WHERE e.initiative_id = p_initiative_id AND e.status = 'active';

  SELECT coalesce(jsonb_agg(row_to_json(s)), '[]'::jsonb) INTO v_engagement_summary
  FROM (
    SELECT e.kind, e.role, count(*) as count
    FROM engagements e
    WHERE e.initiative_id = p_initiative_id AND e.status = 'active'
    GROUP BY e.kind, e.role ORDER BY e.kind, e.role
  ) s;

  IF v_caller_person_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'engagement_id', e.id, 'kind', e.kind, 'role', e.role,
      'status', e.status, 'start_date', e.start_date
    ) INTO v_user_engagement
    FROM engagements e
    WHERE e.initiative_id = p_initiative_id AND e.person_id = v_caller_person_id AND e.status = 'active'
    LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'initiative', jsonb_build_object(
      'id', v_initiative.id, 'title', v_initiative.title, 'kind', v_initiative.kind,
      'status', v_initiative.status, 'description', v_initiative.description,
      'legacy_tribe_id', v_initiative.legacy_tribe_id, 'created_at', v_initiative.created_at,
      'metadata', COALESCE(v_initiative.metadata, '{}'::jsonb)
    ),
    'kind_config', v_kind_config, 'board_id', v_board_id, 'leader', v_leader,
    'member_count', v_member_count, 'engagement_summary', v_engagement_summary,
    'user_engagement', v_user_engagement
  );
END;
$function$;
