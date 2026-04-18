-- ADR-0015 Phase 3e — DROP COLUMN events.tribe_id (ÚLTIMO C3, 12/12)
--
-- Scope:
--   - 5 writers refactored (create_event, create_initiative_event,
--     create_recurring_weekly_events, curate_item events branch, link_webinar_event)
--   - 28 readers refactored (via JOIN initiatives / i.legacy_tribe_id derivation)
--   - 2 views dropped + recreated (impact_hours_summary, recurring_event_groups)
--   - DROP COLUMN events.tribe_id
--   - idx_events_tribe auto-drops
--
-- LANGUAGE sql functions must come BEFORE the DROP (parse-time check):
--   calc_attendance_pct, get_events_with_attendance, get_tribe_stats, tribe_impact_ranking
--
-- Incidental cleanup during refactor (scope creep documented in issue log):
--   - detect_operational_alerts / exec_all_tribes_summary / exec_cross_tribe_comparison /
--     get_cross_tribe_comparison / get_tribe_stats still referenced stale `pb.tribe_id`
--     (broken post Phase 3d). Since these RPCs are being CREATE OR REPLACE'd anyway for
--     events.tribe_id refactor, also swept their `pb.tribe_id` references.
--   - get_cross_tribe_comparison additionally had `bi.tribe_id` (never existed) — fixed too.
--
-- Data state pre-drop (verified): 270 rows | 0 tribe_only | 2 init_only | 150 both | 118 neither.
-- Closes ADR-0015 Phase 3.

-- ============================================================================
-- 1. LANGUAGE sql functions (parse-time check requires refactor BEFORE drop)
-- ============================================================================

-- 1.1 calc_attendance_pct
CREATE OR REPLACE FUNCTION public.calc_attendance_pct()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ROUND(COALESCE(AVG(pct), 0)::numeric, 1)
  FROM (
    SELECT m.id,
      CASE WHEN expected > 0 THEN (attended::numeric / expected * 100) ELSE NULL END as pct
    FROM members m
    CROSS JOIN LATERAL (
      SELECT
        (
          (SELECT count(*) FROM events e WHERE e.type = 'geral' AND e.date >= '2026-01-01' AND e.date <= current_date)
          +
          (SELECT count(*) FROM events e JOIN initiatives i ON i.id = e.initiative_id
           WHERE e.type = 'tribo' AND i.legacy_tribe_id = m.tribe_id
             AND e.date >= '2026-01-01' AND e.date <= current_date)
          +
          (SELECT count(*) FROM attendance a JOIN events e ON e.id = a.event_id WHERE a.member_id = m.id AND e.type = '1on1' AND e.date >= '2026-01-01' AND e.date <= current_date)
          +
          CASE WHEN m.operational_role IN ('tribe_leader', 'manager', 'deputy_manager') THEN
            (SELECT count(*) FROM events e WHERE e.type = 'lideranca' AND e.date >= '2026-01-01' AND e.date <= current_date)
          ELSE 0 END
        ) as expected,
        (SELECT count(*) FROM attendance a JOIN events e ON e.id = a.event_id
         WHERE a.member_id = m.id AND a.present = true
         AND e.type IN ('geral', 'tribo', '1on1', 'lideranca')
         AND e.date >= '2026-01-01' AND e.date <= current_date
        ) as attended
    ) stats
    WHERE m.is_active = true AND m.current_cycle_active = true
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
      AND stats.expected > 0
  ) sub
  WHERE pct IS NOT NULL;
$function$;

-- 1.2 get_events_with_attendance
CREATE OR REPLACE FUNCTION public.get_events_with_attendance(p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, title text, date date, type text, nature text, duration_minutes integer, time_start time without time zone, meeting_link text, youtube_url text, is_recorded boolean, audience_level text, tribe_id integer, attendee_count bigint, agenda_text text, agenda_url text, minutes_text text, minutes_url text, recording_url text, recording_type text, notes text, visibility text, external_attendees text[], recurrence_group uuid, initiative_id uuid, initiative_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    e.id, e.title, e.date, e.type, e.nature,
    e.duration_minutes, e.time_start, e.meeting_link,
    e.youtube_url, e.is_recorded, e.audience_level,
    i.legacy_tribe_id AS tribe_id,
    (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id) AS attendee_count,
    e.agenda_text, e.agenda_url,
    e.minutes_text, e.minutes_url,
    e.recording_url, e.recording_type,
    e.notes, e.visibility,
    e.external_attendees, e.recurrence_group,
    e.initiative_id,
    i.title AS initiative_name
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
$function$;

-- 1.3 get_tribe_stats (also fixes stale pb.tribe_id from Phase 3d)
CREATE OR REPLACE FUNCTION public.get_tribe_stats(p_tribe_id integer)
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH cycle AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1),
  tribe_members AS (
    SELECT id FROM members WHERE tribe_id = p_tribe_id AND is_active AND current_cycle_active
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
    'member_count', (SELECT count(*) FROM tribe_members),
    'events_held', (SELECT count(*) FROM tribe_events),
    'attendance_rate', (SELECT round(
      count(a.*)::numeric / NULLIF((SELECT count(*) FROM tribe_members) * (SELECT count(*) FROM tribe_events), 0) * 100, 0
    ) FROM att a),
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
  );
$function$;

