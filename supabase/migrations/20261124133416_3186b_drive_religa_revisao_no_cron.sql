-- #3186b: o cron diário volta a mandar a revisão da ACL (#3179), sem skip_acl_review. Aplicar só depois do deploy da
-- EF reconcile-initiative-drive-access da #3186 e do ensaio que mede os achados diretos.
-- ANTES: o mesmo comando com body {"source":"pg_cron","skip_acl_review":true}, da pausa 20261124023550 (#3187);
-- md5(command) vivo 15a1c513abe1a23d303884b267dcb3fc. DEPOIS: md5(command) 917bd43b5307a77d82b319f3c1196476.
-- DEPOIS: o comando da captura 20260805000442 (#1376), igual ao de antes da pausa. Mesmo nome, então substitui.
SELECT cron.schedule(
  'membership-drive-reconcile-daily',
  '0 4 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/reconcile-initiative-drive-access',
    body := '{"source":"pg_cron"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    timeout_milliseconds := 150000
  );
  $cron$
);
