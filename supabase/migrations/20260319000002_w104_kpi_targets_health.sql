-- ═══════════════════════════════════════════════════════════════════════════
-- W104 — Portfolio KPI Calibration & Monitoring
-- Date: 2026-03-12
-- Purpose: Configurable KPI targets + health RPC crossing targets vs reality
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── Table: portfolio_kpi_targets ───
CREATE TABLE IF NOT EXISTS public.portfolio_kpi_targets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_code text NOT NULL DEFAULT 'cycle3-2026',
  metric_key text NOT NULL,
  metric_label jsonb NOT NULL,
  target_value numeric NOT NULL,
  warning_threshold numeric NOT NULL,
  critical_threshold numeric NOT NULL,
  unit text DEFAULT 'count',
  source_query text,
  display_order int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  UNIQUE(cycle_code, metric_key)
);

COMMENT ON TABLE public.portfolio_kpi_targets IS 'Configurable KPI targets per cycle for portfolio health monitoring';

ALTER TABLE public.portfolio_kpi_targets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_read_kpi_targets" ON public.portfolio_kpi_targets
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "anon_read_kpi_targets" ON public.portfolio_kpi_targets
  FOR SELECT TO anon USING (true);

CREATE POLICY "admin_write_kpi_targets" ON public.portfolio_kpi_targets
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager'))
    )
  );

-- ─── Seed: 2026 cycle targets ───
INSERT INTO public.portfolio_kpi_targets (cycle_code, metric_key, metric_label, target_value, warning_threshold, critical_threshold, unit, source_query, display_order) VALUES
('cycle3-2026', 'articles_published', '{"pt":"Artigos Técnicos","en":"Technical Articles","es":"Artículos Técnicos"}', 10, 6, 3, 'count', 'board_items com status published em boards de publicação', 1),
('cycle3-2026', 'webinars_completed', '{"pt":"Webinars","en":"Webinars","es":"Webinars"}', 6, 4, 2, 'count', 'events com type=webinar e date<=now()', 2),
('cycle3-2026', 'ia_pilots', '{"pt":"Pilotos IA","en":"AI Pilots","es":"Pilotos IA"}', 3, 2, 1, 'count', 'projetos registrados como piloto IA (inclui o Hub)', 3),
('cycle3-2026', 'impact_hours', '{"pt":"Horas de Impacto","en":"Impact Hours","es":"Horas de Impacto"}', 1800, 1200, 600, 'hours', 'impact_hours_total view', 4),
('cycle3-2026', 'certification_rate', '{"pt":"Certificação IA","en":"AI Certification","es":"Certificación IA"}', 70, 50, 30, 'percent', 'cpmai_certified / total active members × 100', 5),
('cycle3-2026', 'chapters_participating', '{"pt":"Capítulos PMI","en":"PMI Chapters","es":"Capítulos PMI"}', 8, 6, 5, 'chapters', 'distinct chapters em members ativos', 6)
ON CONFLICT (cycle_code, metric_key) DO NOTHING;

-- ─── RPC: exec_portfolio_health ───
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
BEGIN
  FOR v_target IN
    SELECT * FROM public.portfolio_kpi_targets
    WHERE cycle_code = p_cycle_code
    ORDER BY display_order
  LOOP
    -- Calculate current value per metric
    CASE v_target.metric_key
      WHEN 'articles_published' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
          AND bi.status IN ('published', 'approved', 'done');

      WHEN 'webinars_completed' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.events e
        WHERE e.type = 'webinar'
          AND e.date <= now();

      WHEN 'ia_pilots' THEN
        -- Hub is pilot #1; count from site_config or default to 1
        v_current := COALESCE(
          (SELECT (value->>'count')::numeric FROM public.site_config WHERE key = 'ia_pilots_count'),
          1
        );

      WHEN 'impact_hours' THEN
        v_current := COALESCE(
          (SELECT total_impact_hours FROM public.impact_hours_total LIMIT 1),
          0
        );

      WHEN 'certification_rate' THEN
        SELECT ROUND(
          COALESCE(
            COUNT(*) FILTER (WHERE cpmai_certified = true)::numeric * 100
            / NULLIF(COUNT(*), 0),
            0
          )
        ) INTO v_current
        FROM public.members
        WHERE current_cycle_active = true;

      WHEN 'chapters_participating' THEN
        SELECT COUNT(DISTINCT chapter)::numeric INTO v_current
        FROM public.members
        WHERE current_cycle_active = true
          AND chapter IS NOT NULL;

      ELSE
        v_current := 0;
    END CASE;

    -- Calculate progress percentage
    v_progress := CASE
      WHEN v_target.target_value > 0 THEN ROUND((v_current / v_target.target_value) * 100)
      ELSE 0
    END;

    -- Determine status
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

COMMIT;
