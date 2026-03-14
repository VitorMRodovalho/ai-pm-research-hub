-- W139 Item 4 + W108: Financial sustainability framework
-- Replaces hardcoded mockup at /admin/sustainability with real schema
-- Tracks costs, revenue/value, and KPIs for the Hub project

-- Cost categories
CREATE TABLE public.cost_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  description text,
  display_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

INSERT INTO public.cost_categories (name, description, display_order) VALUES
  ('infrastructure', 'Infraestrutura tecnica (hosting, dominio, APIs)', 1),
  ('licenses', 'Licencas de software e ferramentas', 2),
  ('events_presential', 'Eventos presenciais (deslocamento, hospedagem, espaco)', 3),
  ('events_online', 'Webinars e eventos online (plataformas, divulgacao)', 4),
  ('content_production', 'Producao de conteudo (design, gravacao, edicao)', 5),
  ('submissions', 'Submissoes PMI (taxa de conferencia, inscricao)', 6),
  ('certifications', 'Certificacoes e badges (Credly, certificados)', 7),
  ('other', 'Outros custos', 8);

-- Cost entries
CREATE TABLE public.cost_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES public.cost_categories(id),
  description text NOT NULL,
  amount_brl numeric(10,2) NOT NULL,
  date date NOT NULL,
  paid_by text NOT NULL DEFAULT 'zero_cost',
  event_id uuid REFERENCES public.events(id),
  submission_id uuid REFERENCES public.publication_submissions(id),
  notes text,
  created_by uuid REFERENCES public.members(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Revenue/value categories
CREATE TABLE public.revenue_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  value_type text NOT NULL DEFAULT 'monetary',
  description text,
  display_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

INSERT INTO public.revenue_categories (name, value_type, description, display_order) VALUES
  ('new_pmi_members', 'monetary', 'Novos membros PMI captados via Hub', 1),
  ('publications_accepted', 'reputational', 'Publicacoes aceitas em conferencias/periodicos', 2),
  ('academic_partnerships', 'qualitative', 'Parcerias academicas estabelecidas', 3),
  ('webinar_leads', 'monetary', 'Leads captados via webinars abertos', 4),
  ('replicable_model', 'qualitative', 'Valor estrategico do modelo replicavel para PMI Global', 5),
  ('consulting_derived', 'qualitative', 'Consultoria derivada por membros', 6),
  ('sponsorships', 'monetary', 'Patrocinios e parcerias comerciais', 7);

-- Revenue/value entries
CREATE TABLE public.revenue_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES public.revenue_categories(id),
  description text NOT NULL,
  value_type text NOT NULL DEFAULT 'monetary',
  amount_brl numeric(10,2),
  date date NOT NULL,
  notes text,
  created_by uuid REFERENCES public.members(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- KPI targets per cycle
CREATE TABLE public.sustainability_kpi_targets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle integer NOT NULL DEFAULT 3,
  kpi_name text NOT NULL,
  kpi_formula text,
  target_value numeric(10,2),
  target_unit text,
  current_value numeric(10,2),
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(cycle, kpi_name)
);

INSERT INTO public.sustainability_kpi_targets (cycle, kpi_name, kpi_formula, target_unit, notes) VALUES
  (3, 'cost_per_active_member', 'SUM(cost_entries.amount_brl) / COUNT(active_members)', 'BRL/member', 'Target: < R$10/membro/mes'),
  (3, 'cost_per_event', 'SUM(cost where event_id IS NOT NULL) / COUNT(events)', 'BRL', 'A definir pelo GP'),
  (3, 'cost_per_publication', 'SUM(cost where submission_id IS NOT NULL) / COUNT(submissions)', 'BRL', 'A definir pelo GP'),
  (3, 'infra_zero_cost_pct', 'COUNT(infra items where paid_by=zero_cost) / COUNT(infra items) * 100', '%', 'Target: 100%'),
  (3, 'revenue_indirect_per_capita', 'SUM(revenue monetary) / COUNT(active_members)', 'BRL/member', 'A definir pelo GP');

-- Indexes
CREATE INDEX idx_cost_entries_category ON public.cost_entries(category_id);
CREATE INDEX idx_cost_entries_date ON public.cost_entries(date);
CREATE INDEX idx_revenue_entries_category ON public.revenue_entries(category_id);
CREATE INDEX idx_revenue_entries_date ON public.revenue_entries(date);

-- Updated_at triggers
CREATE OR REPLACE FUNCTION public.update_sustainability_timestamp()
RETURNS trigger AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cost_entry_updated BEFORE UPDATE ON public.cost_entries
  FOR EACH ROW EXECUTE FUNCTION public.update_sustainability_timestamp();
CREATE TRIGGER trg_revenue_entry_updated BEFORE UPDATE ON public.revenue_entries
  FOR EACH ROW EXECUTE FUNCTION public.update_sustainability_timestamp();

-- RLS
ALTER TABLE public.cost_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cost_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.revenue_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.revenue_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sustainability_kpi_targets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view cost categories" ON public.cost_categories FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated can view costs" ON public.cost_entries FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated can view revenue categories" ON public.revenue_categories FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated can view revenue" ON public.revenue_entries FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated can view KPIs" ON public.sustainability_kpi_targets FOR SELECT TO authenticated USING (true);

GRANT SELECT ON public.cost_categories TO authenticated;
GRANT SELECT ON public.cost_entries TO authenticated;
GRANT SELECT ON public.revenue_categories TO authenticated;
GRANT SELECT ON public.revenue_entries TO authenticated;
GRANT SELECT ON public.sustainability_kpi_targets TO authenticated;

-- SECURITY DEFINER RPC: Create cost entry
CREATE OR REPLACE FUNCTION public.create_cost_entry(
  p_category_name text, p_description text, p_amount_brl numeric, p_date date,
  p_paid_by text DEFAULT 'zero_cost', p_event_id uuid DEFAULT NULL,
  p_submission_id uuid DEFAULT NULL, p_notes text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_id uuid; v_caller_id uuid; v_member_id uuid; v_category_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;
  IF NOT EXISTS (
    SELECT 1 FROM public.members WHERE auth_id = v_caller_id
    AND (operational_role IN ('manager', 'deputy_manager') OR is_superadmin = true)
  ) THEN RAISE EXCEPTION 'Only managers and superadmins can create cost entries'; END IF;
  SELECT id INTO v_category_id FROM public.cost_categories WHERE name = p_category_name;
  IF v_category_id IS NULL THEN RAISE EXCEPTION 'Invalid cost category: %', p_category_name; END IF;
  INSERT INTO public.cost_entries (category_id, description, amount_brl, date, paid_by, event_id, submission_id, notes, created_by)
  VALUES (v_category_id, p_description, p_amount_brl, p_date, p_paid_by, p_event_id, p_submission_id, p_notes, v_member_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

-- SECURITY DEFINER RPC: Create revenue entry
CREATE OR REPLACE FUNCTION public.create_revenue_entry(
  p_category_name text, p_description text, p_date date,
  p_value_type text DEFAULT 'monetary', p_amount_brl numeric DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_id uuid; v_caller_id uuid; v_member_id uuid; v_category_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;
  IF NOT EXISTS (
    SELECT 1 FROM public.members WHERE auth_id = v_caller_id
    AND (operational_role IN ('manager', 'deputy_manager') OR is_superadmin = true)
  ) THEN RAISE EXCEPTION 'Only managers and superadmins can create revenue entries'; END IF;
  SELECT id INTO v_category_id FROM public.revenue_categories WHERE name = p_category_name;
  IF v_category_id IS NULL THEN RAISE EXCEPTION 'Invalid revenue category: %', p_category_name; END IF;
  INSERT INTO public.revenue_entries (category_id, description, value_type, amount_brl, date, notes, created_by)
  VALUES (v_category_id, p_description, p_value_type, p_amount_brl, p_date, p_notes, v_member_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

-- Dashboard aggregation RPC
CREATE OR REPLACE FUNCTION public.get_sustainability_dashboard(p_cycle integer DEFAULT 3)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
  v_total_costs numeric;
  v_total_revenue numeric;
  v_active_count integer;
  v_costs_by_category jsonb;
  v_revenue_by_category jsonb;
  v_kpis jsonb;
  v_monthly_costs jsonb;
BEGIN
  SELECT COALESCE(SUM(amount_brl), 0) INTO v_total_costs FROM public.cost_entries;
  SELECT COALESCE(SUM(amount_brl), 0) INTO v_total_revenue FROM public.revenue_entries WHERE value_type = 'monetary';
  SELECT count(*) INTO v_active_count FROM public.members WHERE is_active = true;

  SELECT jsonb_agg(jsonb_build_object(
    'category', cc.name, 'description', cc.description,
    'total', COALESCE(sub.total, 0), 'count', COALESCE(sub.cnt, 0)
  ) ORDER BY cc.display_order)
  INTO v_costs_by_category
  FROM public.cost_categories cc
  LEFT JOIN (SELECT category_id, SUM(amount_brl) as total, COUNT(*) as cnt FROM public.cost_entries GROUP BY category_id) sub ON sub.category_id = cc.id;

  SELECT jsonb_agg(jsonb_build_object(
    'category', rc.name, 'description', rc.description, 'value_type', rc.value_type,
    'total', COALESCE(sub.total, 0), 'count', COALESCE(sub.cnt, 0)
  ) ORDER BY rc.display_order)
  INTO v_revenue_by_category
  FROM public.revenue_categories rc
  LEFT JOIN (SELECT category_id, SUM(amount_brl) as total, COUNT(*) as cnt FROM public.revenue_entries GROUP BY category_id) sub ON sub.category_id = rc.id;

  SELECT jsonb_agg(jsonb_build_object(
    'name', kpi_name, 'formula', kpi_formula, 'target', target_value,
    'current', current_value, 'unit', target_unit, 'notes', notes
  )) INTO v_kpis FROM public.sustainability_kpi_targets WHERE cycle = p_cycle;

  SELECT jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'total', total) ORDER BY month)
  INTO v_monthly_costs
  FROM (SELECT date_trunc('month', date) as month, SUM(amount_brl) as total FROM public.cost_entries WHERE date >= (now() - interval '12 months') GROUP BY date_trunc('month', date)) sub;

  v_result := jsonb_build_object(
    'total_costs', v_total_costs,
    'total_revenue', v_total_revenue,
    'active_members', v_active_count,
    'cost_per_member', CASE WHEN v_active_count > 0 THEN ROUND(v_total_costs / v_active_count, 2) ELSE 0 END,
    'infra_zero_cost_pct', (
      SELECT CASE WHEN COUNT(*) > 0
        THEN ROUND(COUNT(*) FILTER (WHERE paid_by = 'zero_cost')::numeric / COUNT(*) * 100, 1) ELSE 100 END
      FROM public.cost_entries ce JOIN public.cost_categories cc ON cc.id = ce.category_id WHERE cc.name = 'infrastructure'
    ),
    'costs_by_category', COALESCE(v_costs_by_category, '[]'::jsonb),
    'revenue_by_category', COALESCE(v_revenue_by_category, '[]'::jsonb),
    'kpis', COALESCE(v_kpis, '[]'::jsonb),
    'monthly_trend', COALESCE(v_monthly_costs, '[]'::jsonb)
  );
  RETURN v_result;
END; $$;

COMMENT ON TABLE public.cost_categories IS 'W139/W108: Cost categories for sustainability tracking.';
COMMENT ON TABLE public.cost_entries IS 'W139/W108: Individual cost records. Written by managers/superadmins via RPC.';
COMMENT ON TABLE public.revenue_categories IS 'W139/W108: Revenue/value generation categories.';
COMMENT ON TABLE public.revenue_entries IS 'W139/W108: Individual revenue/value records.';
COMMENT ON TABLE public.sustainability_kpi_targets IS 'W139/W108: KPI targets per cycle for sustainability monitoring.';