-- 1.4 tribe_impact_ranking
CREATE OR REPLACE FUNCTION public.tribe_impact_ranking()
 RETURNS TABLE(tribe_id integer, tribe_name text, total_events bigint, total_hours numeric, avg_attendance numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select
    t.id as tribe_id,
    t.name as tribe_name,
    count(distinct e.id) as total_events,
    coalesce(sum(e.duration_minutes)::numeric / 60.0, 0) as total_hours,
    case when count(distinct e.id) = 0 then 0
         else (count(a.id)::numeric / count(distinct e.id))
    end as avg_attendance
  from public.tribes t
  left join public.initiatives i on i.legacy_tribe_id = t.id
  left join public.events e on e.initiative_id = i.id
  left join public.attendance a on a.event_id = e.id and a.present = true
  group by t.id, t.name
  order by total_hours desc;
$function$;

-- ============================================================================
-- 2. PLPGSQL readers (no parse-time dependency, but refactored here for atomicity)
-- ============================================================================

-- 2.1 bulk_mark_excused
CREATE OR REPLACE FUNCTION public.bulk_mark_excused(p_member_id uuid, p_date_from date, p_date_to date, p_reason text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid; v_caller_role text; v_is_admin boolean; v_caller_tribe int;
  v_member_tribe int;
  v_count int := 0;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT tribe_id INTO v_member_tribe FROM public.members WHERE id = p_member_id;

  IF NOT (
    v_is_admin = true
    OR v_caller_role IN ('manager', 'deputy_manager')
    OR (v_caller_role = 'tribe_leader' AND v_caller_tribe = v_member_tribe)
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  INSERT INTO public.attendance (event_id, member_id, excused, excuse_reason)
  SELECT e.id, p_member_id, true, p_reason
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.date >= p_date_from AND e.date <= p_date_to
    AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms')
    AND (
      e.type IN ('geral', 'kickoff')
      OR (e.type = 'tribo' AND i.legacy_tribe_id = v_member_tribe)
      OR (e.type = 'lideranca' AND EXISTS (SELECT 1 FROM members m WHERE m.id = p_member_id AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')))
    )
    AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.excused = false)
  ON CONFLICT (event_id, member_id) DO UPDATE SET excused = true, excuse_reason = p_reason, updated_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN json_build_object('success', true, 'events_marked', v_count, 'date_from', p_date_from, 'date_to', p_date_to);
END;
$function$;

-- 2.2 detect_and_notify_detractors
CREATE OR REPLACE FUNCTION public.detect_and_notify_detractors()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count int := 0;
  v_member record;
  v_leader record;
BEGIN
  PERFORM 1 FROM members WHERE auth_id = auth.uid() AND (is_superadmin = true OR operational_role = 'manager');
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

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

-- 2.3 detect_and_notify_detractors_cron
CREATE OR REPLACE FUNCTION public.detect_and_notify_detractors_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count int := 0;
  v_member record;
  v_leader record;
BEGIN
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

-- 2.4 detect_operational_alerts (also fixes stale pb.tribe_id)
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
  SELECT id INTO v_caller_id FROM members
  WHERE auth_id = auth.uid()
  AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

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

-- 2.5 exec_all_tribes_summary (also fixes stale pb.tribe_id)
CREATE OR REPLACE FUNCTION public.exec_all_tribes_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_result jsonb;
  v_cycle_start date;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager', 'sponsor', 'chapter_liaison') THEN
    RAISE EXCEPTION 'Unauthorized: GP or DM required';
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

-- 2.6 exec_cross_tribe_comparison (also fixes stale pb.tribe_id)
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
  SELECT id INTO v_caller_id FROM members
  WHERE auth_id = auth.uid()
  AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  SELECT jsonb_build_object(
    'tribes', (
      SELECT jsonb_agg(jsonb_build_object(
        'tribe_id', t.id,
        'tribe_name', t.name,
        'quadrant', t.quadrant_name,
        'leader', (SELECT name FROM members WHERE id = t.leader_member_id),
        'member_count', (SELECT COUNT(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active),
        'members_inactive_30d', (
          SELECT COUNT(*) FROM members m
          WHERE m.tribe_id = t.id AND m.is_active
          AND m.id NOT IN (
            SELECT DISTINCT a.member_id FROM attendance a
            JOIN events e ON e.id = a.event_id
            WHERE e.date >= (current_date - 30) AND e.date <= CURRENT_DATE
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
              COUNT(*) FILTER (WHERE EXISTS (SELECT 1 FROM attendance a2 WHERE a2.event_id = e.id AND a2.member_id IN (SELECT id FROM members WHERE tribe_id = t.id AND is_active)))::numeric
              / NULLIF((SELECT COUNT(*) FROM members WHERE tribe_id = t.id AND is_active)::numeric * COUNT(DISTINCT e.id), 0)
            , 2), 0)
          FROM events e
          LEFT JOIN initiatives i ON i.id = e.initiative_id
          WHERE (i.legacy_tribe_id = t.id OR e.initiative_id IS NULL) AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'total_hours', (
          SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
          FROM attendance a JOIN events e ON e.id = a.event_id
          WHERE a.member_id IN (SELECT id FROM members WHERE tribe_id = t.id AND is_active)
          AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'meetings_count', (
          SELECT COUNT(*) FROM events e
          JOIN initiatives i ON i.id = e.initiative_id
          WHERE i.legacy_tribe_id = t.id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'total_xp', (
          SELECT COALESCE(SUM(gp.points), 0) FROM gamification_points gp
          WHERE gp.member_id IN (SELECT id FROM members WHERE tribe_id = t.id AND is_active)
        ),
        'avg_xp', (
          SELECT COALESCE(ROUND(AVG(sub.total)::numeric, 1), 0)
          FROM (SELECT SUM(gp.points) AS total FROM gamification_points gp
                WHERE gp.member_id IN (SELECT id FROM members WHERE tribe_id = t.id AND is_active)
                GROUP BY gp.member_id) sub
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

-- 2.7 exec_impact_hours_v2
CREATE OR REPLACE FUNCTION public.exec_impact_hours_v2(p_cycle_code text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  with scoped as (
    select * from public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)
  ),
  attendance_scope as (
    select
      s.member_id,
      coalesce(i.legacy_tribe_id, s.tribe_id) as tribe_id,
      s.chapter,
      e.id as event_id,
      greatest(coalesce(e.duration_actual, e.duration_minutes, 0), 0)::numeric / 60.0 as impact_hours
    from scoped s
    join public.attendance a on a.member_id = s.member_id and a.present is true
    join public.events e on e.id = a.event_id
    left join public.initiatives i on i.id = e.initiative_id
    where e.date::timestamptz >= s.cycle_start
      and (
        s.cycle_end is null
        or e.date::timestamptz < s.cycle_end + interval '1 day'
      )
      and (p_tribe_id is null or coalesce(i.legacy_tribe_id, s.tribe_id) = p_tribe_id)
      and (p_chapter is null or s.chapter = p_chapter)
  ),
  totals as (
    select
      coalesce(round(sum(impact_hours), 1), 0)::numeric as total_impact_hours,
      count(*)::integer as total_attendances,
      count(distinct event_id)::integer as total_events
    from attendance_scope
  ),
  target_meta as (
    select coalesce(annual_target_hours, 1800)::numeric as annual_target_hours
    from public.impact_hours_total
    limit 1
  )
  select jsonb_build_object(
    'cycle_code', (select max(cycle_code) from scoped),
    'cycle_label', (select max(cycle_label) from scoped),
    'total_impact_hours', coalesce((select total_impact_hours from totals), 0),
    'total_attendances', coalesce((select total_attendances from totals), 0),
    'total_events', coalesce((select total_events from totals), 0),
    'annual_target_hours', coalesce((select annual_target_hours from target_meta), 1800),
    'percent_of_target', case
      when coalesce((select annual_target_hours from target_meta), 0) <= 0 then 0
      else round(
        coalesce((select total_impact_hours from totals), 0)
        * 100
        / nullif((select annual_target_hours from target_meta), 0),
        1
      )
    end,
    'breakdown_by_tribe', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.impact_hours desc, t.tribe_id)
      from (
        select
          tribe_id,
          round(sum(impact_hours), 1)::numeric as impact_hours,
          count(*)::integer as total_attendances,
          count(distinct event_id)::integer as total_events
        from attendance_scope
        where tribe_id is not null
        group by tribe_id
      ) t
    ), '[]'::jsonb),
    'breakdown_by_chapter', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.impact_hours desc, c.chapter)
      from (
        select
          chapter,
          round(sum(impact_hours), 1)::numeric as impact_hours,
          count(*)::integer as total_attendances,
          count(distinct event_id)::integer as total_events
        from attendance_scope
        where chapter is not null and trim(chapter) <> ''
        group by chapter
      ) c
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'total_impact_hours', 0,
    'total_attendances', 0,
    'total_events', 0,
    'annual_target_hours', 1800,
    'percent_of_target', 0,
    'breakdown_by_tribe', '[]'::jsonb,
    'breakdown_by_chapter', '[]'::jsonb
  ));
end;
$function$;

-- 2.8 exec_tribe_dashboard
CREATE OR REPLACE FUNCTION public.exec_tribe_dashboard(p_tribe_id integer, p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record; v_tribe record; v_leader record; v_cycle_start date; v_result jsonb;
  v_members_total int; v_members_active int; v_members_by_role jsonb; v_members_by_chapter jsonb; v_members_list jsonb;
  v_board record; v_prod_total int := 0; v_prod_by_status jsonb := '{}'::jsonb;
  v_articles_submitted int := 0; v_articles_approved int := 0; v_articles_published int := 0;
  v_curation_pending int := 0; v_avg_days_to_approval numeric := 0;
  v_attendance_rate numeric := 0; v_total_meetings int := 0; v_total_hours numeric := 0;
  v_avg_attendance numeric := 0; v_members_with_streak int := 0; v_members_inactive_30d int := 0;
  v_last_meeting_date date; v_next_meeting jsonb := '{}'::jsonb;
  v_tribe_total_xp int := 0; v_tribe_avg_xp numeric := 0;
  v_top_contributors jsonb := '[]'::jsonb; v_cpmai_certified int := 0;
  v_attendance_by_month jsonb := '[]'::jsonb; v_production_by_month jsonb := '[]'::jsonb;
  v_meeting_slots jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;
  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found'; END IF;
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = p_tribe_id)
    AND NOT (v_caller.tribe_id = p_tribe_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.members m2
      WHERE m2.id = v_caller.id
        AND ('sponsor' = ANY(m2.designations) OR 'chapter_liaison' = ANY(m2.designations))
        AND m2.chapter IN (SELECT chapter FROM public.members WHERE tribe_id = p_tribe_id AND chapter IS NOT NULL LIMIT 1)
    )
  THEN RAISE EXCEPTION 'Unauthorized: insufficient permissions for tribe %', p_tribe_id; END IF;
  v_cycle_start := COALESCE(
    (SELECT MIN(date) FROM public.events WHERE title ILIKE '%kick%off%' AND date >= '2026-01-01'),
    '2026-03-05'::date
  );
  SELECT id, name, photo_url INTO v_leader FROM public.members WHERE id = v_tribe.leader_member_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('day_of_week', tms.day_of_week, 'time_start', tms.time_start, 'time_end', tms.time_end)), '[]'::jsonb)
  INTO v_meeting_slots
  FROM public.tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true;
  SELECT COUNT(*) INTO v_members_total FROM public.members WHERE tribe_id = p_tribe_id AND is_active = true;
  SELECT COUNT(*) INTO v_members_active FROM public.members WHERE tribe_id = p_tribe_id AND is_active = true AND current_cycle_active = true;
  SELECT COALESCE(jsonb_object_agg(role, cnt), '{}'::jsonb) INTO v_members_by_role
  FROM (SELECT operational_role AS role, COUNT(*) AS cnt FROM public.members
    WHERE tribe_id = p_tribe_id AND is_active = true GROUP BY operational_role) sub;
  SELECT COALESCE(jsonb_object_agg(ch, cnt), '{}'::jsonb) INTO v_members_by_chapter
  FROM (SELECT COALESCE(chapter, 'N/A') AS ch, COUNT(*) AS cnt FROM public.members
    WHERE tribe_id = p_tribe_id AND is_active = true GROUP BY chapter) sub;
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id, 'name', m.name, 'chapter', m.chapter, 'operational_role', m.operational_role,
      'xp_total', COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0),
      'attendance_rate', COALESCE(
        (SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(COUNT(*), 0), 2)
         FROM public.attendance a
         JOIN public.events e ON e.id = a.event_id
         JOIN public.initiatives i ON i.id = e.initiative_id
         WHERE a.member_id = m.id AND i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE), 0),
      'cpmai_certified', COALESCE(m.cpmai_certified, false),
      'last_activity_at', GREATEST(m.updated_at, (SELECT MAX(a2.created_at) FROM public.attendance a2 WHERE a2.member_id = m.id))
    ) ORDER BY COALESCE((SELECT SUM(points) FROM public.gamification_points WHERE member_id = m.id), 0) DESC
  ), '[]'::jsonb) INTO v_members_list
  FROM public.members m WHERE m.tribe_id = p_tribe_id AND m.is_active = true;
  SELECT pb.* INTO v_board
  FROM public.project_boards pb
  JOIN public.initiatives i ON i.id = pb.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND pb.domain_key = 'research_delivery' AND pb.is_active = true
  LIMIT 1;
  IF v_board.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_prod_total FROM public.board_items WHERE board_id = v_board.id;
    SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb) INTO v_prod_by_status
    FROM (SELECT status, COUNT(*) AS cnt FROM public.board_items WHERE board_id = v_board.id GROUP BY status) sub;
    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review', 'approved', 'published')) INTO v_articles_submitted
    FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status = 'approved') INTO v_articles_approved FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status = 'published') INTO v_articles_published FROM public.board_items WHERE board_id = v_board.id;
    SELECT COUNT(*) FILTER (WHERE curation_status IN ('submitted', 'under_review')) INTO v_curation_pending FROM public.board_items WHERE board_id = v_board.id;
  END IF;
  SELECT COUNT(DISTINCT e.id), COALESCE(SUM(COALESCE(e.duration_actual, e.duration_minutes, 60)) / 60.0, 0)
  INTO v_total_meetings, v_total_hours
  FROM public.events e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;
  IF v_total_meetings > 0 AND v_members_active > 0 THEN
    SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(v_members_active * v_total_meetings, 0), 2)
    INTO v_attendance_rate
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;
    SELECT ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(v_total_meetings, 0), 1)
    INTO v_avg_attendance
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE;
  END IF;
  SELECT MAX(e.date) INTO v_last_meeting_date
  FROM public.events e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id AND e.date <= CURRENT_DATE;
  SELECT COUNT(*) INTO v_members_inactive_30d
  FROM public.members m WHERE m.tribe_id = p_tribe_id AND m.is_active = true
    AND NOT EXISTS (SELECT 1 FROM public.attendance a JOIN public.events e ON e.id = a.event_id
      WHERE a.member_id = m.id AND a.present = true AND e.date >= (CURRENT_DATE - INTERVAL '30 days'));
  SELECT jsonb_build_object('day_of_week', tms.day_of_week, 'time_start', tms.time_start) INTO v_next_meeting
  FROM public.tribe_meeting_slots tms WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true LIMIT 1;
  SELECT COALESCE(SUM(gp.points), 0) INTO v_tribe_total_xp
  FROM public.gamification_points gp WHERE gp.member_id IN (SELECT id FROM public.members WHERE tribe_id = p_tribe_id AND is_active = true);
  v_tribe_avg_xp := CASE WHEN v_members_active > 0 THEN ROUND(v_tribe_total_xp::numeric / v_members_active, 1) ELSE 0 END;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', sub.name, 'xp', sub.xp, 'rank', sub.rn)), '[]'::jsonb) INTO v_top_contributors
  FROM (SELECT m.name, SUM(gp.points) AS xp, ROW_NUMBER() OVER (ORDER BY SUM(gp.points) DESC) AS rn
    FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id
    WHERE m.tribe_id = p_tribe_id AND m.is_active = true GROUP BY m.id, m.name
    ORDER BY xp DESC LIMIT 5) sub;
  SELECT COUNT(*) INTO v_cpmai_certified FROM public.members
  WHERE tribe_id = p_tribe_id AND is_active = true AND cpmai_certified = true;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', sub.month, 'rate', sub.rate) ORDER BY sub.month), '[]'::jsonb) INTO v_attendance_by_month
  FROM (SELECT TO_CHAR(e.date, 'YYYY-MM') AS month,
      ROUND(COUNT(*) FILTER (WHERE a.present = true)::numeric / NULLIF(COUNT(*), 0), 2) AS rate
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
    GROUP BY TO_CHAR(e.date, 'YYYY-MM')) sub;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', sub.month, 'cards_created', sub.created, 'cards_completed', sub.completed) ORDER BY sub.month), '[]'::jsonb) INTO v_production_by_month
  FROM (SELECT TO_CHAR(bi.created_at, 'YYYY-MM') AS month, COUNT(*) AS created,
      COUNT(*) FILTER (WHERE bi.status = 'done') AS completed
    FROM public.board_items bi WHERE bi.board_id = v_board.id AND bi.created_at >= v_cycle_start
    GROUP BY TO_CHAR(bi.created_at, 'YYYY-MM')) sub;
  v_result := jsonb_build_object(
    'tribe', jsonb_build_object('id', v_tribe.id, 'name', v_tribe.name,
      'quadrant', v_tribe.quadrant, 'quadrant_name', v_tribe.quadrant_name,
      'leader', CASE WHEN v_leader.id IS NOT NULL THEN jsonb_build_object('id', v_leader.id, 'name', v_leader.name, 'avatar_url', v_leader.photo_url) ELSE NULL END,
      'meeting_slots', v_meeting_slots, 'whatsapp_url', v_tribe.whatsapp_url, 'drive_url', v_tribe.drive_url),
    'members', jsonb_build_object('total', v_members_total, 'active', v_members_active,
      'by_role', v_members_by_role, 'by_chapter', v_members_by_chapter, 'list', v_members_list),
    'production', jsonb_build_object('total_cards', v_prod_total, 'by_status', v_prod_by_status,
      'articles_submitted', v_articles_submitted, 'articles_approved', v_articles_approved,
      'articles_published', v_articles_published, 'curation_pending', v_curation_pending,
      'avg_days_to_approval', v_avg_days_to_approval),
    'engagement', jsonb_build_object('attendance_rate', v_attendance_rate, 'total_meetings', v_total_meetings,
      'total_hours', ROUND(v_total_hours, 1), 'avg_attendance_per_meeting', v_avg_attendance,
      'members_inactive_30d', v_members_inactive_30d, 'last_meeting_date', v_last_meeting_date, 'next_meeting', v_next_meeting),
    'gamification', jsonb_build_object('tribe_total_xp', v_tribe_total_xp, 'tribe_avg_xp', v_tribe_avg_xp,
      'top_contributors', v_top_contributors,
      'certification_progress', jsonb_build_object('cpmai_certified', v_cpmai_certified)),
    'trends', jsonb_build_object('attendance_by_month', v_attendance_by_month, 'production_by_month', v_production_by_month)
  );
  RETURN v_result;
