-- ═══════════════════════════════════════════════════════════════
-- Fix certification_rate: use aggregated course progress instead of binary cpmai_certified
-- Old formula: COUNT(cpmai_certified=true) / COUNT(eligible) → binary 0% or 100% per member
-- New formula: AVG(completed_courses / total_courses) × 100 → aggregated progress
-- Example: 10 members at 80% + 30 at 0% = (10×0.8 + 30×0.0) / 40 × 100 = 20%
-- ═══════════════════════════════════════════════════════════════

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
  v_cycle_start date;
  v_cycle_end date;
BEGIN
  -- Resolve cycle date range
  SELECT cycle_start, COALESCE(cycle_end, current_date)
  INTO v_cycle_start, v_cycle_end
  FROM public.cycles
  WHERE cycle_code = (
    CASE p_cycle_code
      WHEN 'cycle3-2026' THEN 'cycle_3'
      ELSE p_cycle_code
    END
  );

  -- Fallback if cycle not found
  IF v_cycle_start IS NULL THEN
    v_cycle_start := '2026-03-01';
    v_cycle_end := current_date;
  END IF;

  FOR v_target IN
    SELECT * FROM public.portfolio_kpi_targets
    WHERE cycle_code = p_cycle_code
    ORDER BY display_order
  LOOP
    CASE v_target.metric_key
      -- a) ARTICLES: board_items published/approved in publication boards, created within cycle
      WHEN 'articles_published' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
          AND bi.status IN ('published', 'approved', 'done')
          AND bi.created_at >= v_cycle_start::timestamptz;

      -- b) WEBINARS: events with type=webinar within cycle date range
      WHEN 'webinars_completed' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.events e
        WHERE e.type = 'webinar'
          AND e.date >= v_cycle_start
          AND e.date <= current_date;

      -- c) IA PILOTS: keep as-is (Hub is pilot #1)
      WHEN 'ia_pilots' THEN
        v_current := COALESCE(
          (SELECT (value->>'count')::numeric FROM public.site_config WHERE key = 'ia_pilots_count'),
          1
        );

      -- d) IMPACT HOURS: sum attendance hours within cycle only
      WHEN 'impact_hours' THEN
        SELECT COALESCE(SUM(e.duration_minutes::numeric / 60.0), 0)
        INTO v_current
        FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        WHERE e.date >= v_cycle_start
          AND e.date <= current_date
          AND a.present = true;

      -- e) CERTIFICATION: aggregated course progress for eligible members
      --    Formula: AVG(completed_courses / total_courses) × 100
      WHEN 'certification_rate' THEN
        SELECT ROUND(COALESCE(AVG(member_pct) * 100, 0))
        INTO v_current
        FROM (
          SELECT
            COALESCE(
              COUNT(cp.id) FILTER (WHERE cp.status = 'completed'),
              0
            )::numeric / NULLIF(tc.cnt, 0) AS member_pct
          FROM public.members m
          CROSS JOIN (SELECT count(*)::numeric AS cnt FROM public.courses) tc
          LEFT JOIN public.course_progress cp ON cp.member_id = m.id
          WHERE m.current_cycle_active = true
            AND m.is_active = true
            AND (
              m.operational_role IN ('researcher', 'tribe_leader', 'manager', 'deputy_manager', 'communicator', 'facilitator')
              OR m.designations && ARRAY['ambassador', 'curator', 'co_gp']
            )
          GROUP BY m.id, tc.cnt
        ) sub;

      -- f) CHAPTERS: keep as-is (correct)
      WHEN 'chapters_participating' THEN
        SELECT COUNT(DISTINCT chapter)::numeric INTO v_current
        FROM public.members
        WHERE current_cycle_active = true
          AND chapter IS NOT NULL;

      ELSE
        v_current := 0;
    END CASE;

    v_progress := CASE
      WHEN v_target.target_value > 0 THEN ROUND((v_current / v_target.target_value) * 100)
      ELSE 0
    END;

    v_status := CASE
      WHEN v_current >= v_target.target_value THEN 'green'
      WHEN v_current >= v_target.warning_threshold THEN 'yellow'
      ELSE 'red'
    END;

    v_result := v_result || jsonb_build_object(
      'metric_key', v_target.metric_key,
      'label', v_target.metric_label,
      'target', v_target.target_value,
      'current', v_current,
      'progress_pct', v_progress,
      'status', v_status,
      'unit', v_target.unit,
      'display_order', v_target.display_order
    );
  END LOOP;

  RETURN v_result;
END;
$$;
