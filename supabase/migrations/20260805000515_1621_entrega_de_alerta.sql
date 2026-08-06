-- #1621 — a detecção existe e a entrega não.
--
-- Medido em 2026-08-06, antes de aplicar:
--   • 65 crons ativos; 71 execuções não-`succeeded` em 30d, em 18 jobs distintos, TODAS
--     `job startup timeout`, e a última em 2026-07-31 (nada nos 6 dias seguintes).
--   • NOVE RPCs `get_*_health` já leem `cron.job_run_details` (get_cron_status, get_digest_health,
--     get_drive_discovery_health, get_extraction_health, get_invitation_health, get_lgpd_cron_health,
--     get_ots_pipeline_health, get_pmi_launch_health, get_selection_health). Todas de PULL.
--     Nenhuma empurra. É essa a forma exata do buraco: a plataforma tem nove leitores de saúde e
--     nenhum entregador.
--   • O template `cron_failure_alert` FUNCIONA — 10 e-mails entregues —, mas é alimentado por uma
--     única fonte fora do banco (o worker `pmi-vep-sync`, aviso de expiração de token do PMI), e ela
--     parou em 2026-05-09. O canal está provado; o que falta são as FONTES.
--
-- ⚠️ Um dos critérios de aceite não sobreviveu à medição, e está corrigido aqui de propósito.
-- O aceite pedia alertar `data_anomaly_log` com `fixed_at IS NULL`. Medido: 151 linhas não
-- resolvidas, TODAS `severity='info'`, em 7 tipos, e todas administrativas
-- (`selection_status_change`, `selection_approval_canonical`, backfill de membro, update de
-- organização). O CHECK permite `critical|warning|info`, mas a tabela NUNCA carregou uma linha que
-- não fosse `info`: apesar do nome, ela é um trilho de auditoria, não um log de anomalia.
-- Entregar essas 151 linhas treinaria o GP a ignorar o canal na primeira semana — é a confusão
-- entre volume de log e população que o #1611 já custou. O gate aqui é `severity IN
-- ('warning','critical')`, que hoje rende ZERO, e o zero é declarado, não escondido.
-- Não é gate morto: o #1599 criou o primeiro produtor real de `warning`
-- (`selection_rescue_cron_error`), então a fonte existe e está calada porque o defeito foi
-- corrigido — que é exatamente o estado que se quer.
--
-- Decisões do PM em 2026-08-06: gate por severity + declarar o zero; entrega por notificação
-- in-app E digest diário por e-mail; escopo = camadas 1 e 3 (Sentry servidor fica fora, porque
-- exige um DSN que só o dono configura e bloquearia o PR).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) O ledger de entrega
-- ─────────────────────────────────────────────────────────────────────────────
-- Sem ledger, uma tempestade de 15 falhas do mesmo cron viraria 15 e-mails, e a defesa morreria
-- de ruído — a lição do #1609, onde 11 reservas geraram 16.722 linhas de log. A chave é lógica
-- (`alert_key`), não por linha de origem: uma tempestade de um cron num dia é UM alerta.
CREATE TABLE IF NOT EXISTS public.alert_deliveries (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_kind     text        NOT NULL,
  alert_key      text        NOT NULL,
  severity       text        NOT NULL CHECK (severity IN ('warning','critical')),
  title          text        NOT NULL,
  detail         jsonb       NOT NULL DEFAULT '{}'::jsonb,
  first_seen_at  timestamptz NOT NULL DEFAULT now(),
  last_seen_at   timestamptz NOT NULL DEFAULT now(),
  occurrences    integer     NOT NULL DEFAULT 1,
  notified_at    timestamptz,          -- entrega in-app (sem cota)
  emailed_at     timestamptz,          -- entrega por e-mail (sujeita ao teto diário)
  resolved_at    timestamptz,
  UNIQUE (alert_kind, alert_key)
);

COMMENT ON TABLE public.alert_deliveries IS
  '#1621 — ledger de alertas entregues. A chave (alert_kind, alert_key) é LÓGICA: uma tempestade do mesmo cron no mesmo dia é um alerta só.';
COMMENT ON COLUMN public.alert_deliveries.notified_at IS
  'Quando virou notificação in-app. Separado de emailed_at porque só o e-mail consome cota da Resend.';

CREATE INDEX IF NOT EXISTS idx_alert_deliveries_open
  ON public.alert_deliveries (alert_kind, last_seen_at DESC) WHERE resolved_at IS NULL;

ALTER TABLE public.alert_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.alert_deliveries FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.alert_deliveries TO authenticated;

DROP POLICY IF EXISTS alert_deliveries_read_gp ON public.alert_deliveries;
CREATE POLICY alert_deliveries_read_gp ON public.alert_deliveries
  FOR SELECT TO authenticated
  USING (public.rls_can('manage_platform'));

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) A camada 3 — vitalidade: distinguir "rodou e fez" de "rodou e NÃO fez"
-- ─────────────────────────────────────────────────────────────────────────────
-- Esta é a classe que motivou a issue. `selection-stuck-scheduled-rescue-daily` teve 62 execuções
-- 100% `succeeded` cobrindo os 6 dias em que estava quebrado: o RPC levantava, o cron engolia, e
-- nenhuma candidatura era resgatada. Qualquer métrica construída sobre `status='failed'` herda essa
-- cegueira — 71 é PISO, não teto.
--
-- O #1599 já deixou a semente pronta: os dois crons de resgate gravam `rescued_count` e
-- `error_count` em `admin_audit_log`. A vigília LÊ esse registro; não há SQL dinâmico, não há
-- sonda a inventar, e adicionar um cron novo é configuração, não código.
CREATE TABLE IF NOT EXISTS public.cron_vitality_watch (
  job_name              text PRIMARY KEY,
  effect_action         text        NOT NULL,   -- admin_audit_log.action que o cron grava
  effect_key            text        NOT NULL,   -- chave numérica em `changes` que mede o EFEITO
  error_key             text,                   -- chave numérica que mede ERRO (opcional)
  max_silent_runs       integer     NOT NULL DEFAULT 3 CHECK (max_silent_runs >= 1),
  alert_on_pure_silence boolean     NOT NULL DEFAULT false,
  expected_max_gap      interval    NOT NULL DEFAULT interval '36 hours',
  enabled               boolean     NOT NULL DEFAULT true,
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.cron_vitality_watch IS
  '#1621 camada 3 — por cron vigiado, ONDE ler o efeito (admin_audit_log.action + chave). Adicionar um cron é configuração, não código.';
COMMENT ON COLUMN public.cron_vitality_watch.alert_on_pure_silence IS
  'Efeito zero SEM erro é ambíguo: pode ser "nada a fazer". Só alerta se o cron declarar que silêncio é anormal. Separar os dois baldes é o requisito de #1532.';

ALTER TABLE public.cron_vitality_watch ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.cron_vitality_watch FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.cron_vitality_watch TO authenticated;

DROP POLICY IF EXISTS cron_vitality_watch_read_gp ON public.cron_vitality_watch;
CREATE POLICY cron_vitality_watch_read_gp ON public.cron_vitality_watch
  FOR SELECT TO authenticated
  USING (public.rls_can('manage_platform'));

-- As sementes. Os dois primeiros são os crons de resgate do arco #1598/#1599 — o primeiro deles é
-- LITERALMENTE o que passou 6 dias verde e vazio. `alert_on_pure_silence=false` porque zero resgates
-- é o estado saudável e comum; o que o pegaria é `rescued_count=0` COM `error_count>0`, que foi o
-- que aconteceu nos 6 dias.
INSERT INTO public.cron_vitality_watch
  (job_name, effect_action, effect_key, error_key, max_silent_runs, alert_on_pure_silence, expected_max_gap, notes)
VALUES
  ('selection-stuck-scheduled-rescue-daily', 'selection.stuck_rescue_cron_run',
   'rescued_count', 'error_count', 3, false, interval '36 hours',
   '#1598/#1599 — 62 execucoes succeeded cobrindo 6 dias quebrado. E a falha historica que motivou o #1621.'),
  ('selection-unbooked-rescue-daily', 'selection.unbooked_rescue_cron_run',
   'rescued_count', 'error_count', 3, false, interval '36 hours',
   'Gemeo do anterior, mesmo formato de registro.'),
  ('platform-alert-sweep-hourly', 'platform.alert_sweep_run',
   'open_count', NULL, 3, false, interval '6 hours',
   'Quem vigia o vigia: se a propria varredura parar, a regra de GAP acusa na proxima vez que ela rodar. Nao substitui um dead-man switch EXTERNO, que fica como follow-up.')
ON CONFLICT (job_name) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Upsert do ledger
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._alert_upsert(
  p_kind     text,
  p_key      text,
  p_severity text,
  p_title    text,
  p_detail   jsonb
)
RETURNS boolean   -- true quando o alerta é NOVO (ou reabriu depois de resolvido)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_was_open boolean;
BEGIN
  SELECT (resolved_at IS NULL) INTO v_was_open
  FROM public.alert_deliveries WHERE alert_kind = p_kind AND alert_key = p_key;

  INSERT INTO public.alert_deliveries AS a
    (alert_kind, alert_key, severity, title, detail)
  VALUES (p_kind, p_key, p_severity, p_title, coalesce(p_detail, '{}'::jsonb))
  ON CONFLICT (alert_kind, alert_key) DO UPDATE SET
    last_seen_at = now(),
    occurrences  = a.occurrences + 1,
    severity     = EXCLUDED.severity,
    title        = EXCLUDED.title,
    detail       = EXCLUDED.detail,
    notified_at  = CASE WHEN a.resolved_at IS NOT NULL THEN NULL ELSE a.notified_at END,
    emailed_at   = CASE WHEN a.resolved_at IS NOT NULL THEN NULL ELSE a.emailed_at END,
    resolved_at  = NULL;

  RETURN (v_was_open IS DISTINCT FROM true);
END;
$function$;

REVOKE ALL ON FUNCTION public._alert_upsert(text,text,text,text,jsonb) FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) A varredura
-- ─────────────────────────────────────────────────────────────────────────────
-- `p_deliver_email` existe por uma razão medida, não por gosto de parâmetro: o teste de contrato
-- precisa exercitar o caminho `critical`, e `critical` FURA o teto diário de propósito. Sem um
-- freio explícito, cada rodada de CI mandaria um alerta sintético para a caixa real dos dois GPs —
-- foi o que aconteceu uma vez, em 2026-08-06 01:43 UTC, antes deste parâmetro existir. Um teste
-- que dispara alerta falso para um humano a cada rodada destrói o canal que ele deveria proteger.
CREATE OR REPLACE FUNCTION public._alert_sweep_cron(p_deliver_email boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_now         timestamptz := now();
  v_novo        int := 0;
  v_resolvidos  int := 0;
  v_abertos     int := 0;
  v_emails      int := 0;
  v_rec         record;
  v_w           record;
  v_gp          record;
  v_efeito      numeric;
  v_erros       numeric;
  v_silenciosas int;
  v_ultima_run  timestamptz;
  v_tem_critico boolean := false;
  v_ultimo_mail timestamptz;
  v_txt         text := '';
  v_html        text := '';
  v_send        jsonb;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _alert_seen (kind text, key text) ON COMMIT DROP;
  -- O `WHERE true` não é decorativo: o papel `service_role` roda com `safeupdate`, que RECUSA
  -- DELETE sem WHERE. Sem ele a varredura funciona pelo pg_cron (que roda como `postgres`) e
  -- falha por PostgREST — a assimetria que o teste de contrato pegou.
  DELETE FROM _alert_seen WHERE true;

  -- Fonte A — falhas registradas de cron. Agrupa por (job, dia): as 71 falhas medidas foram 3
  -- tempestades de `job startup timeout`, e alertar por execução daria 71 linhas para 3 fatos.
  -- A janela é de 48h de propósito. Um cron falhando AGORA é acionável; uma tempestade de infra
  -- que se resolveu sozinha há seis dias é arqueologia, e entregá-la no primeiro disparo
  -- ensinaria o GP a arquivar o canal sem ler. A prova de que a entrega funciona vem do teste
  -- por MUTAÇÃO, que é o que o aceite pede — não de um lote histórico.
  FOR v_rec IN
    SELECT j.jobname,
           d.start_time::date AS dia,
           count(*)           AS n,
           max(d.start_time)  AS ultima,
           left(coalesce(max(d.return_message), ''), 200) AS msg
    FROM cron.job_run_details d
    JOIN cron.job j ON j.jobid = d.jobid
    WHERE d.status <> 'succeeded'
      AND d.start_time > v_now - interval '48 hours'
    GROUP BY 1, 2
  LOOP
    INSERT INTO _alert_seen VALUES ('cron_run_failed', v_rec.jobname || '|' || v_rec.dia);
    IF public._alert_upsert(
         'cron_run_failed',
         v_rec.jobname || '|' || v_rec.dia,
         'warning',
         format('Cron %s falhou %s vez(es) em %s', v_rec.jobname, v_rec.n, v_rec.dia),
         jsonb_build_object('job', v_rec.jobname, 'dia', v_rec.dia, 'falhas', v_rec.n,
                            'ultima', v_rec.ultima, 'mensagem', v_rec.msg)
       ) THEN
      v_novo := v_novo + 1;
    END IF;
  END LOOP;

  -- Fonte B — anomalia REAL. Gate por severity, e não por `fixed_at IS NULL`. Ver o cabeçalho:
  -- a tabela tem 151 linhas abertas e todas são `info` administrativo.
  FOR v_rec IN
    SELECT id, anomaly_type, severity, description, detected_at
    FROM public.data_anomaly_log
    WHERE fixed_at IS NULL
      AND severity IN ('warning', 'critical')
  LOOP
    INSERT INTO _alert_seen VALUES ('data_anomaly_open', v_rec.id::text);
    IF public._alert_upsert(
         'data_anomaly_open',
         v_rec.id::text,
         v_rec.severity,
         format('Anomalia %s: %s', v_rec.anomaly_type, left(coalesce(v_rec.description, ''), 160)),
         jsonb_build_object('anomaly_id', v_rec.id, 'tipo', v_rec.anomaly_type,
                            'severity', v_rec.severity, 'detectada_em', v_rec.detected_at)
       ) THEN
      v_novo := v_novo + 1;
    END IF;
  END LOOP;

  -- Fonte C — vitalidade
  FOR v_w IN SELECT * FROM public.cron_vitality_watch WHERE enabled LOOP
    SELECT max(created_at) INTO v_ultima_run
    FROM public.admin_audit_log WHERE action = v_w.effect_action;

    -- (C1) não rodou. Cobre cron desabilitado, renomeado ou que nunca chegou a existir.
    --
    -- ⚠️ A carência é obrigatória, não cosmética: uma vigília recém-registrada NÃO PODE ter
    -- histórico, e sem a carência a primeira varredura acusaria a si mesma de estar parada — um
    -- `critical` falso que fura o teto de e-mail e estreia o canal com um alerta errado. É a
    -- forma "valor ausente tratado como valor medido".
    IF v_ultima_run IS NULL AND v_w.created_at >= v_now - v_w.expected_max_gap THEN
      CONTINUE;
    END IF;

    IF v_ultima_run IS NULL OR (v_now - v_ultima_run) > v_w.expected_max_gap THEN
      INSERT INTO _alert_seen VALUES ('cron_not_running', v_w.job_name);
      IF public._alert_upsert(
           'cron_not_running', v_w.job_name, 'critical',
           format('Cron %s não registra execução desde %s',
                  v_w.job_name, coalesce(v_ultima_run::text, 'NUNCA')),
           jsonb_build_object('job', v_w.job_name, 'ultima_execucao', v_ultima_run,
                              'gap_tolerado', v_w.expected_max_gap::text,
                              'acao_auditada', v_w.effect_action)
         ) THEN
        v_novo := v_novo + 1;
      END IF;
      CONTINUE;
    END IF;

    -- (C2) sonda ausente. Uma chave que não existe no payload NÃO pode dividir balde com
    -- "efeito zero": falha de sonda e violação são fatos diferentes (#1532).
    SELECT count(*) FILTER (WHERE (changes ->> v_w.effect_key) IS NULL)
      INTO v_silenciosas
    FROM ( SELECT changes FROM public.admin_audit_log
            WHERE action = v_w.effect_action
            ORDER BY created_at DESC LIMIT v_w.max_silent_runs ) r;

    IF v_silenciosas > 0 THEN
      INSERT INTO _alert_seen VALUES ('vitality_probe_missing', v_w.job_name);
      IF public._alert_upsert(
           'vitality_probe_missing', v_w.job_name, 'warning',
           format('Sonda de vitalidade quebrada: %s não traz a chave "%s"',
                  v_w.effect_action, v_w.effect_key),
           jsonb_build_object('job', v_w.job_name, 'acao', v_w.effect_action,
                              'chave_ausente', v_w.effect_key, 'execucoes_sem_a_chave', v_silenciosas)
         ) THEN
        v_novo := v_novo + 1;
      END IF;
      CONTINUE;
    END IF;

    SELECT coalesce(sum((changes ->> v_w.effect_key)::numeric), 0),
           CASE WHEN v_w.error_key IS NULL THEN 0
                ELSE coalesce(sum(coalesce((changes ->> v_w.error_key)::numeric, 0)), 0) END
      INTO v_efeito, v_erros
    FROM ( SELECT changes FROM public.admin_audit_log
            WHERE action = v_w.effect_action
            ORDER BY created_at DESC LIMIT v_w.max_silent_runs ) r;

    -- (C3) efeito ZERO com ERRO. É a assinatura exata dos 6 dias do #1598: o cron roda, marca
    -- verde, não resgata ninguém, e engole a causa.
    IF v_efeito = 0 AND v_erros > 0 THEN
      INSERT INTO _alert_seen VALUES ('cron_effect_zero_with_errors', v_w.job_name);
      IF public._alert_upsert(
           'cron_effect_zero_with_errors', v_w.job_name, 'critical',
           format('Cron %s roda VERDE e não produz efeito: %s em %s execuções, com %s erro(s)',
                  v_w.job_name, v_w.effect_key, v_w.max_silent_runs, v_erros),
           jsonb_build_object('job', v_w.job_name, 'efeito', v_efeito, 'erros', v_erros,
                              'janela_execucoes', v_w.max_silent_runs,
                              'acao_auditada', v_w.effect_action)
         ) THEN
        v_novo := v_novo + 1;
      END IF;

    -- (C4) silêncio PURO. Ambíguo por natureza — só alerta se o cron declarar que é anormal.
    ELSIF v_efeito = 0 AND v_w.alert_on_pure_silence THEN
      INSERT INTO _alert_seen VALUES ('cron_silent', v_w.job_name);
      IF public._alert_upsert(
           'cron_silent', v_w.job_name, 'warning',
           format('Cron %s sem efeito em %s execuções seguidas', v_w.job_name, v_w.max_silent_runs),
           jsonb_build_object('job', v_w.job_name, 'efeito', v_efeito,
                              'janela_execucoes', v_w.max_silent_runs)
         ) THEN
        v_novo := v_novo + 1;
      END IF;
    END IF;
  END LOOP;

  -- Resolução: o que estava aberto e não foi revisto nesta varredura deixou de valer.
  WITH fechados AS (
    UPDATE public.alert_deliveries a
       SET resolved_at = v_now
     WHERE a.resolved_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM _alert_seen s WHERE s.kind = a.alert_kind AND s.key = a.alert_key)
    RETURNING 1
  )
  SELECT count(*) INTO v_resolvidos FROM fechados;

  SELECT count(*) INTO v_abertos FROM public.alert_deliveries WHERE resolved_at IS NULL;

  -- Entrega 1: notificação in-app (sem cota, sempre que há alerta novo).
  IF EXISTS (SELECT 1 FROM public.alert_deliveries WHERE resolved_at IS NULL AND notified_at IS NULL) THEN
    FOR v_gp IN
      SELECT m.id, m.email, m.name FROM public.members m
      WHERE m.is_active AND public.can_by_member(m.id, 'manage_platform')
    LOOP
      FOR v_rec IN
        SELECT title, severity FROM public.alert_deliveries
        WHERE resolved_at IS NULL AND notified_at IS NULL ORDER BY severity, first_seen_at
      LOOP
        -- overload de 7 argumentos (recipient, type, title, body, link, source_type, source_id).
        -- Explícito porque `create_notification` tem TRÊS overloads e a ambiguidade já derrubou
        -- uma RPC antes.
        PERFORM public.create_notification(
          v_gp.id,
          'platform_alert',
          CASE WHEN v_rec.severity = 'critical' THEN '[CRÍTICO] ' ELSE '[ALERTA] ' END || v_rec.title,
          'Detectado pela varredura de alertas da plataforma (#1621).',
          '/admin',
          'system',
          NULL::uuid
        );
      END LOOP;
    END LOOP;

    UPDATE public.alert_deliveries SET notified_at = v_now
     WHERE resolved_at IS NULL AND notified_at IS NULL;
  END IF;

  -- Entrega 2: digest por e-mail. Teto de um por ~dia, salvo `critical`, que fura o teto.
  -- Silêncio quando não há novidade — um canal que fala todo dia sem ter o que dizer deixa de
  -- ser lido.
  SELECT max(emailed_at) INTO v_ultimo_mail FROM public.alert_deliveries;
  SELECT bool_or(severity = 'critical') INTO v_tem_critico
    FROM public.alert_deliveries WHERE resolved_at IS NULL AND emailed_at IS NULL;

  IF p_deliver_email
     AND EXISTS (SELECT 1 FROM public.alert_deliveries WHERE resolved_at IS NULL AND emailed_at IS NULL)
     AND ( v_ultimo_mail IS NULL
           OR (v_now - v_ultimo_mail) >= interval '20 hours'
           OR coalesce(v_tem_critico, false) )
  THEN
    FOR v_rec IN
      SELECT severity, title, detail FROM public.alert_deliveries
      WHERE resolved_at IS NULL AND emailed_at IS NULL
      ORDER BY (severity = 'critical') DESC, first_seen_at
    LOOP
      v_txt := v_txt || '- [' || upper(v_rec.severity) || '] ' || v_rec.title || E'\n';
      v_html := v_html || '<li><strong>[' || upper(v_rec.severity) || ']</strong> '
             || replace(replace(replace(v_rec.title, '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
             || '</li>';
    END LOOP;
    v_html := '<ul>' || v_html || '</ul>';

    FOR v_gp IN
      SELECT m.id, m.email, m.name FROM public.members m
      WHERE m.is_active AND m.email IS NOT NULL
        AND public.can_by_member(m.id, 'manage_platform')
    LOOP
      BEGIN
        v_send := public.campaign_send_one_off(
          'platform_alert_digest',
          v_gp.email,
          jsonb_build_object(
            'alerts_text',    v_txt,
            'alerts_html',    v_html,
            'open_count',     v_abertos,
            'resolved_count', v_resolvidos,
            'generated_at',   to_char(v_now AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || ' BRT'
          ),
          jsonb_build_object('language', 'pt', 'recipient_name', v_gp.name,
                             'source', '_alert_sweep_cron')
        );
        v_emails := v_emails + 1;
      EXCEPTION WHEN OTHERS THEN
        -- Uma falha de envio não pode abortar a varredura nem apagar o alerta: os alertas ficam
        -- SEM `emailed_at` e saem na próxima rodada. Falhar aqui e perder o registro seria
        -- repetir o defeito que esta issue existe para fechar.
        RAISE WARNING '_alert_sweep_cron: envio para % falhou: %', v_gp.email, SQLERRM;
      END;
    END LOOP;

    IF v_emails > 0 THEN
      UPDATE public.alert_deliveries SET emailed_at = v_now
       WHERE resolved_at IS NULL AND emailed_at IS NULL;
    END IF;
  END IF;

  -- O registro da própria varredura (é o que a watch `platform-alert-sweep-hourly` lê).
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'platform.alert_sweep_run', 'system', NULL,
    jsonb_build_object('new_count', v_novo, 'resolved_count', v_resolvidos,
                       'open_count', v_abertos, 'emails_sent', v_emails),
    jsonb_build_object('issue', 1621, 'run_at', v_now)
  );

  RETURN jsonb_build_object(
    'success',        true,
    'new_count',      v_novo,
    'resolved_count', v_resolvidos,
    'open_count',     v_abertos,
    'emails_sent',    v_emails,
    'run_at',         v_now
  );
END;
$function$;

REVOKE ALL ON FUNCTION public._alert_sweep_cron(boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._alert_sweep_cron(boolean) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) O template do digest
-- ─────────────────────────────────────────────────────────────────────────────
-- Não reaproveita `cron_failure_alert`: aquele declara `worker` + `failure_count` como variáveis
-- obrigatórias e fala de UM worker, não de um digest. Reusá-lo obrigaria a mentir nos dois campos.
INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, category, variables)
VALUES (
  'Digest de alertas da plataforma (#1621)',
  'platform_alert_digest',
  jsonb_build_object('pt', '[Núcleo IA] Alertas da plataforma - {{generated_at}}'),
  jsonb_build_object('pt',
    '<p>Varredura de alertas da plataforma em <strong>{{generated_at}}</strong>.</p>'
    || '<p>Novos ou ainda sem entrega por e-mail:</p>{{alerts_html}}'
    || '<p>Abertos no total: <strong>{{open_count}}</strong>. Resolvidos nesta varredura: <strong>{{resolved_count}}</strong>.</p>'
    || '<p>Detalhe em <a href="https://nucleoia.pmigo.org.br/admin">nucleoia.pmigo.org.br/admin</a>.</p>'),
  jsonb_build_object('pt',
    'Varredura de alertas da plataforma em {{generated_at}}.' || E'\n\n'
    || 'Novos ou ainda sem entrega por e-mail:' || E'\n{{alerts_text}}\n'
    || 'Abertos no total: {{open_count}}. Resolvidos nesta varredura: {{resolved_count}}.' || E'\n\n'
    || 'Detalhe em https://nucleoia.pmigo.org.br/admin'),
  'operational',
  jsonb_build_object(
    'alerts_text',    jsonb_build_object('type','text','required',true),
    'alerts_html',    jsonb_build_object('type','text','required',true),
    'open_count',     jsonb_build_object('type','number','required',true),
    'resolved_count', jsonb_build_object('type','number','required',true),
    'generated_at',   jsonb_build_object('type','text','required',true)
  )
)
ON CONFLICT (slug) DO UPDATE SET
  subject   = EXCLUDED.subject,
  body_html = EXCLUDED.body_html,
  body_text = EXCLUDED.body_text,
  variables = EXCLUDED.variables,
  updated_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) O agendamento
-- ─────────────────────────────────────────────────────────────────────────────
-- De hora em hora, e não uma vez ao dia: a DETECÇÃO precisa ser fresca (uma notificação in-app não
-- custa cota), enquanto o E-MAIL tem teto de ~1 por dia dentro da própria função. Assim um
-- `critical` não espera 24h e um dia calmo não gera e-mail nenhum.
SELECT cron.unschedule('platform-alert-sweep-hourly')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'platform-alert-sweep-hourly');

SELECT cron.schedule('platform-alert-sweep-hourly', '7 * * * *', $cron$SELECT public._alert_sweep_cron();$cron$);

NOTIFY pgrst, 'reload schema';
