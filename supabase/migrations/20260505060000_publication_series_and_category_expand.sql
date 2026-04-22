-- ============================================================================
-- Issue #94 Quick Wins — Publication Series (Akita pattern) + category expand
--
-- Cria primitivo canônico `publication_series` inspirado no blog do Akita
-- (akitaonrails.com/en com 21 anos de conteúdo agrupado em séries nomeadas:
-- "M.Akita Chronicles", "Frank*", "Omarchy", "Vibe Code", "RANT").
--
-- Decisão arquitetural pendente (ADR-020 — aguarda review PM): webinar_series
-- (proposto em #89) e publication_series (aqui) são o mesmo conceito. Por
-- ora, `format_default='multi'` permite série que gera tanto blog quanto
-- webinar quanto newsletter. Quando ADR-020 aprovar unificação, renomear
-- para `content_series`.
--
-- Seed inicial: 5 séries que o GP pode começar a popular imediatamente.
--
-- Related: #89, #94. ADR-020 (Publication Pipeline) aguarda aprovação.
-- ============================================================================

-- Table
CREATE TABLE IF NOT EXISTS public.publication_series (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  title_i18n jsonb NOT NULL,              -- {"pt":"...", "en":"...", "es":"..."}
  description_i18n jsonb,
  cover_image_url text,
  hero_tribe_id integer REFERENCES public.tribes(id),
  hero_initiative_id uuid REFERENCES public.initiatives(id),
  cadence_hint text CHECK (cadence_hint IN ('weekly','biweekly','monthly','quarterly','sporadic','one_shot')),
  format_default text CHECK (format_default IN ('blog_post','webinar','newsletter','podcast','deep_dive','multi')),
  is_active boolean DEFAULT true,
  editorial_voice text,                   -- "Rant","Crônica","Tutorial técnico","Research essay","Case study"
  target_audience text,                   -- "Desenvolvedor BR intermediário","PM de capítulo PMI","Researcher de IA aplicada"
  created_by uuid REFERENCES public.members(id),
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_publication_series_active ON public.publication_series(is_active) WHERE is_active = true;
CREATE INDEX idx_publication_series_tribe ON public.publication_series(hero_tribe_id) WHERE hero_tribe_id IS NOT NULL;

-- RLS
ALTER TABLE public.publication_series ENABLE ROW LEVEL SECURITY;

CREATE POLICY publication_series_read_members ON public.publication_series
  FOR SELECT USING (rls_is_member());

CREATE POLICY publication_series_superadmin_all ON public.publication_series
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_superadmin = true)
  );

CREATE POLICY publication_series_v4_org_scope ON public.publication_series
  FOR ALL USING ((organization_id = auth_org()) OR (organization_id IS NULL));