END;
$function$;

-- 2.9 get_admin_dashboard
CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_result jsonb; v_cycle_start date; v_current_cycle int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM members WHERE auth_id = auth.uid() AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager', 'sponsor', 'chapter_liaison'))) THEN RAISE EXCEPTION 'Admin only'; END IF;
  SELECT cycle_start,
    CASE WHEN cycle_code ~ '^\w+_\d+$' THEN substring(cycle_code from '\d+')::int ELSE sort_order END
  INTO v_cycle_start, v_current_cycle
  FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-01-01'; END IF;
  IF v_current_cycle IS NULL THEN v_current_cycle := 3; END IF;
  SELECT jsonb_build_object(
    'generated_at', now(),
    'kpis', jsonb_build_object(
      'active_members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'adoption_7d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*), 0) * 100, 1) FROM members WHERE is_active AND current_cycle_active),
      'deliverables_completed', (SELECT count(*) FROM board_items WHERE status = 'done'),
      'deliverables_total', (SELECT count(*) FROM board_items WHERE status != 'archived'),
      'impact_hours', (SELECT COALESCE(get_impact_hours_excluding_excused(), 0)),
      'cpmai_current', (SELECT count(DISTINCT member_id) FROM gamification_points WHERE category = 'cert_cpmai' AND created_at >= v_cycle_start),
      'cpmai_target', (SELECT target_value FROM annual_kpi_targets WHERE kpi_key = 'cpmai_certified' AND cycle = v_current_cycle LIMIT 1),
      'chapters_current', (SELECT count(DISTINCT chapter) FROM members WHERE is_active = true AND chapter IS NOT NULL),
      'chapters_target', (SELECT target_value FROM annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND cycle = v_current_cycle LIMIT 1)
    ),
    'alerts', (SELECT COALESCE(jsonb_agg(alert), '[]'::jsonb) FROM (
      SELECT jsonb_build_object('severity', 'high', 'message', count(*) || ' pesquisadores sem tribo', 'action_label', 'Ir para Tribos', 'action_href', '/admin/tribes') as alert FROM members WHERE is_active = true AND tribe_id IS NULL AND operational_role NOT IN ('sponsor', 'chapter_liaison', 'manager', 'deputy_manager', 'observer') HAVING count(*) > 0
      UNION ALL SELECT jsonb_build_object('severity', 'medium', 'message', count(*) || ' stakeholders sem conta', 'action_label', 'Ver Membros', 'action_href', '/admin/members') FROM members WHERE is_active = true AND auth_id IS NULL AND operational_role IN ('sponsor', 'chapter_liaison') HAVING count(*) > 0
      UNION ALL SELECT jsonb_build_object('severity', 'medium', 'message', count(*) || ' membros em risco de dropout', 'action_label', 'Ver lista', 'action_href', '/admin/members') FROM members m WHERE m.is_active = true AND m.current_cycle_active AND m.tribe_id IS NOT NULL AND m.id NOT IN (SELECT a.member_id FROM attendance a JOIN events e ON e.id = a.event_id WHERE e.date > now() - interval '60 days') HAVING count(*) > 0
      UNION ALL SELECT jsonb_build_object('severity', 'high', 'message', t.name || ' sem reuniao ha ' || (current_date - max(e.date)) || ' dias', 'action_label', 'Ver Tribo', 'action_href', '/tribe/' || t.id) FROM tribes t LEFT JOIN initiatives i ON i.legacy_tribe_id = t.id LEFT JOIN events e ON e.initiative_id = i.id AND e.type = 'tribo' AND e.date <= current_date WHERE t.is_active = true GROUP BY t.id, t.name HAVING max(e.date) IS NOT NULL AND current_date - max(e.date) > 14
      UNION ALL SELECT jsonb_build_object('severity', 'medium', 'message', count(*) || ' membros detractors (3+ faltas consecutivas)', 'action_label', 'Quadro de Presenca', 'action_href', '/attendance?tab=grid') FROM members m WHERE m.is_active AND m.current_cycle_active AND m.tribe_id IS NOT NULL AND m.id IN (SELECT dc.member_id FROM (SELECT a2.member_id, count(*) as consec FROM (SELECT member_id, ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY e2.date DESC) as rn FROM events e2 LEFT JOIN attendance a ON a.event_id = e2.id AND a.excused IS NOT TRUE WHERE e2.date >= (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1) AND e2.date < current_date AND e2.type IN ('geral', 'tribo') AND NOT EXISTS (SELECT 1 FROM attendance ax WHERE ax.event_id = e2.id AND ax.member_id = a.member_id)) a2 WHERE a2.rn <= 5 GROUP BY a2.member_id HAVING count(*) >= 3) dc) HAVING count(*) > 0
    ) sub),
    'recent_activity', (SELECT COALESCE(jsonb_agg(r.activity ORDER BY r.ts DESC), '[]'::jsonb) FROM (
      SELECT * FROM (SELECT jsonb_build_object('type', 'audit', 'message', actor.name || ' ' || al.action || ' em ' || COALESCE(target.name, '?'), 'details', al.changes, 'timestamp', al.created_at) as activity, al.created_at as ts FROM admin_audit_log al LEFT JOIN members actor ON actor.id = al.actor_id LEFT JOIN members target ON target.id = al.target_id WHERE al.created_at > now() - interval '7 days' ORDER BY al.created_at DESC LIMIT 10) a1
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'campaign', 'message', 'Campanha "' || ct.name || '" enviada', 'timestamp', cs.created_at), cs.created_at FROM campaign_sends cs JOIN campaign_templates ct ON ct.id = cs.template_id WHERE cs.created_at > now() - interval '7 days' ORDER BY cs.created_at DESC LIMIT 5) a2
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'publication', 'message', m.name || ' submeteu "' || ps.title || '"', 'timestamp', ps.submission_date), ps.submission_date FROM publication_submissions ps JOIN publication_submission_authors psa ON psa.submission_id = ps.id JOIN members m ON m.id = psa.member_id WHERE ps.submission_date > now() - interval '30 days' ORDER BY ps.submission_date DESC LIMIT 5) a3
    ) r LIMIT 15)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- 2.10 get_attendance_grid
