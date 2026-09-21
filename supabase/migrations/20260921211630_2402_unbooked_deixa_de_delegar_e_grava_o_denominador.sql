-- #2402: o resgate de convite nao agendado deixa de delegar um caso que ninguem recebia.
--
-- O BURACO, medido em 21/09/2026.
--   O predicado deste cron excluia quem tivesse `interview_reschedule_requested_at` preenchido, com
--   o comentario "reschedule em curso = job33 cuida". O job33 e
--   `process_pending_reschedule_nudges`, e ele NAO cuidava: so cutuca e escala, nunca redespacha.
--   E o irmao `_selection_stuck_scheduled_rescue_cron` exige `status = 'interview_scheduled'` mais
--   uma entrevista `scheduled` vencida.
--   ⇒ Uma candidatura `interview_pending`, com a flag ligada e ZERO entrevistas, nao era vista por
--   nenhum dos tres: o primeiro delegava, o segundo nao alcancava, o terceiro so avisava.
--
--   Sobre as 15 candidaturas `interview_pending` em ciclo aberto, cada clausula reprovando:
--     sem e-mail .......................... 0
--     carencia de 10 dias nao vencida .... 13
--     cap automatico (`< 1`) estourado .... 3
--     flag de reagendamento ............... 3   <- esta clausula
--     ja tem slot futuro .................. 0
--     ELEGIVEIS ........................... 0
--
--   E a flag quase nunca se desliga: `request_interview_reschedule` grava `now()`, NENHUMA funcao
--   grava NULL, e o unico ponto que limpa em todo o repositorio e `src/pages/api/calendar-webhook.ts`,
--   isto e, o candidato conseguir agendar. O mecanismo que resgata quem nao agenda era desligado
--   pelo proprio ato de pedir para reagendar.
--
--   Custo humano observado: 3 candidaturas paradas, uma delas com 19 aberturas do link de
--   agendamento e zero agendamento, diagnostico `abriu_e_nao_agendou` que o sistema so conseguiu
--   emitir depois do conserto da #2403.
--
-- A DECISAO, ratificada pelo dono em 21/09 (kit `decision-records-kit`: a ratificacao do humano E o
-- artefato): "Unbooked deixa de delegar e alcanca o caso".
--   Descartadas: fazer o job33 redespachar (mexeria no cron recem-consertado e juntaria dois tetos
--   diferentes no mesmo laco), dar dono a limpeza da flag (resolve por outro eixo e deixa o
--   predicado ainda delegando para ninguem), e nao mudar (a escalacao avisa, e avisar nao e
--   resgatar).
--
-- O QUE MUDA, e o que NAO muda.
--   (a) sai a clausula `interview_reschedule_requested_at IS NULL`;
--   (b) entra o DENOMINADOR `examined` no audit e no retorno, que e a outra metade do pedido da
--       #2402: "rescued_count: 0" nao distinguia fila vazia de fila errada;
--   (c) `rpc_version` passa a 'p2402', para o audit dizer qual versao rodou.
--   O CAP NAO MUDA. `interview_auto_rescue_count < 1` continua sendo o freio, e e ele que impede
--   este cron de insistir com quem ja recebeu resgate automatico.
--
-- GUARD. `tests/contracts/D3-auto-rescue.test.mjs` afirmava sobre `20260805000219`, o arquivo que
-- CRIOU a funcao, enquanto o corpo vivo vinha de `20260805000511` desde as correcoes da #1599:
-- md5 `31656212...` contra `0a5fc39d...`, medido. Estava verde afirmando texto morto. Ele passa a
-- ler `latestFunctionCapture`, e a assercao sobre a clausula roda com COMENTARIO MASCARADO, porque
-- este cabecalho cita a clausula removida e um match sobre o corpo cru casaria o comentario.
--
-- Cross-ref: #2402, #2403 (a escalacao que voltou a funcionar), #1586, #1599, #1590.

CREATE OR REPLACE FUNCTION public._selection_unbooked_rescue_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_app       record;
  v_result    jsonb;
  v_rescued   int := 0;
  -- #2402 o DENOMINADOR. "rescued_count: 0" nao distingue fila vazia de fila errada, que e o
  -- titulo desta issue. So a contagem de quem o laco EXAMINOU separa as duas.
  v_examined  int := 0;
  v_refused   int := 0;
  v_errors    int := 0;
  v_error_rows   jsonb := '[]'::jsonb;
  v_refusal_rows jsonb := '[]'::jsonb;
  v_run_at    timestamptz := now();
  v_grace     interval;
