-- ADR-0049: Meeting↔Board Traceability — Onda 2 closure (4 of 4 remaining RPCs)
--
-- Closes #84 Onda 2 to 11/11 (~100%):
--   * get_agenda_smart       — replaces dumb generate_agenda_template (5 sections)
--   * update_card_during_meeting — atomic card mutation + board_item_event_links
--   * meeting_close          — atomic close with drift signal counting
--   * get_tribe_housekeeping — KPI rollup using tribe_kpi_contributions (Onda 1 schema)
--
-- Prerequisites: ADR-0045 (schema hardening: board_item_event_links + tribe_kpi_contributions)
-- Cross-ref: ADR-0046/0047/0048 (action item lifecycle, card history, prep pack)
--
-- Rollback: DROP FUNCTION calls at the bottom (commented).
--
-- Audience:
--   * get_agenda_smart        — authenticated (read; downstream RLS at frontend join time)
--   * update_card_during_meeting — V4 write_board
--   * meeting_close           — V4 manage_event
--   * get_tribe_housekeeping  — authenticated

-- =====================================================================
-- RPC 1: get_agenda_smart(p_event_id uuid)
-- =====================================================================

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

    -- Section A: Carry-forward action items (90d, unresolved, prior)
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

    -- Section B: Cards at-risk (forecast slip OR staleness)
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

    -- Section C: Annual KPIs RED/YELLOW relevant to this initiative (via tribe_kpi_contributions)
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
        AND COALESCE(akt.current_value, 0) < akt.target_value * 0.9  -- RED or YELLOW only
    ), '[]'::jsonb),

    -- Section D: Showcase candidates — members in initiative with recent (60d) deliverable
    -- but NOT yet showcased in any prior event
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

    -- Section E: At-risk tribe_deliverables for this initiative (current cycle, due ≤14d or overdue)
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

COMMENT ON FUNCTION public.get_agenda_smart(uuid) IS
  'ADR-0049 #84 Onda 2: smart agenda. Returns event + carry-forward + at-risk cards + RED/YELLOW KPIs + showcase candidates + at-risk deliverables. Replaces dumb generate_agenda_template. Authenticated read.';

