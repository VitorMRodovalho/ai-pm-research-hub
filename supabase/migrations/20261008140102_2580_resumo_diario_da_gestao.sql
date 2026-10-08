-- #2580 frente 2, regra 4 (decisoes do GP de 08/10/2026, D4 e C1 a C4): os alertas operacionais da gestao viram um
-- resumo diario, 08h de Brasilia, com o que ficou pendente desde o ultimo resumo.
--
-- C1: entram a varredura de alertas da plataforma e os alertas que saiam na hora para quem administra a plataforma
--     (teto diario de e-mail, "Ja me filiei", contas nao ligadas). Eles continuam no sino na hora (`suppress`).
-- C2: alerta `critical` da varredura continua saindo na hora.
-- C3: o "Ja me filiei" entra no resumo.
-- C4: o resumo diario de termos assinados fica como esta.

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
  v_txt         text := '';
  v_html        text := '';
  v_send        jsonb;
  v_duracao_ms  int;
  -- #1649 — pré-filtro por faixa de runid + guarda
  v_runid_corte   bigint;
  v_faixa_inicio  timestamptz;
  v_faixa_cobre   boolean := false;
  v_sql           text;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _alert_seen (kind text, key text) ON COMMIT DROP;
  -- O `WHERE true` não é decorativo: o papel `service_role` roda com `safeupdate`, que RECUSA
  -- DELETE sem WHERE. Sem ele a varredura funciona pelo pg_cron (que roda como `postgres`) e
  -- falha por PostgREST — a assimetria que o teste de contrato pegou.
  DELETE FROM _alert_seen WHERE true;

  -- #1649 — corte da faixa e GUARDA. Custo medido: 0,289 ms, 9 buffers.
  -- A guarda pergunta "a faixa começa ANTES do início da janela?". Se não começar, o pré-filtro
  -- excluiria falhas reais, então ele é desligado (v_faixa_cobre = false) e a varredura corre
  -- completa, mais lenta e correta, com a degradação registrada.
  SELECT max(runid) - 20000 INTO v_runid_corte FROM cron.job_run_details;

  IF v_runid_corte IS NOT NULL THEN
    SELECT d.start_time INTO v_faixa_inicio
    FROM cron.job_run_details d
    WHERE d.runid > v_runid_corte
    ORDER BY d.runid
    LIMIT 1;

    v_faixa_cobre := (v_faixa_inicio IS NOT NULL
                      AND v_faixa_inicio <= v_now - interval '48 hours');
  END IF;

  IF NOT v_faixa_cobre THEN
    RAISE WARNING '_alert_sweep_cron: faixa de runid nao cobre 48h (inicio=%); varrendo tabela inteira. Aumentar a constante em #1649.', v_faixa_inicio;
  END IF;

  -- Fonte A — falhas registradas de cron. Agrupa por (job, dia): as 71 falhas medidas foram 3
  -- tempestades de `job startup timeout`, e alertar por execução daria 71 linhas para 3 fatos.
  -- A janela é de 48h de propósito. Um cron falhando AGORA é acionável; uma tempestade de infra
  -- que se resolveu sozinha há seis dias é arqueologia, e entregá-la no primeiro disparo
  -- ensinaria o GP a arquivar o canal sem ler. A prova de que a entrega funciona vem do teste
  -- por MUTAÇÃO, que é o que o aceite pede — não de um lote histórico.
  --
  -- ⚠️ O filtro é POSITIVO (`= 'failed'`), e isso não é estilo. `<> 'succeeded'` também casa o
  -- estado EM VOO: enquanto a própria varredura roda, a linha dela em `cron.job_run_details` está
  -- `running`, e o filtro negativo a lia como falha — a varredura acusava a si mesma, e mandou
  -- e-mail sobre isso em 2026-08-06 02:07 UTC. "Não teve sucesso" e "falhou" são conjuntos
  -- diferentes quando o em-progresso divide a mesma coluna.
  v_sql := format(
    'SELECT j.jobname, d.start_time::date AS dia, count(*) AS n, '
    || 'max(d.start_time) AS ultima, '
    || 'left(coalesce(max(d.return_message), %L), 200) AS msg '
    || 'FROM cron.job_run_details d '
    || 'JOIN cron.job j ON j.jobid = d.jobid '
    || 'WHERE %s d.status = %L AND d.start_time > %L::timestamptz - interval ''48 hours'' '
    || 'GROUP BY 1, 2',
    '',
    CASE WHEN v_faixa_cobre THEN format('d.runid > %s AND ', v_runid_corte) ELSE '' END,
    'failed',
    v_now
  );

  FOR v_rec IN EXECUTE v_sql
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

  -- Entrega 2: e-mail na hora SO quando ha alerta `critical` (#2580 C2). O resto sai no resumo
  -- diario da gestao das 08h de Brasilia (_management_daily_digest_cron), que carimba emailed_at.
  SELECT bool_or(severity = 'critical') INTO v_tem_critico
    FROM public.alert_deliveries WHERE resolved_at IS NULL AND emailed_at IS NULL;

  IF p_deliver_email
     AND EXISTS (SELECT 1 FROM public.alert_deliveries WHERE resolved_at IS NULL AND emailed_at IS NULL)
     AND coalesce(v_tem_critico, false)
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

  -- #1649 — o custo da própria varredura vira dado. Sem isto, o pré-filtro acima seria uma
  -- otimização sem termômetro: a degradação voltaria calada e só apareceria quando o cron
  -- horário estourasse em produção.
  v_duracao_ms := round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000)::int;

  -- O registro da própria varredura (é o que a watch `platform-alert-sweep-hourly` lê).
  -- `janela_degradada` = a guarda reprovou e esta corrida varreu a tabela inteira.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'platform.alert_sweep_run', 'system', NULL,
    jsonb_build_object('new_count', v_novo, 'resolved_count', v_resolvidos,
                       'open_count', v_abertos, 'emails_sent', v_emails,
                       'duration_ms', v_duracao_ms,
                       'janela_degradada', (NOT v_faixa_cobre)),
    jsonb_build_object('issue', 1621, 'run_at', v_now)
  );

  RETURN jsonb_build_object(
    'success',        true,
    'new_count',      v_novo,
    'resolved_count', v_resolvidos,
    'open_count',     v_abertos,
    'emails_sent',    v_emails,
    'duration_ms',    v_duracao_ms,
    'janela_degradada', (NOT v_faixa_cobre),
    'run_at',         v_now
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.email_cap_reached(p_lane text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_inicio timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo';
  v_teto int := public.email_daily_cap();
  v_hoje int := public.email_sends_today();
  v_novos int;
BEGIN
  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, is_read, delivery_mode)
  SELECT m.id,
         'system_alert',
         'Teto diário de e-mails do hub atingido',
         format('O hub enviou %s e-mails hoje e chegou ao teto de %s (caminho: %s). O que faltou sai no próximo dia. '
                'O teto mora em site_config, chave email_daily_cap.', v_hoje, v_teto, coalesce(p_lane, '?')),
         '/admin',
         'email_daily_cap',
         false,
         -- #2580 C1: no sino na hora; o e-mail sai no resumo diario da gestao.
         'suppress'
  FROM public.members m
  WHERE m.is_active IS TRUE
    AND public.can_by_member(m.id, 'manage_platform')
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = m.id AND n.source_type = 'email_daily_cap' AND n.created_at >= v_inicio
    );
  GET DIAGNOSTICS v_novos = ROW_COUNT;
  RETURN v_novos;
