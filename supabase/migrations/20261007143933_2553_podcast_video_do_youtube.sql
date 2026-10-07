-- #2553: o /podcast liga cada episodio ao video da pilula no YouTube (decisao do GP em 07/10/2026).
-- WHAT: get_public_podcast_episodes passa a devolver 'video_url' em cada episodio: o video do canal do Nucleo ja
--       ingerido em comms_media_items (canal youtube) cujo titulo contem o titulo do episodio e que saiu ate 7 dias
--       antes ou depois dele; havendo mais de um, o mais proximo na data.
-- WHY:  as pilulas saem em video e em audio, e a pagina so tocava o audio. Sem tabela de mapeamento: o vinculo sai
--       do dado, e video privado ou agendado nao entra, porque o sync do YouTube so traz o que esta publico.
--       O resto do corpo nao muda: sem descricao e sem autor.
-- ROLLBACK: reaplicar 20261007124801_2553_podcast_idioma_do_audio.sql.
CREATE OR REPLACE FUNCTION public.get_public_podcast_episodes(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cfg AS (
    SELECT c.config
    FROM public.comms_channel_config c
    WHERE c.channel = 'spotify'
  ),
  ultima AS (
    SELECT max(m.synced_at) AS em
    FROM public.comms_media_items m
    WHERE m.channel = 'spotify'
  ),
  eps AS (
    SELECT
      m.external_id,
      m.published_at,
      m.thumbnail_url,
      m.payload,
      substring(m.caption FROM '^\s*\[([^\]]+)\]') AS series,
      btrim(regexp_replace(m.caption, '^\s*\[[^\]]+\]\s*', '')) AS title
    FROM public.comms_media_items m
    CROSS JOIN ultima u
    WHERE m.channel = 'spotify'
      AND m.media_type = 'EPISODE'
      AND m.synced_at >= u.em - interval '1 hour'
      AND m.published_at IS NOT NULL
      AND m.published_at <= now()
  )
  SELECT jsonb_build_object(
    'show_url', (SELECT cfg.config ->> 'show_url' FROM cfg),
    'synced_at', (SELECT u.em FROM ultima u),
    'total', (SELECT count(*) FROM eps),
    'episodes', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object(
                 'id', e.external_id,
                 'title', e.title,
                 'series', e.series,
                 'published_at', e.published_at,
                 'duration_seconds', (e.payload ->> 'duration_seconds')::integer,
                 'cover_url', e.thumbnail_url,
                 'audio_url', e.payload ->> 'audio_url',
                 'audio_type', e.payload ->> 'audio_type',
                 'audio_language', e.payload ->> 'audio_language',
                 'video_url', CASE WHEN v.video_id IS NOT NULL THEN 'https://www.youtube.com/watch?v=' || v.video_id END
               )
               ORDER BY e.published_at DESC
             )
      FROM (
        SELECT * FROM eps
        ORDER BY published_at DESC
        LIMIT greatest(1, least(COALESCE(p_limit, 100), 200))
      ) e
      LEFT JOIN LATERAL (
        SELECT y.external_id AS video_id
        FROM public.comms_media_items y
        WHERE y.channel = 'youtube'
          AND y.media_type = 'VIDEO'
          AND y.external_id ~ '^[A-Za-z0-9_-]{11}$'
          AND y.published_at IS NOT NULL
          AND y.published_at <= now()
          AND y.published_at BETWEEN e.published_at - interval '7 days' AND e.published_at + interval '7 days'
          AND length(e.title) >= 15
          AND strpos(lower(y.caption), lower(e.title)) > 0
        ORDER BY abs(extract(epoch FROM (y.published_at - e.published_at)))
        LIMIT 1
      ) v ON true
    ), '[]'::jsonb)
  );
$function$;

-- CREATE OR REPLACE keeps the ACL; restated so this capture carries the grants like the first one.
REVOKE ALL ON FUNCTION public.get_public_podcast_episodes(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_podcast_episodes(integer) TO anon, authenticated, service_role;
