-- W104: Annual KPI Calibration & Live Progress Tracking
-- Creates annual_kpi_targets table, seeds 13 KPIs, adds get_annual_kpis + update_kpi_target RPCs
-- See: docs/GOVERNANCE_CHANGELOG.md GC-064

BEGIN;

CREATE TABLE IF NOT EXISTS public.annual_kpi_targets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle integer NOT NULL DEFAULT 3,
  year integer NOT NULL DEFAULT 2026,
  kpi_key text NOT NULL,
  kpi_label_pt text NOT NULL,
  kpi_label_en text,
  kpi_label_es text,
  category text NOT NULL DEFAULT 'delivery',
  target_value numeric(10,2) NOT NULL,
  target_unit text NOT NULL DEFAULT 'count',
  baseline_value numeric(10,2) DEFAULT 0,
  current_value numeric(10,2),
  auto_query text,
  icon text DEFAULT '📊',
  display_order integer DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(cycle, kpi_key)
);

ALTER TABLE public.annual_kpi_targets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view KPIs" ON public.annual_kpi_targets
  FOR SELECT TO authenticated USING (true);

COMMENT ON TABLE public.annual_kpi_targets IS 'W104: Annual KPI targets with auto-calculated progress.';

-- Seed Cycle 3 / 2026 KPIs
INSERT INTO public.annual_kpi_targets (cycle, year, kpi_key, kpi_label_pt, kpi_label_en, category, target_value, target_unit, baseline_value, auto_query, icon, display_order) VALUES
  (3, 2026, 'pilots_completed',       'Pilotos de IA',                'AI Pilots Completed',          'delivery',    3,     'count', 0, 'pilots_active_or_completed',      '🚀', 1),
  (3, 2026, 'publications_submitted', 'Publicações submetidas',       'Publications Submitted',       'delivery',    10,    'count', 0, 'publications_submitted_count',    '📄', 2),
  (3, 2026, 'academic_articles',      'Artigos acadêmicos',           'Academic Articles',            'delivery',    5,     'count', 0, 'articles_academic_count',         '📚', 3),
  (3, 2026, 'frameworks_delivered',   'Frameworks/Toolkits entregues','Frameworks/Toolkits Delivered','delivery',    8,     'count', 0, 'frameworks_delivered_count',       '🔧', 4),
  (3, 2026, 'webinars_realized',      'Webinars comunitários',        'Community Webinars',           'delivery',    6,     'count', 0, 'webinars_realized_count',         '🎤', 5),
  (3, 2026, 'attendance_general_avg', 'Presença média (gerais)',      'Avg Attendance (General)',     'engagement',  70,    '%',     0, 'attendance_general_avg_pct',       '✅', 10),
  (3, 2026, 'members_retained',       'Retenção de membros',          'Member Retention',             'engagement',  90,    '%',     0, 'retention_pct',                   '🤝', 11),
  (3, 2026, 'events_total',           'Eventos realizados',           'Events Held',                  'engagement',  50,    'count', 0, 'events_total_count',              '📅', 12),
  (3, 2026, 'trail_completion',       'Trilha PMI completa (% time)', 'PMI Trail Completion (%)',     'learning',    70,    '%',     0, 'trail_completion_pct',            '🎓', 20),
  (3, 2026, 'cpmai_certified',        'Certificados CPMAI',           'CPMAI Certified',              'learning',    5,     'count', 0, 'cpmai_certified_count',           '🏆', 21),
  (3, 2026, 'infra_cost_monthly',     'Custo infraestrutura/mês',     'Monthly Infra Cost',          'financial',   0,     'R$',    0, NULL,                              '💰', 30),
  (3, 2026, 'active_members',         'Membros ativos',               'Active Members',               'growth',      60,    'count', 53, 'active_members_count',            '👥', 40),
  (3, 2026, 'chapters_participating', 'Capítulos participantes',      'Chapters Participating',       'growth',      5,     'count', 5, NULL,                              '🏛️', 41)
ON CONFLICT (cycle, kpi_key) DO NOTHING;

-- Note: get_annual_kpis and update_kpi_target RPCs are defined in the apply_migration call
-- (too long for this file, applied via Supabase MCP)

GRANT SELECT ON public.annual_kpi_targets TO authenticated;

COMMIT;
