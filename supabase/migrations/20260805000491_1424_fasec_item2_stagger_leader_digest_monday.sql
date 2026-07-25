-- #1424 Fase C (item 2) — tirar o digest de lider da colisao de sabado
--
-- Os dois digests semanais disparavam no mesmo dia, a 30 min um do outro:
--   jobid 26 send-weekly-member-digest  sab 12:00 UTC
--   jobid 27 send-weekly-leader-digest  sab 12:30 UTC
--
-- Medido em 2026-07-25 (consultas ao vivo):
--   - media de envios por dia da semana (28d): Seg 15,5 · Ter 47,8 · Qua 16,3 ·
--     Qui 28,3 · Sex 50,0 · SAB 124,8 · Dom 32,0.
--   - o pico de sabado E o proprio digest: em 18/07 os 108 envios do dia foram
--     71 member digest + 37 leader digest, sem trafego concorrente.
--   - projecao do sabado ja com as Fases A+B e a agregacao (mig 490):
--     71 + 20 = ~91 contra DAILY_SEND_CAP=90. Margem ~zero.
--
-- Por que mover o digest de LIDER (o menor) e nao o de membro (o maior):
--   sabado nao tem trafego alem dos digests, entao o member digest (71) fica la
--   com folga de ~19. Mover os 71 para um dia util seria PIOR: numa segunda cheia
--   (30 envios) daria ~101 e o cap diferiria o excedente. Mover os 20 do lider
--   para segunda (dia mais vazio, 15,5) deixa os dois dias folgados:
--     sabado ~71 (folga 19) · segunda ~35 (folga 55)
--
-- Bonus de produto: o digest de lider e o acionavel (atas pendentes, presencas
-- nao registradas, champions nao conferidos). Chegar na segunda de manha
-- (12:00 UTC = 09:00 America/Sao_Paulo) poe as pendencias na frente do lider no
-- inicio da semana de trabalho, e nao no sabado.
--
-- Transicao (uma vez so): o ultimo disparo no modelo antigo foi sabado 25/07 e o
-- primeiro no novo sera segunda 27/07, 2 dias depois. Como get_weekly_initiative_digest
-- reporta o ESTADO ATUAL de pendencias numa janela rolante de 7 dias (#1470), esse
-- primeiro envio repete boa parte do anterior. E redundancia pontual, nao erro: o
-- conteudo continua correto, e a cadencia volta a ser semanal a partir dai.
--
-- Altera apenas o schedule; o command do job fica intacto.

DO $$
DECLARE
  v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid
  FROM cron.job
  WHERE jobname = 'send-weekly-leader-digest';

  IF v_jobid IS NULL THEN
    RAISE EXCEPTION 'cron job send-weekly-leader-digest nao encontrado — verifique o nome antes de aplicar';
  END IF;

  -- '0 12 * * 1' = toda segunda-feira as 12:00 UTC (09:00 America/Sao_Paulo)
  PERFORM cron.alter_job(job_id := v_jobid, schedule := '0 12 * * 1');
END $$;
