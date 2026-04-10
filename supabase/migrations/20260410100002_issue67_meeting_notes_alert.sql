-- ============================================================
-- Issue #67: Add operational alert for recorded events without meeting notes
-- Adds ALERT 6 to detect_operational_alerts:
-- events with youtube_url/recording_url but minutes_text empty/null/placeholder
-- ============================================================

CREATE OR REPLACE FUNCTION public.detect_operational_alerts()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
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

  -- ALERT 1: Tribes with no meeting in current cycle or 14+ days since last
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
    FROM tribes t LEFT JOIN events e ON e.tribe_id = t.id
    WHERE t.is_active = true
    GROUP BY t.id, t.name
    HAVING MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) < current_date - 14
       OR MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) IS NULL
  ) sub;
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  -- ALERT 2: Members absent from last 3 tribe meetings
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
    WHERE e.tribe_id = m.tribe_id AND e.date >= current_date - 21 AND a.present = true
  );
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  -- ALERT 3: Tribes with zero card movement in 14+ days
  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'medium', 'type', 'tribe_stagnant_production',
    'tribe_id', t.id, 'tribe_name', t.name,
    'message', t.name || ' sem movimentação de cards em 14+ dias'
  ))
  INTO v_tmp
  FROM tribes t WHERE t.is_active = true
  AND t.id NOT IN (
    SELECT DISTINCT pb.tribe_id FROM board_lifecycle_events ble
    JOIN board_items bi ON bi.id = ble.item_id
    JOIN project_boards pb ON pb.id = bi.board_id
    WHERE ble.created_at >= now() - interval '14 days' AND pb.tribe_id IS NOT NULL
  );
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  -- ALERT 4: Onboarding overdue
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

  -- ALERT 5: KPI at risk
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

  -- ALERT 6 (Issue #67): Recorded events without meeting notes
  -- Event has youtube_url OR recording_url but minutes_text is null/empty/placeholder
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

-- Helper RPC for meeting notes compliance metric
CREATE OR REPLACE FUNCTION public.get_meeting_notes_compliance()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  WITH stats AS (
    SELECT
      e.tribe_id AS t_id,
      t.name as t_name,
      count(*) FILTER (WHERE e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL) as recorded,
      count(*) FILTER (
        WHERE (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL)
          AND e.minutes_text IS NOT NULL
          AND length(trim(e.minutes_text)) >= 20
          AND lower(trim(e.minutes_text)) NOT IN ('teste', 'teste teste', 'test', 'placeholder', '-')
      ) as with_minutes
    FROM events e
    LEFT JOIN tribes t ON t.id = e.tribe_id
    WHERE e.date <= current_date
    GROUP BY e.tribe_id, t.name
  )
  SELECT jsonb_build_object(
    'by_tribe', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'tribe_id', s.t_id,
          'tribe_name', coalesce(s.t_name, 'Gerais/sem tribo'),
          'recorded', s.recorded,
          'with_minutes', s.with_minutes,
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
$$;

GRANT EXECUTE ON FUNCTION public.get_meeting_notes_compliance() TO authenticated;

NOTIFY pgrst, 'reload schema';