CREATE OR REPLACE FUNCTION public.get_attendance_grid(p_tribe_id integer DEFAULT NULL::integer, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_caller_tribe_id
    FROM members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_member_id, 'manage_partner');

  IF NOT v_is_admin AND NOT v_is_stakeholder THEN
    IF v_caller_tribe_id IS NOT NULL THEN
      p_tribe_id := v_caller_tribe_id;
    ELSE
      RETURN jsonb_build_object('error', 'No tribe assigned');
    END IF;
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type, e.nature,
           i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date) AS week_number
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms', 'evento_externo')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.initiative_id IS NULL OR e.type = 'tribo')
    ORDER BY e.date
  ),
  active_members AS (
    SELECT m.id, m.name, m.tribe_id, m.chapter, m.operational_role, m.designations
    FROM members m
    WHERE m.is_active = true
      AND m.operational_role NOT IN ('guest', 'none')
      AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
  ),
  eligibility AS (
    SELECT m.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        WHEN ge.type = 'tribo' AND (m.tribe_id = ge.tribe_id OR m.operational_role IN ('manager', 'deputy_manager')) THEN true
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        WHEN ge.type = 'comms' AND m.designations && ARRAY['comms_team', 'comms_leader', 'comms_member'] THEN true
        ELSE false
      END AS is_eligible
    FROM active_members m CROSS JOIN grid_events ge
  ),
  cell_status AS (
    SELECT el.member_id, el.event_id, el.is_eligible,
      CASE
        WHEN NOT el.is_eligible THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN 'scheduled'
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL THEN 'present'
        ELSE 'absent'
      END AS status
    FROM eligibility el JOIN grid_events ge ON ge.id = el.event_id
    LEFT JOIN attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
  ),
  member_stats AS (
    SELECT cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2) AS rate,
      ROUND(SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1) AS hours
    FROM cell_status cs JOIN grid_events ge ON ge.id = cs.event_id
    GROUP BY cs.member_id
  ),
  detractor_calc AS (
    SELECT cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2 JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.status = 'absent' AND sub.rn <= (
        SELECT MIN(rn2) FROM (
          SELECT status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3 JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.status = 'present'
      )) AS consecutive_absences
    FROM cell_status cs GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM active_members),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms), 0),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc WHERE consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc WHERE consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type, 'nature', ge.nature,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_future', (ge.date > CURRENT_DATE)
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'tribes', (SELECT COALESCE(jsonb_agg(tribe_row ORDER BY tribe_row->>'tribe_name'), '[]'::jsonb) FROM (
      SELECT jsonb_build_object(
        'tribe_id', t.id, 'tribe_name', t.name,
        'leader_name', COALESCE((SELECT m2.name FROM members m2 WHERE m2.tribe_id = t.id AND m2.operational_role = 'tribe_leader' LIMIT 1), '—'),
        'avg_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN active_members am ON am.id = ms.member_id WHERE am.tribe_id = t.id), 0),
        'member_count', (SELECT COUNT(*) FROM active_members am WHERE am.tribe_id = t.id),
        'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', am.id, 'name', am.name, 'chapter', am.chapter,
          'rate', COALESCE(ms.rate, 0), 'hours', COALESCE(ms.hours, 0),
          'eligible_count', COALESCE(ms.eligible_count, 0), 'present_count', COALESCE(ms.present_count, 0),
          'detractor_status', CASE
            WHEN COALESCE(dc.consecutive_absences, 0) >= 3 THEN 'detractor'
            WHEN COALESCE(dc.consecutive_absences, 0) = 2 THEN 'at_risk'
            ELSE 'regular' END,
          'consecutive_absences', COALESCE(dc.consecutive_absences, 0),
          'attendance', (SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
            FROM cell_status cs WHERE cs.member_id = am.id)
        ) ORDER BY COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
          FROM active_members am
          LEFT JOIN member_stats ms ON ms.member_id = am.id
          LEFT JOIN detractor_calc dc ON dc.member_id = am.id
          WHERE am.tribe_id = t.id)
      ) AS tribe_row
      FROM tribes t WHERE t.is_active = true AND (p_tribe_id IS NULL OR t.id = p_tribe_id)
    ) sub)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- 2.11 get_attendance_summary
