-- ═══════════════════════════════════════════════════════════════
-- Sprint A: KPI Quarterly decomposition
-- Breaks annual targets into quarterly milestones for better
-- sponsor communication and team pacing
-- ═══════════════════════════════════════════════════════════════

-- 0. Create ia_pilots table (needed by exec_portfolio_health)
CREATE TABLE IF NOT EXISTS public.ia_pilots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text,
  objectives text[],
  technologies text[],
  status text DEFAULT 'active' CHECK (status IN ('planning', 'active', 'completed', 'cancelled')),
  lead_member_id uuid REFERENCES public.members(id),
  tribe_id int REFERENCES public.tribes(id),
  start_date date NOT NULL,
  end_date date,
  results_summary text,
  impact_metrics jsonb,
  github_url text,
  demo_url text,
  cycle_code text DEFAULT 'cycle3-2026',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

COMMENT ON TABLE public.ia_pilots IS 'KPI #7: Projetos pilotos planejados/gerenciados com IA como co-piloto';

ALTER TABLE public.ia_pilots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ia_pilots_read" ON public.ia_pilots FOR SELECT USING (true);
CREATE POLICY "ia_pilots_admin_write" ON public.ia_pilots FOR ALL USING (
  EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
    AND (m.is_superadmin OR m.operational_role IN ('manager', 'deputy_manager')))
);

-- Seed: Hub is Pilot #1
INSERT INTO public.ia_pilots (
  title, description, objectives, technologies, status,
  lead_member_id, start_date, demo_url, github_url, cycle_code
) VALUES (
  'AI & PM Research Hub — Plataforma SaaS',
  'Plataforma de gestão colaborativa do Núcleo, construída com IA como co-piloto (Claude Code). Serve 66+ membros em 8 tribos com BoardEngine, dark mode, gamificação, attendance tracking, e KPI monitoring.',
  ARRAY[
    'Demonstrar uso de IA como co-piloto em desenvolvimento de software real',
    'Criar plataforma zero-cost para gestão de pesquisa colaborativa',
    'Servir como case study para o Núcleo sobre IA aplicada a projetos'
  ],
  ARRAY['Claude Code (Anthropic)', 'Astro SSR', 'Supabase PostgreSQL', 'Cloudflare Pages', '@dnd-kit', 'PostHog'],
  'active',
  (SELECT id FROM public.members WHERE name = 'Vitor Maia Rodovalho' LIMIT 1),
  '2026-03-01',
  'https://ai-pm-research-hub.pages.dev',
  'https://github.com/VitorMRodovalho/ai-pm-research-hub',
  'cycle3-2026'
) ON CONFLICT DO NOTHING;

-- 1. Create quarterly targets table
CREATE TABLE IF NOT EXISTS public.portfolio_kpi_quarterly_targets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kpi_target_id uuid REFERENCES public.portfolio_kpi_targets(id) NOT NULL,
  quarter int NOT NULL CHECK (quarter BETWEEN 1 AND 4),
  quarter_target numeric NOT NULL,
  quarter_cumulative_target numeric NOT NULL,
  notes text,
  UNIQUE(kpi_target_id, quarter)
);

COMMENT ON TABLE public.portfolio_kpi_quarterly_targets IS
  'Decomposição trimestral das metas anuais — rolling forecast';

-- RLS
ALTER TABLE public.portfolio_kpi_quarterly_targets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "quarterly_targets_read" ON public.portfolio_kpi_quarterly_targets
  FOR SELECT USING (true);

-- 2. Seed quarterly distribution
WITH targets AS (
  SELECT id, metric_key FROM public.portfolio_kpi_targets
  WHERE cycle_code = 'cycle3-2026'
)
INSERT INTO public.portfolio_kpi_quarterly_targets
  (kpi_target_id, quarter, quarter_target, quarter_cumulative_target, notes)
SELECT t.id, q.quarter, q.target, q.cumulative, q.notes
FROM targets t
JOIN (VALUES
  ('articles_published', 1, 1, 1, 'Ramp-up: 1 artigo em produção'),
  ('articles_published', 2, 4, 5, 'Pico de produção'),
  ('articles_published', 3, 4, 9, 'Pico de produção'),
  ('articles_published', 4, 1, 10, 'Fechamento'),
  ('webinars_completed', 1, 1, 1, 'Primeiro webinar do ciclo'),
  ('webinars_completed', 2, 2, 3, NULL),
  ('webinars_completed', 3, 2, 5, NULL),
  ('webinars_completed', 4, 1, 6, NULL),
  ('ia_pilots', 1, 1, 1, 'Hub é Piloto #1'),
  ('ia_pilots', 2, 1, 2, NULL),
  ('ia_pilots', 3, 1, 3, NULL),
  ('ia_pilots', 4, 0, 3, NULL),
  ('meeting_hours', 1, 18, 18, '~6 semanas × 3h'),
  ('meeting_hours', 2, 30, 48, NULL),
  ('meeting_hours', 3, 30, 78, NULL),
  ('meeting_hours', 4, 12, 90, NULL),
  ('impact_hours', 1, 360, 360, NULL),
  ('impact_hours', 2, 600, 960, NULL),
  ('impact_hours', 3, 600, 1560, NULL),
  ('impact_hours', 4, 240, 1800, NULL),
  ('certification_trail', 1, 30, 30, 'Base: 30% completaram'),
  ('certification_trail', 2, 20, 50, NULL),
  ('certification_trail', 3, 15, 65, NULL),
  ('certification_trail', 4, 5, 70, NULL),
  ('cpmai_certified', 1, 1, 1, NULL),
  ('cpmai_certified', 2, 1, 2, NULL),
  ('cpmai_certified', 3, 0, 2, NULL),
  ('cpmai_certified', 4, 0, 2, NULL),
  ('chapters_participating', 1, 5, 5, 'Base: 5 ativos'),
  ('chapters_participating', 2, 1, 6, NULL),
  ('chapters_participating', 3, 1, 7, NULL),
  ('chapters_participating', 4, 1, 8, NULL),
  ('partner_entities', 1, 0, 0, 'Foco em ramp-up operacional'),
  ('partner_entities', 2, 1, 1, NULL),
  ('partner_entities', 3, 1, 2, NULL),
  ('partner_entities', 4, 1, 3, NULL)
) AS q(metric_key, quarter, target, cumulative, notes)
ON t.metric_key = q.metric_key
ON CONFLICT DO NOTHING;

-- 3. Update exec_portfolio_health to include quarterly data
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
        SELECT COALESCE(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0), 0)
        INTO v_current
        FROM public.events e
        WHERE e.date >= v_year_start AND e.date <= current_date;

      WHEN 'impact_hours' THEN
        SELECT COALESCE(SUM(e.duration_minutes::numeric / 60.0), 0)
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
      'target', v_target.target_value,
      'current', v_current,
      'progress_pct', v_progress,
      'status', v_status,
      'unit', v_target.unit,
      'display_order', v_target.display_order,
      'quarter', v_current_quarter,
      'quarter_target', COALESCE(v_q_target, 0),
      'quarter_cumulative', COALESCE(v_q_cumulative, 0),
      'quarter_progress_pct', v_q_progress,
      'quarter_status', v_q_status
    );
  END LOOP;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.exec_portfolio_health(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exec_portfolio_health(text) TO anon;
