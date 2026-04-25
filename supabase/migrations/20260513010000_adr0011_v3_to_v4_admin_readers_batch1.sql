-- ADR-0011 V3→V4 admin-readers batch 1 — replace hardcoded operational_role / is_superadmin
-- gates with `public.can_by_member(v_caller_id, 'manage_platform')`.
--
-- Context: the `tests/contracts/rpc-v4-auth.test.mjs` parser was tightened today
-- and surfaced 22 hidden V3 violations across post-cutover (20260424+) migrations.
-- This migration migrates the first 10 (the "admin readers" group). Remaining
-- 12 RPCs (exec_tribe_dashboard, bulk_mark_excused, get_member_attendance_hours,
-- get_tribe_events_timeline, get_tribe_attendance_grid, etc.) will be handled in
-- a follow-up batch — they require different actions (write_board / manage_member /
-- analytics permission) and partial scoping logic, not blanket manage_platform.
--
-- RPCs covered (ALL gated to `manage_platform`):
--   1. detect_and_notify_detractors        (admin manager-only writer over notifications)
--   2. detect_operational_alerts           (admin operations dashboard reader)
--   3. send_attendance_reminders           (admin manager-only writer over notifications)
--   4. exec_all_tribes_summary             (executive tribes summary reader)
--   5. get_cross_tribe_comparison          (cross-tribe analytics reader, json-returning)
--   6. exec_cycle_report                   (executive cycle report reader)
--   7. get_admin_dashboard                 (admin home dashboard reader)
--   8. exec_cross_tribe_comparison         (executive cross-tribe analytics reader, jsonb)
--   9. get_adoption_dashboard              (admin adoption metrics reader)
--  10. get_campaign_analytics              (admin campaign analytics reader)
--
-- Behavior change (intentional, accepted by PM 2026-04-24):
--   V3 gates accepted `sponsor` and `chapter_liaison` operational_roles for some of
--   these readers (notably get_admin_dashboard, exec_all_tribes_summary,
--   get_cross_tribe_comparison, get_adoption_dashboard, exec_cycle_report). Under
--   V4 `manage_platform`, sponsors and chapter_liaisons that are NOT superadmin no
--   longer have access (7 users total: 5 sponsors + 2 chapter_liaisons). This is
--   a tightening per ADR-0011/0007 — `can_by_member()` automatically respects
--   `is_superadmin` (superadmins always pass). If sponsor/chapter_liaison access
--   is required for any of these surfaces, PM will seed `manage_platform` for
--   those engagement_kind × operational_role permissions in a separate change.
--
-- Pattern applied:
--   IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
--     RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
--   END IF;
--
-- Body below the gate is preserved byte-for-byte from the latest definition of
-- each RPC across post-cutover migrations (latest CREATE OR REPLACE wins). Only
-- the auth gate and its supporting variable declarations were rewritten.

-- ============================================================================
-- 1. detect_and_notify_detractors  (latest: 20260428050000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.detect_and_notify_detractors()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_count int := 0;
  v_member record;
  v_leader record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  FOR v_member IN
    SELECT m.id, m.name, m.tribe_id
    FROM members m
    WHERE m.is_active = true
    AND m.current_cycle_active = true
    AND m.operational_role NOT IN ('sponsor', 'chapter_liaison')
    AND NOT EXISTS (
      SELECT 1 FROM attendance a
      JOIN events e ON a.event_id = e.id
      WHERE a.member_id = m.id AND a.present = true
      AND e.date >= (now() - interval '21 days')::date
    )
    AND EXISTS (
      SELECT 1 FROM events e
      LEFT JOIN initiatives i ON i.id = e.initiative_id
      WHERE e.date >= (now() - interval '21 days')::date
      AND (e.type IN ('geral', 'tribo') OR i.legacy_tribe_id = m.tribe_id)
    )
  LOOP
    FOR v_leader IN
      SELECT m2.id FROM members m2
      WHERE m2.is_active = true AND (
        m2.is_superadmin = true
        OR m2.operational_role IN ('manager', 'deputy_manager')
        OR (m2.operational_role = 'tribe_leader' AND m2.tribe_id = v_member.tribe_id)
      )
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.recipient_id = v_leader.id
        AND n.type = 'attendance_detractor'
        AND n.source_id = v_member.id
        AND n.created_at > now() - interval '7 days'
      ) THEN
        PERFORM create_notification(
          v_leader.id,
          'attendance_detractor',
          'Detractor Alert: ' || v_member.name,
          v_member.name || ' missed 3+ consecutive eligible meetings',
          '/admin/members',
          'member',
          v_member.id
        );
      END IF;
    END LOOP;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('detractors_found', v_count);
END;
$function$;