CREATE OR REPLACE FUNCTION public.get_attendance_summary(p_cycle_start date DEFAULT '2026-01-01'::date, p_cycle_end date DEFAULT '2026-06-30'::date, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS TABLE(member_id uuid, member_name text, tribe_id integer, tribe_name text, operational_role text, geral_present bigint, geral_total bigint, geral_pct numeric, tribe_present bigint, tribe_total bigint, tribe_pct numeric, combined_pct numeric, last_attendance date, consecutive_misses integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  WITH cycle_gerals AS (
    SELECT count(*) as cnt FROM events WHERE type = 'geral' AND date BETWEEN p_cycle_start AND p_cycle_end
  ),
  cycle_tribe_meetings AS (
    SELECT i.legacy_tribe_id as tid, count(*) as cnt
    FROM events e
    JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.type = 'tribo' AND e.date BETWEEN p_cycle_start AND p_cycle_end
    GROUP BY i.legacy_tribe_id
  ),
  member_gerals AS (
    SELECT a.member_id as mid, count(*) as cnt
    FROM attendance a JOIN events e ON e.id = a.event_id
    WHERE a.present AND e.type = 'geral' AND e.date BETWEEN p_cycle_start AND p_cycle_end
    GROUP BY a.member_id
  ),
  member_tribes AS (
    SELECT a.member_id as mid, count(*) as cnt
    FROM attendance a JOIN events e ON e.id = a.event_id
    WHERE a.present AND e.type = 'tribo' AND e.date BETWEEN p_cycle_start AND p_cycle_end
    GROUP BY a.member_id
  ),
  last_att AS (
    SELECT a.member_id as mid, max(e.date) as last_date
    FROM attendance a JOIN events e ON e.id = a.event_id WHERE a.present GROUP BY a.member_id
  )
  SELECT m.id, m.name, m.tribe_id, t.name, m.operational_role,
    COALESCE(mg.cnt, 0)::bigint,
    (SELECT cnt FROM cycle_gerals)::bigint,
    CASE WHEN (SELECT cnt FROM cycle_gerals) > 0
      THEN round(COALESCE(mg.cnt, 0)::numeric / (SELECT cnt FROM cycle_gerals) * 100, 1) ELSE 0 END,
    COALESCE(mt.cnt, 0)::bigint,
    COALESCE(ctm.cnt, 0)::bigint,
    CASE WHEN COALESCE(ctm.cnt, 0) > 0
      THEN round(COALESCE(mt.cnt, 0)::numeric / ctm.cnt * 100, 1) ELSE 0 END,
    round(
      0.4 * CASE WHEN (SELECT cnt FROM cycle_gerals) > 0
        THEN COALESCE(mg.cnt, 0)::numeric / (SELECT cnt FROM cycle_gerals) * 100 ELSE 0 END
      + 0.6 * CASE WHEN COALESCE(ctm.cnt, 0) > 0
        THEN COALESCE(mt.cnt, 0)::numeric / ctm.cnt * 100 ELSE 0 END
    , 1),
    la.last_date, 0
  FROM members m
  LEFT JOIN tribes t ON t.id = m.tribe_id
  LEFT JOIN member_gerals mg ON mg.mid = m.id
  LEFT JOIN member_tribes mt ON mt.mid = m.id
  LEFT JOIN cycle_tribe_meetings ctm ON ctm.tid = m.tribe_id
  LEFT JOIN last_att la ON la.mid = m.id
  WHERE m.is_active = true
    AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
  ORDER BY combined_pct ASC NULLS FIRST;
END;
$function$;

-- 2.12 get_cross_tribe_comparison (also fixes stale pb.tribe_id + bi.tribe_id)
CREATE OR REPLACE FUNCTION public.get_cross_tribe_comparison()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cycle_start date;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager', 'tribe_leader', 'sponsor', 'chapter_liaison')
         OR designations && ARRAY['chapter_board', 'curator'])
  ) THEN RETURN json_build_object('error', 'Unauthorized'); END IF;

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

-- 2.13 get_meeting_detail
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

