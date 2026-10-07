-- #2553: o sync do YouTube roda tambem as 10:17 BRT (decisao do GP em 07/10/2026).
-- WHAT: agenda a EF sync-comms-metrics so para o canal youtube, todo dia as 13:17 UTC (10:17 BRT).
-- WHY:  as pilulas saem no YouTube por volta das 09:55 BRT, e o job diario (06:00 UTC, 03:00 BRT) so trazia o video
--       no dia seguinte; sem o video ingerido, o episodio do /podcast fica sem o link. E uma rodada a mais por dia,
--       nao uma por hora, porque a busca da API do YouTube custa 100 unidades por chamada. O job diario segue igual.
-- AUTH: o mesmo caminho do job diario sync-comms-metrics-daily: header x-sync-secret com o segredo sync_comms_secret
--       do vault, aceito pela EF em validSecrets. A chave de servico nao entra no comando.
-- ROLLBACK: SELECT cron.unschedule('sync-comms-youtube-1017-brt');
SELECT cron.schedule(
  'sync-comms-youtube-1017-brt',
  '17 13 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/sync-comms-metrics',
    body := '{"channels": ["youtube"], "source": "pg_cron", "triggered_by": "cron_youtube_1017_brt"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sync-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'sync_comms_secret' LIMIT 1)
    ),
    timeout_milliseconds := 60000
  );
  $cron$
);
