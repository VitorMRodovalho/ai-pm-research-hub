-- Release record: v1.0.0-beta
UPDATE public.releases SET is_current = false WHERE is_current = true;

INSERT INTO public.releases (version, title, description, release_type, is_current,
  waves_included, git_tag, released_at)
VALUES (
  'v1.0.0-beta',
  'Beta Launch',
  'First release to 52 active members across 5 PMI chapters. BoardEngine, Portfolio Dashboard, Gamification, Events, Attendance, Tier Viewer, Publications, Sustainability, Adoption Dashboard, Help, Blog Editor.',
  'beta',
  true,
  ARRAY['W138','W139','W140','W141','W142','W143','W144','W104','W105','W106','W107','W108'],
  'v1.0.0-beta',
  now()
);