-- ============================================================================
-- 2. detect_operational_alerts  (latest: 20260428050000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.detect_operational_alerts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_alerts jsonb := '[]'::jsonb;
  v_tmp jsonb;
  v_cycle_start date;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  SELECT cycle_start::date INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := current_date - 90; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', CASE WHEN sub.last_in_cycle IS NULL THEN 'medium' ELSE 'high' END,
    'type', 'tribe_no_meeting',
    'tribe_id', sub.id, 'tribe_name', sub.name, 'days_since', sub.days_since,
    'message', CASE
      WHEN sub.last_in_cycle IS NULL THEN sub.name || ' sem reunião registrada neste ciclo'
      ELSE sub.name || ' sem reunião há ' || sub.days_since || ' dias'
    END
  ))
  INTO v_tmp
  FROM (
    SELECT t.id, t.name,
      MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) as last_in_cycle,
      EXTRACT(DAY FROM now() - MAX(e.date) FILTER (WHERE e.date >= v_cycle_start)::timestamp)::int as days_since
    FROM tribes t
    LEFT JOIN initiatives i ON i.legacy_tribe_id = t.id
    LEFT JOIN events e ON e.initiative_id = i.id
    WHERE t.is_active = true
    GROUP BY t.id, t.name
    HAVING MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) < current_date - 14
       OR MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) IS NULL
  ) sub;
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'medium', 'type', 'member_absence_streak',
    'member_name', m.name, 'tribe_name', t.name,
    'message', m.name || ' ausente em últimas reuniões da ' || t.name
  ))
  INTO v_tmp
  FROM members m JOIN tribes t ON t.id = m.tribe_id
  WHERE m.is_active AND m.tribe_id IS NOT NULL
  AND m.id NOT IN (
    SELECT DISTINCT a.member_id FROM attendance a
    JOIN events e ON e.id = a.event_id
    LEFT JOIN initiatives i2 ON i2.id = e.initiative_id
    WHERE i2.legacy_tribe_id = m.tribe_id AND e.date >= current_date - 21 AND a.present = true
  );
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'medium', 'type', 'tribe_stagnant_production',
    'tribe_id', t.id, 'tribe_name', t.name,
    'message', t.name || ' sem movimentação de cards em 14+ dias'
  ))
  INTO v_tmp
  FROM tribes t WHERE t.is_active = true
  AND t.id NOT IN (
    SELECT DISTINCT i3.legacy_tribe_id
    FROM board_lifecycle_events ble
    JOIN board_items bi ON bi.id = ble.item_id
    JOIN project_boards pb ON pb.id = bi.board_id
    JOIN initiatives i3 ON i3.id = pb.initiative_id
    WHERE ble.created_at >= now() - interval '14 days' AND i3.legacy_tribe_id IS NOT NULL
  );
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'low', 'type', 'onboarding_overdue',
    'member_name', sa.applicant_name, 'step', op.step_key,
    'message', sa.applicant_name || ' atrasou ' || op.step_key
  ))
  INTO v_tmp
  FROM onboarding_progress op
  JOIN selection_applications sa ON sa.id = op.application_id
  WHERE op.status = 'overdue';
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'high', 'type', 'kpi_at_risk',
    'kpi_name', pkt.metric_key, 'target_value', pkt.target_value,
    'message', pkt.metric_key || ' abaixo de 50% da meta'
  ))
  INTO v_tmp
  FROM portfolio_kpi_targets pkt
  WHERE pkt.target_value > 0 AND pkt.critical_threshold > 0
  AND pkt.critical_threshold < (pkt.target_value * 0.5);
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', CASE WHEN e.type IN ('geral', 'kickoff', 'lideranca') THEN 'high' ELSE 'medium' END,
    'type', 'recorded_event_without_minutes',
    'event_id', e.id, 'event_title', e.title, 'event_type', e.type, 'event_date', e.date,
    'has_youtube', e.youtube_url IS NOT NULL,
    'has_recording', e.recording_url IS NOT NULL,
    'message', 'Evento gravado sem ata: ' || e.title || ' (' || e.date || ')'
  ))
  INTO v_tmp
  FROM events e
  WHERE (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL)
    AND (
      e.minutes_text IS NULL
      OR trim(e.minutes_text) = ''
      OR lower(trim(e.minutes_text)) IN ('teste', 'teste teste', 'test', 'placeholder', '-')
      OR length(trim(e.minutes_text)) < 20
    )
    AND e.date >= v_cycle_start
    AND e.date <= current_date;
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  RETURN jsonb_build_object(
    'alerts', v_alerts,
    'total', jsonb_array_length(v_alerts),
    'by_severity', jsonb_build_object(
      'high', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'high'),
      'medium', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'medium'),
      'low', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'low')
    ),
    'checked_at', now()
  );
END;
$function$;