-- 2.14 get_meeting_notes_compliance
CREATE OR REPLACE FUNCTION public.get_meeting_notes_compliance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  WITH stats AS (
    SELECT
      i.legacy_tribe_id AS t_id,
      COALESCE(i.title, 'Gerais/sem tribo') AS group_name,
      count(*) FILTER (WHERE e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL) AS recorded,
      count(*) FILTER (
        WHERE (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL)
          AND e.minutes_text IS NOT NULL
          AND length(trim(e.minutes_text)) >= 20
          AND lower(trim(e.minutes_text)) NOT IN ('teste', 'teste teste', 'test', 'placeholder', '-')
      ) AS with_minutes
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date <= current_date
    GROUP BY i.legacy_tribe_id, COALESCE(i.title, 'Gerais/sem tribo')
  )
  SELECT jsonb_build_object(
    'by_tribe', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'tribe_id', s.t_id, 'tribe_name', s.group_name,
          'recorded', s.recorded, 'with_minutes', s.with_minutes,
          'pct', CASE WHEN s.recorded > 0 THEN round(100.0 * s.with_minutes / s.recorded) ELSE 100 END
        ) ORDER BY CASE WHEN s.recorded > 0 THEN round(100.0 * s.with_minutes / s.recorded) ELSE 100 END ASC
      ) FROM stats s WHERE s.recorded > 0
    ), '[]'::jsonb),
    'total_recorded', (SELECT sum(recorded) FROM stats),
    'total_with_minutes', (SELECT sum(with_minutes) FROM stats),
    'overall_pct', CASE
      WHEN (SELECT sum(recorded) FROM stats) > 0
      THEN round(100.0 * (SELECT sum(with_minutes) FROM stats) / (SELECT sum(recorded) FROM stats))
      ELSE 100
    END
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- 2.15 get_member_attendance_hours
CREATE OR REPLACE FUNCTION public.get_member_attendance_hours(p_member_id uuid, p_cycle_code text DEFAULT 'cycle_3'::text)
 RETURNS TABLE(total_hours numeric, total_events integer, avg_hours_per_event numeric, current_streak integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_is_admin boolean;
  v_cycle_start date;
  v_streak int := 0;
  v_rec record;
  v_target_tribe int;
BEGIN
  SELECT id, operational_role, is_superadmin
  INTO v_caller_id, v_caller_role, v_is_admin
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (v_caller_id = p_member_id OR v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager', 'tribe_leader')) THEN
    RAISE EXCEPTION 'Unauthorized: can only view own attendance or requires admin role';
  END IF;

  SELECT cycle_start INTO v_cycle_start
  FROM public.cycles WHERE cycle_code = p_cycle_code;

  IF v_cycle_start IS NULL THEN
    RETURN QUERY SELECT 0::numeric, 0::int, 0::numeric, 0::int;
    RETURN;
  END IF;

  SELECT tribe_id INTO v_target_tribe FROM public.members WHERE id = p_member_id;

  FOR v_rec IN
    SELECT e.id,
           EXISTS(SELECT 1 FROM public.attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id) AS was_present
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND e.date <= current_date
      AND (e.initiative_id IS NULL
           OR i.legacy_tribe_id = v_target_tribe)
    ORDER BY e.date DESC
  LOOP
    IF v_rec.was_present THEN
      v_streak := v_streak + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;

  RETURN QUERY
  SELECT
    COALESCE(SUM(e.duration_minutes / 60.0), 0)::numeric          AS total_hours,
    COUNT(DISTINCT a.event_id)::int                                AS total_events,
    CASE WHEN COUNT(DISTINCT a.event_id) > 0
      THEN (COALESCE(SUM(e.duration_minutes / 60.0), 0) / COUNT(DISTINCT a.event_id))::numeric
      ELSE 0::numeric
    END                                                            AS avg_hours_per_event,
    v_streak                                                       AS current_streak
  FROM public.attendance a
  JOIN public.events e ON e.id = a.event_id
  WHERE a.member_id = p_member_id
    AND e.date >= v_cycle_start;
END;
$function$;

-- 2.16 get_my_attendance_history
CREATE OR REPLACE FUNCTION public.get_my_attendance_history(p_limit integer DEFAULT 30)
 RETURNS TABLE(event_id uuid, event_title text, event_type text, event_date date, duration_minutes integer, present boolean, excused boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_tribe_id int;
BEGIN
  SELECT m.id, m.tribe_id INTO v_member_id, v_tribe_id
  FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  IF v_member_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.type,
    e.date::date,
    e.duration_minutes,
    COALESCE(a.present, false),
    COALESCE(a.excused, false)
  FROM events e
  LEFT JOIN attendance a ON a.event_id = e.id AND a.member_id = v_member_id
  LEFT JOIN initiatives i ON i.id = e.initiative_id
  WHERE e.date <= CURRENT_DATE
    AND (
      e.type IN ('geral', 'kickoff')
      OR (e.type = 'tribo' AND i.legacy_tribe_id = v_tribe_id)
      OR a.id IS NOT NULL
      OR EXISTS (SELECT 1 FROM event_invited_members eim WHERE eim.event_id = e.id AND eim.member_id = v_member_id)
      OR is_event_mandatory_for_member(e.id, v_member_id)
    )
  ORDER BY e.date DESC
  LIMIT p_limit;
END;
$function$;

-- 2.17 get_near_events
CREATE OR REPLACE FUNCTION public.get_near_events(p_member_id uuid, p_window_hours integer DEFAULT 2)
 RETURNS TABLE(event_id uuid, event_title text, event_date date, event_type text, duration_minutes integer, already_checked_in boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tribe_id int;
BEGIN
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
  ORDER BY e.date ASC
  LIMIT 3;
END;
$function$;

-- 2.18 get_recent_events
CREATE OR REPLACE FUNCTION public.get_recent_events(p_days_back integer DEFAULT 30, p_days_forward integer DEFAULT 7)
 RETURNS TABLE(id uuid, date date, type text, title text, tribe_id integer, tribe_name text, headcount bigint, duration_minutes integer, duration_actual integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    e.id, e.date, e.type, e.title, i.legacy_tribe_id,
    i.title AS tribe_name,
    (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present) AS headcount,
    e.duration_minutes, e.duration_actual
  FROM events e
  LEFT JOIN initiatives i ON i.id = e.initiative_id
  WHERE e.date BETWEEN current_date - p_days_back AND current_date + p_days_forward
  ORDER BY e.date DESC;
END;
$function$;

-- 2.19 get_tribe_attendance_grid
CREATE OR REPLACE FUNCTION public.get_tribe_attendance_grid(p_tribe_id integer, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_caller_tribe_id
    FROM members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_member_id, 'manage_partner');

  IF NOT v_is_admin AND NOT v_is_stakeholder
     AND COALESCE(v_caller_tribe_id, -1) <> p_tribe_id THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type, i.legacy_tribe_id AS tribe_id,
           i.title AS tribe_name,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number
    FROM events e LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff') OR e.type = 'lideranca')
      AND (p_event_type IS NULL OR e.type = p_event_type)
      AND (e.initiative_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    ORDER BY e.date
  ),
  grid_members AS (
    SELECT m.id, m.name, m.tribe_id, m.chapter, m.operational_role, m.designations, m.member_status
    FROM members m
    WHERE m.member_status = 'active' AND m.tribe_id = p_tribe_id
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    UNION
    SELECT DISTINCT m.id, m.name, m.tribe_id, m.chapter, m.operational_role, m.designations, m.member_status
    FROM members m JOIN attendance a ON a.member_id = m.id JOIN grid_events ge ON ge.id = a.event_id
    WHERE m.member_status IN ('observer', 'alumni', 'inactive')
      AND (m.tribe_id = p_tribe_id OR EXISTS (
        SELECT 1 FROM member_status_transitions mst
        WHERE mst.member_id = m.id AND mst.previous_tribe_id = p_tribe_id))
  ),
  eligibility AS (
    SELECT m.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.type IN ('geral', 'kickoff') THEN true
        WHEN ge.type = 'tribo' AND ge.tribe_id = p_tribe_id THEN true
        WHEN ge.type = 'lideranca' AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader') THEN true
        ELSE false
      END AS is_eligible
    FROM grid_members m CROSS JOIN grid_events ge
  ),
  cell_status AS (
    SELECT el.member_id, el.event_id, el.is_eligible,
      CASE
        WHEN NOT el.is_eligible THEN 'na'
        WHEN ge.date > CURRENT_DATE THEN CASE WHEN gm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL THEN 'present'
        ELSE CASE
          WHEN gm.member_status != 'active' AND (gm.offboarded_at IS NULL OR gm.offboarded_at::date > ge.date) THEN 'absent'
          WHEN gm.member_status != 'active' AND gm.offboarded_at IS NOT NULL AND gm.offboarded_at::date <= ge.date THEN 'na'
          ELSE 'absent' END
      END AS status
    FROM eligibility el JOIN grid_events ge ON ge.id = el.event_id
    JOIN (SELECT id, member_status, offboarded_at FROM members) gm ON gm.id = el.member_id
    LEFT JOIN attendance a ON a.member_id = el.member_id AND a.event_id = el.event_id
  ),
  member_stats AS (
    SELECT cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2) AS rate,
      ROUND(SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1) AS hours
    FROM cell_status cs JOIN grid_events ge ON ge.id = cs.event_id GROUP BY cs.member_id
  ),
  detractor_calc AS (
    SELECT cs.member_id,
      (SELECT COUNT(*) FROM (
        SELECT status, ROW_NUMBER() OVER (ORDER BY ge2.date DESC) AS rn
        FROM cell_status cs2 JOIN grid_events ge2 ON ge2.id = cs2.event_id
        WHERE cs2.member_id = cs.member_id AND cs2.status IN ('present', 'absent')
        ORDER BY ge2.date DESC
      ) sub WHERE sub.status = 'absent' AND sub.rn <= COALESCE((
        SELECT MIN(rn2) FROM (
          SELECT status, ROW_NUMBER() OVER (ORDER BY ge3.date DESC) AS rn2
          FROM cell_status cs3 JOIN grid_events ge3 ON ge3.id = cs3.event_id
          WHERE cs3.member_id = cs.member_id AND cs3.status IN ('present', 'absent')
          ORDER BY ge3.date DESC
        ) sub2 WHERE sub2.status = 'present'), 999)) AS consecutive_absences
    FROM cell_status cs GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM grid_members WHERE member_status = 'active'),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'perfect_attendance', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate >= 1.0),
      'below_50', (SELECT COUNT(*) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active' AND ms.rate < 0.5 AND ms.rate > 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0),
      'detractors_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences >= 3),
      'at_risk_count', (SELECT COUNT(*) FROM detractor_calc dc JOIN grid_members gm ON gm.id = dc.member_id WHERE gm.member_status = 'active' AND dc.consecutive_absences = 2)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type,
      'tribe_id', ge.tribe_id, 'tribe_name', ge.tribe_name,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', (ge.tribe_id = p_tribe_id), 'is_future', (ge.date > CURRENT_DATE)
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', am.id, 'name', am.name, 'chapter', am.chapter, 'member_status', am.member_status,
      'rate', COALESCE(ms.rate, 0), 'hours', COALESCE(ms.hours, 0),
      'eligible_count', COALESCE(ms.eligible_count, 0), 'present_count', COALESCE(ms.present_count, 0),
      'detractor_status', CASE
        WHEN am.member_status != 'active' THEN 'inactive'
        WHEN COALESCE(dc.consecutive_absences, 0) >= 3 THEN 'detractor'
        WHEN COALESCE(dc.consecutive_absences, 0) = 2 THEN 'at_risk'
        ELSE 'regular' END,
      'consecutive_absences', COALESCE(dc.consecutive_absences, 0),
      'attendance', (SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
        FROM cell_status cs WHERE cs.member_id = am.id)
    ) ORDER BY CASE WHEN am.member_status = 'active' THEN 0 ELSE 1 END, COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
      FROM grid_members am
      LEFT JOIN member_stats ms ON ms.member_id = am.id
      LEFT JOIN detractor_calc dc ON dc.member_id = am.id)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- 2.20 get_tribe_events_timeline
CREATE OR REPLACE FUNCTION public.get_tribe_events_timeline(p_tribe_id integer, p_upcoming_limit integer DEFAULT 3, p_past_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_upcoming jsonb;
  v_past jsonb;
  v_next_recurring jsonb;
  v_tribe_member_count int;
  v_now_brt timestamptz := NOW() AT TIME ZONE 'America/Sao_Paulo';
  v_today_brt date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT count(*) INTO v_tribe_member_count
  FROM members
  WHERE tribe_id = p_tribe_id AND is_active = true
    AND operational_role NOT IN ('sponsor', 'chapter_liaison');

  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'date', row_data->>'title'), '[]'::jsonb)
  INTO v_upcoming
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'date', e.date,
      'type', e.type,
      'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_minutes, 60),
      'meeting_link', e.meeting_link,
      'audience_level', e.audience_level,
      'tribe_id', i.legacy_tribe_id,
      'is_tribe_event', (i.legacy_tribe_id = p_tribe_id),
      'agenda_text', e.agenda_text,
      'eligible_count', CASE
        WHEN e.type IN ('geral', 'kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN i.legacy_tribe_id = p_tribe_id THEN v_tribe_member_count
        ELSE 0
      END
    ) as row_data
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff', 'lideranca'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
      AND (
        e.date > v_today_brt
        OR (
          e.date = v_today_brt
          AND (
            e.date::timestamp
            + COALESCE(
                (SELECT tms.time_start FROM tribe_meeting_slots tms
                 WHERE tms.tribe_id = i.legacy_tribe_id AND tms.is_active LIMIT 1),
                '19:30'::time
              )
            + (COALESCE(e.duration_minutes, 60) || ' minutes')::interval
          )::timestamp > v_now_brt::timestamp
        )
      )
    ORDER BY e.date ASC
    LIMIT p_upcoming_limit
  ) sub;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'date') DESC), '[]'::jsonb)
  INTO v_past
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'title', e.title,
      'date', e.date,
      'type', e.type,
      'nature', e.nature,
      'duration_minutes', COALESCE(e.duration_actual, e.duration_minutes, 60),
      'tribe_id', i.legacy_tribe_id,
      'is_tribe_event', (i.legacy_tribe_id = p_tribe_id),
      'youtube_url', e.youtube_url,
      'recording_url', e.recording_url,
      'recording_type', e.recording_type,
      'has_recording', (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL),
      'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true),
      'eligible_count', CASE
        WHEN e.type IN ('geral', 'kickoff') THEN (SELECT count(*) FROM members WHERE is_active AND current_cycle_active)
        WHEN i.legacy_tribe_id = p_tribe_id THEN v_tribe_member_count
        ELSE 0
      END,
      'agenda_text', e.agenda_text,
      'minutes_text', e.minutes_text
    ) as row_data
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date <= v_today_brt
      AND (i.legacy_tribe_id = p_tribe_id OR e.type IN ('geral', 'kickoff'))
      AND COALESCE(e.visibility, 'all') != 'gp_only'
    ORDER BY e.date DESC
    LIMIT p_past_limit
  ) sub;

  SELECT jsonb_build_object(
    'day_of_week', tms.day_of_week,
    'time_start', tms.time_start,
    'time_end', tms.time_end,
    'day_name_pt', CASE tms.day_of_week
      WHEN 0 THEN 'Domingo' WHEN 1 THEN 'Segunda' WHEN 2 THEN 'Terça'
      WHEN 3 THEN 'Quarta' WHEN 4 THEN 'Quinta' WHEN 5 THEN 'Sexta' WHEN 6 THEN 'Sábado'
    END,
    'day_name_en', CASE tms.day_of_week
      WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday'
      WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday' WHEN 6 THEN 'Saturday'
    END
  ) INTO v_next_recurring
  FROM tribe_meeting_slots tms
  WHERE tms.tribe_id = p_tribe_id AND tms.is_active = true
  LIMIT 1;

  RETURN jsonb_build_object(
    'upcoming', v_upcoming,
    'past', v_past,
    'next_recurring', COALESCE(v_next_recurring, 'null'::jsonb),
    'tribe_member_count', v_tribe_member_count
  );
