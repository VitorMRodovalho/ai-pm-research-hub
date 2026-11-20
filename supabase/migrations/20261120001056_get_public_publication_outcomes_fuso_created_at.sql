-- #3093, revisão da PR #3094: o último braço do coalesce (created_at, timestamptz) passa a ser lido no fuso de Brasília,
-- como o ano. Antes, created_at::date usava o fuso da sessão (UTC), e um registro sem nenhuma data, criado entre 21h e
-- meia-noite de 31/12 em Brasília, caía no ano seguinte. O resto do corpo é o mesmo de 20261119230710.
-- Rollback: reaplicar supabase/migrations/20261119230710_get_public_publication_outcomes.sql.
CREATE OR REPLACE FUNCTION public.get_public_publication_outcomes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH y AS (SELECT extract(year FROM (now() AT TIME ZONE 'America/Sao_Paulo'))::int AS yr),
  base AS (
    SELECT ps.status::text AS status, ps.target_type::text AS target_type
    FROM public.publication_submissions ps, y
    WHERE extract(year FROM coalesce(ps.acceptance_date, ps.presentation_date, ps.submission_date, (ps.created_at AT TIME ZONE 'America/Sao_Paulo')::date))::int = y.yr
      AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.id = ps.initiative_id AND i.visibility = 'confidential')
  )
  SELECT jsonb_build_object(
    'year', (SELECT yr FROM y),
    'published', count(*) FILTER (WHERE status = 'published'),
    'presented', count(*) FILTER (WHERE status = 'presented'),
    'presented_chapter_event', count(*) FILTER (WHERE status = 'presented' AND target_type = 'pmi_chapter_event'),
    'presented_congress', count(*) FILTER (WHERE status = 'presented' AND target_type IS DISTINCT FROM 'pmi_chapter_event'),
    'under_evaluation', count(*) FILTER (WHERE status IN ('submitted', 'under_review'))
  )
  FROM base;
$function$;

REVOKE ALL ON FUNCTION public.get_public_publication_outcomes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_publication_outcomes() TO anon, authenticated, service_role;
