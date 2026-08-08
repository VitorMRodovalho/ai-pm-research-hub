-- #1649 — a varredura de alertas estourava um teto que não é dela, e ninguém media o crescimento.
--
-- O SINTOMA
-- `1621 behavioural: estado saudável é SILENCIOSO` falhou 5 vezes em 07/08/2026 com
-- `canceling statement due to statement timeout`, DUAS delas em commits que só mexiam em markdown.
-- O rerun deixou de resolver. Todo PR passou a ter ~60% de chance de vermelho por causa que não
-- é dele, e isso pressiona bypass.
--
-- POR QUE 8s É O TETO ERRADO PARA ESTA FUNÇÃO
-- `service_role` NÃO define `statement_timeout` próprio: herda `8s` do `authenticator`. Esse é o
-- orçamento de uma chamada INTERATIVA do PostgREST, e faz sentido lá. Só que o chamador natural
-- desta função é o `pg_cron` (job `platform-alert-sweep-hourly`), que roda como `postgres` e não
-- tem teto algum. Quem esbarra nos 8s é a suíte de contrato, que chama a varredura pelo PostgREST.
-- Ou seja: uma varredura em lote estava sendo medida com a régua de uma consulta de tela.
--
-- O QUE FOI MEDIDO ANTES DE ESCOLHER (07/08/2026)
--   - `cron.job_run_details`: 146.203 linhas, 150 MB, ~2.400 linhas/dia, só o índice do pkey
--   - o filtro `status='failed'` da fonte A descarta 146.201 de 146.201 linhas: trabalho 100%
--     desperdiçado para devolver zero
--   - seq scan completo: 152 ms A QUENTE (5.376 buffers vindos do disco); com cache frio, depois
--     de ~35 min de suíte, passa dos 8s
--   - a RPC inteira: 233 ms → 314 ms a quente
--   - `reltuples` estava em 29 — as estatísticas NUNCA tinham sido coletadas, e o planejador
--     montava Nested Loop achando 1 linha. `ANALYZE cron.job_run_details` corrigiu para 146.203.
--
-- AS DUAS SAÍDAS QUE NÃO DERAM
--   - **Índice parcial** em `cron.job_run_details`: seria a correção de raiz, mas a tabela é do
--     pg_cron (dono `supabase_admin`) e o `postgres` não é membro dele —
--     `ERROR 42501: must be owner of table job_run_details`.
--   - **Limitar por `runid`** (o único índice existente): MEDIDO e PIOR — 3.294 ms contra 152 ms,
--     porque troca leitura sequencial por 20 mil buscas no heap.
--
-- A CORREÇÃO, E POR QUE NÃO É MÁSCARA
-- Teto próprio de 60s, local à transação. Sozinho isso seria máscara: quando a tabela dobrar, o
-- problema volta e some do radar até o cron horário começar a estourar em produção. Por isso a
-- função passa a gravar `duration_ms` na MESMA linha de auditoria que ela já escreve
-- (`platform.alert_sweep_run`) — a degradação vira um número observável na superfície que o
-- próprio #1621 lê, em vez de um vermelho intermitente de CI. `_alert_sweep_cron` continua sendo
-- a única fonte da verdade sobre o próprio custo.
--
-- Nada mais do corpo mudou: base é o corpo VIVO (`pg_get_functiondef`), não o arquivo de migration.
--
-- Refs #1649, #1621, #1640

CREATE OR REPLACE FUNCTION public._alert_sweep_cron(p_deliver_email boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_now         timestamptz := now();
  v_t0          timestamptz := clock_timestamp();   -- #1649: relógio de parede, não o da transação
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
  v_duracao_ms  int;
BEGIN
  -- #1649 — teto PRÓPRIO, local à transação. O chamador natural desta função é o `pg_cron` (roda
  -- como `postgres`, sem teto); quem esbarra nos 8s herdados do `authenticator` é a suíte de
  -- contrato chamando pelo PostgREST. 8s é orçamento de consulta de tela, não de varredura em
  -- lote. O antídoto contra isso virar máscara é o `duration_ms` gravado no fim.
  PERFORM set_config('statement_timeout', '60s', true);

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
  -- ⚠️ O filtro é POSITIVO (`= 'failed'`), e isso não é estilo. `<> 'succeeded'` também casa o
  -- estado EM VOO: enquanto a própria varredura roda, a linha dela em `cron.job_run_details` está
  -- `running`, e o filtro negativo a lia como falha — a varredura acusava a si mesma, e mandou
  -- e-mail sobre isso em 2026-08-06 02:07 UTC. "Não teve sucesso" e "falhou" são conjuntos
  -- diferentes quando o em-progresso divide a mesma coluna.
  --
  -- ⚠️ #1649: esta é a varredura cara (150 MB, seq scan). Não há índice utilizável e não podemos
  -- criar um — a tabela é do pg_cron. Limitar por `runid` foi medido e é PIOR (3.294 ms vs 152 ms).
    WHERE d.status = 'failed'
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

  -- #1649 — o custo da própria varredura vira dado. Sem isto, o teto de 60s acima seria máscara:
  -- a degradação voltaria calada e só apareceria quando o cron horário estourasse em produção.
  v_duracao_ms := round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000)::int;

  -- O registro da própria varredura (é o que a watch `platform-alert-sweep-hourly` lê).
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'platform.alert_sweep_run', 'system', NULL,
    jsonb_build_object('new_count', v_novo, 'resolved_count', v_resolvidos,
                       'open_count', v_abertos, 'emails_sent', v_emails,
                       'duration_ms', v_duracao_ms),
    jsonb_build_object('issue', 1621, 'run_at', v_now)
  );

  RETURN jsonb_build_object(
    'success',        true,
    'new_count',      v_novo,
    'resolved_count', v_resolvidos,
    'open_count',     v_abertos,
    'emails_sent',    v_emails,
    'duration_ms',    v_duracao_ms,
    'run_at',         v_now
  );
END;
$function$;