END;
$function$;

-- 2.21 list_meetings_with_notes
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

  SELECT count(*) INTO v_total
  FROM events e
  LEFT JOIN initiatives i ON i.id = e.initiative_id
  WHERE (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
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

-- 2.22 list_radar_global (drop now-noop tribe_id filter)
CREATE OR REPLACE FUNCTION public.list_radar_global(p_webinars_limit integer DEFAULT 5, p_publications_limit integer DEFAULT 5)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_webinars json;
  v_publications json;
  v_today date := current_date;
BEGIN
  SELECT coalesce(json_agg(row_to_json(w)), '[]'::json) INTO v_webinars
  FROM (
    SELECT e.id, e.title, e.date, e.meeting_link, e.type
    FROM public.events e
    WHERE e.type = 'webinar'
      AND e.date >= v_today
    ORDER BY e.date ASC
    LIMIT p_webinars_limit
  ) w;

  SELECT coalesce(json_agg(row_to_json(p)), '[]'::json) INTO v_publications
  FROM (
    SELECT bi.id, bi.title, bi.description, bi.updated_at
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    WHERE coalesce(pb.domain_key, '') = 'publications_submissions'
      AND bi.status = 'done'
      AND pb.is_active = true
    ORDER BY bi.updated_at DESC NULLS LAST
    LIMIT p_publications_limit
  ) p;

  RETURN json_build_object(
    'webinars', coalesce(v_webinars, '[]'::json),
    'publications', coalesce(v_publications, '[]'::json)
  );
END;
$function$;

-- 2.23 send_attendance_reminders
CREATE OR REPLACE FUNCTION public.send_attendance_reminders()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_event record;
  v_count int := 0;
BEGIN
  PERFORM 1 FROM members WHERE auth_id = auth.uid() AND (is_superadmin = true OR operational_role = 'manager');
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

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

-- 2.24 send_attendance_reminders_cron
CREATE OR REPLACE FUNCTION public.send_attendance_reminders_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_event record;
  v_count int := 0;
BEGIN
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
-- 3. Writers (remove tribe_id from INSERT/UPDATE; initiative_id remains)
-- ============================================================================

-- 3.1 create_event (keep p_tribe_id param for lookup; drop from INSERT)
CREATE OR REPLACE FUNCTION public.create_event(p_type text, p_title text, p_date date, p_duration_minutes integer DEFAULT 90, p_tribe_id integer DEFAULT NULL::integer, p_meeting_link text DEFAULT NULL::text, p_nature text DEFAULT 'recorrente'::text, p_visibility text DEFAULT 'all'::text, p_agenda_text text DEFAULT NULL::text, p_agenda_url text DEFAULT NULL::text, p_external_attendees text[] DEFAULT NULL::text[], p_invited_member_ids uuid[] DEFAULT NULL::uuid[], p_audience_level text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_member_id uuid;
  v_member_tribe_id integer;
  v_is_admin boolean;
  v_event_id uuid;
  v_audience text;
  v_initiative_id uuid;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_member_tribe_id
  FROM members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT public.can_by_member(v_member_id, 'manage_event') THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized: requires manage_event permission');
  END IF;

  IF p_type NOT IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN
    RETURN json_build_object('success', false, 'error', 'Invalid event type: ' || p_type);
  END IF;

  IF p_nature NOT IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN
    p_nature := 'avulsa';
  END IF;

  IF p_type IN ('parceria','entrevista','1on1') THEN
    p_visibility := 'gp_only';
  ELSIF p_visibility NOT IN ('all','leadership','gp_only') THEN
    p_visibility := 'all';
  END IF;

  IF p_type = 'tribo' AND p_tribe_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'tribe_id required for tribe events');
  END IF;

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    IF p_type NOT IN ('tribo') THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe events');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_member_tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
    p_external_attendees := NULL;
    p_invited_member_ids := NULL;
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  v_audience := COALESCE(p_audience_level,
    CASE p_type
      WHEN 'tribo'     THEN 'tribe'
      WHEN 'lideranca' THEN 'leadership'
      WHEN 'comms'     THEN 'leadership'
      ELSE 'all'
    END
  );

  INSERT INTO events (
    type, title, date, duration_minutes,
    initiative_id,
    audience_level, meeting_link,
    nature, visibility, agenda_text, agenda_url,
    external_attendees, invited_member_ids, created_by
  )
  VALUES (
    p_type, p_title, p_date, p_duration_minutes,
    v_initiative_id,
    v_audience, p_meeting_link,
    p_nature, p_visibility, p_agenda_text, p_agenda_url,
    p_external_attendees, p_invited_member_ids, auth.uid()
  )
  RETURNING id INTO v_event_id;

  IF p_agenda_text IS NOT NULL OR p_agenda_url IS NOT NULL THEN
    UPDATE events SET agenda_posted_at = now(), agenda_posted_by = v_member_id
    WHERE id = v_event_id;
  END IF;

  RETURN json_build_object('success', true, 'event_id', v_event_id);
END; $function$;

-- 3.2 create_initiative_event (remove tribe_id column + var)
CREATE OR REPLACE FUNCTION public.create_initiative_event(p_initiative_id uuid, p_title text, p_date date, p_time_start time without time zone DEFAULT '19:00:00'::time without time zone, p_duration_minutes integer DEFAULT 60, p_type text DEFAULT 'geral'::text, p_meeting_link text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_person_id uuid;
  v_initiative record;
  v_event_id uuid;
BEGIN
  SELECT p.id INTO v_caller_person_id FROM persons p WHERE p.auth_id = auth.uid();
  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT can(v_caller_person_id, 'manage_event', 'initiative', p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_event permission');
  END IF;

  SELECT id, kind, status INTO v_initiative
  FROM initiatives WHERE id = p_initiative_id;

  IF v_initiative IS NULL THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;
  IF v_initiative.status NOT IN ('active', 'draft') THEN
    RETURN jsonb_build_object('error', 'Initiative is not active');
  END IF;

  INSERT INTO events (title, date, time_start, duration_minutes, type,
                      initiative_id, created_by, meeting_link, organization_id)
  VALUES (p_title, p_date, p_time_start, p_duration_minutes, p_type,
          p_initiative_id, auth.uid(), p_meeting_link,
          '2b4f58ab-7c45-4170-8718-b77ee69ff906')
  RETURNING id INTO v_event_id;

  RETURN jsonb_build_object('ok', true, 'event_id', v_event_id);
END;
$function$;

-- 3.3 create_recurring_weekly_events (add initiative lookup; drop tribe_id from INSERT)
CREATE OR REPLACE FUNCTION public.create_recurring_weekly_events(p_type text, p_title_template text, p_start_date date, p_duration_minutes integer DEFAULT 60, p_n_weeks integer DEFAULT 10, p_meeting_link text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_is_recorded boolean DEFAULT false, p_audience_level text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller   RECORD;
  v_group_id UUID := gen_random_uuid();
  v_week     INTEGER;
  v_date     DATE;
  v_title    TEXT;
  v_ids      UUID[] := '{}';
  v_new_id   UUID;
  v_initiative_id UUID;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_caller IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF v_caller.is_superadmin THEN
    NULL;
  ELSIF v_caller.operational_role IN ('manager', 'deputy_manager') THEN
    NULL;
  ELSIF v_caller.operational_role = 'tribe_leader' THEN
    IF p_type NOT IN ('tribo', 'tribe_meeting') THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe meetings');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
  ELSE
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;

  IF p_type = 'tribe_meeting' THEN
    p_type := 'tribo';
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  FOR v_week IN 1..p_n_weeks LOOP
    v_date  := p_start_date + ((v_week - 1) * 7);
    v_title := REPLACE(
                 REPLACE(p_title_template, '{n}', v_week::TEXT),
                 '{date}', TO_CHAR(v_date, 'DD/MM')
               );

    INSERT INTO public.events
      (type, title, date, duration_minutes, initiative_id, meeting_link,
       is_recorded, recurrence_group, created_by, audience_level)
    VALUES
      (p_type, v_title, v_date, p_duration_minutes,
       v_initiative_id, p_meeting_link, p_is_recorded, v_group_id, auth.uid(),
       p_audience_level)
    RETURNING id INTO v_new_id;

    v_ids := array_append(v_ids, v_new_id);
  END LOOP;

  RETURN json_build_object(
    'success',          true,
    'recurrence_group', v_group_id,
    'events_created',   p_n_weeks,
    'event_ids',        v_ids
  );
END;
$function$;

-- 3.4 curate_item (events branch: remove tribe_id from SETs)
CREATE OR REPLACE FUNCTION public.curate_item(p_table text, p_id uuid, p_action text, p_tags text[] DEFAULT NULL::text[], p_tribe_id integer DEFAULT NULL::integer, p_audience_level text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller record;
  v_rows integer := 0;
  v_enqueue_publication boolean := false;
  v_initiative_id uuid := NULL;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin
      or v_caller.operational_role in ('manager', 'deputy_manager')
    ) then
    raise exception 'Admin access required';
  end if;

  if p_action not in ('approve', 'reject', 'update_tags') then
    raise exception 'Invalid action: %', p_action;
  end if;

  if p_tribe_id is not null then
    SELECT id INTO v_initiative_id FROM public.initiatives WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  end if;

  if p_table = 'knowledge_assets' then
    if p_action = 'approve' then
      update public.knowledge_assets
      set
        is_active = true,
        published_at = coalesce(published_at, now()),
        tags = coalesce(p_tags, tags),
        metadata = case
          when p_tribe_id is null then metadata
          else jsonb_set(coalesce(metadata, '{}'::jsonb), '{target_tribe_id}', to_jsonb(p_tribe_id), true)
        end
      where id = p_id;
    elsif p_action = 'reject' then
      update public.knowledge_assets
      set
        is_active = false,
        published_at = null
      where id = p_id;
    else
      update public.knowledge_assets
      set tags = coalesce(p_tags, tags)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'artifacts' then
    if p_action = 'approve' then
      update public.artifacts
      set
        curation_status = 'approved',
        tags = coalesce(p_tags, tags),
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
      v_enqueue_publication := coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), '') = 'pmi_submission';
    elsif p_action = 'reject' then
      update public.artifacts
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.artifacts
      set
        tags = coalesce(p_tags, tags),
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'hub_resources' then
    if p_action = 'approve' then
      update public.hub_resources
      set
        curation_status = 'approved',
        tags = coalesce(p_tags, tags),
        initiative_id = coalesce(v_initiative_id, initiative_id)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.hub_resources
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.hub_resources
      set
        tags = coalesce(p_tags, tags),
        initiative_id = coalesce(v_initiative_id, initiative_id)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'events' then
    if p_action = 'approve' then
      update public.events
      set
        curation_status = 'approved',
        initiative_id = coalesce(v_initiative_id, initiative_id),
        audience_level = coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), audience_level)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.events
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.events
      set
        initiative_id = coalesce(v_initiative_id, initiative_id),
        audience_level = coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), audience_level)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  else
    raise exception 'Invalid table: %', p_table;
  end if;

  if v_rows = 0 then
    raise exception 'Item not found: % in %', p_id, p_table;
  end if;

  if p_table = 'artifacts' and p_action = 'approve' and v_enqueue_publication then
    perform public.enqueue_artifact_publication_card(p_id, v_caller.id);
  end if;

  return jsonb_build_object(
    'success', true,
    'table', p_table,
    'id', p_id,
    'action', p_action,
    'tribe_id', p_tribe_id,
    'audience_level', p_audience_level,
    'publication_enqueued', (p_table = 'artifacts' and p_action = 'approve' and v_enqueue_publication),
    'by', v_caller.name
  );
