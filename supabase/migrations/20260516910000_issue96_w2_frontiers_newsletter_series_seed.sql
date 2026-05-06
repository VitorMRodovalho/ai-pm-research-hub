-- Issue #96 W2 partial: seed Frontiers newsletter as 6th publication_series + add 'linkedin_newsletter' target type
-- Newsletter já está LIVE em LinkedIn (id 7440224833159790592, editor Fabricio).
-- Outros gates (PI/jurídico per #96 Gate 0) permanecem para PM action — não tocados nesta migration.

DO $$
BEGIN
  ALTER TYPE submission_target_type ADD VALUE IF NOT EXISTS 'linkedin_newsletter';
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

INSERT INTO public.publication_series (
  slug, title_i18n, description_i18n,
  cadence_hint, format_default, is_active,
  editorial_voice, target_audience, organization_id
) VALUES (
  'frontiers-newsletter',
  jsonb_build_object(
    'pt', 'Frontiers in AI & Project Management',
    'en', 'Frontiers in AI & Project Management',
    'es', 'Frontiers in AI & Project Management'
  ),
  jsonb_build_object(
    'pt', 'Newsletter LinkedIn editada por Fabricio (Vice-GP Núcleo) explorando fronteiras entre IA e gerenciamento de projetos. URL canônica: https://www.linkedin.com/newsletters/frontiers-in-ai-project-mgmt-7440224833159790592/. Já em produção (publicada externamente). Ratificação retroativa via PI fluxo pendente — Gate 0 #96.',
    'en', 'LinkedIn newsletter edited by Fabricio (Vice-GP Núcleo) exploring frontiers between AI and project management. Canonical URL: https://www.linkedin.com/newsletters/frontiers-in-ai-project-mgmt-7440224833159790592/. Already in production. Retroactive PI alignment pending — Gate 0 of #96.'
  ),
  'monthly',
  'multi',
  true,
  'Editorial profissional com cross-disciplinary insight (PMBOK, AI, governance, ethics)',
  'PMs, AI practitioners, voluntários Núcleo & ecossistema PMI Latam',
  (SELECT id FROM public.organizations WHERE slug = 'nucleo-ia' LIMIT 1)
)
ON CONFLICT (slug) DO NOTHING;

NOTIFY pgrst, 'reload schema';
