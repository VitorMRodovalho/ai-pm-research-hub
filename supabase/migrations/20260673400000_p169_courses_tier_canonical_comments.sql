-- p169 — Document courses.tier as canonical (deprecate category)
-- Code-review finding: courses.category and courses.tier coexist with diverging values
-- (tier='master' ↔ category='master_cert'). No live RPC actually filters by category
-- (audit p169: only is_trail used). Document tier as canonical to prevent future
-- confusion. category retained for backward compat — future migration may drop it.

COMMENT ON COLUMN public.courses.tier IS
  'CANONICAL (p169+) — Trail PMI AI tier model: core|specialty|complementary|master. Use this for grouping/render decisions. NOT NULL + CHECK constrained.';

COMMENT ON COLUMN public.courses.category IS
  'LEGACY (deprecated p169) — Original taxonomy: core|complementary|optional|master_cert. Maintained for backward compat but no live RPC filters by it. Prefer courses.tier or courses.is_trail.';

COMMENT ON COLUMN public.courses.is_trail IS
  'TRUE for the 6 PMIxAI mini-certs (4 core + 2 specialty) that have Credly badges tracked in classifyBadge() PMI_TRAIL_KEYWORDS. FALSE for complementary courses and master cert. Use to count "mandatory trail" completion.';