-- ============================================================================
-- 3. send_attendance_reminders  (latest: 20260428050000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.send_attendance_reminders()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_event record;
  v_count int := 0;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  FOR v_event IN
    SELECT e.id, e.title, e.date, i.legacy_tribe_id AS tribe_id, e.type
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date = current_date
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.type = 'attendance_reminder'
      AND n.source_id = e.id
    )
  LOOP
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'attendance_reminder',
      v_event.title || ' starts soon!',
      'Don''t forget to check in!',
      '/attendance',
      'event',
      v_event.id
    FROM members m
    WHERE m.is_active = true
    AND m.current_cycle_active = true
    AND (v_event.type IN ('geral', 'tribo') OR m.tribe_id = v_event.tribe_id)
    AND NOT EXISTS (
      SELECT 1 FROM notifications n2
      WHERE n2.recipient_id = m.id AND n2.type = 'attendance_reminder' AND n2.source_id = v_event.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM notification_preferences np
      WHERE np.member_id = m.id AND 'attendance_reminder' = ANY(np.muted_types)
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('events_reminded', v_count);
END;
$function$;

-- ============================================================================
-- 4. exec_all_tribes_summary  (latest: 20260428050000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.exec_all_tribes_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  v_cycle_start := COALESCE(
    (SELECT MIN(date) FROM public.events
     WHERE title ILIKE '%kick%off%' AND date >= '2026-01-01'),
    '2026-03-05'::date
  );

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'tribe_id', t.id,
      'name', t.name,
      'quadrant', t.quadrant,
      'member_count', (SELECT COUNT(*) FROM public.members WHERE tribe_id = t.id AND is_active = true),
      'attendance_rate', COALESCE(
        (SELECT ROUND(
          COUNT(*) FILTER (WHERE a.present = true)::numeric /
          NULLIF(COUNT(*), 0), 2
        ) FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        JOIN public.initiatives i2 ON i2.id = e.initiative_id
        WHERE i2.legacy_tribe_id = t.id AND e.date >= v_cycle_start),
        0
      ),
      'articles_count', COALESCE(
        (SELECT COUNT(*) FROM public.board_items bi
         JOIN public.project_boards pb ON pb.id = bi.board_id
         JOIN public.initiatives i3 ON i3.id = pb.initiative_id
         WHERE i3.legacy_tribe_id = t.id AND bi.curation_status IN ('submitted', 'approved', 'published')),
        0
      ),
      'xp_total', COALESCE(
        (SELECT SUM(gp.points) FROM public.gamification_points gp
         WHERE gp.member_id IN (SELECT id FROM public.members WHERE tribe_id = t.id AND is_active = true)),
        0
      ),
      'leader_name', (SELECT name FROM public.members WHERE id = t.leader_member_id)
    ) ORDER BY t.id
  ), '[]'::jsonb) INTO v_result
  FROM public.tribes t
  WHERE t.is_active = true AND t.workstream_type = 'research';

  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 5. get_cross_tribe_comparison  (latest: 20260428050000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_cross_tribe_comparison()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_start date;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  RETURN (
    SELECT json_agg(row_to_json(r) ORDER BY r.attendance_rate DESC NULLS LAST)
    FROM (
      SELECT
        t.id as tribe_id,
        t.name as tribe_name,
        (SELECT m2.name FROM members m2 WHERE m2.tribe_id = t.id AND m2.operational_role = 'tribe_leader' LIMIT 1) as leader_name,
        (SELECT count(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active AND m.current_cycle_active) as member_count,
        (SELECT round(
          count(*) FILTER (WHERE a.id IS NOT NULL AND a.excused IS NOT TRUE)::numeric /
          NULLIF(count(*) FILTER (WHERE a.id IS NULL OR a.excused IS NOT TRUE), 0) * 100, 0
        )
        FROM events e
        JOIN initiatives ti ON ti.id = e.initiative_id
        CROSS JOIN members m
        LEFT JOIN attendance a ON a.event_id = e.id AND a.member_id = m.id
        WHERE e.date >= v_cycle_start AND e.date < current_date
          AND e.type = 'tribo' AND ti.legacy_tribe_id = t.id
          AND m.tribe_id = t.id AND m.is_active
        ) as attendance_rate,
        (SELECT count(*) FROM board_items bi
         JOIN project_boards pb ON pb.id = bi.board_id
         JOIN initiatives ti ON ti.id = pb.initiative_id
         WHERE ti.legacy_tribe_id = t.id AND bi.status = 'done') as cards_done,
        (SELECT count(*) FROM board_items bi
         JOIN project_boards pb ON pb.id = bi.board_id
         JOIN initiatives ti ON ti.id = pb.initiative_id
         WHERE ti.legacy_tribe_id = t.id AND bi.status = 'in_progress') as cards_in_progress,
        (SELECT count(*) FROM board_items bi
         JOIN project_boards pb ON pb.id = bi.board_id
         JOIN initiatives ti ON ti.id = pb.initiative_id
         WHERE ti.legacy_tribe_id = t.id AND bi.status NOT IN ('archived', 'done')) as cards_total,
        (SELECT round(sum(e.duration_minutes * sub.att_count)::numeric / 60, 1)
         FROM events e
         JOIN initiatives ti ON ti.id = e.initiative_id
         JOIN (SELECT event_id, count(*) as att_count FROM attendance WHERE excused IS NOT TRUE GROUP BY event_id) sub ON sub.event_id = e.id
         WHERE ti.legacy_tribe_id = t.id AND e.date >= v_cycle_start AND e.date <= current_date
        ) as impact_hours,
        (SELECT count(*) FROM events e
         JOIN initiatives ti ON ti.id = e.initiative_id
         WHERE ti.legacy_tribe_id = t.id AND e.date >= v_cycle_start AND e.date <= current_date AND e.type = 'tribo') as events_held,
        (SELECT max(e.date) FROM events e
         JOIN initiatives ti ON ti.id = e.initiative_id
         WHERE ti.legacy_tribe_id = t.id AND e.date <= current_date AND e.type = 'tribo') as last_meeting
      FROM tribes t
      WHERE t.is_active = true
    ) r
  );
END;
$function$;

-- ============================================================================
-- 6. exec_cycle_report  (latest: 20260428100000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.exec_cycle_report(p_cycle_code text DEFAULT 'cycle3-2026'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb; v_kpis jsonb; v_members jsonb; v_tribes jsonb;
  v_production jsonb; v_engagement jsonb; v_curation jsonb; v_cycle jsonb; v_attendance jsonb;
  v_total_members int; v_active_members int;
  v_start date := '2026-01-01';
  v_end date := '2026-06-30';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  SELECT jsonb_build_object(
    'code', COALESCE(c.cycle_code, p_cycle_code),
    'name', COALESCE(c.cycle_label, 'Ciclo 3 — 2026/1'),
    'start_date', c.cycle_start, 'end_date', c.cycle_end
  ) INTO v_cycle FROM public.cycles c WHERE c.cycle_code = p_cycle_code OR c.is_current = true LIMIT 1;
  IF v_cycle IS NULL THEN v_cycle := jsonb_build_object('code', p_cycle_code, 'name', 'Ciclo 3', 'start_date', v_start, 'end_date', v_end); END IF;

  v_kpis := public.get_kpi_dashboard(v_start, v_end);

  SELECT COUNT(*) INTO v_total_members FROM public.members;
  SELECT COUNT(*) INTO v_active_members FROM public.members WHERE current_cycle_active = true;

  SELECT jsonb_build_object(
    'total', v_total_members, 'active', v_active_members,
    'by_chapter', COALESCE((SELECT jsonb_agg(jsonb_build_object('chapter', chapter, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT chapter, count(*) AS cnt FROM public.members WHERE current_cycle_active = true AND chapter IS NOT NULL GROUP BY chapter) sub), '[]'::jsonb),
    'by_role', COALESCE((SELECT jsonb_agg(jsonb_build_object('role', operational_role, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT COALESCE(operational_role, 'none') AS operational_role, count(*) AS cnt FROM public.members WHERE current_cycle_active = true GROUP BY operational_role) sub), '[]'::jsonb),
    'retention_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE COALESCE(array_length(cycles, 1), 0) > 1)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true AND cycles IS NOT NULL), 0)),
    'new_this_cycle', (SELECT COUNT(*) FROM public.members WHERE current_cycle_active = true AND (cycles IS NULL OR COALESCE(array_length(cycles, 1), 0) <= 1))
  ) INTO v_members;

  SELECT COALESCE(jsonb_agg(tribe_data ORDER BY tribe_data->>'name'), '[]'::jsonb) INTO v_tribes
  FROM (SELECT jsonb_build_object('id', t.id, 'name', t.name,
    'leader', COALESCE((SELECT m.name FROM public.members m WHERE m.tribe_id = t.id AND m.operational_role = 'tribe_leader' LIMIT 1), '—'),
    'member_count', (SELECT COUNT(*) FROM public.members m WHERE m.tribe_id = t.id AND m.current_cycle_active = true),
    'board_items_total', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'board_items_completed', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status = 'done'), 0),
    'completion_pct', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE bi.status = 'done')::numeric * 100 / NULLIF(COUNT(*), 0)) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'articles_produced', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status IN ('done', 'published') AND (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0)
  ) AS tribe_data FROM public.tribes t WHERE t.is_active = true) sub;

  SELECT jsonb_build_object(
    'articles_submitted', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0),
    'articles_published', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('done', 'published')), 0),
    'articles_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('review', 'in_progress')), 0),
    'webinars_completed', (SELECT COUNT(*) FROM public.events WHERE type = 'webinar' AND date <= now()),
    'webinars_planned', (SELECT COUNT(*) FROM public.events WHERE type = 'webinar' AND date > now())
  ) INTO v_production;

  SELECT jsonb_build_object(
    'total_events', (SELECT COUNT(*) FROM public.events WHERE date BETWEEN v_start AND v_end),
    'total_attendance_hours', COALESCE((SELECT round(sum(COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)) / 60) FROM events e WHERE e.date BETWEEN v_start AND v_end), 0),
    'avg_attendance_per_event', COALESCE((SELECT ROUND(AVG(ac)) FROM (SELECT COUNT(*) AS ac FROM public.attendance a JOIN events e ON e.id = a.event_id WHERE a.present = true AND e.date BETWEEN v_start AND v_end GROUP BY a.event_id) sub), 0),
    'total_attendance_records', (SELECT COUNT(*) FROM public.attendance WHERE present = true),
    'certification_completion_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE cpmai_certified = true)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true), 0))
  ) INTO v_engagement;

  SELECT jsonb_build_object(
    'items_submitted', COALESCE((SELECT COUNT(*) FROM public.curation_review_log), 0),
    'items_approved', COALESCE((SELECT COUNT(*) FROM public.curation_review_log WHERE decision = 'approved'), 0),
    'items_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items WHERE status = 'review'), 0),
    'avg_review_days', COALESCE((SELECT ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) / 86400)::numeric, 1) FROM public.curation_review_log), 0),
    'sla_compliance_rate', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE completed_at <= due_date)::numeric * 100 / NULLIF(COUNT(*) FILTER (WHERE due_date IS NOT NULL), 0)) FROM public.curation_review_log), 0)
  ) INTO v_curation;

  SELECT COALESCE(jsonb_agg(att_row ORDER BY att_row->>'tribe_name'), '[]'::jsonb) INTO v_attendance
  FROM (SELECT jsonb_build_object('tribe_id', t.id, 'tribe_name', t.name,
    'members_count', (SELECT count(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active AND m.operational_role NOT IN ('sponsor','chapter_liaison','guest','none')),
    'avg_geral_pct', COALESCE((SELECT round(avg(sub.geral_pct), 1) FROM get_attendance_summary(v_start, v_end, t.id) sub), 0),
    'avg_tribe_pct', COALESCE((SELECT round(avg(sub.tribe_pct), 1) FROM get_attendance_summary(v_start, v_end, t.id) sub), 0),
    'avg_combined_pct', COALESCE((SELECT round(avg(sub.combined_pct), 1) FROM get_attendance_summary(v_start, v_end, t.id) sub), 0),
    'at_risk_count', COALESCE((SELECT count(*) FROM get_attendance_summary(v_start, v_end, t.id) sub WHERE sub.combined_pct < 50 AND sub.combined_pct > 0), 0)
  ) AS att_row FROM tribes t WHERE t.is_active = true) sub;

  v_result := jsonb_build_object('cycle', v_cycle, 'kpis', v_kpis, 'members', v_members, 'tribes', v_tribes, 'production', v_production, 'engagement', v_engagement, 'curation', v_curation, 'attendance', v_attendance);
  RETURN v_result;
END; $function$;

-- ============================================================================
-- 7. get_admin_dashboard  (latest: 20260428130000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb; v_cycle_start date; v_current_cycle int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  SELECT cycle_start,
    CASE WHEN cycle_code ~ '^\w+_\d+$' THEN substring(cycle_code from '\d+')::int ELSE sort_order END
  INTO v_cycle_start, v_current_cycle
  FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-01-01'; END IF;
  IF v_current_cycle IS NULL THEN v_current_cycle := 3; END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'kpis', jsonb_build_object(
      'active_members', (SELECT count(*) FROM public.members WHERE is_active AND current_cycle_active),
      'adoption_7d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*), 0) * 100, 1) FROM public.members WHERE is_active AND current_cycle_active),
      'deliverables_completed', (SELECT count(*) FROM public.board_items WHERE status = 'done'),
      'deliverables_total', (SELECT count(*) FROM public.board_items WHERE status != 'archived'),
      'impact_hours', (SELECT COALESCE(public.get_impact_hours_excluding_excused(), 0)),
      'cpmai_current', (SELECT count(DISTINCT member_id) FROM public.gamification_points WHERE category = 'cert_cpmai' AND created_at >= v_cycle_start),
      'cpmai_target', (SELECT target_value FROM public.annual_kpi_targets WHERE kpi_key = 'cpmai_certified' AND cycle = v_current_cycle LIMIT 1),
      'chapters_current', (SELECT count(DISTINCT chapter) FROM public.members WHERE is_active = true AND chapter IS NOT NULL),
      'chapters_target', (SELECT target_value FROM public.annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND cycle = v_current_cycle LIMIT 1)
    ),
    'alerts', (SELECT COALESCE(jsonb_agg(alert), '[]'::jsonb) FROM (
      SELECT jsonb_build_object(
        'severity', 'high',
        'message', count(*) || ' pesquisadores sem tribo',
        'action_label', 'Ir para Tribos',
        'action_href', '/admin/tribes'
      ) AS alert
      FROM public.members m
      WHERE m.is_active = true
        AND public.get_member_tribe(m.id) IS NULL
        AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'manager', 'deputy_manager', 'observer')
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' stakeholders sem conta',
        'action_label', 'Ver Membros',
        'action_href', '/admin/members'
      )
      FROM public.members
      WHERE is_active = true AND auth_id IS NULL AND operational_role IN ('sponsor', 'chapter_liaison')
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' membros em risco de dropout',
        'action_label', 'Ver lista',
        'action_href', '/admin/members'
      )
      FROM public.members m
      WHERE m.is_active = true AND m.current_cycle_active
        AND public.get_member_tribe(m.id) IS NOT NULL
        AND m.id NOT IN (
          SELECT a.member_id FROM public.attendance a
          JOIN public.events e ON e.id = a.event_id
          WHERE e.date > now() - interval '60 days'
        )
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'high',
        'message', t.name || ' sem reuniao ha ' || (current_date - max(e.date)) || ' dias',
        'action_label', 'Ver Tribo',
        'action_href', '/tribe/' || t.id
      )
      FROM public.tribes t
      LEFT JOIN public.initiatives i ON i.legacy_tribe_id = t.id
      LEFT JOIN public.events e ON e.initiative_id = i.id AND e.type = 'tribo' AND e.date <= current_date
      WHERE t.is_active = true
      GROUP BY t.id, t.name
      HAVING max(e.date) IS NOT NULL AND current_date - max(e.date) > 14

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' membros detractors (3+ faltas consecutivas)',
        'action_label', 'Quadro de Presenca',
        'action_href', '/attendance?tab=grid'
      )
      FROM public.members m
      WHERE m.is_active AND m.current_cycle_active
        AND public.get_member_tribe(m.id) IS NOT NULL
        AND m.id IN (
          SELECT dc.member_id FROM (
            SELECT a2.member_id, count(*) as consec
            FROM (
              SELECT member_id, ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY e2.date DESC) as rn
              FROM public.events e2
              LEFT JOIN public.attendance a ON a.event_id = e2.id AND a.excused IS NOT TRUE
              WHERE e2.date >= (SELECT cycle_start FROM public.cycles WHERE is_current LIMIT 1)
                AND e2.date < current_date
                AND e2.type IN ('geral', 'tribo')
                AND NOT EXISTS (SELECT 1 FROM public.attendance ax WHERE ax.event_id = e2.id AND ax.member_id = a.member_id)
            ) a2
            WHERE a2.rn <= 5
            GROUP BY a2.member_id
            HAVING count(*) >= 3
          ) dc
        )
      HAVING count(*) > 0
    ) sub),
    'recent_activity', (SELECT COALESCE(jsonb_agg(r.activity ORDER BY r.ts DESC), '[]'::jsonb) FROM (
      SELECT * FROM (SELECT jsonb_build_object('type', 'audit', 'message', actor.name || ' ' || al.action || ' em ' || COALESCE(target.name, '?'), 'details', al.changes, 'timestamp', al.created_at) as activity, al.created_at as ts FROM public.admin_audit_log al LEFT JOIN public.members actor ON actor.id = al.actor_id LEFT JOIN public.members target ON target.id = al.target_id WHERE al.created_at > now() - interval '7 days' ORDER BY al.created_at DESC LIMIT 10) a1
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'campaign', 'message', 'Campanha "' || ct.name || '" enviada', 'timestamp', cs.created_at), cs.created_at FROM public.campaign_sends cs JOIN public.campaign_templates ct ON ct.id = cs.template_id WHERE cs.created_at > now() - interval '7 days' ORDER BY cs.created_at DESC LIMIT 5) a2
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'publication', 'message', m.name || ' submeteu "' || ps.title || '"', 'timestamp', ps.submission_date), ps.submission_date FROM public.publication_submissions ps JOIN public.publication_submission_authors psa ON psa.submission_id = ps.id JOIN public.members m ON m.id = psa.member_id WHERE ps.submission_date > now() - interval '30 days' ORDER BY ps.submission_date DESC LIMIT 5) a3
    ) r LIMIT 15)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 8. exec_cross_tribe_comparison  (latest: 20260428140000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.exec_cross_tribe_comparison(p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date := '2026-03-01';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  SELECT jsonb_build_object(
    'tribes', (
      SELECT jsonb_agg(jsonb_build_object(
        'tribe_id', t.id,
        'tribe_name', t.name,
        'quadrant', t.quadrant_name,
        'leader', (SELECT name FROM members WHERE id = t.leader_member_id),
        'member_count', (
          SELECT COUNT(*) FROM public.members m
          WHERE m.is_active
            AND EXISTS (
              SELECT 1 FROM public.engagements e
              JOIN public.initiatives i ON i.id = e.initiative_id
              WHERE e.person_id = m.person_id
                AND e.kind = 'volunteer' AND e.status = 'active'
                AND i.kind = 'research_tribe' AND i.legacy_tribe_id = t.id
            )
        ),
        'members_inactive_30d', (
          SELECT COUNT(*) FROM public.members m
          WHERE m.is_active
            AND EXISTS (
              SELECT 1 FROM public.engagements e
              JOIN public.initiatives i ON i.id = e.initiative_id
              WHERE e.person_id = m.person_id
                AND e.kind = 'volunteer' AND e.status = 'active'
                AND i.kind = 'research_tribe' AND i.legacy_tribe_id = t.id
            )
            AND m.id NOT IN (
              SELECT DISTINCT a.member_id FROM public.attendance a
              JOIN public.events e2 ON e2.id = a.event_id
              WHERE e2.date >= (current_date - 30) AND e2.date <= CURRENT_DATE
            )
        ),
        'total_cards', (
          SELECT COUNT(*) FROM board_items bi
          JOIN project_boards pb ON pb.id = bi.board_id
          JOIN initiatives ti ON ti.id = pb.initiative_id
          WHERE ti.legacy_tribe_id = t.id
        ),
        'cards_completed', (
          SELECT COUNT(*) FROM board_items bi
          JOIN project_boards pb ON pb.id = bi.board_id
          JOIN initiatives ti ON ti.id = pb.initiative_id
          WHERE ti.legacy_tribe_id = t.id AND bi.status IN ('done','approved','published')
        ),
        'articles_submitted', (
          SELECT COUNT(*) FROM board_lifecycle_events ble
          JOIN board_items bi ON bi.id = ble.item_id
          JOIN project_boards pb ON pb.id = bi.board_id
          JOIN initiatives ti ON ti.id = pb.initiative_id
          WHERE ti.legacy_tribe_id = t.id AND ble.action = 'submission'
        ),
        'attendance_rate', (
          SELECT COALESCE(
            ROUND(
              COUNT(*) FILTER (WHERE EXISTS (
                SELECT 1 FROM attendance a2
                WHERE a2.event_id = e.id
                  AND a2.member_id IN (
                    SELECT m2.id FROM public.members m2
                    WHERE m2.is_active
                      AND EXISTS (
                        SELECT 1 FROM public.engagements e3
                        JOIN public.initiatives i3 ON i3.id = e3.initiative_id
                        WHERE e3.person_id = m2.person_id
                          AND e3.kind = 'volunteer' AND e3.status = 'active'
                          AND i3.kind = 'research_tribe' AND i3.legacy_tribe_id = t.id
                      )
                  )
              ))::numeric
              / NULLIF(
                (
                  SELECT COUNT(*)::numeric FROM public.members m4
                  WHERE m4.is_active
                    AND EXISTS (
                      SELECT 1 FROM public.engagements e4
                      JOIN public.initiatives i4 ON i4.id = e4.initiative_id
                      WHERE e4.person_id = m4.person_id
                        AND e4.kind = 'volunteer' AND e4.status = 'active'
                        AND i4.kind = 'research_tribe' AND i4.legacy_tribe_id = t.id
                    )
                ) * COUNT(DISTINCT e.id), 0)
            , 2), 0)
          FROM events e
          LEFT JOIN initiatives i ON i.id = e.initiative_id
          WHERE (i.legacy_tribe_id = t.id OR e.initiative_id IS NULL) AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'total_hours', (
          SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
          FROM attendance a JOIN events e ON e.id = a.event_id
          WHERE a.member_id IN (
            SELECT m5.id FROM public.members m5
            WHERE m5.is_active
              AND EXISTS (
                SELECT 1 FROM public.engagements e5
                JOIN public.initiatives i5 ON i5.id = e5.initiative_id
                WHERE e5.person_id = m5.person_id
                  AND e5.kind = 'volunteer' AND e5.status = 'active'
                  AND i5.kind = 'research_tribe' AND i5.legacy_tribe_id = t.id
              )
          )
          AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'meetings_count', (
          SELECT COUNT(*) FROM events e
          JOIN initiatives i ON i.id = e.initiative_id
          WHERE i.legacy_tribe_id = t.id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'total_xp', (
          SELECT COALESCE(SUM(gp.points), 0) FROM gamification_points gp
          WHERE gp.member_id IN (
            SELECT m6.id FROM public.members m6
            WHERE m6.is_active
              AND EXISTS (
                SELECT 1 FROM public.engagements e6
                JOIN public.initiatives i6 ON i6.id = e6.initiative_id
                WHERE e6.person_id = m6.person_id
                  AND e6.kind = 'volunteer' AND e6.status = 'active'
                  AND i6.kind = 'research_tribe' AND i6.legacy_tribe_id = t.id
              )
          )
        ),
        'avg_xp', (
          SELECT COALESCE(ROUND(AVG(sub.total)::numeric, 1), 0)
          FROM (
            SELECT SUM(gp.points) AS total
            FROM gamification_points gp
            WHERE gp.member_id IN (
              SELECT m7.id FROM public.members m7
              WHERE m7.is_active
                AND EXISTS (
                  SELECT 1 FROM public.engagements e7
                  JOIN public.initiatives i7 ON i7.id = e7.initiative_id
                  WHERE e7.person_id = m7.person_id
                    AND e7.kind = 'volunteer' AND e7.status = 'active'
                    AND i7.kind = 'research_tribe' AND i7.legacy_tribe_id = t.id
                )
            )
            GROUP BY gp.member_id
          ) sub
        ),
        'last_meeting_date', (
          SELECT MAX(e.date) FROM events e
          JOIN initiatives i ON i.id = e.initiative_id
          WHERE i.legacy_tribe_id = t.id AND e.date <= CURRENT_DATE
        ),
        'days_since_last_meeting', (
          SELECT EXTRACT(DAY FROM now() - MAX(e.date)::timestamp)::int
          FROM events e
          JOIN initiatives i ON i.id = e.initiative_id
          WHERE i.legacy_tribe_id = t.id AND e.date <= CURRENT_DATE
        )
      ) ORDER BY t.id)
      FROM tribes t
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 9. get_adoption_dashboard  (latest: 20260428140000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_adoption_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  WITH tier_stats AS (
    SELECT operational_role, count(*)::integer as total,
      count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::integer as seen_7d,
      count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::integer as seen_30d,
      count(*) FILTER (WHERE last_seen_at IS NULL)::integer as never,
      ROUND(AVG(total_sessions)::numeric, 1) as avg_sessions
    FROM members WHERE is_active = true GROUP BY operational_role
  ),
  tribe_stats AS (
    SELECT t.id as tribe_id, t.name as tribe_name,
      count(m.id)::integer as total,
      count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '7 days')::integer as seen_7d,
      count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '30 days')::integer as seen_30d,
      count(m.id) FILTER (WHERE m.last_seen_at IS NULL)::integer as never,
      ROUND(AVG(m.total_sessions)::numeric, 1) as avg_sessions
    FROM tribes t
    LEFT JOIN members m ON public.get_member_tribe(m.id) = t.id AND m.is_active = true
    WHERE t.is_active = true GROUP BY t.id, t.name
  ),
  daily AS (
    SELECT session_date, count(DISTINCT member_id)::integer as cnt, sum(pages_visited)::integer as pvs
    FROM member_activity_sessions WHERE session_date > CURRENT_DATE - 30 GROUP BY session_date
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'summary', jsonb_build_object(
      'total_active', (SELECT count(*) FROM members WHERE is_active = true AND current_cycle_active = true),
      'total_registered', (SELECT count(*) FROM members),
      'ever_logged_in', (SELECT count(*) FROM members WHERE is_active = true AND auth_id IS NOT NULL),
      'seen_last_7d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '7 days'),
      'seen_last_30d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '30 days'),
      'never_seen', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at IS NULL),
      'adoption_pct_7d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members),
      'adoption_pct_30d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::numeric / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members),
      'avg_sessions_per_member', (SELECT ROUND(AVG(total_sessions)::numeric, 1) FROM members WHERE is_active = true AND total_sessions > 0)
    ),
    'lifecycle', jsonb_build_object(
      'total_ever', (SELECT count(*) FROM members),
      'active_c3', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni' OR (NOT is_active AND operational_role IN ('alumni','observer','guest'))),
      'observers_active', (SELECT count(*) FROM members WHERE is_active AND operational_role = 'observer'),
      'founders_total', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations)),
      'founders_active', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations) AND is_active AND current_cycle_active),
      'founders_with_auth', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations) AND auth_id IS NOT NULL),
      'sponsors_total', (SELECT count(*) FROM members WHERE operational_role = 'sponsor' AND is_active),
      'sponsors_with_auth', (SELECT count(*) FROM members WHERE operational_role = 'sponsor' AND is_active AND auth_id IS NOT NULL),
      'liaisons_total', (SELECT count(*) FROM members WHERE operational_role = 'chapter_liaison' AND is_active),
      'liaisons_with_auth', (SELECT count(*) FROM members WHERE operational_role = 'chapter_liaison' AND is_active AND auth_id IS NOT NULL),
      'retention_c2_c3', (SELECT ROUND(
        count(DISTINCT mh3.member_id)::numeric * 100 / NULLIF(count(DISTINCT mh2.member_id), 0), 1)
        FROM member_cycle_history mh2
        LEFT JOIN member_cycle_history mh3 ON mh3.member_id = mh2.member_id AND mh3.cycle_code = 'cycle_3'
        WHERE mh2.cycle_code = 'cycle_2')
    ),
    'by_tier', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'tier', ts.operational_role, 'total', ts.total, 'seen_7d', ts.seen_7d,
      'seen_30d', ts.seen_30d, 'never', ts.never, 'avg_sessions', ts.avg_sessions
    )), '[]'::jsonb) FROM tier_stats ts),
    'by_tribe', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'tribe_id', ts.tribe_id, 'tribe_name', ts.tribe_name, 'total', ts.total,
      'seen_7d', ts.seen_7d, 'seen_30d', ts.seen_30d, 'never', ts.never,
      'avg_sessions', ts.avg_sessions
    ) ORDER BY ts.tribe_id), '[]'::jsonb) FROM tribe_stats ts),
    'daily_activity', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'date', d.dt::text, 'unique_members', COALESCE(dy.cnt, 0),
      'total_pageviews', COALESCE(dy.pvs, 0)
    ) ORDER BY d.dt), '[]'::jsonb)
    FROM generate_series(CURRENT_DATE - 30, CURRENT_DATE, '1 day') d(dt)
    LEFT JOIN daily dy ON dy.session_date = d.dt),
    'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id, 'name', m.name, 'tier', m.operational_role,
      'designations', m.designations,
      'tribe_id', public.get_member_tribe(m.id), 'tribe_name', t.name,
      'has_auth', m.auth_id IS NOT NULL, 'last_seen', m.last_seen_at,
      'total_sessions', m.total_sessions, 'last_pages', m.last_active_pages,
      'is_founder', 'founder' = ANY(m.designations),
      'status', CASE
        WHEN m.last_seen_at IS NULL THEN 'never'
        WHEN m.last_seen_at > now() - interval '7 days' THEN 'active'
        WHEN m.last_seen_at > now() - interval '30 days' THEN 'inactive'
        ELSE 'dormant' END
    ) ORDER BY m.last_seen_at DESC NULLS LAST), '[]'::jsonb)
    FROM members m LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
    WHERE m.is_active = true),
    'mcp_usage', (SELECT get_mcp_adoption_stats()),
    'auth_providers', (SELECT get_auth_provider_stats()),
    'designation_counts', (
      SELECT COALESCE(jsonb_object_agg(d, cnt), '{}'::jsonb) FROM (
        SELECT unnest(designations) as d, count(*) as cnt
        FROM members WHERE is_active = true AND designations != '{}'
        GROUP BY d
      ) x
    )
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 10. get_campaign_analytics  (latest: 20260428140000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_campaign_analytics(p_send_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  IF p_send_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'send', (
        SELECT jsonb_build_object(
          'id', cs.id, 'template_name', ct.name, 'subject', ct.subject,
          'sent_at', cs.sent_at, 'created_at', cs.created_at, 'status', cs.status
        )
        FROM campaign_sends cs JOIN campaign_templates ct ON ct.id = cs.template_id
        WHERE cs.id = p_send_id
      ),
      'funnel', jsonb_build_object(
        'total', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id),
        'delivered', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (delivered_at IS NOT NULL OR delivered = true)),
        'opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true)),
        'human_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
        'bot_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
        'clicked', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND clicked_at IS NOT NULL),
        'bounced', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND bounced_at IS NOT NULL),
        'complained', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND complained_at IS NOT NULL)
      ),
      'rates', jsonb_build_object(
        'delivery_rate', (
          SELECT ROUND(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric / NULLIF(count(*), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'open_rate', (
          SELECT ROUND(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'open_rate_total', (
          SELECT ROUND(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'click_rate', (
          SELECT ROUND(count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric
            / NULLIF(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        )
      ),
      'recipients', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'member_name', COALESCE(m.name, cr.external_name, ''),
          'email', COALESCE(m.email, cr.external_email, ''),
          'role', m.operational_role, 'tribe_name', t.name,
          'delivered', (cr.delivered_at IS NOT NULL OR cr.delivered = true),
          'opened', (cr.opened_at IS NOT NULL OR cr.opened = true),
          'open_count', cr.open_count, 'bot_suspected', cr.bot_suspected,
          'clicked', cr.clicked_at IS NOT NULL, 'click_count', cr.click_count,
          'bounced', cr.bounced_at IS NOT NULL, 'bounce_type', cr.bounce_type,
          'complained', cr.complained_at IS NOT NULL,
          'status', CASE
            WHEN cr.complained_at IS NOT NULL THEN 'complained'
            WHEN cr.bounced_at IS NOT NULL THEN 'bounced'
            WHEN cr.clicked_at IS NOT NULL THEN 'clicked'
            WHEN (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = false THEN 'opened'
            WHEN (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = true THEN 'bot_opened'
            WHEN cr.delivered_at IS NOT NULL OR cr.delivered = true THEN 'delivered'
            ELSE 'sent'
          END
        ) ORDER BY cr.delivered_at DESC NULLS LAST), '[]'::jsonb)
        FROM campaign_recipients cr
        LEFT JOIN members m ON m.id = cr.member_id
        LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
        WHERE cr.send_id = p_send_id
      ),
      'by_role', (
        SELECT COALESCE(jsonb_agg(sub), '[]'::jsonb) FROM (
          SELECT jsonb_build_object(
            'role', COALESCE(m.operational_role, 'external'),
            'total', count(*),
            'delivered', count(*) FILTER (WHERE cr.delivered_at IS NOT NULL OR cr.delivered = true),
            'opened', count(*) FILTER (WHERE (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = false),
            'bot_opened', count(*) FILTER (WHERE (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = true),
            'clicked', count(*) FILTER (WHERE cr.clicked_at IS NOT NULL)
          ) AS sub
          FROM campaign_recipients cr LEFT JOIN members m ON m.id = cr.member_id
          WHERE cr.send_id = p_send_id
          GROUP BY COALESCE(m.operational_role, 'external')
        ) agg
      )
    ) INTO v_result;
  ELSE
    SELECT jsonb_build_object(
      'total_sends', (SELECT count(*) FROM campaign_sends WHERE status = 'sent'),
      'total_recipients', (SELECT count(*) FROM campaign_recipients),
      'total_delivered', (SELECT count(*) FROM campaign_recipients WHERE delivered_at IS NOT NULL OR delivered = true),
      'total_opened', (SELECT count(*) FROM campaign_recipients WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
      'total_opened_incl_bots', (SELECT count(*) FROM campaign_recipients WHERE opened_at IS NOT NULL OR opened = true),
      'total_bot_opens', (SELECT count(*) FROM campaign_recipients WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
      'total_clicked', (SELECT count(*) FROM campaign_recipients WHERE clicked_at IS NOT NULL),
      'total_bounced', (SELECT count(*) FROM campaign_recipients WHERE bounced_at IS NOT NULL),
      'overall_rates', jsonb_build_object(
        'delivery_rate', (SELECT ROUND(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric / NULLIF(count(*), 0) * 100, 1) FROM campaign_recipients),
        'open_rate', (SELECT ROUND(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false)::numeric / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1) FROM campaign_recipients),
        'open_rate_total', (SELECT ROUND(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1) FROM campaign_recipients),
        'click_rate', (SELECT ROUND(count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric / NULLIF(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false), 0) * 100, 1) FROM campaign_recipients)
      ),
      'recent_sends', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', cs.id, 'template_name', ct.name, 'sent_at', cs.sent_at, 'created_at', cs.created_at,
          'total', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id),
          'delivered', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (delivered_at IS NOT NULL OR delivered = true)),
          'opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
          'bot_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
          'clicked', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND clicked_at IS NOT NULL),
          'bounced', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND bounced_at IS NOT NULL)
        ) ORDER BY cs.created_at DESC), '[]'::jsonb)
        FROM campaign_sends cs JOIN campaign_templates ct ON ct.id = cs.template_id
        WHERE cs.status = 'sent' LIMIT 20
      )
    ) INTO v_result;
  END IF;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
