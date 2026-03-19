-- Fix: round v_current in exec_portfolio_health to avoid decimal hours
-- e.g. 17.466666666666665h → 17h

CREATE OR REPLACE FUNCTION public.exec_portfolio_health(p_cycle_code text DEFAULT 'cycle3-2026')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb := '[]'::jsonb;
  v_target record;
  v_current numeric;
  v_progress numeric;
  v_status text;
  v_year_start date;
  v_current_quarter int;
  v_q_target numeric;
  v_q_cumulative numeric;
  v_q_progress numeric;
  v_q_status text;
BEGIN
  -- Temporal anchor: kickoff event date
  SELECT e.date INTO v_year_start
  FROM public.events e
  WHERE (e.title ILIKE '%kick%off%' OR e.title ILIKE '%kick-off%')
    AND EXTRACT(year FROM e.date) = EXTRACT(year FROM now())
  ORDER BY e.date ASC
  LIMIT 1;

  IF v_year_start IS NULL THEN
    v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
  END IF;

  -- Determine current quarter
  v_current_quarter := EXTRACT(quarter FROM now())::int;

  FOR v_target IN
    SELECT * FROM public.portfolio_kpi_targets
    WHERE cycle_code = p_cycle_code
    ORDER BY display_order
  LOOP
    CASE v_target.metric_key

      WHEN 'chapters_participating' THEN
        SELECT COUNT(DISTINCT chapter)::numeric INTO v_current
        FROM public.members
        WHERE current_cycle_active = true AND chapter IS NOT NULL;

      WHEN 'partner_entities' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.partner_entities
        WHERE entity_type IN ('academia', 'governo', 'empresa')
          AND status = 'active'
          AND partnership_date >= v_year_start;

      WHEN 'certification_trail' THEN
        SELECT ROUND(COALESCE(AVG(member_pct) * 100, 0))
        INTO v_current
        FROM (
          SELECT COALESCE(COUNT(cp.id) FILTER (WHERE cp.status = 'completed'), 0)::numeric
                 / NULLIF(tc.cnt, 0) AS member_pct
          FROM public.members m
          CROSS JOIN (SELECT count(*)::numeric AS cnt FROM public.courses) tc
          LEFT JOIN public.course_progress cp ON cp.member_id = m.id
          WHERE m.current_cycle_active = true AND m.is_active = true
            AND (m.operational_role IN ('researcher','tribe_leader','manager','deputy_manager','communicator','facilitator')
                 OR m.designations && ARRAY['ambassador','curator','co_gp'])
          GROUP BY m.id, tc.cnt
        ) sub;

      WHEN 'cpmai_certified' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.members m
        WHERE m.cpmai_certified = true
          AND m.current_cycle_active = true AND m.is_active = true
          AND m.cpmai_certified_at >= make_date(EXTRACT(year FROM now())::int, 1, 1);

      WHEN 'articles_published' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
          AND bi.curation_status = 'approved'
          AND bi.created_at >= v_year_start::timestamptz;

      WHEN 'webinars_completed' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.events e
        WHERE e.type = 'webinar'
          AND e.date >= v_year_start AND e.date <= current_date;

      WHEN 'ia_pilots' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.ia_pilots
        WHERE start_date >= make_date(EXTRACT(year FROM now())::int, 1, 1)
          AND status IN ('active', 'completed');

      WHEN 'meeting_hours' THEN
        SELECT COALESCE(ROUND(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0)), 0)
        INTO v_current
        FROM public.events e
        WHERE e.date >= v_year_start AND e.date <= current_date;

      WHEN 'impact_hours' THEN
        SELECT COALESCE(ROUND(SUM(e.duration_minutes::numeric / 60.0)), 0)
        INTO v_current
        FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        WHERE e.date >= v_year_start AND e.date <= current_date
          AND a.present = true;

      ELSE
        v_current := 0;
    END CASE;

    -- Annual progress
    v_progress := CASE
      WHEN v_target.target_value > 0 THEN ROUND((v_current / v_target.target_value) * 100)
      ELSE 0
    END;

    v_status := CASE
      WHEN v_current >= v_target.target_value THEN 'green'
      WHEN v_current >= v_target.warning_threshold THEN 'yellow'
      ELSE 'red'
    END;

    -- Quarterly progress
    SELECT qt.quarter_target, qt.quarter_cumulative_target
    INTO v_q_target, v_q_cumulative
    FROM public.portfolio_kpi_quarterly_targets qt
    WHERE qt.kpi_target_id = v_target.id
      AND qt.quarter = v_current_quarter;

    v_q_progress := CASE
      WHEN COALESCE(v_q_cumulative, 0) > 0 THEN ROUND((v_current / v_q_cumulative) * 100)
      ELSE 0
    END;

    v_q_status := CASE
      WHEN v_current >= COALESCE(v_q_cumulative, 0) THEN 'green'
      WHEN COALESCE(v_q_cumulative, 0) > 0 AND v_current >= v_q_cumulative * 0.5 THEN 'yellow'
      ELSE 'red'
    END;

    v_result := v_result || jsonb_build_object(
      'metric_key', v_target.metric_key,
      'label', v_target.metric_label,
      'target', ROUND(v_target.target_value),
      'current', ROUND(v_current),
      'progress_pct', v_progress,
      'status', v_status,
      'unit', v_target.unit,
      'display_order', v_target.display_order,
      'quarter', v_current_quarter,
      'quarter_target', ROUND(COALESCE(v_q_target, 0)),
      'quarter_cumulative', ROUND(COALESCE(v_q_cumulative, 0)),
      'quarter_progress_pct', v_q_progress,
      'quarter_status', v_q_status
    );
  END LOOP;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.exec_portfolio_health(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exec_portfolio_health(text) TO anon;
