-- p169 #3 — Public RPC for trail courses (eliminates parallel SoT in trail.ts)
-- TrailSection.astro frontmatter will call this at SSR time instead of importing
-- static COURSES array from src/data/trail.ts. DB courses table becomes the
-- single source of truth. trail.ts retained only as TypeScript interface (type-only).
-- Public-callable (anon + authenticated) — no PII, just course catalog metadata.
-- Rollback: DROP FUNCTION public.get_trail_courses();

CREATE OR REPLACE FUNCTION public.get_trail_courses()
RETURNS TABLE(
  code              text,
  name              text,
  tier              text,
  is_trail          boolean,
  url               text,
  sort_order        integer,
  credly_badge_name text,
  has_credly        boolean
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    c.code,
    c.name,
    c.tier,
    c.is_trail,
    c.url,
    c.sort_order,
    c.credly_badge_name,
    (c.credly_badge_name IS NOT NULL) AS has_credly
  FROM public.courses c
  ORDER BY
    CASE c.tier
      WHEN 'core' THEN 1
      WHEN 'specialty' THEN 2
      WHEN 'complementary' THEN 3
      WHEN 'master' THEN 4
      ELSE 5
    END,
    c.sort_order,
    c.code;
$function$;

GRANT EXECUTE ON FUNCTION public.get_trail_courses() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
