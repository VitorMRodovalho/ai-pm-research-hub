-- ============================================================================
-- #1812 — data_retention_policy ganha executor, e a cobertura ganha ratchet
-- ----------------------------------------------------------------------------
-- MEDIDO EM 16/08/2026, no banco:
--   * 6 politicas ativas na tabela;
--   * ZERO funcoes em public referenciam data_retention_policy;
--   * admin_run_retention_cleanup, a unica que a lia, foi aposentada em 16/08 (#1809)
--     por citar tres colunas inexistentes. Nunca teve chamador nem cron: nunca executou.
--
-- As seis alcancam 0 linhas HOJE, mas so porque a plataforma tem 155 dias. A data em que
-- cada uma passa a morder (linha elegivel mais antiga + horizonte):
--   notifications (lidas)       180d  -> 2026-09-09   <- a proxima
--   visitor_leads (nao convert) 90d   -> 2026-10-03
--   data_anomaly_log            365d  -> 2027-05-13
--   board_lifecycle_events      730d  -> 2028-03-13   (archive, sem destino: #1814)
--   attendance                  1095d -> 2029-03-05   (archive, sem destino: #1814)
--   selection_applications      1095d -> 0 candidatos pelo proprio anchor (5a e 3a)
--
-- DESENHO — a tabela vira REGISTRO, nao um segundo executor:
--
--   1. `executor` nomeia o JOB que executa a linha. Uma politica sem job nomeado e uma
--      declaracao de controle que ninguem exerce, e o ratchet passa a cobrar isso.
--
--   2. A varredura generica (_data_retention_sweep) executa APENAS as linhas cujo executor
--      e o job dela. O predicado de cada ramo sai da DESCRICAO da propria linha, sem
--      qualificador inventado -- foi inventando qualificador que a funcao aposentada
--      derivou ("status = 'resolved'" sobre uma tabela que nao tem status).
--
--   3. selection_applications NAO e executada aqui. Ela ja tem caminho proprio, revisado:
--      anonymize_premember_applications, cron lgpd-anonymize-premember-monthly, DORMANTE
--      DE PROPOSITO (SPEC #905, portao de parecer legal R1-R5, prazo maximo de ativacao
--      sugerido 30/09/2026). Um executor generico que rodasse essa linha passaria por cima
--      de um portao juridico. A linha aponta para o job dedicado e o ratchet a mostra
--      descoberta enquanto o job estiver dormante -- que e a verdade.
--
--   4. retention_days dessa linha vai de 1095 (3 anos) para 1825 (5 anos): 1095 nunca foi
--      honrado por nada, e 5 anos e o argumento que o job dormente REALMENTE carrega
--      (p_years := 5). O ratchet passa a exigir que o numero declarado seja igual ao
--      argumento do job. Quando o parecer legal ratificar (recomendacao: 2 anos rejeitado /
--      1 ano desistente), os dois se movem juntos ou o CI fica vermelho.
--
-- O QUE ESTA MIGRATION NAO FAZ: implementar `archive`. Nao existe destino de arquivamento
-- na plataforma (nenhuma tabela *_archiv* em public). As duas linhas seguem ATIVAS e
-- descobertas, nomeadas na base do ratchet e na issue #1814 -- lacuna declarada, nao
-- invisivel. A funcao aposentada tratava archive como `v_affected := 0`, que e a forma
-- exata de parecer controle sem exercer nenhum.
--
-- ROLLBACK:
--   SELECT cron.unschedule('data-retention-sweep-daily');
--   DROP FUNCTION public._data_retention_sweep_cron();
--   DROP FUNCTION public._data_retention_sweep(boolean);
--   DROP FUNCTION public._audit_retention_policy_coverage();
--   ALTER TABLE public.data_retention_policy DROP COLUMN executor;
--   UPDATE public.data_retention_policy SET retention_days = 1095
--    WHERE table_name = 'selection_applications' AND cleanup_type = 'anonymize';
--   (nenhum backfill destrutivo: a varredura nasce apagando 0 linhas em todas as tabelas.)
-- ============================================================================

-- ── 1. o registro ───────────────────────────────────────────────────────────
ALTER TABLE public.data_retention_policy
  ADD COLUMN IF NOT EXISTS executor text;

COMMENT ON COLUMN public.data_retention_policy.executor IS
  'Nome do job de cron que executa esta politica. NULL = politica declarada sem executor, '
  'que o ratchet _audit_retention_policy_coverage() reporta como descoberta. A varredura '
  'generica _data_retention_sweep so executa linhas cujo executor e data-retention-sweep-daily; '
  'as demais apontam para o caminho dedicado que ja existe (#1812).';

-- executor de cada linha, resolvido por (tabela, tipo) -- nunca por id gerado
UPDATE public.data_retention_policy SET executor = 'data-retention-sweep-daily'
 WHERE cleanup_type = 'delete' AND table_name IN ('notifications', 'data_anomaly_log', 'visitor_leads');

UPDATE public.data_retention_policy SET executor = 'lgpd-anonymize-premember-monthly',
       retention_days = 1825,
       description = 'Candidaturas de pre-membro em estado terminal (manter agregado pseudonimizado). '
                     || 'Executada pelo caminho dedicado do SPEC #905, dormante ate o parecer legal R1-R5.'
 WHERE cleanup_type = 'anonymize' AND table_name = 'selection_applications';

-- attendance e board_lifecycle_events ficam com executor NULL DE PROPOSITO (#1814):
-- declarar um job que nao existe seria a mesma mentira em outra coluna.

-- ── 2. a varredura ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._data_retention_sweep(p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_job_name  constant text := 'data-retention-sweep-daily';
  v_policy    record;
  v_cutoff    timestamptz;
  v_affected  int;
  v_handled   boolean;
  v_reason    text;
  v_results   jsonb := '[]'::jsonb;
  v_total     int := 0;
  v_uncovered int := 0;
BEGIN
  -- Percorre TODAS as politicas ativas, inclusive as que nao sao desta varredura. Uma saida
  -- que so lista o que foi executado nao distingue "nada a apagar" de "ninguem executa" --
  -- que era exatamente o estado anterior desta tabela.
  FOR v_policy IN
    SELECT * FROM public.data_retention_policy WHERE is_active = true ORDER BY table_name
  LOOP
    v_cutoff   := now() - (v_policy.retention_days || ' days')::interval;
    v_affected := 0;
    v_handled  := false;
    v_reason   := NULL;

    IF v_policy.executor IS NULL THEN
      v_reason := 'politica ativa sem executor declarado';
    ELSIF v_policy.executor IS DISTINCT FROM v_job_name THEN
      v_reason := 'executada pelo caminho dedicado ' || v_policy.executor;

    -- ── ramos desta varredura. O qualificador de cada um vem da DESCRICAO da linha. ──
    ELSIF v_policy.cleanup_type = 'delete' AND v_policy.table_name = 'notifications' THEN
      -- descricao: "Notificacoes lidas com mais de 6 meses" -> o qualificador declarado e "lidas".
      -- is_read e read_at sao perfeitamente consistentes (0 divergencias em 6.671 linhas, 16/08);
      -- is_read e o flag que a aplicacao escreve. A funcao aposentada citava `read`, que nao existe.
      IF p_dry_run THEN
        SELECT count(*) INTO v_affected FROM public.notifications
         WHERE is_read = true AND created_at < v_cutoff;
      ELSE
        DELETE FROM public.notifications WHERE is_read = true AND created_at < v_cutoff;
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;
      v_handled := true;

    ELSIF v_policy.cleanup_type = 'delete' AND v_policy.table_name = 'data_anomaly_log' THEN
      -- descricao: "Logs de anomalia com mais de 1 ano" -> SEM qualificador de resolucao, e
      -- nenhum e inventado aqui. A funcao aposentada exigia status = 'resolved' sobre uma tabela
      -- que nao tem status; e as 165 linhas vivas tem fixed_at e auto_fixed ambos zerados, entao
      -- qualquer qualificador de resolucao apagaria nada e pareceria politica cumprida.
      IF p_dry_run THEN
        SELECT count(*) INTO v_affected FROM public.data_anomaly_log WHERE detected_at < v_cutoff;
      ELSE
        DELETE FROM public.data_anomaly_log WHERE detected_at < v_cutoff;
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;
      v_handled := true;

    ELSIF v_policy.cleanup_type = 'delete' AND v_policy.table_name = 'visitor_leads' THEN
      -- descricao: "unconverted visitor leads auto-deleted after 90 days" -> o qualificador
      -- declarado e "unconverted", isto e, sem promocao a candidatura (promoted_at IS NULL);
      -- lead dispensado continua sendo lead nao convertido. Esta politica NUNCA teve ramo.
      IF p_dry_run THEN
        SELECT count(*) INTO v_affected FROM public.visitor_leads
         WHERE promoted_at IS NULL AND created_at < v_cutoff;
      ELSE
        DELETE FROM public.visitor_leads WHERE promoted_at IS NULL AND created_at < v_cutoff;
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;
      v_handled := true;

    ELSE
      v_reason := 'sem ramo implementado nesta varredura para ' || v_policy.cleanup_type;
    END IF;

    v_total := v_total + v_affected;
    IF NOT v_handled AND v_policy.executor IS DISTINCT FROM 'lgpd-anonymize-premember-monthly' THEN
      v_uncovered := v_uncovered + 1;
    END IF;

    v_results := v_results || jsonb_build_object(
      'table',    v_policy.table_name,
      'type',     v_policy.cleanup_type,
      'days',     v_policy.retention_days,
      'cutoff',   v_cutoff,
      'executor', v_policy.executor,
      'handled',  v_handled,
      'affected', CASE WHEN v_handled THEN v_affected ELSE NULL END,
      'reason',   v_reason
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success',           true,
    'dry_run',           p_dry_run,
    'policies',          v_results,
    'affected_total',    v_total,
    'uncovered_policies', v_uncovered,
    'executed_at',       now()
  );
END;
$function$;

COMMENT ON FUNCTION public._data_retention_sweep(boolean) IS
  'Executor generico do #1812 para data_retention_policy. Executa apenas as linhas cujo executor '
  'e data-retention-sweep-daily; as demais aparecem na saida com handled=false e o motivo, para que '
  '"nada a apagar" nunca se confunda com "ninguem executa" -- a confusao que fez esta tabela declarar '
  '6 politicas por 155 dias sem executor nenhum. O predicado de cada ramo sai da DESCRICAO da linha, '
  'sem qualificador inventado. p_dry_run = true por padrao: a chamada nua conta, nao apaga.';

-- ── 3. o cron ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._data_retention_sweep_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_report jsonb;
BEGIN
  v_report := public._data_retention_sweep(p_dry_run := false);

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'data_retention.sweep', 'system', NULL,
    jsonb_build_object(
      'affected_total',     v_report->'affected_total',
      'uncovered_policies', v_report->'uncovered_policies'
    ),
    v_report
  );

  RETURN v_report;
END;
$function$;

COMMENT ON FUNCTION public._data_retention_sweep_cron() IS
  'Wrapper diario do #1812: roda _data_retention_sweep com p_dry_run := false e grava a corrida '
  'inteira em admin_audit_log (action data_retention.sweep), inclusive as politicas que esta '
  'varredura nao executa. A linha de auditoria e o que torna a retencao verificavel depois do fato.';

-- ── 4. o ratchet de cobertura ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._audit_retention_policy_coverage()
RETURNS TABLE(
  politica text, tabela text, tipo text, dias int, executor text,
  job_registrado boolean, job_ativo boolean, ramo_implementado boolean,
  horizonte_bate boolean, coberta boolean, motivo text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH sweep AS (
    SELECT p.prosrc
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = '_data_retention_sweep'
  ),
  pol AS (
    SELECT r.table_name, r.cleanup_type, r.retention_days, r.executor,
           j.jobid IS NOT NULL AS job_registrado,
           COALESCE(j.active, false) AS job_ativo,
           j.command AS job_command
    FROM public.data_retention_policy r
    LEFT JOIN cron.job j ON j.jobname = r.executor
    WHERE r.is_active = true
  ),
  aval AS (
    SELECT p.*,
           -- Ramo implementado deriva do CATALOGO, nao de lista de nomes: procura a propria
           -- condicao de ramo no corpo vivo da varredura. Casar so o nome da tabela daria falso
           -- positivo com qualquer mencao em comentario.
           CASE
             WHEN p.executor IS NULL THEN false
             WHEN p.executor <> 'data-retention-sweep-daily' THEN true
             ELSE EXISTS (
               SELECT 1 FROM sweep s
               WHERE s.prosrc ~ ('v_policy\.table_name = ''' || p.table_name || '''')
             )
           END AS ramo_implementado,
           -- O numero declarado tem de ser o numero que o executor dedicado REALMENTE carrega.
           -- Sem isto a tabela volta a declarar um horizonte que nada honra (era 1095 contra os
           -- 1825 do job dormente). Vale so para caminho dedicado com p_years no comando.
           CASE
             WHEN p.executor IS NULL OR p.executor = 'data-retention-sweep-daily' THEN true
             WHEN p.job_command IS NULL THEN false
             WHEN p.job_command !~ 'p_years\s*:=\s*[0-9]+' THEN true
             ELSE p.retention_days
                  = (substring(p.job_command from 'p_years\s*:=\s*([0-9]+)'))::int * 365
           END AS horizonte_bate
    FROM pol p
  )
  SELECT a.table_name || '/' || a.cleanup_type,
         a.table_name, a.cleanup_type, a.retention_days, a.executor,
         a.job_registrado, a.job_ativo, a.ramo_implementado, a.horizonte_bate,
         (a.job_registrado AND a.job_ativo AND a.ramo_implementado AND a.horizonte_bate),
         nullif(concat_ws('; ',
           CASE WHEN a.executor IS NULL          THEN 'sem executor declarado' END,
           CASE WHEN a.executor IS NOT NULL AND NOT a.job_registrado THEN 'job ' || a.executor || ' nao registrado em cron.job' END,
           CASE WHEN a.job_registrado AND NOT a.job_ativo THEN 'job ' || a.executor || ' registrado porem INATIVO' END,
           CASE WHEN NOT a.ramo_implementado AND a.executor IS NOT NULL THEN 'varredura sem ramo para esta tabela' END,
           CASE WHEN NOT a.horizonte_bate     THEN 'retention_days difere do argumento do job' END
         ), '')
  FROM aval a
  ORDER BY (a.job_registrado AND a.job_ativo AND a.ramo_implementado AND a.horizonte_bate), a.table_name;
$function$;

COMMENT ON FUNCTION public._audit_retention_policy_coverage() IS
  'Ratchet do #1812. Devolve TODAS as politicas ativas -- nao so as descobertas -- com coberta e o '
  'motivo, para que lista vazia seja distinguivel de guard cego. Uma politica so conta como coberta '
  'quando o job nomeado existe, esta ATIVO, tem ramo implementado (derivado do corpo vivo da varredura, '
  'nao de lista de nomes) e o horizonte declarado bate com o argumento do job. Base declarada em '
  '16/08/2026: 3 descobertas -- attendance/archive e board_lifecycle_events/archive, sem destino de '
  'arquivamento na plataforma (#1814), e selection_applications/anonymize, cujo job esta dormante por '
  'portao de parecer legal (SPEC #905 R1-R5). Uma quarta derruba o CI.';

-- ── 5. grants: CREATE FUNCTION concede EXECUTE a PUBLIC ─────────────────────
-- A varredura APAGA linhas; o ratchet le pg_proc e cron.job. Nenhuma das tres tem chamador
-- no app: o consumidor e o cron (service_role).
REVOKE ALL ON FUNCTION public._data_retention_sweep(boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._data_retention_sweep(boolean) TO service_role;

REVOKE ALL ON FUNCTION public._data_retention_sweep_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._data_retention_sweep_cron() TO service_role;

REVOKE ALL ON FUNCTION public._audit_retention_policy_coverage() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_retention_policy_coverage() TO service_role;

-- ── 6. agenda ───────────────────────────────────────────────────────────────
-- 04:25 UTC diario: depois de membership-drive-reconcile (04:00) e antes do bloco de 05:00.
-- cron.schedule faz UPSERT por nome (re-execucao idempotente).
SELECT cron.schedule(
  'data-retention-sweep-daily',
  '25 4 * * *',
  $cron$SELECT public._data_retention_sweep_cron()$cron$
);

NOTIFY pgrst, 'reload schema';
