-- ============================================================================
-- #1819 — a retencao do #1812 entra no painel de saude de LGPD
-- ----------------------------------------------------------------------------
-- MEDIDO EM 16/08/2026: get_lgpd_cron_health reportava quatro jobs e nao via nada do que o
-- #1812 entregou -- nem a varredura `data-retention-sweep-daily` (ativa, 0 execucoes, primeira
-- corrida amanha as 04:25 UTC), nem a cobertura das politicas (3 cobertas, 3 descobertas).
--
-- QUATRO CUIDADOS, todos deliberados:
--
--   1. A varredura e DIARIA. O limiar de 35 dias que serve aos jobs mensais esconderia semanas
--      de silencio de um job que apaga linha todo dia. Ela ganha driver PROPRIO: ativa e
--      silenciosa ha mais de 2 dias = vermelho.
--
--   2. NUNCA-RODOU nao e vermelho. A varredura nasce com zero execucoes; sem a guarda
--      `v_sweep_days_since IS NOT NULL` o painel ficaria vermelho no minuto em que isto subisse.
--      Mesmo tratamento que o 999 ja recebe nos mensais.
--
--   3. A cobertura e INFORMACIONAL, nunca driver de saude. A base declarada tem descobertas por
--      desenho (o archive sem destino do #1814 e o portao legal do SPEC #905). Deixa-las pintarem
--      o painel de amarelo permanente treinaria todo mundo a ignorar o painel -- a mesma
--      disciplina de "nao gritar lobo" que o relatorio de consistencia da selecao ja aplica ao
--      dispatch gap. Quem cobra regressao e o ratchet no CI, vermelho na QUARTA descoberta.
--
--   4. `max_days_since_any_job_ran` NAO muda de significado: segue sendo sobre os mensais.
--      Enfiar um job diario naquele numero daria um segundo sentido ao mesmo campo.
--
-- A funcao tem `SET search_path TO ''`: toda referencia nova e qualificada.
-- O corpo nao foi transcrito -- saiu da captura de 20260805000280 (drift 0) e recebeu seis
-- substituicoes contadas, uma ocorrencia cada.
--
-- ROLLBACK: recriar get_lgpd_cron_health a partir da captura de 20260805000280.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_lgpd_cron_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_inactive_pending integer;
  v_jobs jsonb;
  v_health text;
  v_max_days_since integer;
  v_premember_pending integer;
  v_premember_active boolean;
  v_premember_registered boolean;
  v_premember_days_since numeric;
  v_sweep_registered boolean;
  v_sweep_active boolean;
  v_sweep_days_since numeric;
  v_retention jsonb;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  SELECT count(*) INTO v_inactive_pending
  FROM public.members
  WHERE member_status IN ('alumni','observer','inactive')
    AND updated_at < now() - interval '5 years'
    AND (name IS NULL OR name NOT ILIKE 'Anonymous%');

  -- #905 pre-member pending (eligible NOW under a conservative 5y default window; 0 until 2031)
  SELECT count(*) INTO v_premember_pending
  FROM public.list_premember_anonymization_candidates(5);

  SELECT coalesce(bool_or(active), false), count(*) > 0
  INTO v_premember_active, v_premember_registered
  FROM cron.job WHERE jobname = 'lgpd-anonymize-premember-monthly';

  SELECT extract(epoch FROM (now() - max(d.start_time))) / 86400
  INTO v_premember_days_since
  FROM cron.job j
  LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
  WHERE j.jobname = 'lgpd-anonymize-premember-monthly';

  -- #1819: a varredura de retencao do #1812. E DIARIA, entao ganha driver de saude PROPRIO --
  -- o limiar de 35 dias dos mensais esconderia semanas de silencio de um job que apaga todo dia.
  SELECT coalesce(bool_or(j.active), false), count(*) > 0
  INTO v_sweep_active, v_sweep_registered
  FROM cron.job j WHERE j.jobname = 'data-retention-sweep-daily';

  SELECT extract(epoch FROM (now() - max(d.start_time))) / 86400
  INTO v_sweep_days_since
  FROM cron.job j
  LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
  WHERE j.jobname = 'data-retention-sweep-daily';

  -- Cobertura das politicas declaradas: INFORMACIONAL, nunca driver de saude. A base declarada
  -- tem descobertas POR DESENHO (o archive sem destino do #1814 e o portao legal do #905); deixa-las
  -- pintarem o painel de amarelo permanente treinaria todo mundo a ignorar o painel. Quem cobra
  -- regressao e o ratchet no CI, que fica vermelho na QUARTA descoberta.
  SELECT jsonb_build_object(
    'policies_total',     count(*),
    'policies_covered',   count(*) FILTER (WHERE c.coberta),
    'policies_uncovered', count(*) FILTER (WHERE NOT c.coberta),
    'uncovered', coalesce(
      jsonb_agg(jsonb_build_object('policy', c.politica, 'reason', c.motivo)) FILTER (WHERE NOT c.coberta),
      '[]'::jsonb),
    'sweep', jsonb_build_object(
      'registered',          v_sweep_registered,
      'active',              v_sweep_active,
      'days_since_last_run', v_sweep_days_since,
      'never_ran',           v_sweep_days_since IS NULL
    ),
    'last_sweep', (
      SELECT jsonb_build_object('at', l.created_at, 'affected_total', l.changes->'affected_total')
      FROM public.admin_audit_log l
      WHERE l.action = 'data_retention.sweep'
      ORDER BY l.created_at DESC LIMIT 1
    ),
    'note', 'Cobertura e informacional: as descobertas declaradas sao rastreadas em issue e travadas '
            || 'por ratchet no CI (_audit_retention_policy_coverage). O driver de saude daqui e a '
            || 'varredura diaria estar ATIVA e silenciosa ha mais de 2 dias.'
  ) INTO v_retention
  FROM public._audit_retention_policy_coverage() c;

  SELECT jsonb_object_agg(jobname, snapshot)
  INTO v_jobs
  FROM (
    SELECT
      j.jobname,
      jsonb_build_object(
        'jobid', j.jobid,
        'schedule', j.schedule,
        'active', j.active,
        'last_run_at', (SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid),
        'last_status', (SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1),
        'last_message', (SELECT return_message FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1),
        'days_since_last_run', (
          SELECT extract(epoch FROM (now() - max(start_time))) / 86400
          FROM cron.job_run_details d WHERE d.jobid = j.jobid
        ),
        'failed_runs_last_90d', (
          SELECT count(*) FROM cron.job_run_details d
          WHERE d.jobid = j.jobid AND d.status = 'failed' AND d.start_time >= now() - interval '90 days'
        )
      ) AS snapshot
    FROM cron.job j
    WHERE j.jobname IN ('lgpd-anonymize-inactive-monthly', 'v4-anonymize-by-kind-monthly', 'log-retention-monthly', 'lgpd-anonymize-premember-monthly', 'data-retention-sweep-daily')
  ) sub;

  -- Worst days-since across the original 3 retention jobs (NULL counted as 999 — never ran).
  -- The premember job is intentionally excluded from this red/green driver while dormant.
  SELECT max(coalesce(days, 999))::integer INTO v_max_days_since
  FROM (
    SELECT extract(epoch FROM (now() - max(d.start_time))) / 86400 AS days
    FROM cron.job j
    LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
    WHERE j.jobname IN ('lgpd-anonymize-inactive-monthly', 'v4-anonymize-by-kind-monthly', 'log-retention-monthly')
    GROUP BY j.jobid
  ) t;

  -- Health: red if any original job is overdue with pending work, OR the premember job is ACTIVE
  -- (i.e. legal has gone live) yet overdue with pending pre-member work. Dormant premember -> neutral.
  v_health := CASE
    -- #1819: job DIARIO ativo e silencioso ha mais de 2 dias e incidente -- ele apaga linha todo dia.
    -- `v_sweep_days_since IS NOT NULL` e o que impede o vermelho de nunca-rodou: a varredura nasce
    -- com zero execucoes, e sem esta guarda o painel ficaria vermelho no minuto em que subisse.
    WHEN v_sweep_active AND v_sweep_days_since IS NOT NULL AND v_sweep_days_since > 2 THEN 'red'
    WHEN v_premember_active AND v_premember_pending > 0 AND coalesce(v_premember_days_since, 999) > 35 THEN 'red'
    WHEN v_max_days_since <= 35 THEN 'green'
    WHEN v_max_days_since = 999 AND v_inactive_pending = 0 THEN 'yellow'
    WHEN v_inactive_pending > 0 AND v_max_days_since > 35 THEN 'red'
    ELSE 'yellow'
  END;

  RETURN jsonb_build_object(
    'pending_anonymization_inactive_5y', v_inactive_pending,
    'pending_premember_anonymization', v_premember_pending,
    'premember_anonymization', jsonb_build_object(
      'registered', v_premember_registered,
      'active', v_premember_active,
      'pending', v_premember_pending,
      'note', 'Dormant until legal-counsel ratifies the pre-member retention window (#905). Go-live = set windows + activate cron.'
    ),
    'data_retention', v_retention,
    'cron_jobs', coalesce(v_jobs, '{}'::jsonb),
    'max_days_since_any_job_ran', v_max_days_since,
    'health_signal', v_health,
    'note', 'Monthly crons fire on 1st of month at 03:30/03:45/04:00/04:15 UTC; the retention sweep is DAILY at 04:25 UTC and has its own 2-day threshold. days_since=999 means never ran (newly registered). max_days_since_any_job_ran stays about the MONTHLY jobs only.',
    'fetched_at', now()
  );
END;
$function$;

-- CREATE OR REPLACE de funcao EXISTENTE preserva as ACLs; a escada de grants de
-- 20260514410000 segue valendo e nao e reconcedida aqui.

NOTIFY pgrst, 'reload schema';
