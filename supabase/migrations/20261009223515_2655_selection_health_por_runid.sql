-- #2655 — get_selection_health le o historico do pg_cron pela PK, sem varrer a tabela.
--
-- O que muda: SO as tres leituras de cron.job_run_details dentro do laco dos 4 crons monitorados.
-- Assinatura, SECURITY DEFINER, search_path, grants, portoes (autenticacao, view_internal_analytics,
-- recusa por conflito de interesse) e o formato do retorno ficam identicos. O corpo de partida e a
-- captura 20260816003424_1801_get_selection_health_ciclo_ativo_por_status.sql, conferida contra o
-- corpo vivo em 09/10/2026 (md5 do corpo normalizado igual dos dois lados).
--
-- Por que: as leituras filtravam por jobid e ordenavam por start_time (ou tiravam max(start_time)).
-- A tabela pertence a supabase_admin, so tem indice na PK (runid) e nao aceita indice nosso, entao
-- cada uma das 3 leituras x 4 crons era uma varredura sequencial inteira: 12 por chamada.
-- Medido em 09/10/2026 (numeros da issue):
--   - heap de ~35 mil paginas; uma chamada completa tocou ~426 mil paginas (12 varreduras preveem
--     ~424 mil) e levou ~4,5 s;
--   - authenticated tem statement_timeout de 8 s; no log do gateway, 13 de 16 cargas de
--     /admin/selection voltaram HTTP 500 por timeout;
--   - cron.job_run_details respondia por 85,7% dos blocos lidos do banco desde o restart.
--
-- Como: runid vem de sequencia e cresce com o tempo (o expurgo noturno do #1742,
-- 20261009205510_1742_expurgo_do_historico_do_cron.sql, se apoia na mesma propriedade). Cada leitura
-- vira `WHERE jobid = X ORDER BY runid DESC LIMIT n`, e o planejador anda a PK de tras para frente
-- (Index Scan Backward using job_run_details_pkey, conferido com EXPLAIN sem ANALYZE) parando ao
-- achar n linhas do job.
--
-- Diferencas de semantica, todas em caso de borda:
--   1. last_run_at: antes era max(start_time), que ignora NULL. Agora e o start_time da rodada de
--      maior runid COM start_time preenchido, entao NULL (rodada ainda 'starting') continua
--      ignorado. So diverge se duas rodadas do mesmo job comecarem fora da ordem do runid.
--   2. last_status: antes `ORDER BY start_time DESC` sem NULLS LAST, e no DESC o Postgres poe NULL
--      PRIMEIRO. Uma rodada com start_time NULL, inclusive uma antiga que travou em 'starting',
--      ganhava de qualquer rodada nova para sempre. Agora vale a rodada mais nova pelo runid: a que
--      esta comecando agora continua aparecendo (e a de maior runid), a travada antiga deixa de
--      mascarar as seguintes.
--   3. last_5_status: o mesmo do item 2 para a lista das 5; a ordem dos itens passa a ser por runid
--      DESC. As chaves de cada item (start, status, msg) nao mudam.
--
-- Custo residual: a varredura para tras so para ao achar n linhas do job. Um job sem nenhuma linha
-- no historico anda a PK inteira (no pior caso o mesmo custo de UMA das varreduras antigas, nao 12).
-- O expurgo do #1742 guarda sempre as 10 mais recentes de cada job, entao job que ja rodou tem linha.
--
-- ROLLBACK: reaplicar o CREATE OR REPLACE FUNCTION da captura anterior,
-- 20260816003424_1801_get_selection_health_ciclo_ativo_por_status.sql.

