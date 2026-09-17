-- #2341: get_digest_health deixa de farejar nome e passa a comparar ESPERADO x ENCONTRADO.
--
-- O defeito, medido em 17/09/2026: a funcao procurava 3 jobs por nome num `WHERE jobname IN
-- (...)`, e `weekly-card-digest-saturday` nao existe mais (removido em maio, p89_cron_audit_fixes,
-- porque duplicava o digest do membro). O `IN` nao devolve a linha que falta, e
-- `max(coalesce(days,999))` so enxerga os jobs ENCONTRADOS — logo o 999 ("nunca rodou") era
-- alcancavel apenas por job que EXISTE. Resultado: job ausente era indistinguivel de job
-- saudavel, e a remocao do digest do membro passaria em VERDE.
--
-- Por que so agora: a funcao pinta verde com `member_digest_pending < 100`, e ate a #2286 essa
-- metrica era baixa PORQUE o carimbo mentia (tudo era carimbado como entregue, nada ficava
-- pendente). Instrumentar antes de consertar o canal daria um verde sem significado.
--
-- O desenho: a expectativa vira DADO, com aposentadoria explicita. Assim "ausente" e "aposentado"
-- param de ser o mesmo silencio, e um job que RESSUSCITA tambem tem sinal.

CREATE TABLE IF NOT EXISTS public.digest_cron_expectations (
  jobname               text PRIMARY KEY,
  purpose               text NOT NULL,
  expected_schedule     text NOT NULL,
  max_days_between_runs integer NOT NULL CHECK (max_days_between_runs > 0),
  retired_at            timestamptz,
  retired_reason        text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  -- Aposentar sem dizer por que devolve o problema que esta tabela existe para resolver:
  -- um silencio sem motivo registrado.
  CONSTRAINT digest_cron_expectations_retired_needs_reason
    CHECK (retired_at IS NULL OR retired_reason IS NOT NULL)
);

ALTER TABLE public.digest_cron_expectations ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.digest_cron_expectations IS
  '#2341: quais cron jobs a familia de digest DEVE ter. get_digest_health compara esta lista com '
  'cron.job, entao um job removido aparece como `ausente` em vez de desaparecer do denominador. '
  'Aposentadoria e DADO (retired_at + retired_reason), nao prosa em comentario: um job aposentado '
  'nao reprova, mas se ele voltar o estado vira `ressuscitado`. Sem RLS-policy de propósito — a '
  'leitura acontece pela RPC SECURITY DEFINER, que exige view_internal_analytics.';

INSERT INTO public.digest_cron_expectations
  (jobname, purpose, expected_schedule, max_days_between_runs, retired_at, retired_reason)
VALUES
  ('send-weekly-member-digest', 'digest semanal do membro (ADR-0022 W2)', '0 12 * * 6', 8, NULL, NULL),
  ('send-weekly-leader-digest', 'digest semanal do lider (ADR-0022 W3) — roda SEGUNDA, nao sabado', '0 12 * * 1', 8, NULL, NULL),
  ('weekly-card-digest-saturday', 'digest de cards do issue #98', '0 12 * * 6',  8,
   '2026-05-01 00:00:00+00', 'aposentado em maio/2026 (p89_cron_audit_fixes): duplicava o digest do membro')
ON CONFLICT (jobname) DO NOTHING;

-- A funcao. Atributos preservados (medidos antes: STABLE, SECURITY DEFINER, search_path='').
-- CREATE OR REPLACE preserva os GRANTs (postgres, authenticated, service_role).
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
    SELECT x.jobname, x.purpose, x.expected_schedule, x.max_days_between_runs,
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
      'purpose', c.purpose,
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

-- #2341: `get_digest_health` e self-gated por `auth.uid()`, entao service_role NAO a exerce
-- (classe do `reference-rpc-com-auth-uid-devolve-nao-autenticado-para-service-role`). O guard de
-- CI precisa medir a cobertura por um caminho que ele possa chamar — e `cron.job` nao e exposto
-- pela PostgREST. Este helper de auditoria e esse caminho, e nao duplica a classificacao: devolve
-- so os fatos crus (existe? esta aposentada?), deixando o veredito para quem consome.
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

REVOKE ALL ON FUNCTION public._audit_digest_cron_coverage() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._audit_digest_cron_coverage() TO service_role;

NOTIFY pgrst, 'reload schema';