end;
$function$;

-- 3.5 link_webinar_event (drop tribe_id from INSERT; keep v_event_tribe_id for audience)
CREATE OR REPLACE FUNCTION public.link_webinar_event(p_webinar_id uuid, p_event_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_member_id uuid; v_event_id uuid;
  v_webinar webinars%ROWTYPE; v_event_initiative_id uuid;
  v_event_tribe_id integer; v_audience text;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: not authenticated'; END IF;

  SELECT * INTO v_webinar FROM public.webinars WHERE id = p_webinar_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'webinar_not_found'; END IF;

  IF NOT (
    public.can_by_member(v_member_id, 'manage_member')
    OR v_member_id = v_webinar.organizer_id
    OR v_member_id = ANY(v_webinar.co_manager_ids)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member or organizer role';
  END IF;

  IF p_event_id IS NOT NULL THEN
    v_event_id := p_event_id;
  ELSE
    v_event_initiative_id := v_webinar.initiative_id;
    IF v_event_initiative_id IS NOT NULL THEN
      SELECT legacy_tribe_id INTO v_event_tribe_id
      FROM public.initiatives WHERE id = v_event_initiative_id;
    END IF;

    v_audience := CASE WHEN v_event_tribe_id IS NOT NULL THEN 'tribe' ELSE 'all' END;

    INSERT INTO public.events (title, type, date, duration_minutes, initiative_id,
      meeting_link, youtube_url, audience_level, created_by, source)
    VALUES (
      v_webinar.title, 'webinar', v_webinar.scheduled_at::date,
      v_webinar.duration_min, v_event_initiative_id,
      v_webinar.meeting_link, v_webinar.youtube_url, v_audience, auth.uid(),
      'webinar_governance'
    )
    RETURNING id INTO v_event_id;
  END IF;

  UPDATE public.webinars SET event_id = v_event_id WHERE id = p_webinar_id;

  INSERT INTO public.webinar_lifecycle_events (webinar_id, action, actor_id, metadata)
  VALUES (p_webinar_id, 'event_linked', v_member_id,
    jsonb_build_object('event_id', v_event_id));

  RETURN jsonb_build_object('ok', true, 'event_id', v_event_id, 'webinar_id', p_webinar_id);
END; $function$;

-- ============================================================================
-- 4. Drop dependent views (block DROP COLUMN)
-- ============================================================================
DROP VIEW IF EXISTS public.impact_hours_summary;
DROP VIEW IF EXISTS public.recurring_event_groups;

-- ============================================================================
-- 5. DROP COLUMN events.tribe_id (idx_events_tribe auto-drops)
-- ============================================================================
ALTER TABLE public.events DROP COLUMN tribe_id;

-- ============================================================================
-- 6. Recreate views (derive tribe_id via JOIN initiatives)
-- ============================================================================
CREATE OR REPLACE VIEW public.impact_hours_summary AS
  SELECT i.legacy_tribe_id AS tribe_id,
      count(DISTINCT e.id) AS total_events,
      count(a.id) FILTER (WHERE (a.present = true)) AS total_attendances,
      ((sum(e.duration_minutes) FILTER (WHERE (a.present = true)))::numeric / 60.0) AS impact_hours_raw,
      sum((((e.duration_minutes)::numeric * 1.0) / 60.0)) FILTER (WHERE (a.present = true)) AS impact_hours
  FROM events e
  LEFT JOIN initiatives i ON i.id = e.initiative_id
  LEFT JOIN attendance a ON a.event_id = e.id
  GROUP BY i.legacy_tribe_id;

CREATE OR REPLACE VIEW public.recurring_event_groups AS
  SELECT e.recurrence_group,
      e.type,
      i.legacy_tribe_id AS tribe_id,
      e.meeting_link,
      min(e.date) AS first_date,
      max(e.date) AS last_date,
      count(*) AS total_events,
      count(*) FILTER (WHERE (e.date < CURRENT_DATE)) AS past_events,
      count(*) FILTER (WHERE (e.date >= CURRENT_DATE)) AS upcoming_events
  FROM events e
  LEFT JOIN initiatives i ON i.id = e.initiative_id
  WHERE (e.recurrence_group IS NOT NULL)
  GROUP BY e.recurrence_group, e.type, i.legacy_tribe_id, e.meeting_link
  ORDER BY (min(e.date)) DESC;

-- Preserve grants (matched pre-drop state: full CRUD on all roles)
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.impact_hours_summary TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.recurring_event_groups TO anon, authenticated, service_role;

-- ============================================================================
-- 7. Reload PostgREST schema cache
-- ============================================================================
NOTIFY pgrst, 'reload schema';
