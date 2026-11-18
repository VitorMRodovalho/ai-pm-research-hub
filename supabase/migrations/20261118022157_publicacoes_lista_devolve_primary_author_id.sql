-- "Minhas submissões" (/publications) e o cartão "Minhas publicações" (/workspace) filtram a lista de
-- get_publication_submissions por primary_author_id, mas a função não devolvia esse campo: o filtro
-- nunca casava, e quem criava uma submissão não a via listada. Efeito medido em 17/11/2026: um mesmo
-- rascunho salvo três vezes, porque a tela não mostrava retorno nem a lista.
--
-- Mudança: a lista passa a devolver primary_author_id (uuid). Corpo, filtro de leitura (vínculo
-- vigente ou autor principal, 20261005183507) e ordem iguais à captura anterior. Acrescentar coluna a
-- RETURNS TABLE muda o tipo de retorno, então é DROP + CREATE (CREATE OR REPLACE recusa), e o DROP
-- leva os privilégios: o REVOKE/GRANT abaixo repõe os de 20260426143952 (sem PUBLIC nem anon).
--
-- Quem chama: src/pages/publications.astro, src/pages/workspace.astro, src/pages/admin/publications.astro,
-- src/pages/publications/submissions.astro. Todos leem por nome; a coluna nova não muda os demais.

DROP FUNCTION IF EXISTS public.get_publication_submissions(submission_status, integer);

CREATE FUNCTION public.get_publication_submissions(p_status submission_status DEFAULT NULL::submission_status, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS TABLE(id uuid, title text, abstract text, target_type submission_target_type, target_name text, status submission_status, submission_date date, presentation_date date, primary_author_id uuid, primary_author_name text, tribe_name text, estimated_cost_brl numeric, actual_cost_brl numeric, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    ps.id, ps.title, ps.abstract, ps.target_type, ps.target_name,
    ps.status, ps.submission_date, ps.presentation_date,
    ps.primary_author_id,
    m.name AS primary_author_name,
    i.title AS tribe_name,
    ps.estimated_cost_brl, ps.actual_cost_brl, ps.created_at
  FROM public.publication_submissions ps
  LEFT JOIN public.members m ON m.id = ps.primary_author_id
  LEFT JOIN public.initiatives i ON i.id = ps.initiative_id
  WHERE (p_status IS NULL OR ps.status = p_status)
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    -- Leitura pela API segue a política de publication_submissions: vínculo vigente ou autor principal.
    AND (NOT public._request_is_rest_caller() OR public.rls_is_authoritative_member()
         OR ps.primary_author_id IN (SELECT m2.id FROM public.members m2 WHERE m2.auth_id = auth.uid()))
  ORDER BY ps.created_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_publication_submissions(submission_status, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_publication_submissions(submission_status, integer) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