END;
$function$;

CREATE OR REPLACE FUNCTION public.request_affiliation_recheck()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_inicio timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo';
  v_novos int;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, is_read, delivery_mode)
  SELECT m.id,
         'system_alert',
         'Pedido de verificação de filiação',
         'Uma pessoa em pré-onboarding informou que se filiou a um capítulo participante. Atualize o JSON da VEP: '
         'a ingestão grava a filiação e o Termo de Voluntariado abre sozinho. Se a filiação não aparecer na VEP, '
         'registre a verificação na fila de filiação.',
         '/admin/filiacao',
         'affiliation_recheck',
         v_member_id,
         false,
         -- #2580 C3: no sino na hora; o e-mail sai no resumo diario da gestao das 08h.
         'suppress'
  FROM public.members m
  WHERE m.is_active IS TRUE
    AND m.id <> v_member_id
    AND public.can_by_member(m.id, 'manage_platform')
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = m.id AND n.source_type = 'affiliation_recheck'
        AND n.source_id = v_member_id AND n.created_at >= v_inicio
    );
  GET DIAGNOSTICS v_novos = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'notified', v_novos);
END;
$function$;

CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE p_type
    -- PR-2 (email audit): the per-signing leadership alert is now in-app only; the daily
    -- digest (volunteer_term_signed_digest) carries the single aggregated email.
    WHEN 'volunteer_agreement_signed'    THEN 'suppress'
    WHEN 'volunteer_term_signed_digest'  THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    -- #1169: ready is redundant with issued at the email layer (issued carries the single email);
    -- kept in-app only. Every ready-cert already fired an issued email (0 ready-without-issued/60d).
    WHEN 'certificate_ready'             THEN 'suppress'
    WHEN 'certificate_issued'            THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'governance_manual_proposed'    THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'
    -- p153 OPP-153.1: project_charter (TAP) notifications
    WHEN 'project_charter_invite'        THEN 'transactional_immediate'
    WHEN 'project_charter_approved'      THEN 'transactional_immediate'
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- #2325 (2026-09-16): o LEMBRETE de que o termo segue aberto. Tipo proprio, separado de
    -- `selection_termo_due` (que anuncia a ABERTURA, no aceite do VEP, e e alvo de replay).
    -- Nasceu porque a cobranca saia como `system`, que o catalogo manda suprimir: 26 avisos a
    -- 16 pessoas que nunca deixaram a plataforma. Catalogado de proposito em vez de cair no
    -- ELSE: o ELSE e `digest_weekly`, que carimba como entregue o que nao renderiza (#2286).
    WHEN 'volunteer_term_pending'        THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): Selection funnel Policy Matrix
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 2 (2026-05-23): admin reminder for overdue interviews
    WHEN 'selection_interview_overdue'   THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 4 (2026-05-23): candidate invite to book interview after
    -- objective evaluations cleared + research_score >= cycle cutoff.
    WHEN 'selection_cutoff_approved'     THEN 'transactional_immediate'
    -- (end p228)
    -- #2013 (2026-08-26): o teto de lembretes de reagendamento foi atingido e o caso vira
    -- trabalho de gente. Imediato de proposito: e o unico aviso, e o digest semanal so
    -- entrega a quem tem OUTRO conteudo na semana (#2010).
    WHEN 'selection_reschedule_escalated' THEN 'transactional_immediate'
    -- #186 (2026-06-05): curation committee broadcast when an item enters curation_pending
    WHEN 'curation_item_submitted'       THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    -- #625 F3 (2026-06-11): radar de renovação de filiação
    WHEN 'affiliation_renewal_d7_urgent'  THEN 'transactional_immediate'
    WHEN 'affiliation_renewal_d30'        THEN 'digest_weekly'
    WHEN 'affiliation_verification_stale' THEN 'digest_weekly'
    -- #1855 (2026-08-18): faixa de filiacao ja VENCIDA. Catalogado de proposito, e nao deixado
    -- cair no ELSE, pelo mesmo motivo registrado no bloco 5b da #625: o ELSE e um default de
    -- conveniencia e um dia muda. digest_weekly porque o PM decidiu 'so lembrete, mesmo tom'.
    WHEN 'affiliation_renewal_expired'    THEN 'digest_weekly'
    -- #2152 (2026-09-03): a verificacao ficou atras do VEP. Vai para a diretoria, nao para o
    -- membro, e no mesmo modo da faixa irma de verificacao obsoleta: e trabalho de fila, nao
    -- urgencia. Catalogado em vez de cair no ELSE, pelo motivo registrado acima.
    WHEN 'affiliation_vep_divergence'     THEN 'digest_weekly'
    -- #1224 PR2 (2026-07-09): one-time onboarding nudge when the PMI enrichment cannot resolve
    -- an entry chapter (profile_private / no_fetch / not_affiliated / ambiguous-no-choice).
    WHEN 'entry_chapter_action_needed'    THEN 'transactional_immediate'
    -- #740 Wave 3c-i (B8): agreement rejected / reissued — member must re-sign, deliver immediately
    WHEN 'volunteer_agreement_rejected'  THEN 'transactional_immediate'
    WHEN 'volunteer_agreement_reissued'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    -- #2285 (2026-09-14): o detector de contas nao ligadas passou a ter cron. Catalogado de
    -- proposito, e nao deixado cair no ELSE, pelo mesmo motivo registrado acima para #625,
    -- #1855 e #2152. Aqui o ELSE e pior que um default inconveniente: digest_weekly monta as
    -- secoes por lista branca de tipos e carimba como entregue o que nao renderizou (#2286).
    -- #2580 C1 (2026-10-08): no sino na hora; o e-mail sai no resumo diario da gestao. `suppress` e nao
    -- digest_weekly: o resumo semanal so le digest_weekly, entao nao ha carimbo sem renderizar (#2286).
    WHEN 'unlinked_accounts_detected'     THEN 'suppress'
    -- #2580 C: o resumo diario da gestao e um e-mail proprio.
    WHEN 'management_daily_digest'        THEN 'transactional_immediate'
    -- #2444 (2026-09-24): rodizio de pareceristas da curadoria. Imediato de proposito: a
    -- designacao e o lembrete sao o que da dono ao parecer; o digest semanal chegaria depois do
    -- prazo de 7 dias. O vencido vai para quem gere a plataforma, tambem imediato: e decisao.
    WHEN 'curation_review_assigned'       THEN 'transactional_immediate'
    WHEN 'curation_review_overdue'        THEN 'transactional_immediate'
    -- #2496 (2026-09-27): aviso a tribo (participantes do card e lideranca da iniciativa) de que o
    -- item entrou em curadoria. Imediato de proposito: caia em card_moved (digest_weekly), com o
    -- codigo cru do status e link generico, e nenhuma das 3 pessoas da tribo recebeu e-mail.
    WHEN 'curation_submitted_to_tribe'    THEN 'transactional_immediate'
    -- #2495 (2026-09-27): piloto do wiki vivo (ADR-0129, emenda 2). Imediatos de proposito: a
    -- lideranca publica na hora e o comite audita em 14 dias; um aviso que chegasse no digest
    -- semanal comeria metade do prazo. O vencido vai para quem gere a plataforma.
    WHEN 'wiki_review_requested'          THEN 'transactional_immediate'
    WHEN 'wiki_page_decision'             THEN 'transactional_immediate'
    WHEN 'wiki_audit_requested'           THEN 'transactional_immediate'
    WHEN 'wiki_audit_overdue'             THEN 'transactional_immediate'
    -- #2495 fase B2 (2026-09-29): "Sugerir melhoria". Imediatos pelo mesmo motivo dos avisos do wiki
    -- acima: a sugestao vai a quem decide sobre a pagina, e a resposta volta a quem sugeriu; um aviso
    -- no digest semanal chegaria depois de a pessoa ter esquecido o que sugeriu.
    WHEN 'wiki_suggestion_received'       THEN 'transactional_immediate'
    WHEN 'wiki_suggestion_decision'       THEN 'transactional_immediate'
    -- #2444 (2026-09-24): a revisao do lider e a devolucao ao autor. Imediatos de proposito: caiam no
    -- ELSE (digest_weekly) e, medido, leader_review_requested nunca gerou uma linha sequer; sem aviso,
    -- 16 cards ficaram parados em leader_review desde maio.
    WHEN 'leader_review_requested'        THEN 'transactional_immediate'
    WHEN 'leader_review_returned'         THEN 'transactional_immediate'
    -- #2454 (2026-09-24): falha de acesso ao Drive. Imediatos: a pessoa esta sem acesso a pasta da
    -- iniciativa agora (e nao sabia: 3 casos medidos), e a falha da conta de servico e acao do
    -- administrador do Workspace.
    WHEN 'drive_access_action_needed'     THEN 'transactional_immediate'
    WHEN 'drive_access_admin_needed'      THEN 'transactional_immediate'
    ELSE 'digest_weekly'
  END;
$function$;

CREATE OR REPLACE FUNCTION public._management_daily_digest_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_batch    uuid := gen_random_uuid();
  v_types    text[] := ARRAY['system_alert', 'unlinked_accounts_detected'];
  v_alerts   jsonb;
  v_open     int;
  v_resolved int;
  v_adm      record;
  v_items    jsonb;
  v_ids      uuid[];
  v_sent     int := 0;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object('severity', a.severity, 'title', a.title, 'first_seen_at', a.first_seen_at)
                            ORDER BY (a.severity = 'critical') DESC, a.first_seen_at), '[]'::jsonb)
    INTO v_alerts
    FROM public.alert_deliveries a
   WHERE a.resolved_at IS NULL AND a.emailed_at IS NULL;
  SELECT count(*) INTO v_open FROM public.alert_deliveries WHERE resolved_at IS NULL;
  SELECT count(*) INTO v_resolved FROM public.alert_deliveries WHERE resolved_at >= now() - interval '24 hours';

  FOR v_adm IN
    SELECT m.id FROM public.members m
     WHERE m.is_active IS TRUE AND public.can_by_member(m.id, 'manage_platform')
  LOOP
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', n.id, 'type', n.type, 'title', n.title, 'body', n.body,
                                                 'link', n.link, 'created_at', n.created_at) ORDER BY n.created_at), '[]'::jsonb),
           COALESCE(array_agg(n.id), '{}'::uuid[])
      INTO v_items, v_ids
      FROM public.notifications n
     WHERE n.recipient_id = v_adm.id
       AND n.delivery_mode = 'suppress'
       AND n.type = ANY(v_types)
       AND n.digest_delivered_at IS NULL
       AND n.created_at >= now() - interval '7 days';

    IF jsonb_array_length(v_alerts) = 0 AND jsonb_array_length(v_items) = 0 THEN
      CONTINUE;
    END IF;

    INSERT INTO public.notifications (
      recipient_id, type, title, body, link, source_type, source_id, is_read, delivery_mode, digest_batch_id
    ) VALUES (
      v_adm.id,
      'management_daily_digest',
      'Resumo diário da gestão',
      jsonb_build_object('version', 1, 'generated_at', now(), 'alerts', v_alerts, 'open_count', v_open,
                         'resolved_24h', v_resolved, 'items', v_items)::text,
      '/admin',
      'management_digest',
      v_batch,
      false,
      'transactional_immediate',
      v_batch
    );

    UPDATE public.notifications
       SET digest_delivered_at = now(), digest_batch_id = v_batch
     WHERE id = ANY(v_ids) AND digest_delivered_at IS NULL;

    v_sent := v_sent + 1;
  END LOOP;

  IF v_sent > 0 THEN
    UPDATE public.alert_deliveries SET emailed_at = now()
     WHERE resolved_at IS NULL AND emailed_at IS NULL;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (NULL, 'platform.management_digest_run', 'system', NULL,
          jsonb_build_object('digests', v_sent, 'alerts', jsonb_array_length(v_alerts)),
          jsonb_build_object('issue', 2580, 'batch_id', v_batch));

  RETURN jsonb_build_object('digests', v_sent, 'alerts', jsonb_array_length(v_alerts), 'batch_id', v_batch);
END;
$function$;

REVOKE ALL ON FUNCTION public._management_daily_digest_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._management_daily_digest_cron() TO service_role;

-- 08h de Brasilia = 11:00 UTC.
SELECT cron.schedule('management-daily-digest', '0 11 * * *', 'SELECT public._management_daily_digest_cron();');

INSERT INTO public.digest_cron_expectations (jobname, description, expected_schedule, max_days_between_runs)
VALUES ('management-daily-digest', 'resumo diario da gestao (#2580 regra 4): 08h de Brasilia', '0 11 * * *', 2)
ON CONFLICT (jobname) DO NOTHING;