CREATE OR REPLACE FUNCTION public.get_selection_health()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id uuid;
  v_active_cycle jsonb;
  v_open_cycles integer := 0;
  v_application_counts jsonb;
  v_stale_tokens integer;
  v_welcome_backlog integer;
  v_crons jsonb;
  v_health_signal text;
  v_critical_cron_down boolean := false;
  v_decided_no_eval jsonb;
  v_unjustified_active int := 0;
  v_cron_names text[] := ARRAY[
    'send-notification-emails',
    'retry-pending-ai-analyses',
    'nudge-reschedule-pending-daily',
    'detect-onboarding-overdue-daily'
  ];
  v_cron_name text;
  v_cron_data jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  -- #1801 — ciclo ativo por STATUS. `created_at` só entra como último desempate, e depois de
  -- `open_date`, para o caso de não haver nenhum ciclo aberto.
  SELECT count(*) INTO v_open_cycles FROM public.selection_cycles WHERE status = 'open';

  SELECT jsonb_build_object(
    'id', c.id,
    'cycle_code', c.cycle_code,
    'title', c.title,
    'status', c.status,
    'phase', c.phase,
    'created_at', c.created_at
  )
  INTO v_active_cycle
  FROM public.selection_cycles c
  ORDER BY (c.status = 'open') DESC,
           c.open_date  DESC NULLS LAST,
           c.created_at DESC
  LIMIT 1;

  -- ADR-0109 PR-2 COI recusal: an active candidate in the active cycle is recused from this surface.
  IF v_active_cycle IS NOT NULL AND public.selection_coi_recused(v_caller_id, (v_active_cycle->>'id')::uuid) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  -- Application counts no ciclo ativo
  SELECT jsonb_build_object(
    'total', count(*),
    'submitted', count(*) FILTER (WHERE status='submitted'),
    'screening', count(*) FILTER (WHERE status='screening'),
    'objective_eval', count(*) FILTER (WHERE status='objective_eval'),
    'interview_pending', count(*) FILTER (WHERE status='interview_pending'),
    'interview_scheduled', count(*) FILTER (WHERE status='interview_scheduled'),
    'interview_done', count(*) FILTER (WHERE status='interview_done'),
    'final_eval', count(*) FILTER (WHERE status='final_eval'),
    'approved', count(*) FILTER (WHERE status IN ('approved','converted')),
    'rejected', count(*) FILTER (WHERE status IN ('rejected','objective_cutoff')),
    'cancelled', count(*) FILTER (WHERE status IN ('cancelled','withdrawn')),
    'waitlist', count(*) FILTER (WHERE status='waitlist'),
    'created_last_7d', count(*) FILTER (WHERE created_at >= now() - interval '7 days')
  )
  INTO v_application_counts
  FROM public.selection_applications
  WHERE cycle_id = (v_active_cycle->>'id')::uuid;

  -- #1572 — decidido sem NENHUMA avaliação submetida, separado entre justificado (aceite antecipado
  -- carimbado) e não justificado. `rejected` é CONTADO mas não é bloqueado na escrita: o portão do
  -- #1572 cobre aprovação, e estender para rejeição é decisão do PM.
  SELECT jsonb_build_object(
    'cycle', jsonb_build_object(
      'approved_without_evaluation',            count(*) FILTER (WHERE eh_ciclo AND eh_aprovado AND n_evals = 0),
      'approved_without_evaluation_justified',  count(*) FILTER (WHERE eh_ciclo AND eh_aprovado AND n_evals = 0 AND early_acceptance_at IS NOT NULL),
      'rejected_without_evaluation',            count(*) FILTER (WHERE eh_ciclo AND NOT eh_aprovado AND n_evals = 0)
    ),
    'all_cycles', jsonb_build_object(
      'approved_without_evaluation',            count(*) FILTER (WHERE eh_aprovado AND n_evals = 0),
      'approved_without_evaluation_justified',  count(*) FILTER (WHERE eh_aprovado AND n_evals = 0 AND early_acceptance_at IS NOT NULL),
      'rejected_without_evaluation',            count(*) FILTER (WHERE NOT eh_aprovado AND n_evals = 0)
    )
  )
  INTO v_decided_no_eval
  FROM (
    SELECT a.early_acceptance_at,
           (a.cycle_id = (v_active_cycle->>'id')::uuid) AS eh_ciclo,
           (a.status IN ('approved','converted'))       AS eh_aprovado,
           (SELECT count(*) FROM public.selection_evaluations e WHERE e.application_id = a.id) AS n_evals
    FROM public.selection_applications a
    WHERE a.status IN ('approved','converted','rejected')
  ) z;

  v_unjustified_active := coalesce((v_decided_no_eval->'cycle'->>'approved_without_evaluation')::int, 0)
                        - coalesce((v_decided_no_eval->'cycle'->>'approved_without_evaluation_justified')::int, 0);

  -- Stale tokens: onboarding_tokens não consumidos há >48h
  SELECT count(*) INTO v_stale_tokens
  FROM public.onboarding_tokens t
  JOIN public.selection_applications a ON a.id = t.source_id
  WHERE t.source_type = 'pmi_application'
    AND COALESCE(t.access_count, 0) = 0
    AND t.issued_at < now() - interval '48 hours'
    AND a.cycle_id = (v_active_cycle->>'id')::uuid;

  -- Welcome backlog: approved sem token consumed (proxy para welcome não dispatched)
  SELECT count(*) INTO v_welcome_backlog
  FROM public.selection_applications a
  WHERE a.cycle_id = (v_active_cycle->>'id')::uuid
    AND a.status IN ('approved','converted')
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_tokens t
      WHERE t.source_id = a.id AND t.source_type = 'pmi_application' AND COALESCE(t.access_count, 0) > 0
    );

  -- Cron health para cada cron relevante
  v_crons := '[]'::jsonb;
  FOREACH v_cron_name IN ARRAY v_cron_names LOOP
    SELECT jsonb_build_object(
      'jobname', v_cron_name,
      'active', j.active,
      'schedule', j.schedule,
      -- #2655 — as tres leituras andam pela PK (runid) de tras para frente e param no LIMIT.
      -- Sem indice em jobid nem em start_time, ordenar por start_time varria a tabela inteira.
      'last_run_at', (
        SELECT d.start_time FROM cron.job_run_details d
        WHERE d.jobid = j.jobid AND d.start_time IS NOT NULL
        ORDER BY d.runid DESC LIMIT 1
      ),
      'last_status', (
        SELECT d.status FROM cron.job_run_details d
        WHERE d.jobid = j.jobid
        ORDER BY d.runid DESC LIMIT 1
      ),
      'last_5_status', (
        SELECT jsonb_agg(jsonb_build_object('start', t.start_time, 'status', t.status, 'msg', t.return_message) ORDER BY t.runid DESC)
        FROM (
          SELECT d2.runid, d2.start_time, d2.status, d2.return_message FROM cron.job_run_details d2
          WHERE d2.jobid = j.jobid
          ORDER BY d2.runid DESC LIMIT 5
        ) t
      )
    )
    INTO v_cron_data
    FROM cron.job j
    WHERE j.jobname = v_cron_name;

    IF v_cron_data IS NULL THEN
      v_cron_data := jsonb_build_object(
        'jobname', v_cron_name,
        'active', false,
        'error', 'cron job not registered'
      );
      -- Critical: 4 monitored crons, all should exist
      v_critical_cron_down := true;
    END IF;

    v_crons := v_crons || jsonb_build_array(v_cron_data);
  END LOOP;

  -- Health signal
  -- #1572 — aprovação sem lastro E sem justificativa no ciclo ATIVO puxa para amarelo. Com o #1801
  -- "ativo" passou a significar o ciclo ABERTO de verdade, então o histórico de 2025 deixa de
  -- prender o sinal.
  v_health_signal := CASE
    WHEN v_critical_cron_down OR v_stale_tokens >= 5 THEN 'red'
    WHEN v_stale_tokens > 0 OR v_welcome_backlog > 0 OR v_unjustified_active > 0 THEN 'yellow'
    ELSE 'green'
  END;

  RETURN jsonb_build_object(
    'active_cycle', COALESCE(v_active_cycle, jsonb_build_object('error', 'no cycle found')),
    'open_cycles', v_open_cycles,
    'application_counts', v_application_counts,
    'decided_without_evaluation', v_decided_no_eval,
    'stale_tokens_48h', v_stale_tokens,
    'welcome_backlog', v_welcome_backlog,
    'crons', v_crons,
    'health_signal', v_health_signal,
    'fetched_at', now()
  );
END;
$function$;

-- Pos-condicao: CREATE OR REPLACE nao mexe em grants, mas confere que a funcao segue SECURITY
-- DEFINER, com o mesmo search_path, executavel por authenticated e nao por anon.
DO $$
DECLARE
  v_oid oid := 'public.get_selection_health()'::regprocedure;
  v_secdef boolean;
  v_config text[];
BEGIN
  SELECT p.prosecdef, p.proconfig INTO v_secdef, v_config FROM pg_proc p WHERE p.oid = v_oid;
  IF NOT v_secdef THEN
    RAISE EXCEPTION '#2655: get_selection_health perdeu SECURITY DEFINER';
  END IF;
  IF v_config IS DISTINCT FROM ARRAY['search_path=public, pg_temp'] THEN
    RAISE EXCEPTION '#2655: search_path mudou: %', v_config;
  END IF;
  IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION '#2655: authenticated perdeu EXECUTE';
  END IF;
  IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION '#2655: anon ganhou EXECUTE';
  END IF;
END
$$;
