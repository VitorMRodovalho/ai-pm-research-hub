-- Fix: detect_operational_alerts — scope meeting alerts to current cycle
-- Tribes with no meetings since cycle start show "sem reunião registrada neste ciclo"
-- instead of counting days from pre-cycle events (e.g. "188 dias").
-- Also returns pilot details (problem_statement, scope, success_metrics).

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

-- Also update get_pilots_summary to return detail fields
CREATE OR REPLACE FUNCTION public.get_pilots_summary()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id', p.id, 'pilot_number', p.pilot_number, 'title', p.title,
    'status', p.status, 'started_at', p.started_at, 'completed_at', p.completed_at,
    'hypothesis', p.hypothesis, 'problem_statement', p.problem_statement,
    'scope', p.scope, 'tribe_name', t.name, 'board_id', p.board_id,
    'days_active', CASE WHEN p.started_at IS NOT NULL THEN CURRENT_DATE - p.started_at ELSE 0 END,
    'success_metrics', COALESCE(p.success_metrics, '[]'::jsonb),
    'metrics_count', jsonb_array_length(COALESCE(p.success_metrics, '[]'::jsonb)),
    'team_count', coalesce(array_length(p.team_member_ids, 1), 0)
  ) ORDER BY p.pilot_number)
  INTO v_result
  FROM public.pilots p LEFT JOIN public.tribes t ON t.id = p.tribe_id;

  RETURN jsonb_build_object(
    'pilots', COALESCE(v_result, '[]'::jsonb),
    'total', (SELECT count(*) FROM public.pilots),
    'active', (SELECT count(*) FROM public.pilots WHERE status = 'active'),
    'target', 3,
    'progress_pct', ROUND((SELECT count(*) FROM public.pilots WHERE status IN ('active','completed'))::numeric / 3 * 100, 0)
  );
END;
$function$;
