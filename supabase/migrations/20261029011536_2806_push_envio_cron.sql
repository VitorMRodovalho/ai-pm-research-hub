-- #2806, envio do push: a lista de hosts de servico de push e o job que chama a EF send-push.
--
-- APLICAR DEPOIS do deploy da EF send-push e dos segredos VAPID. Na ordem errada nada se perde: sem os segredos a
-- EF devolve 500 antes de reivindicar a fila, e o corte de 1 h dela impede que avisos acumulados saiam depois.
--
-- push_service_hosts: o endpoint da inscricao vem do navegador do membro, e a EF so faz POST para host igual ou
-- subdominio de um destes. Fonte de cada um, lida em 28/10/2026:
--   push.apple.com ................... documentacao da Apple de web push ("allow access for https://*.push.apple.com");
--   updates.push.services.mozilla.com  documentacao do autopush da Mozilla (endpoint de producao);
--   fcm.googleapis.com ............... blog oficial do Chrome (endpoint https://fcm.googleapis.com/fcm/send/..., texto de 2016);
--   notify.windows.com ............... NAO VERIFICADO na fonte oficial: a pagina de push do Edge nao nomeia o host, e a
--                                      politica ForceBuiltInPushMessagingClient so diz que o Edge usa o WNS; o host vem
--                                      de forum e de biblioteca de terceiros.
-- Um host que falte so deixa aquele navegador sem push (a EF conta em skips.hostNotAllowed e nao apaga a inscricao),
-- e acrescentar ou corrigir e um UPDATE neste valor.
--
-- O job roda a cada minuto, mas so chama a EF quando existe aviso imediato ainda sem marca de push (indice parcial
-- idx_notifications_push_pending). Sem aviso, nenhuma chamada sai, e o JWT VAPID nao e renovado a toa.
-- ROLLBACK: SELECT cron.unschedule('send-push');
INSERT INTO public.platform_settings (key, value, description) VALUES
  ('push_service_hosts', '["push.apple.com", "fcm.googleapis.com", "updates.push.services.mozilla.com", "notify.windows.com"]'::jsonb,
   '#2806: hosts de servico de push para onde a EF send-push pode enviar (o host do endpoint tem de ser igual ou subdominio de um destes).')
ON CONFLICT (key) DO NOTHING;

SELECT cron.unschedule('send-push')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-push');

SELECT cron.schedule(
  'send-push',
  '* * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-push',
    body := '{"source": "pg_cron"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    timeout_milliseconds := 30000
  )
  WHERE EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.delivery_mode = 'transactional_immediate' AND n.push_dispatched_at IS NULL
  );
  $cron$
);
