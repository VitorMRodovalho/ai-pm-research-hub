-- p170 BUG-HOI — Canonical impact hours formula
--
-- PM ask 2026-05-16: 3 surfaces mostravam valores diferentes:
--   /attendance  view impact_hours_total                 = 656.2h
--   /admin       RPC get_impact_hours_excluding_excused  = 666.2h  (BUG: ignora present=true)
--   /#kpis       RPC exec_portfolio_health(impact_hours) = 597.8h  (CORRETO)
--
-- Análise:
--   • /attendance falta COALESCE(duration_actual, duration_minutes) → -58h
--   • /admin não filtra present=true → conta 8 unexcused absences (+10h)
--   • /#kpis usa formula correta mas hardcoded inline (drift possível)
--
-- Fix: criar RPC canônico unificado + refactor 3 surfaces pra consumi-lo.
--
-- Fórmula canônica:
--   SUM(COALESCE(e.duration_actual, e.duration_minutes) / 60)
--   WHERE a.present = true AND a.excused IS NOT TRUE
--     AND e.date BETWEEN p_start AND p_end
--
-- Default range: calendar year YTD (Jan 1 → CURRENT_DATE), match prior semantics.
--
-- Post-fix: 3 surfaces convergem em 597.8h (current).
--
-- Rollback:
--   DROP FUNCTION public.get_impact_hours_canonical(date, date);
--   -- Restore /attendance view + 2 RPCs from migration history if needed.

-- ============================================================
-- Canonical RPC (source of truth)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_impact_hours_canonical(
  p_start_date date DEFAULT make_date(EXTRACT(year FROM now())::int, 1, 1),
  p_end_date   date DEFAULT CURRENT_DATE
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    ROUND(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0), 1),
    0
  )
  FROM public.events e
  JOIN public.attendance a ON a.event_id = e.id
  WHERE e.date >= p_start_date
    AND e.date <= p_end_date
    AND a.present = true
    AND a.excused IS NOT TRUE;
$function$;

COMMENT ON FUNCTION public.get_impact_hours_canonical(date, date) IS
  'p170 BUG-HOI — source of truth canônico para Horas de Impacto. Fórmula: SUM(COALESCE(duration_actual, duration_minutes)/60) WHERE present=true AND excused IS NOT TRUE. Default range: Jan 1 YTD. Consumido por impact_hours_total view + get_impact_hours_excluding_excused + exec_portfolio_health(impact_hours).';

GRANT EXECUTE ON FUNCTION public.get_impact_hours_canonical(date, date) TO authenticated, anon;

-- ============================================================
-- /attendance view: rebuild com formula canônica
-- ============================================================
CREATE OR REPLACE VIEW public.impact_hours_total AS
SELECT
  -- canonical formula inline (view não pode ser dropada e recriada sem cascade quebrar consumidores)
  COALESCE(
    ROUND(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0)
          FILTER (WHERE a.present = true AND a.excused IS NOT TRUE), 1),
    0
  ) AS total_impact_hours,
  count(DISTINCT e.id) AS total_events,
  count(a.id) FILTER (WHERE a.present = true AND a.excused IS NOT TRUE) AS total_attendances,
  1800.0 AS annual_target_hours,
  ROUND(
    COALESCE(
      SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0)
        FILTER (WHERE a.present = true AND a.excused IS NOT TRUE),
      0
    ) / 18.0,
    1
  ) AS percent_of_target
FROM public.events e
LEFT JOIN public.attendance a ON a.event_id = e.id
WHERE e.date >= make_date(EXTRACT(year FROM now())::int, 1, 1)
  AND e.date <= CURRENT_DATE;

COMMENT ON VIEW public.impact_hours_total IS
  'p170 BUG-HOI — refactored to canonical formula (COALESCE duration_actual + excused filter). Match get_impact_hours_canonical() exactly. Antes p170: SUM(duration_minutes) only.';

-- ============================================================
-- /admin RPC: delegate to canonical (fix BUG present filter)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_impact_hours_excluding_excused()
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.get_impact_hours_canonical();
$function$;

COMMENT ON FUNCTION public.get_impact_hours_excluding_excused() IS
  'p170 BUG-HOI — agora delegate pra get_impact_hours_canonical(). Pre-p170 tinha BUG: contava unexcused absences como presenças (+10h drift). Mantido pra backward compat de get_admin_dashboard que cita este nome.';

GRANT EXECUTE ON FUNCTION public.get_impact_hours_excluding_excused() TO authenticated;

-- ============================================================
-- /#kpis RPC exec_portfolio_health: only impact_hours branch changes
-- ============================================================
CREATE OR REPLACE FUNCTION public.exec_portfolio_health(p_cycle_code text DEFAULT 'cycle3-2026'::text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_year_start := make_date(EXTRACT(year FROM now())::int, 1, 1);
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
        SELECT calc_trail_completion_pct() INTO v_current;

      WHEN 'cpmai_certified' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.members m
        WHERE m.cpmai_certified = true
          AND m.current_cycle_active = true AND m.is_active = true
          AND m.cpmai_certified_at >= v_year_start;

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
        WHERE start_date >= v_year_start
          AND status IN ('active', 'completed');

      WHEN 'meeting_hours' THEN
        SELECT COALESCE(ROUND(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0)), 0)
        INTO v_current
        FROM public.events e
        WHERE e.date >= v_year_start AND e.date <= current_date;

      WHEN 'impact_hours' THEN
        -- p170 BUG-HOI: delegate pra canonical RPC (anteriormente inline + missing excused filter)
        v_current := public.get_impact_hours_canonical(v_year_start, current_date);

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
$function$;

COMMENT ON FUNCTION public.exec_portfolio_health(text) IS
  'p170 BUG-HOI — impact_hours branch agora delegate pra get_impact_hours_canonical(). Outras branches unchanged.';

NOTIFY pgrst, 'reload schema';
