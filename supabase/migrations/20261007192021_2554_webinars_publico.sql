-- #2554: a pagina publica /webinars le uma RPC propria, que o visitante pode executar.
-- WHAT: get_public_webinars() devolve so os campos que a pagina mostra, dos webinars confirmados e concluidos.
-- WHY:  a pagina chamava list_webinars_v2, sem EXECUTE para anon, e saia vazia para todo visitante. Abrir aquela
--       funcao para anon nao serve: ela devolve notas, organizador, co-gestores e o card ligado.
-- SCOPE: so status confirmed e completed, fora de iniciativa confidencial (is_confidential_initiative, que nao
--       depende da sessao). O link de entrada so sai para webinar confirmado e futuro; a gravacao e a contagem de
--       presentes, so para concluido. list_webinars_v2 segue igual para o admin e o MCP.
-- ROLLBACK: DROP FUNCTION public.get_public_webinars();
CREATE OR REPLACE FUNCTION public.get_public_webinars()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at DESC), '[]'::jsonb)
  FROM (
    SELECT
      w.id,
      w.title,
      w.description,
      w.scheduled_at,
      w.duration_min,
      w.status,
      w.chapter_code,
      i.title AS tribe_name,
      CASE WHEN w.status = 'confirmed' AND w.scheduled_at > now() THEN w.meeting_link END AS meeting_link,
      CASE WHEN w.status = 'completed' THEN w.youtube_url END AS youtube_url,
      CASE WHEN w.status = 'completed' THEN
        (SELECT count(*) FROM public.attendance a WHERE a.event_id = w.event_id AND a.present = true)
      END AS attendee_count
    FROM public.webinars w
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    WHERE w.status IN ('confirmed', 'completed')
      AND NOT public.is_confidential_initiative(w.initiative_id)
  ) r;
$function$;

REVOKE ALL ON FUNCTION public.get_public_webinars() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_webinars() TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_public_webinars() IS
  '#2554: leitura publica dos webinars (confirmados e concluidos, fora de iniciativa confidencial) para a pagina /webinars.';
