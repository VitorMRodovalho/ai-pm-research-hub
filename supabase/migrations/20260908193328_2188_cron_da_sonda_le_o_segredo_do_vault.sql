-- #2188 — o cron da sonda passa a ler o segredo do Vault, nao de um GUC.
--
-- O DEFEITO DE DESENHO, descoberto ao CONFIGURAR o segredo (08/09). A onda anterior escreveu o
-- cron lendo `current_setting('app.agenda_probe_internal_secret')`, copiando o comentario da
-- migration do cert-pdf-render. Medido ao tentar aplicar:
--
--   ALTER DATABASE postgres SET app.agenda_probe_internal_secret = '...'
--   ERROR: 42501: permission denied to set parameter
--
-- O role do Supabase nao e superuser, entao esse GUC NAO PODE ser setado por esta plataforma. O
-- cron ficaria para sempre no ramo "sem segredo configurado, nao chama nada" -- verde, silencioso
-- e inutil. O comentario que eu copiei descrevia um caminho que nunca funcionou aqui, e copiar
-- comentario nao e o mesmo que verificar o caminho.
--
-- O padrao que FUNCIONA neste projeto e o Vault, e ele ja estava na minha frente: o cron
-- `publish-scheduled-social` le `vault.decrypted_secrets`, e o proprio `cert_pdf_internal_secret`
-- esta no Vault desde 2026-05-23, apesar do comentario da migration dele dizer GUC.
--
-- ⚠️ ACHADO COLATERAL, de outra frente e NAO consertado aqui: os dois gatilhos de PDF de
-- certificado divergem. `_trg_certificate_pdf_autogen` le do Vault (funciona);
-- `_trg_event_guest_cert_pdf_autogen` le do GUC (que nao existe e nao pode ser criado), entao o
-- PDF de certificado de convidado de evento externo (#1098) pula em silencio desde sempre.
--
-- O segredo esta no Vault como `agenda_probe_internal_secret`, pareado com o wrangler secret
-- AGENDA_PROBE_INTERNAL_SECRET. Conferido por hash: sha256 identico dos dois lados, sem o valor
-- transitar por log, transcript ou arquivo versionado.

SELECT cron.unschedule('interview-agenda-probe')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'interview-agenda-probe');

SELECT cron.schedule(
  'interview-agenda-probe',
  '17 */6 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://nucleoia.vitormr.dev/api/internal/agenda-availability-probe',
    body := '{"source":"pg_cron"}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        SELECT decrypted_secret FROM vault.decrypted_secrets
        WHERE name = 'agenda_probe_internal_secret' LIMIT 1
      )
    ),
    timeout_milliseconds := 120000
  )
  -- Sem segredo no Vault o cron NAO chama: um Bearer nulo viraria 401 quatro vezes ao dia, e um
  -- 401 recorrente e ruido que ninguem investiga. A ausencia tem de ser silenciosa e verdadeira.
  WHERE EXISTS (
    SELECT 1 FROM vault.decrypted_secrets WHERE name = 'agenda_probe_internal_secret'
  );
  $cron$
);
