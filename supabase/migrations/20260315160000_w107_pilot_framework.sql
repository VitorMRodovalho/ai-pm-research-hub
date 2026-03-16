-- W107: AI Pilot Registration Framework
-- Schema: pilots + releases tables, RPCs, seed Pilot #1
BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- BLOCO 1: Schema — pilots + releases tables
-- ═══════════════════════════════════════════════════════════════

-- 1.1 Releases table (version tracking)
CREATE TABLE IF NOT EXISTS public.releases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version text NOT NULL UNIQUE,
  title text NOT NULL,
  description text,
  release_type text NOT NULL DEFAULT 'minor',
  is_current boolean DEFAULT false,
  released_at timestamptz DEFAULT now(),
  git_tag text,
  git_sha text,
  waves_included text[],
  stats jsonb DEFAULT '{}',
  created_by uuid REFERENCES public.members(id),
  created_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_releases_current
  ON public.releases (is_current) WHERE is_current = true;

ALTER TABLE public.releases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view releases" ON public.releases;
CREATE POLICY "Anyone can view releases" ON public.releases
  FOR SELECT USING (true);

COMMENT ON TABLE public.releases IS 'W107: Platform release tracking. Current release shown in footer.';

-- 1.2 Pilots table (lightweight, 8 PMI fields + auto-metrics)
CREATE TABLE IF NOT EXISTS public.pilots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pilot_number integer NOT NULL UNIQUE,
  title text NOT NULL,
  hypothesis text,
  problem_statement text,
  scope text,
  status text NOT NULL DEFAULT 'draft',
  started_at date,
  completed_at date,
  board_id uuid REFERENCES public.project_boards(id),
  tribe_id integer REFERENCES public.tribes(id),
  one_pager_md text,
  success_metrics jsonb DEFAULT '[]',
  lessons_learned jsonb DEFAULT '[]',
  team_member_ids uuid[] DEFAULT '{}',
  created_by uuid REFERENCES public.members(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.pilots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated can view pilots" ON public.pilots;
CREATE POLICY "Authenticated can view pilots" ON public.pilots
  FOR SELECT TO authenticated USING (true);

COMMENT ON TABLE public.pilots IS 'W107: AI Pilot projects. KPI target: 3 per year.';

-- 1.3 Seed Pilot #1
INSERT INTO public.pilots (
  pilot_number, title, hypothesis, problem_statement, scope, status,
  started_at, one_pager_md, success_metrics, team_member_ids, created_by
) VALUES (
  1,
  'AI & PM Research Hub — Plataforma SaaS',
  'Se aplicarmos IA generativa e PMBOK 8 para transformar a operação do Núcleo em plataforma data-centric, gamificada e com indicadores à vista, o time vai agir colaborativamente vendo resultado.',
  'Gestão via 6 ferramentas desconectadas (WhatsApp, Trello, Miro, Drive, Planilhas, Email). Zero visibilidade preditiva. Engajamento por obrigação. Custo de coordenação crescente com 5 capítulos e 8 tribos.',
  'Plataforma web completa: BoardEngine (5 views, PMBOK dates, mirror cards), Portfolio Dashboard, Gamificação (10 categorias, Credly sync), Eventos com audiência personalizada, Presença com denominador por membro, Comunicação, Governança. Zero-cost architecture.',
  'active',
  '2026-03-04',
  NULL,
  '[
    {"name": "Ferramentas consolidadas", "target": "1", "baseline": "6", "unit": "ferramentas", "auto_query": null},
    {"name": "Tempo GP para relatório", "target": "0", "baseline": "4", "unit": "h/semana", "auto_query": null},
    {"name": "Entregas com baseline", "target": "56", "baseline": "0", "unit": "artefatos", "auto_query": "artifacts_with_baseline"},
    {"name": "Testes automatizados", "target": "500", "baseline": "0", "unit": "testes", "auto_query": null},
    {"name": "Custo infraestrutura", "target": "0", "baseline": "0", "unit": "R$/mês", "auto_query": null},
    {"name": "Adoção Beta", "target": "80", "baseline": "0", "unit": "% membros ativos", "auto_query": "adoption_pct"},
    {"name": "Releases", "target": "10", "baseline": "0", "unit": "releases", "auto_query": "release_count"},
    {"name": "Decisões de governança", "target": "50", "baseline": "5", "unit": "decisões", "auto_query": null},
    {"name": "Membros ativos", "target": "53", "baseline": "0", "unit": "membros", "auto_query": "active_members_count"}
  ]'::jsonb,
  ARRAY[
    (SELECT id FROM members WHERE name LIKE '%Vitor%Maia%'),
    (SELECT id FROM members WHERE name LIKE '%Fabricio%Costa%')
  ],
  (SELECT id FROM members WHERE name LIKE '%Vitor%Maia%')
)
ON CONFLICT (pilot_number) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- BLOCO 2: RPCs
-- ═══════════════════════════════════════════════════════════════

