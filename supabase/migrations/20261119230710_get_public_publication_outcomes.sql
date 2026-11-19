-- Home (GP 19/11/2026): as publicações do ano com avaliação externa, em quebra, ao lado da meta da curadoria.
-- Lê publication_submissions, a mesma base do business case. Ano = ano corrente em America/Sao_Paulo, pela data mais
-- antiga que existir entre aceite, apresentação, submissão e criação. Apresentada em evento de capítulo PMI conta à
-- parte; toda outra apresentada é congresso, para a soma das duas fechar com o total. Em avaliação = submitted +
-- under_review. Rascunho não entra. Iniciativa confidencial não entra (ADR-0105).
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
    WHERE extract(year FROM coalesce(ps.acceptance_date, ps.presentation_date, ps.submission_date, ps.created_at::date))::int = y.yr
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
