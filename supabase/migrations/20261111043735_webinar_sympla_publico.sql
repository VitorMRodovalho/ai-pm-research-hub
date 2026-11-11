-- WHAT: get_public_webinars() passa a devolver sympla_event_url, a pagina da inscricao opcional no Sympla, com a
--       mesma regra do link de entrada: so com phase nao nula (webinar confirmado, ate scheduled_at + duration_min).
-- WHY:  decisao W4 do GP (11/11/2026): o workshop de 26/11 tem inscricao opcional no Sympla, e quem chega pelo
--       Instagram nao tem link clicavel na legenda; o botao fica na pagina /webinars. A coluna ja existia (p95 #129).
-- SCOPE: assinatura, SECURITY DEFINER, STABLE, search_path e grants iguais; o resto do corpo e o da captura
--        20261106001708. Concluido nao devolve o link: a inscricao acabou.
-- ROLLBACK: reaplicar o corpo de get_public_webinars da 20261106001708.
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
      CASE WHEN ph.phase IS NOT NULL THEN w.meeting_link END AS meeting_link,
      ph.phase,
      CASE WHEN ph.phase IS NOT NULL THEN w.sympla_event_url END AS sympla_event_url,
      CASE WHEN w.status = 'completed' THEN w.youtube_url END AS youtube_url,
      CASE WHEN w.status = 'completed' THEN
        (SELECT count(*) FROM public.attendance a WHERE a.event_id = w.event_id AND a.present = true)
      END AS attendee_count
    FROM public.webinars w
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    CROSS JOIN LATERAL (
      SELECT CASE WHEN w.status = 'confirmed'
                  THEN public._meeting_window_phase(w.scheduled_at, w.duration_min, now())
             END AS phase
    ) ph
    WHERE w.status IN ('confirmed', 'completed')
      AND NOT public.is_confidential_initiative(w.initiative_id)
  ) r;
$function$;

REVOKE ALL ON FUNCTION public.get_public_webinars() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_webinars() TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_public_webinars() IS
  '#2554: leitura publica dos webinars (confirmados e concluidos, fora de iniciativa confidencial) para a pagina /webinars. phase (upcoming ou live) vem de _meeting_window_phase; o link de entrada e o da inscricao opcional no Sympla (decisao W4, GP 11/11/2026) saem so com phase nao nula, ate scheduled_at + duration_min.';
