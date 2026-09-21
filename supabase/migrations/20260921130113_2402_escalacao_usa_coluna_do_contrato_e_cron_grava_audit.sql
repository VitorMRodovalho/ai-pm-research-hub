-- #2402: a escalacao do cutucao de reagendamento nunca disparou, e o cron nao tinha leitor.
--
-- MEDIDO em 21/09/2026:
--   * `_selection_cycle_recipients` devolve TABLE(member_id uuid, via text). O bloco de escalacao
--     chamava `create_notification(r.id, ...)`. Provado nos dois sentidos com PREPARE, que planeja
--     sem executar: `r.member_id` planeja OK, `r.id` devolve `42703: column r.id does not exist`.
--   * o erro caia no `EXCEPTION WHEN OTHERS`, virava entrada em `v_errors`, e `v_errors` voltava
--     no jsonb de retorno. `cron.job_run_details.return_message` guarda "1 row": o retorno de um
--     cron chamado por SELECT NAO TEM LEITOR.
--   * e este cron, ao contrario de `_selection_unbooked_rescue_cron` e
--     `_selection_stuck_scheduled_rescue_cron`, nao gravava `admin_audit_log` nem
--     `data_anomaly_log`. As correcoes 1 e 3 da #1599 foram aplicadas aos dois irmaos e nao a ele.
--   * efeito: 12 execucoes `succeeded` consecutivas (09/09 a 20/09) sobre 3 candidaturas acima do
--     teto de despachos, com `interview_reschedule_escalated_at` NULL nas tres e
--     `interview_reschedule_last_nudged_at` congelado em 26/08, que e a data em que a escalacao
--     subiu. Ou seja: o mecanismo nunca funcionou um dia sequer.
--   * um dos diagnosticos represados: 19 aberturas do link e zero agendamento, que o proprio
--     codigo classifica como `abriu_e_nao_agendou` e manda tratar por contato humano.
--
-- O QUE ESTA MIGRATION FAZ, e o que ela NAO faz:
--   (a) troca `r.id` por `r.member_id`;
--   (b) grava `admin_audit_log` no fim do run, com o DENOMINADOR (`examined`), que e o que a
--       #2402 pede ao dizer que "nenhum resgatado" nao distingue fila vazia de fila errada;
--   (c) publica em `data_anomaly_log` quando houver erro, como nos irmaos.
--   NAO fecha o buraco de predicado entre os tres crons (candidatura `interview_pending` com
--   flag de reagendamento e zero entrevistas nao e resgatada por ninguem). Isso e decisao de
--   desenho e fica na #2402.
--
-- Guard: tests/contracts/2013-lembrete-de-reagendamento-com-teto-e-diagnostico.test.mjs, que
-- passa a derivar a coluna do destinatario do CONTRATO DE RETORNO de `_selection_cycle_recipients`
-- em vez de afirmar que a string aparece no corpo. A versao anterior do guard ficava verde com o
-- mecanismo morto: afirmava presenca de `_selection_cycle_recipients` e de
-- `'selection_reschedule_escalated'`, e nenhuma das duas amarra a COLUNA ao resultado.

CREATE OR REPLACE FUNCTION public.process_pending_reschedule_nudges()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
  v_first_name text;
  v_booking_url text;
  v_dispatch jsonb;
  v_nudges_sent int := 0;
  v_errors jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_processed jsonb := '[]'::jsonb;
  v_nudge_initial interval;
  v_nudge_repeat interval;
  -- #2013
  v_max_dispatches int;
  v_escalations int := 0;
  -- #2402 o denominador. "nenhum resgatado" e ambiguo entre fila vazia e fila errada; so a
  -- contagem de quem o laco EXAMINOU separa as duas.
  v_examined int := 0;
  v_escalated jsonb := '[]'::jsonb;
  v_ep record;
  v_diag text;
  v_diag_code text;
