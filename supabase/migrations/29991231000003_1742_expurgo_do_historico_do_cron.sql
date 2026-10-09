-- =====================================================================================
-- #1742 -- expurgo do historico do pg_cron (cron.job_run_details)
--
-- MEDIDO em 2026-10-09: cron.job_run_details tinha 282 MB de um banco de 702 MB, 300.919 linhas
-- desde 2026-03-21, 2.454 rodadas novas nas ultimas 24h e NENHUM job que limpasse. O unico indice e
-- a PK em runid e a tabela pertence ao supabase_admin, entao nao da para criar indice aqui. O
-- Supabase alertou falta de orcamento de IO de disco no mesmo dia.
--
-- REGRA (decisao do GP em 2026-10-09: "14 dias + 10 por job"):
--   - apaga rodada BEM-SUCEDIDA com mais de 14 dias;
--   - rodada com FALHA fica 90 dias, porque as funcoes de saude contam falhas em janelas de 30 e
--     90 dias (get_digest_health, get_drive_discovery_health, get_lgpd_cron_health,
--     get_ots_pipeline_health); com 14 dias essas janelas virariam 14 sem ninguem saber;
--   - as 10 rodadas mais recentes de cada job ficam sempre, para os 7 jobs mensais nao aparecerem
--     como "nunca rodou" (get_lgpd_cron_health usa limiar de 35 dias).
--
-- COMO, sem varrer a tabela a cada lote (revisado pelo data-architect em 2026-10-09):
--   - runid cresce com o tempo: o corte de 14 dias vira um runid, achado por busca binaria pela PK
--     (~20 leituras de indice). start_time NULL conta como recente (apaga menos, nunca mais);
--   - o DELETE confere de novo a idade e o status de cada linha (cinto e suspensorio: se a
--     monotonicidade falhar, nenhuma linha recente sai);
--   - as 10 ultimas de cada job saem de UMA varredura por execucao (o unico full scan da noite);
--   - o DELETE anda em faixas de runid pela PK. Tudo roda numa transacao: quem limita WAL, tempo e
--     tuplas mortas e p_max (50.000 por noite). O backlog inicial (~266 mil) se dilui em ~6 noites.
-- Espaco: o DELETE libera paginas para reuso (a tabela para de crescer); devolver o arquivo ao
-- disco exige VACUUM FULL, que so o dono (supabase_admin) pode rodar.
-- search_path vazio: tudo qualificado (cron., pg_temp.); funcoes de pg_catalog resolvem sozinhas.
-- ROLLBACK: SELECT cron.unschedule('cron-history-purge-nightly');
--           DROP FUNCTION public._purge_cron_job_run_details(integer, integer, integer, integer, integer);
-- =====================================================================================

CREATE OR REPLACE FUNCTION public._purge_cron_job_run_details(
  p_keep_days        integer DEFAULT 14,
  p_keep_failed_days integer DEFAULT 90,
  p_keep_per_job     integer DEFAULT 10,
  p_batch            integer DEFAULT 5000,
  p_max              integer DEFAULT 50000
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_limite        timestamptz := now() - make_interval(days => p_keep_days);
  v_limite_falha  timestamptz := now() - make_interval(days => p_keep_failed_days);
  v_lo       bigint;
  v_hi       bigint;
  v_mid      bigint;
  v_t        timestamptz;
  v_corte    bigint;
  v_de       bigint;
  v_n        integer;
  v_apagadas integer := 0;
  v_mantidas integer;
BEGIN
  IF p_keep_days < 7 OR p_keep_failed_days < p_keep_days OR p_keep_per_job < 1
     OR p_batch < 1 OR p_max < 1 THEN
    RAISE EXCEPTION 'parametros invalidos: keep_days >= 7, keep_failed_days >= keep_days, keep_per_job/batch/max >= 1';
  END IF;

  SELECT min(d.runid), max(d.runid) INTO v_lo, v_hi FROM cron.job_run_details d;
  IF v_lo IS NULL THEN
    RETURN jsonb_build_object('apagadas', 0, 'motivo', 'historico vazio');
  END IF;

  -- Busca binaria: menor runid cuja primeira rodada a partir dele comecou em v_limite ou depois
  -- (ou sem start_time, que conta como recente). Abaixo dele so ha rodadas antigas.
  v_corte := v_hi + 1;
  WHILE v_lo <= v_hi LOOP
    v_mid := v_lo + (v_hi - v_lo) / 2;
    SELECT d.start_time INTO v_t FROM cron.job_run_details d
     WHERE d.runid >= v_mid ORDER BY d.runid LIMIT 1;
    IF v_t IS NULL OR v_t >= v_limite THEN
      v_corte := least(v_corte, v_mid);
      v_hi := v_mid - 1;
    ELSE
      v_lo := v_mid + 1;
    END IF;
  END LOOP;

  -- As p_keep_per_job rodadas mais recentes de cada job ficam, tenham a idade que tiverem.
  CREATE TEMP TABLE IF NOT EXISTS _cron_keep (runid bigint PRIMARY KEY) ON COMMIT DROP;
  TRUNCATE pg_temp._cron_keep;
  INSERT INTO pg_temp._cron_keep (runid)
  SELECT x.runid FROM (
    SELECT d.runid, row_number() OVER (PARTITION BY d.jobid ORDER BY d.runid DESC) AS rn
    FROM cron.job_run_details d
  ) x WHERE x.rn <= p_keep_per_job;
  GET DIAGNOSTICS v_mantidas = ROW_COUNT;

  SELECT min(d.runid) INTO v_de FROM cron.job_run_details d;
  WHILE v_de < v_corte AND v_apagadas < p_max LOOP
    DELETE FROM cron.job_run_details d
     WHERE d.runid >= v_de
       AND d.runid < least(v_de + p_batch, v_corte)
       AND coalesce(d.start_time, '-infinity'::timestamptz) < v_limite
       AND (d.status = 'succeeded'
            OR coalesce(d.start_time, '-infinity'::timestamptz) < v_limite_falha)
       AND NOT EXISTS (SELECT 1 FROM pg_temp._cron_keep k WHERE k.runid = d.runid);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_apagadas := v_apagadas + v_n;
    v_de := v_de + p_batch;
  END LOOP;

  RETURN jsonb_build_object(
    'apagadas', v_apagadas,
    'corte_runid', v_corte,
    'limite', v_limite,
    'limite_falha', v_limite_falha,
    'protegidas_por_job', v_mantidas,
    'parou_no_teto', v_de < v_corte
  );
END;
$function$;

-- Funcao de manutencao: so o cron (postgres, dono do job) a chama. No Supabase os privilegios
-- padrao dao EXECUTE a PUBLIC, anon, authenticated e service_role; a chave service_role circula nas
-- lanes de teste, entao ela sai tambem.
REVOKE ALL ON FUNCTION public._purge_cron_job_run_details(integer, integer, integer, integer, integer)
  FROM PUBLIC, anon, authenticated, service_role;

-- Toda noite as 04:17 UTC (01:17 em Brasilia), fora das reunioes e do CI diurno. pg_cron 1.6.4:
-- schedule com nome existente atualiza o job, entao reaplicar e idempotente.
SELECT cron.schedule(
  'cron-history-purge-nightly',
  '17 4 * * *',
  $$SELECT public._purge_cron_job_run_details()$$
);
