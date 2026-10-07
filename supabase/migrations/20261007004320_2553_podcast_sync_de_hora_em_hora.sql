-- #2553: sync do podcast de hora em hora (decisao do GP em 06/10/2026, Decisao 2, opcao A).
-- WHAT: agenda a EF sync-comms-metrics so para o canal spotify, de hora em hora no minuto 17.
-- WHY:  o job diario (06:00 UTC) deixaria cada episodio novo ate um dia fora de /podcast. O canal spotify
--       le so o RSS publico: sem cota de API, sem token, uma requisicao por rodada. O job diario segue igual
--       e tambem roda o spotify; a sobreposicao das 06h e inofensiva (upsert por channel, external_id).
-- AUTH: o mesmo caminho do job diario sync-comms-metrics-daily: header x-sync-secret com o segredo
--       sync_comms_secret do vault, aceito pela EF em validSecrets. A chave de servico nao entra no comando.
-- ROLLBACK: SELECT cron.unschedule('sync-comms-podcast-hourly');
SELECT cron.schedule(
  'sync-comms-podcast-hourly',
  '17 * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/sync-comms-metrics',
    body := '{"channels": ["spotify"], "source": "pg_cron", "triggered_by": "cron_podcast_hourly"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sync-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'sync_comms_secret' LIMIT 1)
    ),
    timeout_milliseconds := 60000
  );
  $cron$
);
