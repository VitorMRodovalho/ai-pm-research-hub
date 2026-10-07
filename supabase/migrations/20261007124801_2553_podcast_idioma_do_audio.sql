-- #2553: o /podcast mostra por episodio o idioma do audio (decisao do GP em 06/10/2026).
-- WHAT: get_public_podcast_episodes passa a devolver 'audio_language' em cada episodio, lido do payload que
--       a EF sync-comms-metrics grava a partir do <language> do RSS (o do item, ou o do canal).
-- WHY:  em en-US e es-LATAM a pagina avisa por episodio que o audio esta em outro idioma, com o nome do
--       idioma vindo do dado (Intl), sem texto fixo. O resto do corpo nao muda: sem descricao e sem autor.
-- ROLLBACK: reaplicar o corpo de 20261006195541_2553_podcast_canal_spotify_e_leitura_publica.sql.
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
                 'audio_language', e.payload ->> 'audio_language'
               )
               ORDER BY e.published_at DESC
             )
      FROM (
        SELECT * FROM eps
        ORDER BY published_at DESC
        LIMIT greatest(1, least(COALESCE(p_limit, 100), 200))
      ) e
    ), '[]'::jsonb)
  );
$function$;

-- CREATE OR REPLACE keeps the ACL; restated so this capture carries the grants like the first one.
REVOKE ALL ON FUNCTION public.get_public_podcast_episodes(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_podcast_episodes(integer) TO anon, authenticated, service_role;
