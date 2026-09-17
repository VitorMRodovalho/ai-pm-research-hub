-- #2341 (correcao): `purpose` -> `description`.
--
-- O guard #1822 reprovou a catraca de "coluna de estado sem dominio declarado", e estava CERTO:
-- `purpose` e um nome que promete enumeracao ("qual proposito, de qual lista"), e o conteudo e
-- frase livre ("digest semanal do membro (ADR-0022 W2)"). Quem le o schema espera um dominio que
-- nunca existiu. A saida nao e inventar um CHECK nem alargar a baseline do guard — e corrigir o
-- NOME para o que a coluna guarda.
--
-- Migration separada de proposito: a 20260917200007 ja foi aplicada, e migration e historia
-- imutavel (`reference-editar-migration-acusa-drift-e-o-drift-e-achado`).

ALTER TABLE public.digest_cron_expectations RENAME COLUMN purpose TO description;

COMMENT ON COLUMN public.digest_cron_expectations.description IS
  '#2341: texto livre que explica para que serve o job. Nao e estado nem enum — se algum dia '
  'precisar de dominio fechado, a coluna certa e outra, com CHECK proprio.';

-- As duas funcoes que leem a coluna acompanham o rename.
CREATE OR REPLACE FUNCTION public.get_digest_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_member_pending integer;
  v_jobs jsonb;
  v_estados jsonb;
  v_health text;
  v_max_days_since integer;
  v_ausentes text[];
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

  -- #2286 fechou o canal, entao ESTA metrica passou a significar "o que o proximo digest vai
  -- mostrar". Antes ela era baixa porque o carimbo mentia.
  SELECT count(*) INTO v_member_pending
  FROM public.notifications
  WHERE delivery_mode = 'digest_weekly'
    AND digest_delivered_at IS NULL;

  -- #2341: LEFT JOIN a partir da EXPECTATIVA, nunca `WHERE jobname IN (...)`. A expectativa e o
  -- denominador; o cron e o que se mede contra ela. Job que falta sobra como linha, com jobid NULL.
  WITH medido AS (
    SELECT x.jobname, x.description, x.expected_schedule, x.max_days_between_runs,
           x.retired_at, x.retired_reason,
           j.jobid, j.schedule AS schedule_real, j.active,
           (SELECT max(d.start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid) AS ultima,
           (SELECT extract(epoch FROM (now() - max(d.start_time))) / 86400
              FROM cron.job_run_details d WHERE d.jobid = j.jobid) AS dias,
           (SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid
             ORDER BY d.start_time DESC LIMIT 1) AS ultimo_status,
           (SELECT count(*) FROM cron.job_run_details d
             WHERE d.jobid = j.jobid AND d.status = 'failed'
               AND d.start_time >= now() - interval '30 days') AS falhas_30d
    FROM public.digest_cron_expectations x
    LEFT JOIN cron.job j ON j.jobname = x.jobname
  ), classificado AS (
    SELECT m.*,
      CASE
        WHEN m.retired_at IS NOT NULL AND m.jobid IS NOT NULL THEN 'ressuscitado'
        WHEN m.retired_at IS NOT NULL                          THEN 'aposentado'
        WHEN m.jobid IS NULL                                   THEN 'ausente'
        WHEN m.active IS NOT TRUE                              THEN 'inativo'
        WHEN m.ultima IS NULL                                  THEN 'nunca_rodou'
        WHEN m.dias > m.max_days_between_runs                  THEN 'silencioso'
        WHEN m.schedule_real <> m.expected_schedule            THEN 'schedule_divergente'
        ELSE 'saudavel'
      END AS estado
    FROM medido m
  )
  SELECT
    jsonb_object_agg(c.jobname, jsonb_build_object(
      'estado', c.estado,
      'description', c.description,
      'jobid', c.jobid,
      'expected_schedule', c.expected_schedule,
      'schedule', c.schedule_real,
      'active', c.active,
      'retired_at', c.retired_at,
      'retired_reason', c.retired_reason,
      'last_run_at', c.ultima,
      'last_status', c.ultimo_status,
      'days_since_last_run', c.dias,
      'failed_runs_last_30d', c.falhas_30d
    )),
    jsonb_object_agg(c.jobname, c.estado),
    -- O pior "dias sem rodar" so entre os jobs VIGENTES que existem: um job ausente nao tem dias,
    -- e por isso ele entra por `v_ausentes`, nao diluido aqui.
    max(CASE WHEN c.retired_at IS NULL AND c.jobid IS NOT NULL
             THEN coalesce(c.dias, 999) END)::integer,
    array_remove(array_agg(CASE WHEN c.estado IN ('ausente','inativo') THEN c.jobname END), NULL)
  INTO v_jobs, v_estados, v_max_days_since, v_ausentes
  FROM classificado c;

  -- Tres estados, e "ausente" NUNCA e verde. Era exatamente o caso que a versao anterior
  -- nao conseguia reprovar.
  v_health := CASE
    WHEN EXISTS (SELECT 1 FROM jsonb_each_text(v_estados) e
                  WHERE e.value IN ('ausente','inativo','silencioso'))          THEN 'red'
    WHEN EXISTS (SELECT 1 FROM jsonb_each_text(v_estados) e
                  WHERE e.value IN ('nunca_rodou','ressuscitado','schedule_divergente')) THEN 'yellow'
    WHEN v_member_pending >= 100                                                THEN 'yellow'
    ELSE 'green'
  END;

  RETURN jsonb_build_object(
    'member_digest_pending', v_member_pending,
    'cron_jobs', coalesce(v_jobs, '{}'::jsonb),
    'job_states', coalesce(v_estados, '{}'::jsonb),
    'missing_jobs', coalesce(v_ausentes, '{}'::text[]),
    'expected_active_jobs', (SELECT count(*) FROM public.digest_cron_expectations WHERE retired_at IS NULL),
    'retired_jobs', (SELECT count(*) FROM public.digest_cron_expectations WHERE retired_at IS NOT NULL),
    'max_days_since_any_job_ran', v_max_days_since,
    'health_signal', v_health,
    'note', '#2341: a expectativa vem de public.digest_cron_expectations, nao de lista no corpo. '
            'Estados: ausente/inativo/silencioso = red; nunca_rodou/ressuscitado/schedule_divergente '
            '= yellow; aposentado nao reprova. member_digest_pending so passou a significar entrega '
            'real depois da #2286.',
    'fetched_at', now()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._audit_digest_cron_coverage()
RETURNS TABLE(jobname text, retired boolean, esta_no_cron boolean,
              schedule_esperado text, schedule_real text, ativo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT x.jobname,
         (x.retired_at IS NOT NULL) AS retired,
         (j.jobid IS NOT NULL)      AS esta_no_cron,
         x.expected_schedule        AS schedule_esperado,
         j.schedule                 AS schedule_real,
         j.active                   AS ativo
  FROM public.digest_cron_expectations x
  LEFT JOIN cron.job j ON j.jobname = x.jobname
  ORDER BY x.jobname;
$$;

NOTIFY pgrst, 'reload schema';
