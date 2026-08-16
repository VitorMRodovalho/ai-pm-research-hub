-- #1801 (e conserto do que o #1572 acabou de introduzir) — o "ciclo ativo" do painel de saúde
-- resolvia por `created_at DESC`, que é a data de ESCRITA da linha, não a do ciclo.
--
-- O backfill do `cycle2-2025` entrou em 2026-07-13, então a linha de um ciclo FECHADO de 2025 virou
-- a mais nova da tabela e este painel passou a descrever esse ciclo inteiro: `application_counts`,
-- `stale_tokens_48h`, `welcome_backlog` e o `health_signal`. Medido em 15/08: a resolução antiga
-- devolve `cycle2-2025` (closed, phase planning); o ciclo aberto é o `cycle4-2026` (evaluating).
--
-- É a causa 1 da #1586(b) reaparecendo em outra função. O precedente do corpo dela é a referência:
-- por STATUS, nunca por `created_at`.
--
-- Dois efeitos que o conserto fecha:
--   1. A recusa por conflito de interesse (ADR-0109) era avaliada contra o ciclo de 2025, então um
--      candidato do ciclo ABERTO não era recusado desta superfície.
--   2. O contador `decided_without_evaluation` do #1572 nasceu apontando para o ciclo errado, e com
--      ele o amarelo: `cycle2-2025` tem 6 aprovadas sem avaliação e nenhuma justificada, o que
--      prenderia o sinal em `yellow` por linhas que já não têm como ganhar justificativa.
--
-- `open_cycles` entra no retorno porque a função precisa devolver UM ciclo, e o #1586(b) já ensinou
-- que um segundo ciclo aberto não pode sumir calado. Aqui ele não é varrido, mas é CONTADO.

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
      'last_run_at', (
        SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid
      ),
      'last_status', (
        SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid
        ORDER BY start_time DESC LIMIT 1
      ),
      'last_5_status', (
        SELECT jsonb_agg(jsonb_build_object('start', start_time, 'status', status, 'msg', return_message) ORDER BY start_time DESC)
        FROM (
          SELECT start_time, status, return_message FROM cron.job_run_details d2
          WHERE d2.jobid = j.jobid ORDER BY start_time DESC LIMIT 5
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