BEGIN
  -- Config-driven grace (fallback literal se a row sumir) — padrão J4 / detector #781.
  SELECT value_interval INTO v_grace FROM public.sla_policies WHERE policy_key = 'interview_booking_grace';
  IF v_grace IS NULL THEN v_grace := interval '10 days'; END IF;

  FOR v_app IN
    SELECT a.id AS app_id
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status = 'interview_pending'                          -- matches the rescue RPC status guard
      AND c.status = 'open'
      AND a.cutoff_approved_email_sent_at IS NOT NULL             -- data-architect blocker 2 (explícito)
      AND a.cutoff_approved_email_sent_at < now() - v_grace       -- ancora no ÚLTIMO convite, não na idade do problema
      AND a.interview_auto_rescue_count < 1                       -- cap=1
      -- #2402: aqui havia `AND a.interview_reschedule_requested_at IS NULL`, com o comentario
      -- "reschedule em curso = job33 cuida". O job33 NAO cuidava: ele so cutuca e escala, e
      -- alem disso o predicado dele exige `interview_status = 'needs_reschedule'`. Uma
      -- candidatura `interview_pending`, com a flag ligada e ZERO entrevistas, ficava sem dono:
      -- este cron delegava e o irmao `_selection_stuck_scheduled_rescue_cron` exige
      -- `interview_scheduled`, entao nao alcancava. Medido em 21/09/2026: 3 candidaturas nesse
      -- estado, uma delas com 19 aberturas do link e zero agendamento.
      -- A flag tambem quase nunca se desliga: `request_interview_reschedule` grava `now()`,
      -- NENHUMA funcao grava NULL, e o unico ponto que limpa em todo o repositorio e
      -- `src/pages/api/calendar-webhook.ts`, isto e, o candidato conseguir agendar. O
      -- mecanismo que resgata quem nao agenda era desligado pelo ato de pedir para reagendar.
      -- Decisao do dono, ratificada em 21/09: o unbooked deixa de delegar e passa a alcancar.
      -- O cap acima (`interview_auto_rescue_count < 1`) continua sendo o freio.
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_interviews si
        WHERE si.application_id = a.id
          AND si.status IN ('scheduled', 'rescheduled')
          AND si.scheduled_at > now()                            -- já tem slot futuro = não está preso
      )
    ORDER BY a.cutoff_approved_email_sent_at ASC                  -- convite mais antigo primeiro
    LIMIT 20                                                       -- small-cohort cap
  LOOP
    v_examined := v_examined + 1;

    -- Per-row subtransaction: uma falha (ex. CUTOFF_NO_BOOKING_URL no re-dispatch, que rola aquele
    -- rescue back atomicamente) nunca aborta o run inteiro.
    BEGIN
      v_result := public.selection_rescue_unbooked_invite(v_app.app_id);

      -- #1599 correção 2 — recusa de gate NÃO é resgate. Aqui isto é o caso vivo: este cron é o
      -- que roda em modo `full`, e recusa é o desfecho ESPERADO para quem não tem análise de IA.
      IF COALESCE((v_result->>'success')::boolean, false) IS TRUE THEN
        v_rescued := v_rescued + 1;
      ELSE
        v_refused := v_refused + 1;
        v_refusal_rows := v_refusal_rows || jsonb_build_object(
          'application_id', v_app.app_id,
          'reason', v_result->>'reason',
          'gate_failed_code', v_result->>'gate_failed_code',
          'gate_failed_reason', v_result->>'gate_failed_reason'
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
      v_error_rows := v_error_rows || jsonb_build_object(
        'application_id', v_app.app_id,
        'sqlstate', SQLSTATE,
        'sqlerrm', SQLERRM
      );
    END;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.unbooked_rescue_cron_run', 'system', NULL,
    jsonb_build_object('examined', v_examined, 'rescued_count', v_rescued, 'refused_count', v_refused, 'error_count', v_errors),
    jsonb_build_object(
      'examined', v_examined,
      'rescued_count', v_rescued,
      'refused_count', v_refused,
      'error_count', v_errors,
      'errors', v_error_rows,
      'refusals', v_refusal_rows,
      'run_at', v_run_at,
      'grace_days', round(EXTRACT(EPOCH FROM v_grace) / 86400.0, 1),
      'limit', 20,
      'rpc_version', 'p2402'
    )
  );

  IF v_errors > 0 THEN
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
    VALUES (
      'selection_rescue_cron_error',
      'warning',
      'selection_rescue_unbooked_invite falhou para ' || v_errors || ' candidatura(s) nesta execução',
      jsonb_build_object('cron', '_selection_unbooked_rescue_cron', 'run_at', v_run_at, 'errors', v_error_rows)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'examined', v_examined,
    'rescued_count', v_rescued,
    'refused_count', v_refused,
    'error_count', v_errors,
    'errors', v_error_rows,
    'refusals', v_refusal_rows,
    'run_at', v_run_at
  );
END;
$function$;