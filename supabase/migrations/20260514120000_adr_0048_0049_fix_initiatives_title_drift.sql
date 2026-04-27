-- Hotfix: forward-only patch for `initiatives.name` reference.
-- Column is `initiatives.title`, not `name`. Affects:
--   * get_meeting_preparation (ADR-0048 p72) — broken since shipped
--   * get_agenda_smart (ADR-0049 p73) — broken on first apply
--   * get_tribe_housekeeping (ADR-0049 p73) — broken on first apply
--
-- This migration restores the canonical body of all three RPCs with the column corrected.
-- Refer to ADR-0048 + ADR-0049 docs for the full surface contract.

-- 1) get_meeting_preparation — restore from ADR-0048 with i.title fix

CREATE OR REPLACE FUNCTION public.get_meeting_preparation(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
    SELECT i.id, i.title, i.kind, i.legacy_tribe_id
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
      jsonb_build_object('id', v_initiative.id, 'title', v_initiative.title,
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
$$;

-- 2) get_agenda_smart — fix initiatives.name -> title (bodies match 110000 corrected file)

CREATE OR REPLACE FUNCTION public.get_agenda_smart(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_event record;
  v_initiative record;
  v_legacy_tribe_id int;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  SELECT e.id, e.title, e.date, e.type, e.duration_minutes, e.meeting_link,
         e.initiative_id, e.agenda_text, e.agenda_url, e.time_start
  INTO v_event FROM public.events e WHERE e.id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  IF v_event.initiative_id IS NOT NULL THEN
    SELECT i.id, i.title, i.kind, i.legacy_tribe_id
    INTO v_initiative FROM public.initiatives i WHERE i.id = v_event.initiative_id;
    v_legacy_tribe_id := v_initiative.legacy_tribe_id;
  END IF;

  v_result := jsonb_build_object(
    'event', jsonb_build_object(
      'id', v_event.id,
      'title', v_event.title,
      'date', v_event.date,
      'time_start', v_event.time_start,
      'type', v_event.type,
      'duration_minutes', v_event.duration_minutes,
      'meeting_link', v_event.meeting_link,
      'agenda_text', v_event.agenda_text,
      'agenda_url', v_event.agenda_url
    ),
    'initiative', CASE WHEN v_initiative.id IS NOT NULL THEN
      jsonb_build_object('id', v_initiative.id, 'title', v_initiative.title,
        'kind', v_initiative.kind, 'legacy_tribe_id', v_initiative.legacy_tribe_id)
    ELSE NULL END,

    'carry_forward_actions', COALESCE((
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
        'days_overdue', CASE
          WHEN mai.due_date IS NOT NULL AND mai.due_date < CURRENT_DATE
          THEN (CURRENT_DATE - mai.due_date)
          ELSE 0 END,
        'days_open', GREATEST(0, EXTRACT(DAY FROM (now() - mai.created_at))::int),
        'board_item_id', mai.board_item_id
      ) ORDER BY
        CASE WHEN mai.due_date < CURRENT_DATE THEN 0 ELSE 1 END,
        mai.due_date NULLS LAST,
        mai.created_at DESC)
      FROM public.meeting_action_items mai
      JOIN public.events e2 ON e2.id = mai.event_id
      WHERE mai.resolved_at IS NULL
        AND e2.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND e2.id <> p_event_id
        AND e2.date < v_event.date
        AND mai.created_at >= (now() - interval '90 days')
        AND mai.kind IN ('action','followup')
    ), '[]'::jsonb),

    'at_risk_cards', COALESCE((
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
        'risk_reasons', jsonb_strip_nulls(jsonb_build_object(
          'forecast_slip', CASE WHEN bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
            AND bi.forecast_date > bi.baseline_date + INTERVAL '7 days'
            THEN (bi.forecast_date - bi.baseline_date) ELSE NULL END,
          'stale_days', CASE WHEN bi.updated_at < now() - interval '14 days'
            AND bi.status NOT IN ('done', 'archived')
            THEN EXTRACT(DAY FROM (now() - bi.updated_at))::int ELSE NULL END
        ))
      ) ORDER BY bi.updated_at ASC)
      FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.members am ON am.id = bi.assignee_id
      WHERE pb.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND pb.is_active = true
        AND bi.status NOT IN ('done','archived')
        AND (
          (bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
            AND bi.forecast_date > bi.baseline_date + INTERVAL '7 days')
          OR bi.updated_at < now() - interval '14 days'
        )
      LIMIT 30
    ), '[]'::jsonb),

    'relevant_kpis', COALESCE((
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
        'icon', akt.icon
      ) ORDER BY
        CASE WHEN COALESCE(akt.current_value, 0) < akt.target_value * 0.7 THEN 0 ELSE 1 END,
        akt.display_order)
      FROM public.tribe_kpi_contributions tkc
      JOIN public.annual_kpi_targets akt ON akt.id = tkc.kpi_target_id
      WHERE tkc.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND akt.target_value IS NOT NULL
        AND COALESCE(akt.current_value, 0) < akt.target_value * 0.9
    ), '[]'::jsonb),

    'showcase_candidates', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', m.id,
        'name', m.name,
        'photo_url', m.photo_url,
        'engagement_kind', ae.kind,
        'recent_completed_cards', (
          SELECT COUNT(*) FROM public.board_items bi
          JOIN public.project_boards pb ON pb.id = bi.board_id
          WHERE bi.assignee_id = m.id
            AND pb.initiative_id = v_event.initiative_id
            AND bi.status = 'done'
            AND bi.actual_completion_date >= CURRENT_DATE - INTERVAL '60 days'
        ),
        'has_unshowcased_artifact', EXISTS (
          SELECT 1 FROM public.board_items bi
          JOIN public.project_boards pb ON pb.id = bi.board_id
          WHERE bi.assignee_id = m.id
            AND pb.initiative_id = v_event.initiative_id
            AND bi.status = 'done'
            AND bi.actual_completion_date >= CURRENT_DATE - INTERVAL '60 days'
            AND NOT EXISTS (
              SELECT 1 FROM public.event_showcases es
              WHERE es.board_item_id = bi.id
                AND es.created_at >= CURRENT_DATE - INTERVAL '90 days'
            )
        )
      ) ORDER BY m.name)
      FROM public.members m
      JOIN public.persons p ON p.legacy_member_id = m.id
      JOIN public.auth_engagements ae ON ae.person_id = p.id
      WHERE m.is_active = true
        AND ae.is_authoritative = true
        AND ae.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.board_items bi2
          JOIN public.project_boards pb2 ON pb2.id = bi2.board_id
          WHERE bi2.assignee_id = m.id
            AND pb2.initiative_id = v_event.initiative_id
            AND bi2.status = 'done'
            AND bi2.actual_completion_date >= CURRENT_DATE - INTERVAL '60 days'
        )
    ), '[]'::jsonb),

    'at_risk_deliverables', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', td.id,
        'title', td.title,
        'cycle_code', td.cycle_code,
        'status', td.status,
        'assigned_member_id', td.assigned_member_id,
        'assignee_name', tdm.name,
        'due_date', td.due_date,
        'days_to_due', CASE WHEN td.due_date IS NOT NULL
          THEN (td.due_date - CURRENT_DATE) ELSE NULL END
      ) ORDER BY td.due_date NULLS LAST)
      FROM public.tribe_deliverables td
      LEFT JOIN public.members tdm ON tdm.id = td.assigned_member_id
      WHERE td.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND td.status NOT IN ('done','cancelled')
        AND (
          td.due_date IS NULL
          OR td.due_date <= CURRENT_DATE + INTERVAL '14 days'
        )
    ), '[]'::jsonb),

    'generated_at', now()
  );

  RETURN v_result;
END;
$$;

-- 3) get_tribe_housekeeping — fix initiatives.name -> title

CREATE OR REPLACE FUNCTION public.get_tribe_housekeeping(
  p_initiative_id uuid DEFAULT NULL,
  p_legacy_tribe_id integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_initiative record;
  v_current_cycle text;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

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
$$;

NOTIFY pgrst, 'reload schema';
