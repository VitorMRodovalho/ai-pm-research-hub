-- #3186: pausa a revisão do acesso às pastas (#3179) no cron diário, até a permissão herdada virar contagem.
-- A primeira leitura real (ensaio de 24/11/2026) deu 371 achados em 29 pastas, 355 deles herdados de pasta acima, que
-- a revisão não deixa revogar na pasta. Decisão do GP: pausar antes do cron das 04:00 UTC. As concessões seguem como
-- antes: só a revisão para (skip_acl_review). Volta: o mesmo cron sem skip_acl_review, na PR da #3186.
SELECT cron.schedule('membership-drive-reconcile-daily', '0 4 * * *', $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/reconcile-initiative-drive-access',
    body := '{"source":"pg_cron","skip_acl_review":true}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    timeout_milliseconds := 150000
  );
  $cron$);