GRANT EXECUTE ON FUNCTION public.get_agenda_smart(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_agenda_smart(uuid) FROM PUBLIC, anon;


-- =====================================================================
-- RPC 2: update_card_during_meeting(p_card_id, p_event_id, p_new_status, p_fields, p_note)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.update_card_during_meeting(
  p_card_id uuid,
  p_event_id uuid,
  p_new_status text DEFAULT NULL,
  p_fields jsonb DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_card record;
  v_event record;
  v_old_status text;
  v_status_changed boolean := false;
  v_fields_applied boolean := false;
  v_link_type text;
  v_link_note text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- V4 gate: write_board (downstream RPCs do their own per-card auth too)
  IF NOT public.can_by_member(v_caller_id, 'write_board') THEN
    RAISE EXCEPTION 'Requires write_board permission';
  END IF;

  -- Resolve card pre-state
  SELECT id, status, organization_id, title INTO v_card
  FROM public.board_items WHERE id = p_card_id;
  IF v_card.id IS NULL THEN
    RETURN jsonb_build_object('error', 'card_not_found');
  END IF;
  v_old_status := v_card.status;

  -- Resolve event
  SELECT id, title, initiative_id INTO v_event
  FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  -- Status change via canonical mover (handles lifecycle event + auth)
  IF p_new_status IS NOT NULL AND p_new_status <> v_old_status THEN
    PERFORM public.move_board_item(
      p_card_id,
      p_new_status,
      NULL,
      COALESCE(p_note, 'Updated during meeting ' || COALESCE(v_event.title, p_event_id::text))
    );
    v_status_changed := true;
  END IF;

  -- Field updates via canonical mutator (handles lifecycle events + auth + baseline lock)
  IF p_fields IS NOT NULL AND p_fields <> '{}'::jsonb THEN
    PERFORM public.update_board_item(p_card_id, p_fields);
    v_fields_applied := true;
  END IF;

  -- Determine link_type:
  --   status_changed → priority signal (most operationally meaningful)
  --   discussed      → catch-all (mention with optional non-status fields, or zero-mutation note)
  v_link_type := CASE WHEN v_status_changed THEN 'status_changed' ELSE 'discussed' END;

  v_link_note := COALESCE(
    p_note,
    CASE
      WHEN v_status_changed AND v_fields_applied
        THEN 'Status: ' || v_old_status || ' → ' || p_new_status || ' (and fields updated)'
      WHEN v_status_changed
        THEN 'Status: ' || v_old_status || ' → ' || p_new_status
      WHEN v_fields_applied
        THEN 'Card fields updated during meeting'
      ELSE 'Discussed during meeting'
    END
  );

  -- INSERT board_item_event_links (idempotent on (card,event,link_type))
  INSERT INTO public.board_item_event_links (
    organization_id, board_item_id, event_id, link_type, author_id, note
  ) VALUES (
    v_card.organization_id, p_card_id, p_event_id, v_link_type, v_caller_id, v_link_note
  )
  ON CONFLICT (board_item_id, event_id, link_type) DO UPDATE
    SET note = EXCLUDED.note;

  RETURN jsonb_build_object(
    'success', true,
    'card_id', p_card_id,
    'event_id', p_event_id,
    'old_status', v_old_status,
    'new_status', CASE WHEN v_status_changed THEN p_new_status ELSE v_old_status END,
    'status_changed', v_status_changed,
    'fields_applied', v_fields_applied,
    'link_type', v_link_type,
    'updated_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.update_card_during_meeting(uuid, uuid, text, jsonb, text) IS
  'ADR-0049 #84 Onda 2: atomic card mutation during meeting. Wraps move_board_item + update_board_item; creates board_item_event_links (status_changed | discussed). V4 write_board.';

GRANT EXECUTE ON FUNCTION public.update_card_during_meeting(uuid, uuid, text, jsonb, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.update_card_during_meeting(uuid, uuid, text, jsonb, text) FROM PUBLIC, anon;


-- =====================================================================
-- RPC 3: meeting_close(p_event_id, p_summary)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.meeting_close(
  p_event_id uuid,
  p_summary text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_event record;
  v_already_closed boolean;
  v_action_count int;
  v_decision_count int;
  v_unresolved_count int;
  v_markdown_action_count int;
  v_structured_drift int;
  v_links_total int;
  v_showcase_count int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- V4 gate: manage_event
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  -- Validate + read event
  SELECT id, title, date, minutes_text, minutes_posted_at
  INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  v_already_closed := v_event.minutes_posted_at IS NOT NULL;

  -- Count structured action items + decisions
  SELECT
    COUNT(*) FILTER (WHERE kind = 'action'),
    COUNT(*) FILTER (WHERE kind = 'decision'),
    COUNT(*) FILTER (WHERE kind IN ('action','followup') AND resolved_at IS NULL)
  INTO v_action_count, v_decision_count, v_unresolved_count
  FROM public.meeting_action_items WHERE event_id = p_event_id;

  -- Count markdown checklist items in minutes_text (best-effort: '- [ ]' pattern)
  v_markdown_action_count := COALESCE(
    (SELECT array_length(regexp_split_to_array(v_event.minutes_text, E'(^|\\n)\\s*-\\s*\\[\\s*\\]'), 1) - 1),
    0
  );
  v_markdown_action_count := GREATEST(0, v_markdown_action_count);
  v_structured_drift := GREATEST(0, v_markdown_action_count - v_action_count);

  -- Count board_item_event_links for this event
  SELECT COUNT(*) INTO v_links_total
  FROM public.board_item_event_links WHERE event_id = p_event_id;

  -- Count showcases registered for this event
  SELECT COUNT(*) INTO v_showcase_count
  FROM public.event_showcases WHERE event_id = p_event_id;

  -- Mark closed (idempotent: only set if not already set)
  IF NOT v_already_closed THEN
    UPDATE public.events
    SET minutes_posted_at = now(),
        minutes_posted_by = v_caller_id,
        notes = CASE
          WHEN p_summary IS NOT NULL AND length(trim(p_summary)) > 0
            THEN COALESCE(notes, '') ||
                 CASE WHEN COALESCE(notes, '') <> '' THEN E'\n\n' ELSE '' END ||
                 '## Meeting close summary (' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ')' ||
                 E'\n' || trim(p_summary)
          ELSE notes
        END,
        updated_at = now()
    WHERE id = p_event_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_event.title,
    'already_closed', v_already_closed,
    'closed_at', CASE WHEN v_already_closed THEN v_event.minutes_posted_at ELSE now() END,
    'action_count', v_action_count,
    'decision_count', v_decision_count,
    'unresolved_actions', v_unresolved_count,
    'markdown_action_count', v_markdown_action_count,
    'structured_drift', v_structured_drift,
    'links_total', v_links_total,
    'showcase_count', v_showcase_count,
    'drift_signal', v_structured_drift > 0,
    'summary_appended', p_summary IS NOT NULL AND length(trim(p_summary)) > 0 AND NOT v_already_closed
  );
END;
$$;

COMMENT ON FUNCTION public.meeting_close(uuid, text) IS
  'ADR-0049 #84 Onda 2: atomic meeting close. Sets minutes_posted_at + counts structured drift (markdown vs action items) + summary append. V4 manage_event. Idempotent.';

GRANT EXECUTE ON FUNCTION public.meeting_close(uuid, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.meeting_close(uuid, text) FROM PUBLIC, anon;


-- =====================================================================
-- RPC 4: get_tribe_housekeeping(p_initiative_id, p_legacy_tribe_id)
-- =====================================================================

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

  -- Resolve initiative (priority: explicit p_initiative_id; fallback: legacy_tribe_id)
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

  -- Best-effort current cycle (default by date logic — accept either explicit cycle3-2026 or current)
  -- If no helper exists, fallback to the cycle of most recent active deliverable
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

    -- Section A: Annual KPIs this initiative contributes to
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

    -- Section B: Cards in this initiative's boards (heuristic: tags overlap with KPI keys via JOIN)
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

    -- Section C: Cycle deliverables for this initiative
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

    -- Rollup metrics
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

COMMENT ON FUNCTION public.get_tribe_housekeeping(uuid, integer) IS
  'ADR-0049 #84 Onda 2: KPI rollup + card-tag-match heuristic + cycle deliverables for an initiative. Closes #84 GAP 7. Authenticated read.';

GRANT EXECUTE ON FUNCTION public.get_tribe_housekeeping(uuid, integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_tribe_housekeeping(uuid, integer) FROM PUBLIC, anon;


-- =====================================================================
-- Reload PostgREST surface
-- =====================================================================

NOTIFY pgrst, 'reload schema';

-- =====================================================================
-- Rollback (commented; restore by uncommenting + apply_migration)
-- =====================================================================
-- DROP FUNCTION IF EXISTS public.get_tribe_housekeeping(uuid, integer);
-- DROP FUNCTION IF EXISTS public.meeting_close(uuid, text);
-- DROP FUNCTION IF EXISTS public.update_card_during_meeting(uuid, uuid, text, jsonb, text);
-- DROP FUNCTION IF EXISTS public.get_agenda_smart(uuid);
