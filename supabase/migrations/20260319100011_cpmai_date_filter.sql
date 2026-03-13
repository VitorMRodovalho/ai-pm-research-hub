-- ═══════════════════════════════════════════════════════════════
-- Fix CPMAI KPI: filter by member's entry date when available
-- Only count certifications obtained during Núcleo participation.
-- Fallback: include if cpmai_certified_at IS NULL (benefit of doubt)
-- ═══════════════════════════════════════════════════════════════

-- Update only the cpmai_certified case in exec_portfolio_health
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

      -- 1) CHAPTERS
      WHEN 'chapters_participating' THEN
        SELECT COUNT(DISTINCT chapter)::numeric INTO v_current
        FROM public.members
        WHERE current_cycle_active = true
          AND chapter IS NOT NULL;

      -- 2) PARTNER ENTITIES (governo/academia/empresa only)
      WHEN 'partner_entities' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.partner_entities
        WHERE entity_type IN ('academia', 'governo', 'empresa')
          AND status = 'active'
          AND partnership_date <= current_date;

      -- 3) CERTIFICATION TRAIL: aggregated course progress
      WHEN 'certification_trail' THEN
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

      -- 4) CPMAI CERTIFIED: count members certified during Núcleo participation
      --    Include if cpmai_certified_at IS NULL (benefit of doubt)
      --    Exclude if certified before earliest cycle start (pilot: 2024-03-01)
      WHEN 'cpmai_certified' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.members m
        WHERE m.cpmai_certified = true
          AND m.current_cycle_active = true
          AND m.is_active = true
          AND (
            m.cpmai_certified_at IS NULL
            OR m.cpmai_certified_at >= '2024-03-01'
          );

      -- 5) ARTICLES: curated/approved only
      WHEN 'articles_published' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
          AND bi.curation_status = 'approved'
          AND bi.created_at >= v_cycle_start::timestamptz;

      -- 6) WEBINARS/TALKS
      WHEN 'webinars_completed' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.events e
        WHERE e.type = 'webinar'
          AND e.date >= v_cycle_start
          AND e.date <= current_date;

      -- 7) IA PILOTS
      WHEN 'ia_pilots' THEN
        v_current := COALESCE(
          (SELECT (value->>'count')::numeric FROM public.site_config WHERE key = 'ia_pilots_count'),
          1
        );

      -- 8) MEETING HOURS: raw sum of event durations
      WHEN 'meeting_hours' THEN
        SELECT COALESCE(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0), 0)
        INTO v_current
        FROM public.events e
        WHERE e.date >= v_cycle_start
          AND e.date <= current_date;

      -- 9) IMPACT HOURS: duration × attendees present
      WHEN 'impact_hours' THEN
        SELECT COALESCE(SUM(e.duration_minutes::numeric / 60.0), 0)
        INTO v_current
        FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        WHERE e.date >= v_cycle_start
          AND e.date <= current_date
          AND a.present = true;

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

GRANT EXECUTE ON FUNCTION public.exec_portfolio_health(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exec_portfolio_health(text) TO anon;
