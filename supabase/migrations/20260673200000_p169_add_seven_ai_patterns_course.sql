-- p169 — Add "PMI Essentials: Seven AI Project Patterns" as complementary course
-- PM ask 2026-05-16: from PMI catalog. Foundation course for the 7 AI patterns taxonomy
-- that underpins PMI-CPMAI Master Cert. Free for everyone.
-- Rollback: DELETE FROM courses WHERE code='AI_PATTERNS';

INSERT INTO public.courses (
  code, name, category, is_free, url, sort_order, credly_badge_name, is_trail, tier, organization_id
) VALUES (
  'AI_PATTERNS',
  'PMI Essentials: Seven AI Project Patterns',
  'complementary',
  true,
  'https://www.pmi.org/shop/p-/elearning/pmi-essentials-seven-ai-project-patterns/el343',
  9,
  NULL,
  false,
  'complementary',
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'
)
ON CONFLICT (code) DO NOTHING;