-- Seed 5 séries iniciais
INSERT INTO public.publication_series (slug, title_i18n, description_i18n, cadence_hint, format_default, editorial_voice, target_audience, hero_tribe_id, hero_initiative_id) VALUES
  (
    'cpmai-journey',
    '{"pt":"CPMAI Journey","en":"CPMAI Journey","es":"CPMAI Journey"}'::jsonb,
    '{"pt":"Acompanhamento quinzenal do grupo de estudos CPMAI — do preparatório até a certificação formal PMI. Herlon como GP da subiniciativa, Pedro como SME.","en":"Biweekly chronicle of the CPMAI study group — from prep to formal PMI certification.","es":"Crónica quincenal del grupo de estudios CPMAI."}'::jsonb,
    'biweekly',
    'multi',
    'Crônica educativa',
    'PMs considerando certificação CPMAI + voluntários Núcleo',
    NULL,
    '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19'::uuid  -- Preparatório CPMAI initiative
  ),
  (
    'trilha-pesquisador',
    '{"pt":"Trilha do Pesquisador","en":"Researcher Path","es":"Camino del Investigador"}'::jsonb,
    '{"pt":"Journey de um voluntário do Núcleo — da seleção ao desligamento. Lições aprendidas, estrutura de ciclo, showcase de contribuições.","en":"Volunteer journey at Núcleo IA — from selection to offboarding.","es":"Viaje del voluntario en Núcleo IA."}'::jsonb,
    'monthly',
    'blog_post',
    'Case study com voz pessoal',
    'Candidatos ao processo seletivo + Community Managers do PMI',
    NULL,
    NULL
  ),
  (
    'behind-nucleo-ia',
    '{"pt":"Behind Núcleo IA","en":"Behind the Núcleo IA","es":"Detrás de Núcleo IA"}'::jsonb,
    '{"pt":"Crônicas sobre a construção da plataforma do Núcleo — ADRs, debug sessions, decisões arquiteturais, multi-agent council pattern. Inspirado no estilo Behind the M.Akita Chronicles.","en":"Behind-the-scenes of building Núcleo IA platform — ADRs, debug sessions, architectural decisions.","es":"Detrás de escenas de la construcción de la plataforma."}'::jsonb,
    'monthly',
    'blog_post',
    'Crônica técnica com storytelling',
    'Dev brasileiro + PMs que querem entender como fazer tech governance em comunidade',
    NULL,
    NULL
  ),
  (
    'weekly-radar-tribe-1',
    '{"pt":"Radar Semanal — T1 Tecnologia","en":"Weekly Radar — T1 Tech","es":"Radar Semanal — T1 Tecnología"}'::jsonb,
    '{"pt":"Digest semanal dos insights mais relevantes sobre IA aplicada a PM, curados pela Tribo 1 Radar Tecnológico. Alimentado via AI Briefing Skill (arXiv + LinkedIn + GitHub trending + RSS).","en":"Weekly digest of AI+PM insights curated by Tribe 1.","es":"Digest semanal de IA+PM curado por Tribo 1."}'::jsonb,
    'weekly',
    'newsletter',
    'Weekly radar',
    'Members Núcleo + subscribers externos interessados em PM+IA',
    1,
    '89e13063-0be5-4f59-a162-0392f4408178'::uuid  -- Radar Tecnológico initiative
  ),
  (
    'tribe-2-agents-deep-dive',
    '{"pt":"Agentes Autônomos: Deep Dive","en":"Autonomous Agents: Deep Dive","es":"Agentes Autónomos: Deep Dive"}'::jsonb,
    '{"pt":"Análises técnicas profundas da Tribo 2 sobre frameworks multi-agent para PM (APM, Claude Sub-Agents, AutoGen, CrewAI). Posts long-form + webinar de fechamento por ciclo.","en":"Deep technical analyses from Tribe 2 on multi-agent PM frameworks.","es":"Análisis técnicos profundos sobre frameworks multi-agent."}'::jsonb,
    'monthly',
    'multi',
    'Deep dive técnico',
    'PM experienced + devs considerando adotar multi-agent workflows',
    2,
    '6c3ffc94-207c-4c63-9e83-c6f3d48529d7'::uuid  -- Agentes Autônomos initiative
  )
ON CONFLICT (slug) DO NOTHING;

COMMENT ON TABLE public.publication_series IS 'Séries temáticas nomeadas para content do Núcleo (blog + webinar + newsletter). Padrão inspirado em akitaonrails.com (M.Akita Chronicles etc.). Related: ADR-020 (pending).';

-- ============================================================================
-- Expand blog_posts.category enum
-- ============================================================================
-- Antigo: case-study, tutorial, announcement, opinion
-- Novo: + deep-dive, weekly-radar, community-spotlight, behind-the-scenes, rant, research-findings

ALTER TABLE public.blog_posts DROP CONSTRAINT IF EXISTS blog_posts_category_check;

ALTER TABLE public.blog_posts ADD CONSTRAINT blog_posts_category_check CHECK (
  category = ANY (ARRAY[
    'case-study',
    'tutorial',
    'announcement',
    'opinion',
    'deep-dive',
    'weekly-radar',
    'community-spotlight',
    'behind-the-scenes',
    'rant',
    'research-findings'
  ])
);

-- ============================================================================
-- Add series linkage em blog_posts (opcional, FK nullable)
-- ============================================================================
ALTER TABLE public.blog_posts ADD COLUMN IF NOT EXISTS series_id uuid REFERENCES public.publication_series(id);
ALTER TABLE public.blog_posts ADD COLUMN IF NOT EXISTS series_position smallint;
ALTER TABLE public.blog_posts ADD COLUMN IF NOT EXISTS github_repo_url text;

CREATE INDEX IF NOT EXISTS idx_blog_posts_series ON public.blog_posts(series_id, series_position) WHERE series_id IS NOT NULL;

COMMENT ON COLUMN public.blog_posts.series_id IS 'FK opcional para publication_series (Akita pattern). Permite posts orfaos (sem série).';
COMMENT ON COLUMN public.blog_posts.github_repo_url IS 'URL do repo GitHub com código reproducível (padrão Akita/GitHub Blog).';