BEGIN
  SELECT value_interval INTO v_nudge_initial FROM public.sla_policies WHERE policy_key = 'reschedule_nudge_initial';
  IF v_nudge_initial IS NULL THEN v_nudge_initial := interval '3 days'; END IF;
  SELECT value_interval INTO v_nudge_repeat FROM public.sla_policies WHERE policy_key = 'reschedule_nudge_repeat';
  IF v_nudge_repeat IS NULL THEN v_nudge_repeat := interval '3 days'; END IF;

  -- #2013 — o teto vem do SSOT. O fallback existe para o cron nunca virar laco infinito se a
  -- chave sumir; ele repete o valor semeado nesta mesma migration, de proposito.
  SELECT NULLIF(value #>> '{}', '')::int INTO v_max_dispatches
  FROM public.platform_settings WHERE key = 'selection.reschedule_nudge_max_dispatches';
  IF v_max_dispatches IS NULL OR v_max_dispatches < 1 THEN v_max_dispatches := 3; END IF;

  -- Cron-context auth bypass (sem JWT). Alinhado ao padrão do ADR-0028 (emenda p89).
  IF auth.role() IS NOT NULL AND auth.role() NOT IN ('service_role') AND auth.uid() IS NOT NULL THEN
    IF NOT public.can_by_member(
      (SELECT id FROM public.members WHERE auth_id = auth.uid()),
      'manage_member'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: cron RPC requires manage_member or service_role';
    END IF;
  END IF;

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.email, a.cycle_id,
           a.interview_reschedule_reason,
           a.interview_reschedule_requested_at,
           a.interview_reschedule_last_nudged_at,
           a.interview_reschedule_escalated_at
    FROM public.selection_applications a
    WHERE a.interview_status = 'needs_reschedule'
      AND a.interview_reschedule_requested_at IS NOT NULL
      AND a.interview_reschedule_requested_at < now() - v_nudge_initial
      AND (
        a.interview_reschedule_last_nudged_at IS NULL
        OR a.interview_reschedule_last_nudged_at < now() - v_nudge_repeat
      )
      AND a.status IN ('interview_pending', 'interview_scheduled')
  LOOP
    v_examined := v_examined + 1;

    -- #2013 — o EPISODIO e a janela desde o pedido de reagendamento. Contar assim faz o teto
    -- se reabrir sozinho quando um pedido NOVO chega, sem coluna de reset em lugar nenhum.
    -- `instrumented` separa "nao abriu" de "nao medi": sem esse filtro, `open_count = 0` de um
    -- despacho nao instrumentado leria como desinteresse e produziria o diagnostico OPOSTO.
    SELECT
      count(*)::int                                                        AS despachos,
      (count(*) FILTER (WHERE d.instrumented))::int                        AS medidos,
      COALESCE(sum(d.open_count) FILTER (WHERE d.instrumented), 0)::int    AS aberturas,
      (count(*) FILTER (WHERE d.booked_at IS NOT NULL))::int               AS agendamentos
    INTO v_ep
    FROM public.selection_dispatch_url_log d
    WHERE d.application_id = v_app.id
      AND d.dispatched_at >= v_app.interview_reschedule_requested_at;

    IF v_ep.despachos >= v_max_dispatches THEN
      -- Teto atingido: o candidato NAO recebe mais nada por este caminho. Uma unica escalacao
      -- por episodio, com o diagnostico que `open_count` ja permitia fazer e ninguem lia.
      IF v_app.interview_reschedule_escalated_at IS NULL
         OR v_app.interview_reschedule_escalated_at < v_app.interview_reschedule_requested_at THEN

        IF v_ep.medidos = 0 THEN
          v_diag_code := 'sem_medicao';
          v_diag := format('%s despacho(s), nenhum instrumentado: nao da para dizer se o e-mail chegou nem se foi aberto.', v_ep.despachos);
        ELSIF v_ep.aberturas = 0 THEN
          v_diag_code := 'nao_abriu';
          v_diag := format('%s e-mail(s) medido(s) e ZERO aberturas: verificar entrega (spam, endereco errado) antes de insistir.', v_ep.medidos);
        ELSE
          v_diag_code := 'abriu_e_nao_agendou';
          v_diag := format('%s abertura(s) e nenhum agendamento: o agendamento provavelmente esta falhando para esta pessoa, vale contato humano.', v_ep.aberturas);
        END IF;

        BEGIN
          -- #2402 CONSERTO. Era `r.id`, e `_selection_cycle_recipients` devolve
          -- TABLE(member_id uuid, via text): nao existe coluna `id`. O statement levantava
          -- 42703 em TODA execucao, o WHEN OTHERS abaixo engolia, e o jsonb de retorno morria
          -- no pg_cron. Resultado: a escalacao nunca disparou uma vez desde 26/08/2026.
          PERFORM public.create_notification(
            r.member_id,
            'selection_reschedule_escalated',
            'Reagendamento sem resposta: ' || v_app.applicant_name,
            format('Teto de %s despacho(s) automatico(s) atingido neste pedido de reagendamento. %s', v_max_dispatches, v_diag),
            '/admin/selection?app=' || v_app.id::text,
            'selection_application',
            v_app.id
          )
          FROM public._selection_cycle_recipients(v_app.cycle_id) r;

          UPDATE public.selection_applications
          SET interview_reschedule_escalated_at = now()
          WHERE id = v_app.id;

          v_escalations := v_escalations + 1;
          v_escalated := v_escalated || jsonb_build_object(
            'application_id', v_app.id,
            'applicant_name', v_app.applicant_name,
            'dispatches', v_ep.despachos,
            'instrumented', v_ep.medidos,
            'opens', v_ep.aberturas,
            'diagnosis_code', v_diag_code,
            'diagnosis', v_diag
          );
        EXCEPTION WHEN OTHERS THEN
          v_errors := v_errors || jsonb_build_object('application_id', v_app.id, 'error', SQLERRM);
        END;
      END IF;

      CONTINUE;
    END IF;

    v_first_name := split_part(v_app.applicant_name, ' ', 1);
    v_dispatch := NULL;
    v_booking_url := NULL;

    -- Subtransação 1: o despacho governado. Commita por si — um erro de envio adiante não a desfaz.
    BEGIN
      v_dispatch := public._dispatch_interview_booking_link(v_app.id, NULL, 'process_pending_reschedule_nudges');
    EXCEPTION WHEN OTHERS THEN
      v_dispatch := jsonb_build_object('success', false, 'failure_code', 'DISPATCH_ERROR', 'message', SQLERRM);
    END;

    IF COALESCE((v_dispatch->>'success')::boolean, false) IS NOT TRUE THEN
      -- Sem link governado não sai cutucão: mandar o literal do Google era o defeito da #1595.
      v_skipped := v_skipped || jsonb_build_object(
        'application_id', v_app.id,
        'failure_code', v_dispatch->>'failure_code',
        'gate_failed_code', v_dispatch->>'gate_failed_code'
      );
      CONTINUE;
    END IF;

    v_booking_url := v_dispatch->>'booking_url';

    -- Subtransação 2: envio + carimbo.
    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'interview_reschedule_nudge',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'reason', COALESCE(v_app.interview_reschedule_reason, '—'),
          'booking_url', v_booking_url
        ),
        p_metadata := jsonb_build_object(
          'source', 'process_pending_reschedule_nudges',
          'application_id', v_app.id,
          'reschedule_requested_at', v_app.interview_reschedule_requested_at,
          'last_nudged_at_before', v_app.interview_reschedule_last_nudged_at,
          'days_pending', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0,
          'link_kind', 'governed_token',
          'gate_mode', v_dispatch->>'gate_mode',
          'dispatch_number', v_ep.despachos + 1,
          'dispatch_cap', v_max_dispatches
        )
      );

      UPDATE public.selection_applications
      SET interview_reschedule_last_nudged_at = now()
      WHERE id = v_app.id;

      v_nudges_sent := v_nudges_sent + 1;
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'gate_mode', v_dispatch->>'gate_mode',
        'dispatch_number', v_ep.despachos + 1,
        'dispatch_cap', v_max_dispatches,
        'days_since_request', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0
      );

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  -- #2402 os dois crons de resgate ja gravavam aqui; este nao gravava em lugar nenhum, e por
  -- isso 12 execucoes seguidas de um erro 42703 nao deixaram rastro. `cron.job_run_details`
  -- guarda apenas "1 row": quem escreve relatorio dentro do valor de retorno escreve para
  -- ninguem. O denominador (`examined`) entra junto, que e o pedido da propria #2402.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.reschedule_nudge_cron_run', 'system', NULL,
    jsonb_build_object(
      'examined', v_examined,
      'nudges_sent', v_nudges_sent,
      'escalations', v_escalations,
      'skipped_count', jsonb_array_length(v_skipped),
      'error_count', jsonb_array_length(v_errors)
    ),
    jsonb_build_object(
      'examined', v_examined,
      'nudges_sent', v_nudges_sent,
      'escalations', v_escalations,
      'skipped_count', jsonb_array_length(v_skipped),
      'error_count', jsonb_array_length(v_errors),
      'errors', v_errors,
      'skipped', v_skipped,
      'escalated', v_escalated,
      'processed', v_processed,
      'dispatch_cap', v_max_dispatches,
      'nudge_initial_days', round(EXTRACT(EPOCH FROM v_nudge_initial) / 86400.0, 1),
      'nudge_repeat_days', round(EXTRACT(EPOCH FROM v_nudge_repeat) / 86400.0, 1),
      'run_at', now(),
      'rpc_version', 'p2402'
    )
  );

  -- #2402 e um erro recorrente deixa de morrer dentro do audit, igual ao que a #1599 fez pelos
  -- irmaos. `data_anomaly_log` e a superficie de anomalia que o projeto ja le.
  IF jsonb_array_length(v_errors) > 0 THEN
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
    VALUES (
      'selection_rescue_cron_error',
      'warning',
      'process_pending_reschedule_nudges falhou para ' || jsonb_array_length(v_errors) || ' candidatura(s) nesta execucao',
      jsonb_build_object('cron', 'process_pending_reschedule_nudges', 'run_at', now(), 'errors', v_errors)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'examined', v_examined,
    'nudges_sent', v_nudges_sent,
    'escalations', v_escalations,
    'dispatch_cap', v_max_dispatches,
    'processed', v_processed,
    'escalated', v_escalated,
    'skipped', v_skipped,
    'errors', v_errors,
    'run_at', now()
  );
END;
$function$;
