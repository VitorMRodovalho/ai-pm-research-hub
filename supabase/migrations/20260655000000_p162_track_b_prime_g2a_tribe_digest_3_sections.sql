-- p162 Track B' G2a — Extend get_weekly_tribe_digest with 3 new sections
-- Refs: ADR-0022 Amendment B (W3 Leader Digest Sections v2), docs/council/p162_track_b_prime_architecture_audit.md
-- 3 new aggregates: ata_pending (recurrence-grouped), attendance_pending, champion_pending
--
-- Semantic strictness (PM ratified):
-- - ata_pending: events past + NOT EXISTS published meeting_artifact (V4 canonical, not minutes_text light)
-- - attendance_pending: events past + zero attendance rows (NOT EXISTS) — not present=false (that's registered absence)
-- - champion_pending: events past + zero champions_awarded active rows (heurística pura; G1 future column eliminates false positive)
--
-- Scope: cycle current. Event types tribo|geral|lideranca only. COALESCE for general events without initiative_id binding.
-- Recurrence grouping applied to ata_pending only (most useful UX); attendance/champion stay per-event.

CREATE OR REPLACE FUNCTION public.get_weekly_tribe_digest(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_tribe record;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
  v_cycle_start timestamptz;
  v_cycle_end timestamptz;
  v_initiative_id uuid;
  v_is_leader boolean;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found: %', p_tribe_id; END IF;

  IF auth.role() = 'service_role'
     OR current_setting('request.jwt.claims', true) IS NULL THEN
    NULL;
  ELSE
    v_is_leader := (v_caller_id IS NOT NULL AND v_caller_id = v_tribe.leader_member_id);
    IF NOT v_is_leader AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: only tribe leader or manage_member can read tribe digest';
    END IF;
  END IF;

  SELECT cycle_start::timestamptz, cycle_end::timestamptz INTO v_cycle_start, v_cycle_end
  FROM public.cycles WHERE is_current = true LIMIT 1;

  SELECT id INTO v_initiative_id FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id LIMIT 1;

  SELECT jsonb_build_object(
    'tribe_id', p_tribe_id,
    'tribe_name', v_tribe.name,
    'initiative_id', v_initiative_id,
    'leader_member_id', v_tribe.leader_member_id,
    'generated_at', now(),
    'window_start', v_window_start,
    'cycle_start', v_cycle_start,
    'cycle_end', v_cycle_end,
    'aggregates', jsonb_build_object(
      'active_members', COALESCE((SELECT count(*) FROM public.members m WHERE m.tribe_id = p_tribe_id AND m.current_cycle_active = true), 0),
      'members_with_overdue_cards', COALESCE((
        SELECT count(DISTINCT bi.assignee_id) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        JOIN public.members m ON m.id = bi.assignee_id
        WHERE i.legacy_tribe_id = p_tribe_id AND m.tribe_id = p_tribe_id
          AND bi.status NOT IN ('done','archived') AND bi.due_date < CURRENT_DATE
      ), 0),
      'cards_overdue_total', COALESCE((SELECT count(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = p_tribe_id AND bi.status NOT IN ('done','archived') AND bi.due_date < CURRENT_DATE), 0),
      'cards_due_next_7d', COALESCE((SELECT count(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = p_tribe_id AND bi.status NOT IN ('done','archived') AND bi.due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'), 0),
      'cards_without_assignee', COALESCE((SELECT count(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = p_tribe_id AND bi.status NOT IN ('done','archived') AND bi.assignee_id IS NULL), 0),
      'cards_without_due_date', COALESCE((SELECT count(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = p_tribe_id AND bi.status NOT IN ('done','archived') AND bi.due_date IS NULL), 0),
      'cards_completed_window', COALESCE((SELECT count(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = p_tribe_id AND bi.status = 'done' AND bi.updated_at >= v_window_start), 0),
      'tribe_health_pct', COALESCE((SELECT CASE WHEN count(*) FILTER (WHERE bi.status NOT IN ('done','archived')) = 0 THEN 100 ELSE (100.0 * count(*) FILTER (WHERE bi.status NOT IN ('done','archived') AND bi.due_date IS NOT NULL) / NULLIF(count(*) FILTER (WHERE bi.status NOT IN ('done','archived')), 0))::int END FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = p_tribe_id), 100),

      'ata_pending', COALESCE((
        WITH pending AS (
          SELECT e.id, e.title, e.date, e.recurrence_group, e.type
          FROM public.events e
          WHERE e.type IN ('tribo','geral','lideranca')
            AND e.date::timestamptz < now()
            AND e.date::timestamptz >= v_cycle_start
            AND (v_cycle_end IS NULL OR e.date::timestamptz < (v_cycle_end + interval '1 day'))
            AND (e.status IS NULL OR e.status != 'cancelled')
            AND (e.initiative_id = v_initiative_id OR (e.type = 'geral' AND e.initiative_id IS NULL))
            AND NOT EXISTS (SELECT 1 FROM public.meeting_artifacts ma WHERE ma.event_id = e.id AND ma.is_published = true)
        ),
        grouped AS (
          SELECT COALESCE(recurrence_group::text, id::text) AS group_key,
                 recurrence_group, (recurrence_group IS NOT NULL) AS is_recurring,
                 count(*) AS occurrence_count,
                 (array_agg(title ORDER BY date DESC))[1] AS sample_title,
                 (array_agg(id ORDER BY date DESC))[1] AS latest_event_id,
                 max(date) AS latest_date
          FROM pending GROUP BY COALESCE(recurrence_group::text, id::text), recurrence_group
        ),
        agg AS (SELECT count(*) AS total_groups, (SELECT count(*) FROM pending) AS total_events FROM grouped),
        top3 AS (SELECT * FROM grouped ORDER BY latest_date DESC LIMIT 3)
        SELECT jsonb_build_object(
          'count_groups', (SELECT total_groups FROM agg),
          'count_events', (SELECT total_events FROM agg),
          'top_groups', COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'is_recurring', is_recurring, 'occurrence_count', occurrence_count,
            'sample_title', sample_title, 'latest_event_id', latest_event_id, 'latest_date', latest_date
          )) FROM top3), '[]'::jsonb)
        )
      ), jsonb_build_object('count_groups', 0, 'count_events', 0, 'top_groups', '[]'::jsonb)),

      'attendance_pending', COALESCE((
        WITH pending AS (
          SELECT e.id, e.title, e.date FROM public.events e
          WHERE e.type IN ('tribo','geral','lideranca')
            AND e.date::timestamptz < now()
            AND e.date::timestamptz >= v_cycle_start
            AND (v_cycle_end IS NULL OR e.date::timestamptz < (v_cycle_end + interval '1 day'))
            AND (e.status IS NULL OR e.status != 'cancelled')
            AND (e.initiative_id = v_initiative_id OR (e.type = 'geral' AND e.initiative_id IS NULL))
            AND NOT EXISTS (SELECT 1 FROM public.attendance a WHERE a.event_id = e.id)
          ORDER BY date DESC
        ),
        top3 AS (SELECT * FROM pending LIMIT 3)
        SELECT jsonb_build_object(
          'count', (SELECT count(*) FROM pending),
          'top_events', COALESCE((SELECT jsonb_agg(jsonb_build_object('event_id', id, 'title', title, 'date', date)) FROM top3), '[]'::jsonb)
        )
      ), jsonb_build_object('count', 0, 'top_events', '[]'::jsonb)),

      'champion_pending', COALESCE((
        WITH pending AS (
          SELECT e.id, e.title, e.date FROM public.events e
          WHERE e.type IN ('tribo','geral','lideranca')
            AND e.date::timestamptz < now()
            AND e.date::timestamptz >= v_cycle_start
            AND (v_cycle_end IS NULL OR e.date::timestamptz < (v_cycle_end + interval '1 day'))
            AND (e.status IS NULL OR e.status != 'cancelled')
            AND (e.initiative_id = v_initiative_id OR (e.type = 'geral' AND e.initiative_id IS NULL))
            AND NOT EXISTS (SELECT 1 FROM public.champions_awarded ca WHERE ca.context_kind = 'event' AND ca.context_id = e.id AND ca.status = 'active')
          ORDER BY date DESC
        ),
        top3 AS (SELECT * FROM pending LIMIT 3)
        SELECT jsonb_build_object(
          'count', (SELECT count(*) FROM pending),
          'top_events', COALESCE((SELECT jsonb_agg(jsonb_build_object('event_id', id, 'title', title, 'date', date)) FROM top3), '[]'::jsonb)
        )
      ), jsonb_build_object('count', 0, 'top_events', '[]'::jsonb))
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_weekly_tribe_digest(integer) IS
'Weekly leader digest aggregates (ADR-0022 Amendment B — p162 Track B''). 8 card-based + 3 documentation hygiene (ata_pending recurrence-grouped, attendance_pending, champion_pending). Cycle-scoped. Event types tribo|geral|lideranca only. COALESCE for general events without initiative binding. Auth: leader or manage_member, service_role/cron bypass.';

NOTIFY pgrst, 'reload schema';

-- Rollback: restore prior body (8 card-based aggregates only). See git history for migration 20260426202437.
