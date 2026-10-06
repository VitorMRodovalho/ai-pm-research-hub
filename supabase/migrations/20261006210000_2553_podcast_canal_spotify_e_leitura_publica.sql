-- #2553 (F2 + F3, recorte do podcast): o canal `spotify` em comms_media_items e a leitura pública dos episódios.
--
-- WHAT: (1) cadastra o canal `spotify` em comms_channel_config, com o RSS público do show; a EF
--       sync-comms-metrics passa a ler esse RSS e gravar um episódio por linha em comms_media_items;
--       (2) get_public_podcast_episodes(p_limit): leitura pública dos episódios para a página /podcast.
-- WHY:  spec docs/specs/2553-vitrine-producao-e-conhecimento.md, seções 4.1 e 4.2, e decisão D4 do GP
--       (06/10/2026): ingestão automática pelo RSS, sem cadastro manual e sem tabela nova.
-- LGPD: a função devolve só o que o próprio feed público publica, e nem tudo: fica de fora a descrição do
--       episódio (cita convidados pelo nome; autoria pública é a decisão D1, ainda aberta) e o autor do
--       item, que a EF nem grava. Nenhum id de membro, nome, e-mail ou telefone.
-- Episódio que sai do feed sai da página: a EF lê o feed inteiro a cada rodada e carimba synced_at em
--       todas as linhas que viu; a função só devolve o que a rodada mais recente carimbou.
-- ROLLBACK: DROP FUNCTION public.get_public_podcast_episodes(integer);
--           DELETE FROM public.comms_channel_config WHERE channel = 'spotify';
--           DELETE FROM public.comms_media_items WHERE channel = 'spotify';

-- 1. O canal. metric_kind é NOT NULL; o RSS não traz série de audiência, então o canal nunca grava em
--    comms_metrics_daily, e 'daily' só satisfaz a coluna.
INSERT INTO public.comms_channel_config (channel, metric_kind, config)
VALUES (
  'spotify',
  'daily',
  jsonb_build_object(
    'rss_url', 'https://anchor.fm/s/110828ed8/podcast/rss',
    'show_id', '2DYjPd9dhwXqy6ZnZnAq7c',
    'show_url', 'https://open.spotify.com/show/2DYjPd9dhwXqy6ZnZnAq7c'
  )
)
ON CONFLICT (channel) DO UPDATE
  SET config = public.comms_channel_config.config || EXCLUDED.config,
      updated_at = now();

-- 2. A leitura pública.
CREATE OR REPLACE FUNCTION public.get_public_podcast_episodes(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
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
                 'audio_type', e.payload ->> 'audio_type'
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

COMMENT ON FUNCTION public.get_public_podcast_episodes(integer) IS
  '#2553: episódios do podcast para a página pública /podcast. Lê comms_media_items (canal spotify, ingerido do '
  'RSS público pela EF sync-comms-metrics). Pública por desenho: devolve só título, série, data, duração, capa e '
  'áudio, que o próprio feed público publica; sem descrição (cita pessoas; decisão D1) e sem autor.';

REVOKE ALL ON FUNCTION public.get_public_podcast_episodes(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_podcast_episodes(integer) TO anon, authenticated, service_role;
