-- ============================================================
-- W140 BLOCO 1: Unified tag system for events, board items, artifacts
-- 3-tier hierarchy: system > administrative > semantic
-- Single catalog, multiple junction tables per domain
-- ============================================================

CREATE TYPE public.tag_tier AS ENUM (
  'system',
  'administrative',
  'semantic'
);

CREATE TYPE public.tag_domain AS ENUM (
  'event',
  'board_item',
  'all'
);

CREATE TABLE public.tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  label_pt text NOT NULL,
  label_en text,
  label_es text,
  color text NOT NULL DEFAULT '#6B7280',
  tier tag_tier NOT NULL DEFAULT 'administrative',
  domain tag_domain NOT NULL DEFAULT 'all',
  description text,
  is_system boolean GENERATED ALWAYS AS (tier = 'system') STORED,
  display_order integer DEFAULT 0,
  created_by uuid REFERENCES public.members(id),
  created_at timestamptz DEFAULT now(),
  UNIQUE(name, domain)
);

-- Event <-> tag junction
CREATE TABLE public.event_tag_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES public.tags(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(event_id, tag_id)
);

-- Board item <-> tag junction (supplements existing text[] tags column)
CREATE TABLE public.board_item_tag_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_item_id uuid NOT NULL REFERENCES public.board_items(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES public.tags(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(board_item_id, tag_id)
);

-- Indexes
CREATE INDEX idx_tags_tier ON public.tags(tier);
CREATE INDEX idx_tags_domain ON public.tags(domain);
CREATE INDEX idx_tags_name ON public.tags(name);
CREATE INDEX idx_event_tag_assign_event ON public.event_tag_assignments(event_id);
CREATE INDEX idx_event_tag_assign_tag ON public.event_tag_assignments(tag_id);
CREATE INDEX idx_board_item_tag_assign_item ON public.board_item_tag_assignments(board_item_id);
CREATE INDEX idx_board_item_tag_assign_tag ON public.board_item_tag_assignments(tag_id);

-- RLS
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_tag_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.board_item_tag_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "All authenticated can view tags" ON public.tags
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "All authenticated can view event tag assignments" ON public.event_tag_assignments
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "All authenticated can view board item tag assignments" ON public.board_item_tag_assignments
  FOR SELECT TO authenticated USING (true);

-- Write policies for admin
CREATE POLICY "Admins can manage tags" ON public.tags
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'))));
CREATE POLICY "Authenticated can manage event tag assignments" ON public.event_tag_assignments
  FOR ALL TO authenticated USING (true);
CREATE POLICY "Authenticated can manage board item tag assignments" ON public.board_item_tag_assignments
  FOR ALL TO authenticated USING (true);

GRANT ALL ON public.tags TO authenticated;
GRANT ALL ON public.event_tag_assignments TO authenticated;
GRANT ALL ON public.board_item_tag_assignments TO authenticated;

-- ============================================================
-- SEED: Event tags (system tier, domain=event)
-- ============================================================
INSERT INTO public.tags (name, label_pt, color, tier, domain, description, display_order) VALUES
  ('general_meeting', 'Geral', '#3B82F6', 'system', 'event', 'Reunião geral — mandatória para membros ativos em tribos + gestão', 1),
  ('tribe_meeting', 'Tribo', '#10B981', 'system', 'event', 'Reunião de tribo — mandatória para membros da tribo', 2),
  ('kickoff', 'Kickoff', '#F59E0B', 'system', 'event', 'Evento de abertura de ciclo', 3),
  ('leadership_meeting', 'Liderança', '#8B5CF6', 'system', 'event', 'Reunião de liderança', 4),
  ('interview', 'Entrevista', '#EC4899', 'system', 'event', 'Entrevista de seleção', 5),
  ('external_event', 'Evento Externo', '#6366F1', 'system', 'event', 'Evento externo ao projeto', 6);

INSERT INTO public.tags (name, label_pt, color, tier, domain, description, display_order) VALUES
  ('workshop_event', 'Workshop', '#14B8A6', 'administrative', 'event', 'Workshop prático', 7),
  ('mentoring', 'Mentoria', '#F97316', 'administrative', 'event', 'Sessão de mentoria', 8),
  ('committee', 'Comitê', '#EF4444', 'administrative', 'event', 'Reunião de comitê', 9),
  ('alignment', 'Alinhamento', '#64748B', 'administrative', 'event', 'Reunião de alinhamento (GP, 1:1, etc.)', 10),
  ('one_on_one', '1:1', '#94A3B8', 'administrative', 'event', 'Reunião individual GP ↔ líder ou GP ↔ membro', 11);

-- ============================================================
-- SEED: Artifact/board item tags (domain=board_item)
-- ============================================================

-- Level 1: Artifact type (system)
INSERT INTO public.tags (name, label_pt, color, tier, domain, description, display_order) VALUES
  ('publicacao', 'Publicação', '#3B82F6', 'system', 'board_item', 'Artigos, e-books, guias, reports publicáveis', 20),
  ('framework', 'Framework', '#8B5CF6', 'system', 'board_item', 'Modelos, matrizes, protocolos, playbooks', 21),
  ('poc', 'Prova de Conceito', '#F59E0B', 'system', 'board_item', 'PoCs, protótipos, plataformas funcionais', 22),
  ('ferramenta', 'Ferramenta', '#10B981', 'system', 'board_item', 'Toolkits, checklists, guias práticos', 23),
  ('webinar', 'Webinar', '#EC4899', 'system', 'board_item', 'Webinars, palestras, apresentações', 24),
  ('workshop_artifact', 'Workshop', '#EF4444', 'system', 'board_item', 'Workshops práticos, treinamentos', 25),
  ('pesquisa', 'Pesquisa', '#6366F1', 'system', 'board_item', 'Levantamentos, revisões de literatura', 26);

-- Level 2: Publication channel (administrative)
INSERT INTO public.tags (name, label_pt, color, tier, domain, description, display_order) VALUES
  ('artigo_linkedin', 'Artigo LinkedIn', '#0A66C2', 'administrative', 'board_item', 'Quick wins, thought leadership', 30),
  ('artigo_academico', 'Artigo Acadêmico', '#1E3A5F', 'administrative', 'board_item', 'Conferências/periódicos PMI', 31),
  ('ebook', 'E-book', '#7C3AED', 'administrative', 'board_item', 'Publicação longa', 32),
  ('infografico', 'Infográfico', '#06B6D4', 'administrative', 'board_item', 'Visual summary', 33),
  ('report', 'Relatório', '#475569', 'administrative', 'board_item', 'Relatório formal', 34),
  ('estudo_caso', 'Estudo de Caso', '#B45309', 'administrative', 'board_item', 'Case study aplicado', 35);

-- Level 3: Gates/milestones (administrative)
INSERT INTO public.tags (name, label_pt, color, tier, domain, description, display_order) VALUES
  ('gate_a', 'Gate A', '#DC2626', 'administrative', 'board_item', 'Primeiro milestone de validação', 40),
  ('gate_b', 'Gate B', '#059669', 'administrative', 'board_item', 'Segundo milestone (lançamento)', 41),
  ('entrega_final', 'Entrega Final', '#7C2D12', 'administrative', 'board_item', 'Último artefato do ciclo', 42),
  ('quick_win', 'Quick Win', '#EA580C', 'administrative', 'board_item', 'Primeira entrega rápida', 43);

-- Cross-domain tags (domain=all)
INSERT INTO public.tags (name, label_pt, color, tier, domain, description, display_order) VALUES
  ('ciclo_3', 'Ciclo 3', '#1D4ED8', 'system', 'all', 'Ciclo 3 (2026/1)', 50),
  ('ciclo_4', 'Ciclo 4', '#7E22CE', 'system', 'all', 'Ciclo 4 (2026/2)', 51);

COMMENT ON TABLE public.tags IS 'W140: Unified tag catalog. 3-tier (system/administrative/semantic), multi-domain (event/board_item/all). Single source of truth for all tagging.';
COMMENT ON TABLE public.event_tag_assignments IS 'W140: N:N junction events ↔ tags.';
COMMENT ON TABLE public.board_item_tag_assignments IS 'W140: N:N junction board items ↔ tags. Supplements existing text[] tags column.';
