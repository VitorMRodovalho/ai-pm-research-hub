-- O webinar confirmado conta como próximo ou ao vivo até scheduled_at + duration_min, e o link vale nesse intervalo.
-- WHAT: _meeting_window_phase() devolve a fase de um encontro num instante dado ('upcoming', 'live', 'ended' ou NULL),
--       com o instante injetado, para a borda ser testável sem esperar o relógio. get_public_webinars() passa a
--       devolver phase, decidida pelo banco, e o meeting_link só sai quando phase não é nula.
-- WHY:  na captura 20261007192021 o link saía só com scheduled_at > now(): o botão de entrar sumia do site no instante
--       em que o webinar começava, e a página cortava a lista do mesmo jeito, pelo relógio do Worker.
-- SCOPE: assinatura, SECURITY DEFINER, STABLE, search_path e grants de get_public_webinars iguais; o resto do corpo é
--        o da captura 20261007192021. duration_min é NOT NULL DEFAULT 60; um nulo conta como 0 (o fim é o início),
--        que é o comportamento de antes. O helper não é SECURITY DEFINER e só service_role o executa direto.
-- ROLLBACK: reaplicar o corpo de get_public_webinars da 20261007192021 e depois
--           DROP FUNCTION public._meeting_window_phase(timestamptz, integer, timestamptz, interval, interval);
CREATE FUNCTION public._meeting_window_phase(
  p_starts_at    timestamptz,
  p_duration_min integer,
  p_now          timestamptz,
  p_open_before  interval DEFAULT NULL,
  p_close_after  interval DEFAULT '0 minutes'::interval
)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $function$
  SELECT CASE
    WHEN p_starts_at IS NULL OR p_now IS NULL THEN NULL
    WHEN p_open_before IS NOT NULL AND p_now < p_starts_at - p_open_before THEN NULL
    WHEN p_now < p_starts_at THEN 'upcoming'
    WHEN p_now < p_starts_at + make_interval(mins => GREATEST(COALESCE(p_duration_min, 0), 0)) THEN 'live'
    WHEN p_now < p_starts_at + make_interval(mins => GREATEST(COALESCE(p_duration_min, 0), 0))
                 + COALESCE(p_close_after, '0 minutes'::interval) THEN 'ended'
    ELSE NULL
  END
$function$;

REVOKE ALL ON FUNCTION public._meeting_window_phase(timestamptz, integer, timestamptz, interval, interval)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._meeting_window_phase(timestamptz, integer, timestamptz, interval, interval)
  TO service_role;

COMMENT ON FUNCTION public._meeting_window_phase(timestamptz, integer, timestamptz, interval, interval) IS
  'Fase de um encontro no instante p_now: upcoming (antes do início, a partir de p_open_before quando não é nulo), live (do início ao fim, início + p_duration_min, nulo conta 0), ended (do fim até p_close_after depois), NULL fora disso.';

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
  '#2554: leitura publica dos webinars (confirmados e concluidos, fora de iniciativa confidencial) para a pagina /webinars. phase (upcoming ou live) vem de _meeting_window_phase; o link sai so com phase nao nula, ate scheduled_at + duration_min.';