-- 2.1 Auto-calculated pilot metrics
CREATE OR REPLACE FUNCTION public.get_pilot_metrics(p_pilot_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_pilot record;
  v_metrics jsonb;
  v_auto_values jsonb := '{}';
BEGIN
  SELECT * INTO v_pilot FROM public.pilots WHERE id = p_pilot_id;
  IF v_pilot IS NULL THEN RETURN NULL; END IF;

  v_auto_values := jsonb_build_object(
    'active_members_count', (SELECT count(*) FROM public.members WHERE is_active = true),
    'adoption_pct', (
      SELECT ROUND(
        count(*) FILTER (WHERE auth_id IS NOT NULL AND onboarding_dismissed_at IS NOT NULL)::numeric
        / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1
      )
      FROM public.members
    ),
    'artifacts_with_baseline', (
      SELECT count(*) FROM public.board_items bi
      WHERE bi.baseline_date IS NOT NULL AND bi.status != 'archived'
      AND EXISTS (
        SELECT 1 FROM board_item_tag_assignments bita
        JOIN tags t ON t.id = bita.tag_id
        WHERE bita.board_item_id = bi.id AND t.name = 'entregavel_lider'
      )
    ),
    'release_count', (SELECT count(*) FROM public.releases),
    'active_boards', (SELECT count(*) FROM public.project_boards WHERE is_active = true),
    'total_events', (SELECT count(*) FROM public.events),
    'total_attendance', (SELECT count(*) FROM public.attendance),
    'gamification_entries', (SELECT count(*) FROM public.gamification_points)
  );

  SELECT jsonb_agg(
    CASE
      WHEN m->>'auto_query' IS NOT NULL AND v_auto_values ? (m->>'auto_query')
      THEN m || jsonb_build_object('current', v_auto_values->(m->>'auto_query'))
      ELSE m
    END
  )
  INTO v_metrics
  FROM jsonb_array_elements(v_pilot.success_metrics) m;

  RETURN jsonb_build_object(
    'pilot', row_to_json(v_pilot),
    'metrics', COALESCE(v_metrics, '[]'::jsonb),
    'auto_values', v_auto_values,
    'days_active', CURRENT_DATE - v_pilot.started_at
  );
END;
$$;

-- 2.2 Get all pilots summary
CREATE OR REPLACE FUNCTION public.get_pilots_summary()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id', p.id,
    'pilot_number', p.pilot_number,
    'title', p.title,
    'status', p.status,
    'started_at', p.started_at,
    'completed_at', p.completed_at,
    'hypothesis', p.hypothesis,
    'tribe_name', t.name,
    'board_id', p.board_id,
    'days_active', CASE WHEN p.started_at IS NOT NULL
      THEN CURRENT_DATE - p.started_at ELSE 0 END,
    'metrics_count', jsonb_array_length(COALESCE(p.success_metrics, '[]'::jsonb)),
    'team_count', array_length(p.team_member_ids, 1)
  ) ORDER BY p.pilot_number)
  INTO v_result
  FROM public.pilots p
  LEFT JOIN public.tribes t ON t.id = p.tribe_id;

  RETURN jsonb_build_object(
    'pilots', COALESCE(v_result, '[]'::jsonb),
    'total', (SELECT count(*) FROM public.pilots),
    'active', (SELECT count(*) FROM public.pilots WHERE status = 'active'),
    'target', 3,
    'progress_pct', ROUND((SELECT count(*) FROM public.pilots WHERE status IN ('active','completed'))::numeric / 3 * 100, 0)
  );
END;
$$;

-- 2.3 Get current release (for footer)
CREATE OR REPLACE FUNCTION public.get_current_release()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT jsonb_build_object(
      'version', version,
      'title', title,
      'released_at', released_at,
      'release_type', release_type
    )
    FROM public.releases
    WHERE is_current = true
    LIMIT 1
  );
END;
$$;

-- Grant access
GRANT SELECT ON public.releases TO authenticated, anon;
GRANT SELECT ON public.pilots TO authenticated;

COMMIT;
