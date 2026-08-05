-- #1598 + #1599 — a cauda do arco #1594/#1595, no mesmo caminho de resgate.
--
-- ============================================================================
-- #1598 — os 2 rescues não checam o retorno do notify (regressão do próprio #1594)
-- ----------------------------------------------------------------------------
-- O #1594 fez a recusa de gate parar de LEVANTAR e passar a devolver `{success:false}`, para que a
-- linha de `gate_attempts` commite. O inventário de consumidores daquele PR cobriu
-- `_selection_cutoff_pending_cron`, `admin/selection.astro` e o `nucleo-mcp` — e NÃO cobriu os dois
-- rescues, que também chamam `notify_selection_cutoff_approved`.
--
-- Medido ao vivo antes desta DDL, com o helper de classe do #1595:
--
--   _audit_functions_matching('notify_selection_cutoff_approved')  -> 4 funções
--   _audit_functions_matching('->>\s*''success''')                 -> não contém os 2 rescues
--
-- Os dois dependiam da EXCEÇÃO para atomicidade, e o corpo dizia isso em letra:
--   "Not wrapped in EXCEPTION — if notify RAISEs, the whole rescue rolls back (atomic), so the
--    cancel + reset never persist orphaned."
-- Essa proteção deixou de existir para RECUSA. Numa recusa hoje:
--   · stuck_interview  — cancela a entrevista, joga a candidatura de volta para interview_pending,
--                        limpa a idempotência, e NÃO manda e-mail. O candidato perde o slot calado.
--   · unbooked_invite  — incrementa `interview_auto_rescue_count` e limpa a idempotência,
--                        QUEIMANDO o cap=1 sem e-mail. A pessoa perde a única tentativa automática.
--
-- ⚠️ Exposição real, medida: `stuck_interview` é quase imune por construção — exige uma linha em
-- `selection_interviews`, que é justamente o gatilho do modo `reuse_prior` (#1595), que não
-- reavalia os 3 gates. A checagem lá é DEFENSIVA e existe para que o padrão seja um só.
-- `unbooked_invite` é o caso vivo: dispara para `interview_pending` que nunca agendou, logo sem
-- linha de entrevista, logo modo `full`, logo sujeito a recusa.
--
-- Correção: a ordem do #1595 em `request_interview_reschedule` — tentar o despacho ANTES de
-- escrever, e sair sem tocar em nada se ele recusar. NÃO pode virar `RAISE`: isso desfaria a linha
-- de `gate_attempts` que o #1594 existe para produzir (SPEC_INTERVIEW_BOOKING_INTEGRITY §4.0).
--
-- ⚠️ O detalhe que obriga o "clear + restore": `notify_selection_cutoff_approved` tem guarda de
-- idempotência no TOPO (`cutoff_approved_email_sent_at IS NOT NULL` → devolve `email_sent:false`).
-- Chamá-lo sem limpar o carimbo devolveria um sucesso VAZIO. Então o carimbo é limpo antes, e
-- RESTAURADO na recusa — deixando a linha byte-idêntica ao que era. `updated_at` não é tocado no
-- caminho de recusa de propósito: o cron do stuck ordena por `updated_at ASC` (mais preso
-- primeiro), e bumpar a coluna numa recusa jogaria a candidatura presa para o FIM da fila,
-- fazendo-a passar fome exatamente enquanto o problema persiste.
--
-- ============================================================================
-- #1599 — os crons de resgate engolem a mensagem do erro
-- ----------------------------------------------------------------------------
-- `selection-stuck-scheduled-rescue-daily` roda `succeeded` no `cron.job_run_details` todos os
-- dias e grava `error_count: 1` no `admin_audit_log`. Medido: SEIS execuções consecutivas com
-- erro (30/07, 31/07, 01/08, 02/08, 03/08, 04/08) — a issue dizia 4+; são 6.
--
-- O laço envolve cada linha em `BEGIN ... EXCEPTION WHEN OTHERS THEN v_errors := v_errors + 1; END`
-- e DESCARTA o `SQLERRM`. Seis dias de falha e zero informação sobre a causa. A causa histórica é
-- portanto IRRECUPERÁVEL — o corpo vivo do `notify` foi reescrito duas vezes desde então (#1584 às
-- 17:19 e #1594/#1595 às 19:50 de 04/08, ambos DEPOIS do último run vermelho das 15:00 UTC) e a
-- mensagem nunca foi gravada. Sonda transacional (abortada, nada commitado) confirma que a mesma
-- chamada SUCEDE hoje. Não se atribui a correção a um commit específico por falta de prova: o que
-- esta migration garante é que a PRÓXIMA falha seja diagnosticável.
--
-- Correções:
--   1. `EXCEPTION WHEN OTHERS` guarda SQLERRM + SQLSTATE + application_id num array, e o audit
--      grava `errors: [...]` além do contador. Padrão que `process_pending_reschedule_nudges` já usa.
--   2. Os crons passam a checar o RETORNO do rescue e contar `refused_count` separado de
--      `rescued_count`. Sem isto, a correção do #1598 acima criaria o MESMO defeito um nível acima:
--      o `PERFORM` cego contaria uma RECUSA como resgate. É a armadilha do #1594 se repetindo no
--      consumidor — mesma classe, outro andar.
--   3. `error_count > 0` deixa de ser invisível: vira linha em `data_anomaly_log`, a superfície de
--      anomalia que o projeto já lê, em vez de um contador que só existe dentro do audit.
--
-- ROLLBACK: reaplicar os corpos da mig 20260805000104 (stuck) e 20260805000219 (unbooked).
-- ============================================================================


-- ============================================================================
-- 1. selection_rescue_stuck_interview — despacha ANTES de cancelar
-- ============================================================================
CREATE OR REPLACE FUNCTION public.selection_rescue_stuck_interview(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller          public.members%ROWTYPE;
  v_is_cron         boolean := false;
  v_app             public.selection_applications%ROWTYPE;
  v_interview       public.selection_interviews%ROWTYPE;
  v_notify          jsonb;
  v_prior_sent_at   timestamptz;
BEGIN
  -- Caller resolution + cron-aware gate (council Option B / ADR-0028).
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    IF current_setting('request.jwt.claims', true) IS NULL OR auth.role() = 'service_role' THEN
      v_is_cron := true;  -- pg_cron / service-role context; v_caller stays NULL (system actor)
    ELSE
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- Authority gate — skip in cron/service context (the service_role-only wrapper IS the gate).
  IF NOT v_is_cron THEN
    IF NOT (
      public.can_by_member(v_caller.id, 'manage_member'::text)
      OR EXISTS (
        SELECT 1 FROM public.selection_committee
        WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
      )
    ) THEN
      RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
    END IF;
  END IF;

  -- Rescue is valid ONLY for a genuinely stuck application (status interview_scheduled).
  -- Guards against re-inviting an app that already advanced (interview_done / final_eval /
  -- approved / rejected / waitlist) but still carries a stale past-scheduled interview row —
  -- which would otherwise discard completed scoring and email a decided candidate. Matches the
  -- meta.interview_stuck predicate (mig 103) that gates the F2 chip + F4 button, and the Wave 2b
  -- cron must filter app.status='interview_scheduled' to avoid calling into this RAISE.
  IF v_app.status <> 'interview_scheduled' THEN
    RAISE EXCEPTION 'Application % is in status % — rescue only valid from interview_scheduled', p_application_id, v_app.status
      USING ERRCODE = 'P0023';
  END IF;

  -- Find the stuck interview: latest scheduled, past, never conducted.
  SELECT * INTO v_interview
  FROM public.selection_interviews
  WHERE application_id = p_application_id
    AND status = 'scheduled'
    AND conducted_at IS NULL
    AND scheduled_at IS NOT NULL
    AND scheduled_at < now()
  ORDER BY scheduled_at DESC
  LIMIT 1;

  IF v_interview IS NULL THEN
    RAISE EXCEPTION 'No stuck interview for application % (need a scheduled, past, not-conducted interview row)', p_application_id
      USING ERRCODE = 'P0022';
  END IF;

  -- ==========================================================================
  -- Step 1 (#1598) — RE-DESPACHO PRIMEIRO. A ordem inverteu de propósito.
  -- --------------------------------------------------------------------------
  -- Antes: cancelava a entrevista, resetava a candidatura e SÓ ENTÃO chamava o notify, confiando
  -- na exceção dele para desfazer tudo. Depois do #1594 a recusa não levanta mais, então o cancel
  -- + reset persistiam SEM e-mail: o candidato perdia o slot e não era avisado.
  --
  -- O carimbo de idempotência precisa cair ANTES da chamada (o notify devolve `already_sent` e não
  -- despacha se ele estiver preenchido) e é RESTAURADO na recusa, para que a recusa não deixe
  -- rastro nenhum na linha. `updated_at` fica intocado no caminho de recusa — ver cabeçalho.
  -- ==========================================================================
  v_prior_sent_at := v_app.cutoff_approved_email_sent_at;

  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = NULL
  WHERE id = p_application_id;

  v_notify := public.notify_selection_cutoff_approved(p_application_id);

  IF COALESCE((v_notify->>'success')::boolean, false) IS NOT TRUE THEN
    -- Recusa de gate. Devolver o carimbo e sair SEM cancelar a entrevista e SEM mexer no status:
    -- a candidatura fica exatamente como estava, e a linha de `gate_attempts` que o core acabou de
    -- gravar sobrevive porque esta transação commita (RETURN, nunca RAISE — #1594).
    UPDATE public.selection_applications
    SET cutoff_approved_email_sent_at = v_prior_sent_at
    WHERE id = p_application_id;

    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'reason', 'gate_refused',
      'rescued', false,
      'interview_cancelled', false,
      'gate_failed_code', v_notify->>'gate_failed_code',
      'gate_failed_reason', v_notify->>'gate_failed_reason',
      'message', v_notify->>'message',
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END
    );
  END IF;

  -- Step 2: cancel the stuck interview (the transition trigger ignores 'cancelled').
  UPDATE public.selection_interviews
  SET status = 'cancelled',
      notes = COALESCE(notes || E'\n', '') ||
              '[rescue ' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24:MI') ||
              ': convite não aceito — reenvio automático do convite de agendamento]'
  WHERE id = v_interview.id;

  -- Step 3: send the application back to interview_pending so it re-enters the invite queue
  -- (mirrors mark_interview_status cancel path). The status guard above already pinned the app
  -- to interview_scheduled, so this only ever moves interview_scheduled -> interview_pending.
  UPDATE public.selection_applications
  SET status = 'interview_pending', updated_at = now()
  WHERE id = p_application_id
    AND status = 'interview_scheduled';

  -- Success audit row (lands only on full success; actor NULL in cron context).
  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.stuck_interview_rescued',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'interview_id', v_interview.id,
      'interview_status_before', 'scheduled',
      'interview_status_after', 'cancelled'
    ),
    jsonb_build_object(
      'interview_id', v_interview.id,
      'prior_scheduled_at', v_interview.scheduled_at,
      'cycle_id', v_app.cycle_id,
      'new_dispatch_path', v_notify->>'resolution_path',
      'resolved_evaluator_id', v_notify->>'resolved_evaluator_id',
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
      'gate_mode', v_notify->>'gate_mode',
      'rpc_version', 'p1598'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'cancelled_interview_id', v_interview.id,
    'prior_scheduled_at', v_interview.scheduled_at,
    'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
    'redispatch', v_notify
  );
END;
$function$;

COMMENT ON FUNCTION public.selection_rescue_stuck_interview(uuid) IS
  'Resgata candidatura presa em interview_scheduled com entrevista passada nunca conduzida. #1598: '
  'o re-despacho acontece ANTES do cancel/reset — na recusa de gate a candidatura fica intacta e a '
  'função devolve {success:false}, nunca levanta (a linha de gate_attempts precisa commitar).';

REVOKE ALL ON FUNCTION public.selection_rescue_stuck_interview(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.selection_rescue_stuck_interview(uuid) TO authenticated, service_role;


-- ============================================================================
-- 2. selection_rescue_unbooked_invite — despacha ANTES de queimar o cap
-- ============================================================================
CREATE OR REPLACE FUNCTION public.selection_rescue_unbooked_invite(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller        public.members%ROWTYPE;
  v_is_cron       boolean := false;
  v_app           public.selection_applications%ROWTYPE;
  v_cycle         public.selection_cycles%ROWTYPE;
  v_notify        jsonb;
  v_trigger_type  text;
  v_has_interview boolean;
  v_prior_sent_at timestamptz;
BEGIN
  -- Caller resolution + cron-aware gate (council Option B / ADR-0028; verbatim ladder da mig 104).
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    IF current_setting('request.jwt.claims', true) IS NULL OR auth.role() = 'service_role' THEN
      v_is_cron := true;  -- pg_cron / service-role context; v_caller stays NULL (system actor)
    ELSE
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- Authority gate — skip in cron/service context (the service_role-only wrapper IS the gate).
  IF NOT v_is_cron THEN
    IF NOT (
      public.can_by_member(v_caller.id, 'manage_member'::text)
      OR EXISTS (
        SELECT 1 FROM public.selection_committee
        WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
      )
    ) THEN
      RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
    END IF;
  END IF;

  -- Guard ciclo (data-architect blocker 1): só re-convidar em ciclo aberto.
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;
  IF v_cycle.status <> 'open' THEN
    RAISE EXCEPTION 'Rescue only valid for open cycle (cycle % is %)', v_app.cycle_id, v_cycle.status;
  END IF;

  -- Guard status: só de interview_pending (convite envelhecido). Outros status já avançaram.
  IF v_app.status <> 'interview_pending' THEN
    RAISE EXCEPTION 'Application % is in status % — unbooked rescue only valid from interview_pending', p_application_id, v_app.status
      USING ERRCODE = 'P0024';
  END IF;

  -- Guard cap (=1): a escalada além do 1º re-convite é responsabilidade do detector (#781), não deste path.
  IF v_app.interview_auto_rescue_count >= 1 THEN
    RAISE EXCEPTION 'Application % already auto-rescued % time(s) — cap reached (escalation is the detector''s job)', p_application_id, v_app.interview_auto_rescue_count
      USING ERRCODE = 'P0025';
  END IF;

  -- Trigger type para audit (legal-counsel R3/R4): nunca agendou vs no-show.
  v_has_interview := EXISTS (
    SELECT 1 FROM public.selection_interviews si WHERE si.application_id = p_application_id
  );
  v_trigger_type := CASE WHEN v_has_interview THEN 'auto_rescue_noshow' ELSE 'auto_rescue_never_booked' END;

  -- ==========================================================================
  -- #1598 — RE-DESPACHO PRIMEIRO, incremento depois. Este é o caso VIVO da issue.
  -- --------------------------------------------------------------------------
  -- Este rescue dispara para `interview_pending` que nunca agendou: sem linha em
  -- `selection_interviews`, logo o core entra em modo `full` (#1595) e REAVALIA os 3 gates. Uma
  -- recusa aqui, na ordem antiga, incrementava `interview_auto_rescue_count` e limpava a
  -- idempotência sem mandar e-mail nenhum — queimando o cap=1 em silêncio, e com ele a única
  -- tentativa automática de re-convite daquela pessoa.
  --
  -- O carimbo cai antes (senão o notify devolve `already_sent` e não despacha) e volta na recusa.
  -- ==========================================================================
  v_prior_sent_at := v_app.cutoff_approved_email_sent_at;

  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = NULL
  WHERE id = p_application_id;

  v_notify := public.notify_selection_cutoff_approved(p_application_id);

  IF COALESCE((v_notify->>'success')::boolean, false) IS NOT TRUE THEN
    -- Recusa: devolver o carimbo, NÃO incrementar o contador, NÃO gravar audit de sucesso.
    -- RETURN e não RAISE — a linha de `gate_attempts` do core precisa commitar (#1594).
    UPDATE public.selection_applications
    SET cutoff_approved_email_sent_at = v_prior_sent_at
    WHERE id = p_application_id;

    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'reason', 'gate_refused',
      'rescued', false,
      'cap_consumed', false,
      'new_count', v_app.interview_auto_rescue_count,
      'gate_failed_code', v_notify->>'gate_failed_code',
      'gate_failed_reason', v_notify->>'gate_failed_reason',
      'message', v_notify->>'message',
      'trigger_type', v_trigger_type,
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END
    );
  END IF;

  -- Sucesso: agora sim o cap é consumido.
  UPDATE public.selection_applications
  SET interview_auto_rescue_count = interview_auto_rescue_count + 1,
      updated_at = now()
  WHERE id = p_application_id;

  -- Audit row (lands only on full success; actor NULL in cron context). metadata legal-counsel R4.
  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.unbooked_invite_rescued',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'interview_auto_rescue_count_after', v_app.interview_auto_rescue_count + 1
    ),
    jsonb_build_object(
      'legal_basis', 'LGPD Art. 7º II — procedimento preliminar de seleção voluntária',
      'trigger_type', v_trigger_type,
      'attempt_number', 1,
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
      'cycle_id', v_app.cycle_id,
      'redispatch', v_notify->>'resolution_path',
      'gate_mode', v_notify->>'gate_mode',
      'rpc_version', 'p1598'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'new_count', v_app.interview_auto_rescue_count + 1,
    'cap_consumed', true,
    'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
    'trigger_type', v_trigger_type,
    'redispatch', v_notify
  );
END;
$function$;

COMMENT ON FUNCTION public.selection_rescue_unbooked_invite(uuid) IS
  'Re-convida candidatura parada em interview_pending cujo último convite envelheceu (cap=1). '
  '#1598: o re-despacho acontece ANTES do incremento — uma recusa de gate não queima mais o cap '
  'em silêncio. Devolve {success:false, gate_failed_code} na recusa; nunca levanta por recusa.';

REVOKE ALL ON FUNCTION public.selection_rescue_unbooked_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.selection_rescue_unbooked_invite(uuid) TO authenticated, service_role;


-- ============================================================================
-- 3. _selection_stuck_scheduled_rescue_cron — grava a mensagem + separa recusa de erro
-- ============================================================================
CREATE OR REPLACE FUNCTION public._selection_stuck_scheduled_rescue_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_app       record;
  v_result    jsonb;
  v_rescued   int := 0;
  v_refused   int := 0;
  v_errors    int := 0;
  v_error_rows   jsonb := '[]'::jsonb;
  v_refusal_rows jsonb := '[]'::jsonb;
  v_run_at    timestamptz := now();
  v_grace     interval;
BEGIN
  SELECT value_interval INTO v_grace FROM public.sla_policies WHERE policy_key = 'stuck_scheduled_grace';
  IF v_grace IS NULL THEN v_grace := interval '48 hours'; END IF;

  FOR v_app IN
    SELECT a.id AS app_id
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status = 'interview_scheduled'        -- matches the rescue RPC status guard
      AND c.status = 'open'
      AND EXISTS (
        SELECT 1 FROM public.selection_interviews si
        WHERE si.application_id = a.id
          AND si.status = 'scheduled'
          AND si.conducted_at IS NULL
          AND si.scheduled_at IS NOT NULL
          AND si.scheduled_at < now() - v_grace
      )
    ORDER BY a.updated_at ASC                     -- oldest-stuck first
    LIMIT 20                                       -- small-cohort cap
  LOOP
    -- Per-row subtransaction: a single failure (e.g. CUTOFF_NO_BOOKING_URL on re-dispatch,
    -- which rolls that rescue back atomically) never aborts the run.
    BEGIN
      v_result := public.selection_rescue_stuck_interview(v_app.app_id);

      -- #1599 correção 2 — checar o RETORNO. Depois do #1598 a recusa de gate chega como
      -- `{success:false}` em vez de exceção: um `PERFORM` cego contaria RECUSA como resgate,
      -- que é a armadilha do #1594 se repetindo um andar acima.
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
      -- #1599 correção 1 — guardar a MENSAGEM. Seis execuções consecutivas gravaram
      -- `error_count: 1` e nada mais, e a causa daquelas seis é hoje irrecuperável.
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
    NULL, 'selection.stuck_rescue_cron_run', 'system', NULL,
    jsonb_build_object('rescued_count', v_rescued, 'refused_count', v_refused, 'error_count', v_errors),
    jsonb_build_object(
      'rescued_count', v_rescued,
      'refused_count', v_refused,
      'error_count', v_errors,
      'errors', v_error_rows,
      'refusals', v_refusal_rows,
      'run_at', v_run_at,
      'grace_hours', EXTRACT(EPOCH FROM v_grace) / 3600,
      'limit', 20,
      'rpc_version', 'p1599'
    )
  );

  -- #1599 correção 3 — um erro recorrente deixa de morrer dentro do audit. `data_anomaly_log` é a
  -- superfície de anomalia que o projeto já lê; um contador dentro de metadata não é lido por nada.
  IF v_errors > 0 THEN
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
    VALUES (
      'selection_rescue_cron_error',
      'warning',
      'selection_rescue_stuck_interview falhou para ' || v_errors || ' candidatura(s) nesta execução',
      jsonb_build_object('cron', '_selection_stuck_scheduled_rescue_cron', 'run_at', v_run_at, 'errors', v_error_rows)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'rescued_count', v_rescued,
    'refused_count', v_refused,
    'error_count', v_errors,
    'errors', v_error_rows,
    'refusals', v_refusal_rows,
    'run_at', v_run_at
  );
END;
$function$;

COMMENT ON FUNCTION public._selection_stuck_scheduled_rescue_cron() IS
  'Cron diário do resgate de entrevista presa. #1599: grava SQLERRM/SQLSTATE por candidatura em '
  'vez de só o contador, conta recusa de gate separado de resgate (#1598), e levanta linha em '
  'data_anomaly_log quando erra — seis execuções silenciosas foram o defeito que motivou isto.';

REVOKE ALL ON FUNCTION public._selection_stuck_scheduled_rescue_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_stuck_scheduled_rescue_cron() TO service_role;


-- ============================================================================
-- 4. _selection_unbooked_rescue_cron — mesma correção
-- ============================================================================
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
      AND a.interview_reschedule_requested_at IS NULL             -- reschedule em curso = job33 cuida
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_interviews si
        WHERE si.application_id = a.id
          AND si.status IN ('scheduled', 'rescheduled')
          AND si.scheduled_at > now()                            -- já tem slot futuro = não está preso
      )
    ORDER BY a.cutoff_approved_email_sent_at ASC                  -- convite mais antigo primeiro
    LIMIT 20                                                       -- small-cohort cap
  LOOP
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
    jsonb_build_object('rescued_count', v_rescued, 'refused_count', v_refused, 'error_count', v_errors),
    jsonb_build_object(
      'rescued_count', v_rescued,
      'refused_count', v_refused,
      'error_count', v_errors,
      'errors', v_error_rows,
      'refusals', v_refusal_rows,
      'run_at', v_run_at,
      'grace_days', round(EXTRACT(EPOCH FROM v_grace) / 86400.0, 1),
      'limit', 20,
      'rpc_version', 'p1599'
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
    'rescued_count', v_rescued,
    'refused_count', v_refused,
    'error_count', v_errors,
    'errors', v_error_rows,
    'refusals', v_refusal_rows,
    'run_at', v_run_at
  );
END;
$function$;

COMMENT ON FUNCTION public._selection_unbooked_rescue_cron() IS
  'Cron do re-convite de candidatura que nunca agendou (cap=1). #1599: grava SQLERRM/SQLSTATE por '
  'candidatura e conta recusa de gate separado de resgate — este é o cron que roda em modo `full`, '
  'onde recusa é desfecho esperado para quem não tem análise de IA (#1598).';

REVOKE ALL ON FUNCTION public._selection_unbooked_rescue_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_unbooked_rescue_cron() TO service_role;

NOTIFY pgrst, 'reload schema';
