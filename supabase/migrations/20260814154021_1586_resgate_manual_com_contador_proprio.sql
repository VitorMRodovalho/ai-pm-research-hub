-- #1586 — o resgate manual ganha contador PRÓPRIO, e com ele um autor.
--
-- O defeito da issue não é o cap, é a AUSÊNCIA de superfície: para re-convidar uma candidatura em
-- `interview_pending` só havia SQL direto, e por ali a conexão é `service_role`, a função entra no
-- ramo `v_is_cron` e o `admin_audit_log` grava `actor_id = NULL` com `dispatch_source: 'cron'` —
-- registra ato do sistema o que foi decisão de uma pessoa. Medido em 03/08/2026 (3 candidaturas) e
-- outra vez em 13/08/2026.
--
-- Mas expor a RPC no MCP, sozinho, não resolveria: medido em 14/08/2026, 7 das 10 candidaturas em
-- `interview_pending` do ciclo aberto já têm `interview_auto_rescue_count >= 1`, e o guard levanta
-- exceção nesse caso. Uma superfície entregue assim recusaria 7 dos 10 casos que ela mostra.
--
-- ⚖️ Decisão do PM (14/08/2026): contador SEPARADO para o resgate manual, com cap 3.
--
-- O racional, que precisa sobreviver a esta migration: o invariante `AI_unbooked_rescue_cap_respected`
-- trata `interview_auto_rescue_count > 1` como violação de schema (baseline 0). Esse cap de 1 é do
-- CRON — existe para o despacho automático não insistir sozinho. Um resgate feito por uma PESSOA,
-- com autor autenticado e linha de auditoria, é outro ato, e por isso conta em coluna própria. Assim
-- o invariante fica intacto e os 7 casos se resolvem.
--
-- O cap manual de 3 é rede de segurança, não o controle principal: o controle é o autor no log.
-- Bloquear em 1 recriaria o mesmo atrito uma volta adiante, e é exatamente o atrito que empurrou o
-- operador para o caminho sem autor.

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS interview_manual_rescue_count integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.selection_applications.interview_manual_rescue_count IS
  '#1586: re-convites de candidatura nao-agendada disparados por uma PESSOA (cap 3), separados de '
  'interview_auto_rescue_count (cap 1, do cron). A separacao mantem o invariante '
  'AI_unbooked_rescue_cap_respected valido para o caminho automatico.';

CREATE OR REPLACE FUNCTION public.selection_rescue_unbooked_invite(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
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
  v_cap           int;
  v_used          int;
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

  -- #1586 — o cap é lido do contador do CAMINHO, não de um contador só.
  -- Automático: cap 1, e o invariante AI_unbooked_rescue_cap_respected vigia essa coluna.
  -- Manual: cap 3, em coluna própria, porque o ato tem autor e linha de auditoria.
  -- A escalada além do cap continua sendo responsabilidade do detector (#781), não deste path.
  IF v_is_cron THEN
    v_cap := 1;
    v_used := v_app.interview_auto_rescue_count;
  ELSE
    v_cap := 3;
    v_used := v_app.interview_manual_rescue_count;
  END IF;

  IF v_used >= v_cap THEN
    RAISE EXCEPTION 'Application % already rescued % time(s) via the % path — cap % reached (escalation is the detector''s job)',
      p_application_id, v_used, CASE WHEN v_is_cron THEN 'automatic' ELSE 'manual' END, v_cap
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
      'new_count', v_used,
      'rescue_path', CASE WHEN v_is_cron THEN 'automatic' ELSE 'manual' END,
      'cap', v_cap,
      'gate_failed_code', v_notify->>'gate_failed_code',
      'gate_failed_reason', v_notify->>'gate_failed_reason',
      'message', v_notify->>'message',
      'trigger_type', v_trigger_type,
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END
    );
  END IF;

  -- Sucesso: agora sim o cap é consumido — no contador do caminho que despachou.
  -- Os dois ramos existem separados de propósito: o literal do incremento automático é o que o
  -- contrato do #1598 casa para provar que a mutação vem DEPOIS do despacho.
  IF v_is_cron THEN
    UPDATE public.selection_applications
    SET interview_auto_rescue_count = interview_auto_rescue_count + 1,
        updated_at = now()
    WHERE id = p_application_id;
  ELSE
    UPDATE public.selection_applications
    SET interview_manual_rescue_count = interview_manual_rescue_count + 1,
        updated_at = now()
    WHERE id = p_application_id;
  END IF;

  -- Audit row (lands only on full success; actor NULL in cron context). metadata legal-counsel R4.
  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.unbooked_invite_rescued',
    'selection_application',
    p_application_id,
    CASE WHEN v_is_cron
      THEN jsonb_build_object('interview_auto_rescue_count_after', v_used + 1)
      ELSE jsonb_build_object('interview_manual_rescue_count_after', v_used + 1)
    END,
    jsonb_build_object(
      'legal_basis', 'LGPD Art. 7º II — procedimento preliminar de seleção voluntária',
      'trigger_type', v_trigger_type,
      'attempt_number', v_used + 1,
      'rescue_path', CASE WHEN v_is_cron THEN 'automatic' ELSE 'manual' END,
      'cap', v_cap,
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
      'cycle_id', v_app.cycle_id,
      'redispatch', v_notify->>'resolution_path',
      'gate_mode', v_notify->>'gate_mode',
      'rpc_version', 'p1586'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'new_count', v_used + 1,
    'cap_consumed', true,
    'rescue_path', CASE WHEN v_is_cron THEN 'automatic' ELSE 'manual' END,
    'cap', v_cap,
    'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
    'trigger_type', v_trigger_type,
    'redispatch', v_notify
  );
END;
$function$;

-- `CREATE FUNCTION` nasce com EXECUTE para PUBLIC: esta RPC DESPACHA E-MAIL a candidato real.
REVOKE ALL ON FUNCTION public.selection_rescue_unbooked_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.selection_rescue_unbooked_invite(uuid) TO authenticated, service_role;
