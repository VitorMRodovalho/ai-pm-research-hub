-- p169 — Backfill courses.url for 8 original rows (URLs lived in src/data/trail.ts)
-- Sync DB → trail.ts so DB becomes single source of truth for #3 refactor.

UPDATE public.courses SET url = 'https://www.pmi.org/shop/p-/elearning/generative-ai-overview-for-project-managers/el083' WHERE code = 'GENAI_OVERVIEW';
UPDATE public.courses SET url = 'https://www.pmi.org/shop/p-/elearning/data-landscape-of-genai-for-project-managers/el106' WHERE code = 'DATA_LANDSCAPE';
UPDATE public.courses SET url = 'https://www.pmi.org/shop/p-/elearning/talking-to-ai-prompt-engineering-for-project-managers/el128' WHERE code = 'PROMPT_ENG';
UPDATE public.courses SET url = 'https://www.pmi.org/shop/p-/elearning/practical-application-of-generative-ai-for-project-managers/el173' WHERE code = 'PRACTICAL_GENAI';
UPDATE public.courses SET url = 'https://www.pmi.org/shop/p-/elearning/ai-in-infrastructure-and-construction-projects/el174' WHERE code = 'AI_INFRA';
UPDATE public.courses SET url = 'https://www.pmi.org/shop/p-/elearning/ai-in-agile-delivery/el251' WHERE code = 'AI_AGILE';
UPDATE public.courses SET url = 'https://www.pmi.org/shop/brazil/p-/elearning/free-introduction-to-cognitive-project-management-in-ai-cpmai/el185' WHERE code = 'CPMAI_INTRO';
UPDATE public.courses SET url = 'https://www.pmi.org/shop/p-/elearning/pmi-citizen-developer-business-architect-cdba-introduction/el058' WHERE code = 'CDBA_INTRO';

-- Also normalize CPMAI_INTRO with hasCredly note: it has a Credly badge but
-- our DB row never had credly_badge_name set. trail.ts had hasCredly=true.
-- Set credly_badge_name to match what classify-badge.ts detects (PMI_NONTRIAL_KEYWORDS CPMAI_INTRO).
UPDATE public.courses SET credly_badge_name = 'Introduction to Cognitive Project Management in AI (CPMAI)™'
  WHERE code = 'CPMAI_INTRO' AND credly_badge_name IS NULL;
