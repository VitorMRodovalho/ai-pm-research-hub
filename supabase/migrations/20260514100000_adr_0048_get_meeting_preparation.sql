-- ============================================================
-- ADR-0048: get_meeting_preparation RPC (#84 Onda 2 cont., 7/10)
-- Read-only prep pack for upcoming meetings.
-- Cross-references: ADR-0045 (schema), ADR-0046+0047 (action items + history), #84
-- Rollback: DROP this fn
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_meeting_preparation(
  p_event_id uuid
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_event record;
  v_initiative record;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  SELECT e.id, e.title, e.date, e.type, e.duration_minutes, e.meeting_link,
         e.initiative_id, e.agenda_text, e.agenda_url
  INTO v_event FROM public.events e WHERE e.id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  IF v_event.initiative_id IS NOT NULL THEN
    SELECT i.id, i.name, i.kind, i.legacy_tribe_id
    INTO v_initiative FROM public.initiatives i WHERE i.id = v_event.initiative_id;
  END IF;

  v_result := jsonb_build_object(
    'event', jsonb_build_object(
      'id', v_event.id,
      'title', v_event.title,
      'date', v_event.date,
      'type', v_event.type,
      'duration_minutes', v_event.duration_minutes,
      'meeting_link', v_event.meeting_link,
      'agenda_text', v_event.agenda_text,
      'agenda_url', v_event.agenda_url
    ),
    'initiative', CASE WHEN v_initiative.id IS NOT NULL THEN
      jsonb_build_object('id', v_initiative.id, 'name', v_initiative.name,
        'kind', v_initiative.kind, 'legacy_tribe_id', v_initiative.legacy_tribe_id)
    ELSE NULL END,
    'expected_attendees', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', m.id,
        'name', m.name,
        'operational_role', m.operational_role,
        'engagement_kind', ae.kind,
        'engagement_role', ae.role,
        'photo_url', m.photo_url
      ) ORDER BY m.name)
      FROM public.members m
      JOIN public.persons p ON p.legacy_member_id = m.id
      JOIN public.auth_engagements ae ON ae.person_id = p.id
      WHERE m.is_active = true
        AND ae.is_authoritative = true
        AND ae.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
    ), '[]'::jsonb),
    'pending_action_items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', mai.id,
        'event_id', mai.event_id,
        'event_title', e2.title,
        'event_date', e2.date,
        'description', mai.description,
        'kind', mai.kind,
        'assignee_name', mai.assignee_name,
        'assignee_id', mai.assignee_id,
        'due_date', mai.due_date,
        'days_open', GREATEST(0, EXTRACT(DAY FROM (now() - mai.created_at))::int)
      ) ORDER BY mai.due_date NULLS LAST, mai.created_at DESC)
      FROM public.meeting_action_items mai
      JOIN public.events e2 ON e2.id = mai.event_id
      WHERE mai.resolved_at IS NULL
        AND e2.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND e2.id <> p_event_id
        AND e2.date < v_event.date
        AND mai.created_at >= (now() - interval '90 days')
    ), '[]'::jsonb),
    'open_cards', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'curation_status', bi.curation_status,
        'assignee_id', bi.assignee_id,
        'assignee_name', am.name,
        'due_date', bi.due_date,
        'forecast_date', bi.forecast_date,
        'baseline_date', bi.baseline_date,
        'days_since_update', GREATEST(0, EXTRACT(DAY FROM (now() - bi.updated_at))::int),
        'tags', bi.tags,
        'is_at_risk', (
          (bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
            AND bi.forecast_date > bi.baseline_date + INTERVAL '7 days')
          OR (bi.updated_at < now() - interval '14 days' AND bi.status NOT IN ('done', 'archived'))
        )
      ) ORDER BY
        CASE WHEN bi.status NOT IN ('done', 'archived') THEN 0 ELSE 1 END,
        bi.due_date NULLS LAST, bi.updated_at DESC)
      FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.members am ON am.id = bi.assignee_id
      WHERE pb.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND pb.is_active = true
        AND bi.status NOT IN ('archived')
      LIMIT 50
    ), '[]'::jsonb),
    'recent_meetings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e3.id,
        'title', e3.title,
        'date', e3.date,
        'type', e3.type,
        'has_minutes', e3.minutes_text IS NOT NULL,
        'attendance_count', (SELECT COUNT(*) FROM public.attendance a WHERE a.event_id = e3.id),
        'open_actions_count', (
          SELECT COUNT(*) FROM public.meeting_action_items
          WHERE event_id = e3.id AND resolved_at IS NULL
        )
      ) ORDER BY e3.date DESC)
      FROM public.events e3
      WHERE e3.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND e3.id <> p_event_id
        AND e3.date < v_event.date
        AND e3.date >= (v_event.date - interval '60 days')
      LIMIT 5
    ), '[]'::jsonb),
    'generated_at', now()
  );

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_meeting_preparation(uuid) FROM anon;

NOTIFY pgrst, 'reload schema';
