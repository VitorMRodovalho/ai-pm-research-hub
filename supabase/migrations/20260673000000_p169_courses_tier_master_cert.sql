-- p169 — Trilha PMI AI: add tier model + PMI-CPMAI master cert
-- PM-confirmed 2026-05-16: 4 tiers (core 4 / specialty 2 / complementary 2 / master 1)
-- Surfaces PMI-CPMAI as "next level" after the 6 mini-certs.
-- Rollback: ALTER TABLE courses DROP COLUMN tier; DELETE FROM courses WHERE code='PMI_CPMAI_MASTER';
--           ALTER TABLE courses DROP CONSTRAINT courses_category_check;
--           ALTER TABLE courses ADD CONSTRAINT courses_category_check CHECK (category IN ('core','complementary','optional'));

-- Step 0: expand category check to allow 'master_cert'
ALTER TABLE public.courses DROP CONSTRAINT courses_category_check;
ALTER TABLE public.courses
  ADD CONSTRAINT courses_category_check
  CHECK (category IN ('core','complementary','optional','master_cert'));

-- Step 1: add tier column (canonical tier model)
ALTER TABLE public.courses
  ADD COLUMN IF NOT EXISTS tier text;

-- Step 2: backfill existing 8 rows
UPDATE public.courses SET tier = 'core' WHERE code IN ('GENAI_OVERVIEW','DATA_LANDSCAPE','PROMPT_ENG','PRACTICAL_GENAI');
UPDATE public.courses SET tier = 'specialty' WHERE code IN ('AI_INFRA','AI_AGILE');
UPDATE public.courses SET tier = 'complementary' WHERE code IN ('CPMAI_INTRO','CDBA_INTRO');

-- Step 3: add PMI-CPMAI master cert row
INSERT INTO public.courses (
  code, name, category, is_free, url, sort_order, credly_badge_name, is_trail, tier, organization_id
) VALUES (
  'PMI_CPMAI_MASTER',
  'PMI Certified Professional in Managing AI (PMI-CPMAI)™',
  'master_cert',
  false,
  'https://www.pmi.org/certifications/managing-artificial-intelligence',
  100,
  'PMI Certified Professional in Managing AI (PMI-CPMAI)™',
  false,
  'master',
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'
)
ON CONFLICT (code) DO NOTHING;

-- Step 4: tier now NOT NULL
ALTER TABLE public.courses
  ALTER COLUMN tier SET NOT NULL;

-- Step 5: CHECK constraint on tier values
ALTER TABLE public.courses
  ADD CONSTRAINT courses_tier_check
  CHECK (tier IN ('core','specialty','complementary','master'));

-- Step 6: index tier for queries
CREATE INDEX IF NOT EXISTS idx_courses_tier ON public.courses(tier, sort_order);

-- Step 7: reload schema cache so PostgREST surfaces new column
NOTIFY pgrst, 'reload schema';
