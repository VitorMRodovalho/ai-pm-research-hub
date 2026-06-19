-- ÉPICO D (funil de seleção sem enterrados) — D3 auto-rescue de candidato convidado-preso.
-- "Fecha o loop": só o 1º convite de agendamento é automático (job51 / notify_selection_cutoff_approved
-- quando cutoff_approved_email_sent_at IS NULL). Depois disso NADA re-dispara por envelhecimento — um
-- aprovado que recebeu o convite e nunca agendou fica preso em interview_pending, invisível a todos os
-- crons de ação. O detector #781 (job60) apenas NOTIFICA o GP. Esta migration adiciona o auto-rescue:
-- re-convite automático ancorado no ÚLTIMO convite (cutoff_approved_email_sent_at), cap=1, depois escala
-- ao GP. unbooked + no-show unificados (ambos = "convite envelhecido sem slot futuro").
--
-- SPEC: docs/specs/SPEC_D3_AUTO_RESCUE_UNBOOKED.md (council GO-with-changes aplicado).
-- Coorte viva (medida 2026-06-18): Hector Rigon (app c78b885b, convite 27/05, 23d, nunca agendou) = o
-- caso indisputável; Edinan/Bruna NÃO (re-convidados há ~2d, dentro do grace).
--
-- Decisões PM (2026-06-18): unbooked + no-show unificados (ancora no último convite, não na idade do
--   problema); cap=1 auto-rescue (1º convite job51 + 1 re-convite; depois escala ao GP).
-- Council: data-architect GO-w-changes (3 blockers: guard ciclo open na RPC; cutoff IS NOT NULL explícito
--   no cron; bucket B do detector ancora no cutoff — mesmo PR) + legal-counsel GO-w-changes (base legal
--   Art. 7º II = procedimento preliminar de seleção, igual D7).
--
-- 🔴 GO-LIVE GATED: o cron _selection_unbooked_rescue_cron() é CRIADO mas NÃO AGENDADO nesta migration.
--   O agendamento depende dos gates legais: R1 (template selection_cutoff_approved ganha linha de "saída
--   por inação", revisão de copy pelo PM) + R5 (verificar DPA/cadeia de operadores do provedor do link de
--   booking). Agendar via follow-up — ver COMMENT na seção 3.
--
-- COMPONENTES (5 blocos):
--   1. Coluna selection_applications.interview_auto_rescue_count int NOT NULL DEFAULT 0 (cap=1).
--   2. RPC selection_rescue_unbooked_invite(uuid) — SECDEF cron-aware (espelha selection_rescue_stuck_interview).
--   3. Cron _selection_unbooked_rescue_cron() — SECDEF service-role-only, NÃO agendado (go-live gated).
--   4. Fix detector detect_stuck_selection_funnel: bucket B ancora no cutoff (não notifica no-show já re-convidado).
--   5. check_schema_invariants(): + invariante AI_unbooked_rescue_cap_respected (35 -> 36).
--
-- ROLLBACK:
--   -- (se o cron tiver sido agendado por follow-up:) SELECT cron.unschedule('selection-unbooked-rescue-daily');
--   DROP FUNCTION IF EXISTS public._selection_unbooked_rescue_cron();
--   DROP FUNCTION IF EXISTS public.selection_rescue_unbooked_invite(uuid);
--   ALTER TABLE public.selection_applications DROP COLUMN IF EXISTS interview_auto_rescue_count;
--   -- detector + check_schema_invariants: re-aplicar o corpo da mig 208 / 216 (reverter os 2 splices).
--   NOTIFY pgrst, 'reload schema';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Coluna nova — contador de re-convites automáticos (cap=1).
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS interview_auto_rescue_count int NOT NULL DEFAULT 0;
COMMENT ON COLUMN public.selection_applications.interview_auto_rescue_count IS
  're-convites automáticos já disparados por _selection_unbooked_rescue_cron (cap=1). NÃO conta o 1º convite do job51 — conta apenas re-envios deste path. D3 auto-rescue, mig 20260805000219.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. RPC selection_rescue_unbooked_invite(uuid) — atomic re-invite of an unbooked/no-show
--    candidate parked in interview_pending. SECDEF + cron-aware gate (council Option B / ADR-0028,
--    espelha selection_rescue_stuck_interview da mig 104). Atomic: notify NÃO em bloco EXCEPTION —
--    se RAISE, rola tudo back. Cap=1 (RAISE P0025 ao reentrar). Guards: ciclo open, status
--    interview_pending (P0024), cap (P0025).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.selection_rescue_unbooked_invite(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller       public.members%ROWTYPE;
  v_is_cron      boolean := false;
  v_app          public.selection_applications%ROWTYPE;
  v_cycle        public.selection_cycles%ROWTYPE;
  v_notify       jsonb;
  v_trigger_type text;
  v_has_interview boolean;
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

  -- Incrementa o contador + limpa o guard de idempotência do notify (re-arma o re-envio).
  UPDATE public.selection_applications
  SET interview_auto_rescue_count = interview_auto_rescue_count + 1,
      cutoff_approved_email_sent_at = NULL,
      updated_at = now()
  WHERE id = p_application_id;

  -- Re-dispatch. NÃO envolvido em EXCEPTION — se notify RAISEs, a função inteira rola back (atômico),
  -- então o incremento + o reset nunca persistem órfãos.
  v_notify := public.notify_selection_cutoff_approved(p_application_id);

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
      'rpc_version', 'd3_auto_rescue_219'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'new_count', v_app.interview_auto_rescue_count + 1,
    'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
    'trigger_type', v_trigger_type,
    'redispatch', v_notify
  );
END;
$$;

REVOKE ALL ON FUNCTION public.selection_rescue_unbooked_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.selection_rescue_unbooked_invite(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.selection_rescue_unbooked_invite(uuid) IS
'D3 auto-rescue (mig 20260805000219): atomically re-invite an unbooked/no-show candidate parked in '
'interview_pending — increment interview_auto_rescue_count (cap=1, RAISE P0025 above), clear '
'cutoff_approved_email_sent_at, then re-dispatch via notify_selection_cutoff_approved (atomic: a notify '
'failure rolls the whole rescue back). Guards: open cycle; status interview_pending (P0024); cap (P0025). '
'Authority: committee lead OR manage_member (cron/service-role bypass per ADR-0028, actor_id NULL + '
'metadata.dispatch_source=cron). Audit action selection.unbooked_invite_rescued.';


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Cron _selection_unbooked_rescue_cron() — SECDEF service-role-only. Varre os apps
--    interview_pending de ciclo aberto cujo ÚLTIMO convite (cutoff_approved_email_sent_at)
--    envelheceu além do interview_booking_grace, ainda sob o cap (count<1), sem reschedule em
--    curso e sem slot futuro, e re-convida cada um via selection_rescue_unbooked_invite.
--    Per-row subtransação + LIMIT 20 (small-cohort cap, igual job52). Espelha
--    _selection_stuck_scheduled_rescue_cron (mig 107).
--
-- 🔴 GO-LIVE GATED: NÃO agendar até PM aprovar copy R1 (saída por inação no template
--    selection_cutoff_approved) + verificar DPA do provedor de booking (R5). Agendar via follow-up:
--    cron.schedule('selection-unbooked-rescue-daily','30 15 * * *',$$SELECT public._selection_unbooked_rescue_cron()$$);
--    — 15h30 UTC, ANTES do detector #781 (16h) para que o re-convite re-sete cutoff=now() e o
--    detector não notifique o GP sobre um caso que o auto-rescue acabou de tratar.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._selection_unbooked_rescue_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $func$
DECLARE
  v_app     record;
  v_rescued int := 0;
  v_errors  int := 0;
  v_run_at  timestamptz := now();
  v_grace   interval;
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
      PERFORM public.selection_rescue_unbooked_invite(v_app.app_id);
      v_rescued := v_rescued + 1;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.unbooked_rescue_cron_run', 'system', NULL,
    jsonb_build_object('rescued_count', v_rescued, 'error_count', v_errors),
    jsonb_build_object(
      'rescued_count', v_rescued,
      'error_count', v_errors,
      'run_at', v_run_at,
      'grace_days', round(EXTRACT(EPOCH FROM v_grace) / 86400.0, 1),
      'limit', 20
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'rescued_count', v_rescued,
    'error_count', v_errors,
    'run_at', v_run_at
  );
END;
$func$;

REVOKE ALL ON FUNCTION public._selection_unbooked_rescue_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_unbooked_rescue_cron() TO service_role;

COMMENT ON FUNCTION public._selection_unbooked_rescue_cron() IS
'D3 auto-rescue (mig 20260805000219): cron — re-invites every interview_pending app (open cycle) whose '
'last invite (cutoff_approved_email_sent_at) aged past interview_booking_grace, still under cap (count<1), '
'no reschedule in flight, no future slot, via selection_rescue_unbooked_invite. LIMIT 20/day, per-row '
'exception isolation, one aggregate audit row (selection.unbooked_rescue_cron_run). NOT SCHEDULED — '
'go-live gated on legal R1 (copy) + R5 (booking-provider DPA); schedule via follow-up at 15h30 UTC.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Fix detector detect_stuck_selection_funnel (data-architect blocker 3, mesmo PR): bucket B
--    (no-show) passa a exigir TAMBÉM cutoff_approved_email_sent_at < now() - v_booking_grace, para
--    não notificar o GP sobre um no-show JÁ re-convidado (o auto-rescue re-seta cutoff=now() → o
--    convite fresco não deve alertar). Corpo reproduzido VERBATIM da mig 208 + 1 linha (Phase-C:
--    esta mig 219 vira a captura mais recente; live pós-apply == este corpo).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.detect_stuck_selection_funnel(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_run_at        timestamptz := now();
  v_booking_grace interval;
  v_noshow_grace  interval;
  v_unbooked_apps int := 0;
  v_noshow_apps   int := 0;
  v_notified      int := 0;
BEGIN
  -- Config-driven windows (fallback ao literal se a row sumir) — padrao J4.
  SELECT value_interval INTO v_booking_grace FROM public.sla_policies WHERE policy_key = 'interview_booking_grace';
  IF v_booking_grace IS NULL THEN v_booking_grace := interval '10 days'; END IF;
  SELECT value_interval INTO v_noshow_grace FROM public.sla_policies WHERE policy_key = 'noshow_recovery_grace';
  IF v_noshow_grace IS NULL THEN v_noshow_grace := interval '3 days'; END IF;

  WITH active_cycle AS (
    SELECT id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1
  ),
  stuck AS (
    -- Bucket A — invited_never_booked (= D5): convidado, sem nenhuma linha de
    -- entrevista, envelhecido alem do booking grace. interview_reschedule_requested_at
    -- IS NULL exclui quem esta no fluxo de reschedule (job33 cuida).
    SELECT
      a.id AS application_id,
      'selection_candidate_unbooked'::text AS n_type,
      'Candidato convidado ainda sem agendar entrevista'::text AS n_title,
      format(
        '%s foi convidado(a) ha %s dia%s e ainda nao agendou a entrevista (sem agendamento registrado). Abra a candidatura em /admin/selection para re-convidar ou encerrar.',
        COALESCE(NULLIF(trim(a.applicant_name), ''),
                 NULLIF(trim(a.first_name || ' ' || COALESCE(a.last_name, '')), ''),
                 'Candidato'),  -- sem email no body (LGPD minimizacao; nome cobre 100% + link identifica)
        EXTRACT(DAY FROM now() - a.cutoff_approved_email_sent_at)::int,
        CASE WHEN EXTRACT(DAY FROM now() - a.cutoff_approved_email_sent_at)::int = 1 THEN '' ELSE 's' END
      ) AS n_body
    FROM public.selection_applications a
    WHERE a.cycle_id = (SELECT id FROM active_cycle)
      AND a.status = 'interview_pending'
      AND a.cutoff_approved_email_sent_at IS NOT NULL
      AND a.interview_reschedule_requested_at IS NULL
      AND a.cutoff_approved_email_sent_at < now() - v_booking_grace
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id
      )

    UNION ALL

    -- Bucket B — noshow_not_recovered (= D3): tem linha noshow, sem recuperacao
    -- POSTERIOR ao ultimo noshow (qualificado por created_at — evita falso-negativo
    -- de completed-antes-de-noshow), sem futuro agendado (exclui Hanae), envelhecido.
    SELECT
      a.id AS application_id,
      'selection_noshow_unrecovered'::text AS n_type,
      'No-show de entrevista sem recuperacao'::text AS n_title,
      format(
        '%s teve no-show de entrevista ha %s dia%s e segue sem nova entrevista agendada. Abra a candidatura em /admin/selection para re-convidar ou encerrar.',
        COALESCE(NULLIF(trim(a.applicant_name), ''),
                 NULLIF(trim(a.first_name || ' ' || COALESCE(a.last_name, '')), ''),
                 'Candidato'),  -- sem email no body (LGPD minimizacao; nome cobre 100% + link identifica)
        EXTRACT(DAY FROM now() - ns.last_noshow_at)::int,
        CASE WHEN EXTRACT(DAY FROM now() - ns.last_noshow_at)::int = 1 THEN '' ELSE 's' END
      ) AS n_body
    FROM public.selection_applications a
    JOIN LATERAL (
      SELECT max(si.created_at) AS last_noshow_created,
             -- scheduled_at e nullable; fallback p/ created_at (NOT NULL) evita
             -- que um noshow sem horario suma silenciosamente do bucket (review MEDIUM).
             COALESCE(max(si.scheduled_at), max(si.created_at)) AS last_noshow_at
      FROM public.selection_interviews si
      WHERE si.application_id = a.id AND si.status = 'noshow'
    ) ns ON ns.last_noshow_created IS NOT NULL
    WHERE a.cycle_id = (SELECT id FROM active_cycle)
      AND a.status = 'interview_pending'
      AND ns.last_noshow_at < now() - v_noshow_grace
      AND a.cutoff_approved_email_sent_at < now() - v_booking_grace  -- D3 (mig 219): nao notificar no-show JA re-convidado (anti-falso-positivo: o auto-rescue re-seta cutoff=now(); convite fresco != preso)
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_interviews si2
        WHERE si2.application_id = a.id
          AND si2.status IN ('scheduled', 'completed')
          AND si2.created_at > ns.last_noshow_created
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_interviews si3
        WHERE si3.application_id = a.id
          AND si3.status IN ('scheduled', 'rescheduled')
          AND si3.scheduled_at > now()
      )
  ),
  -- Fan-out: 1 nudge por manager (GP). ADR-0011 Amendment A.
  targets AS (
    SELECT s.application_id, s.n_type, s.n_title, s.n_body, m.id AS recipient_id
    FROM stuck s
    CROSS JOIN public.members m
    WHERE m.operational_role = 'manager'
  ),
  -- Idempotencia: 1 nudge por (manager, app) a cada 7 dias, filtrando pelos 2 types novos.
  to_insert AS (
    SELECT t.*
    FROM targets t
    WHERE NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = t.recipient_id
        AND n.source_type = 'selection_application'
        AND n.source_id   = t.application_id
        AND n.type IN ('selection_candidate_unbooked', 'selection_noshow_unrecovered')
        AND n.created_at > now() - interval '7 days'
    )
  ),
  inserted AS (
    INSERT INTO public.notifications (
      recipient_id, type, title, body, link, source_type, source_id, delivery_mode
    )
    SELECT
      ti.recipient_id, ti.n_type, ti.n_title, ti.n_body,
      '/admin/selection/applications/' || ti.application_id::text,
      'selection_application', ti.application_id,
      public._delivery_mode_for(ti.n_type)
    FROM to_insert ti
    WHERE NOT p_dry_run            -- dry_run: nao insere; ainda reporta a coorte
    RETURNING 1
  )
  SELECT
    (SELECT count(DISTINCT application_id) FROM stuck WHERE n_type = 'selection_candidate_unbooked')::int,
    (SELECT count(DISTINCT application_id) FROM stuck WHERE n_type = 'selection_noshow_unrecovered')::int,
    (SELECT count(*) FROM inserted)::int
  INTO v_unbooked_apps, v_noshow_apps, v_notified;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'unbooked_apps', v_unbooked_apps,
    'noshow_apps', v_noshow_apps,
    'notified', v_notified,
    'booking_grace_days', round(EXTRACT(EPOCH FROM v_booking_grace) / 86400.0, 1),
    'noshow_grace_days', round(EXTRACT(EPOCH FROM v_noshow_grace) / 86400.0, 1),
    'run_at', v_run_at
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. check_schema_invariants() + invariante AI_unbooked_rescue_cap_respected (35 -> 36). Corpo
--    reproduzido VERBATIM da mig 216 (35 invariantes) com UM RETURN QUERY adicionado antes do END
--    (padrão AG/AH). Phase-C: esta mig 219 vira a captura mais recente; live pós-apply == este corpo.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
        WHEN bool_or(
          (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
              AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
          OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
              AND ae.role IN ('leader','co_leader','owner','coordinator'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'observer') THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status='active' AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status='active' AND is_active=false) OR (member_status IN ('observer','alumni','inactive') AND is_active=true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND designations IS NOT NULL AND array_length(designations,1)>0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status='active' AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
      AND NOT EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status IN ('review','approved','activated')
          AND ac.closed_at IS NULL
      )
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL — unless an open approval_chain (review/approved/activated, closed_at NULL) is in flight that will lock the version on close (Phase IP-1, chain-aware).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role='external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id=m.person_id AND ae.kind='external_signer' AND ae.status='active' AND ae.is_authoritative=true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive') AND m.anonymized_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id=m.id)
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected AS (
    SELECT a.id AS application_id, a.research_score AS cached,
      CASE
        WHEN e.obj_avg IS NOT NULL AND e.int_avg IS NOT NULL THEN round(e.obj_avg + e.int_avg, 2)
        WHEN e.obj_avg IS NOT NULL THEN round(e.obj_avg, 2)
        ELSE NULL
      END AS expected
    FROM public.selection_applications a
    CROSS JOIN LATERAL (
      SELECT AVG(weighted_subtotal) FILTER (WHERE evaluation_type='objective' AND submitted_at IS NOT NULL) AS obj_avg,
        AVG(weighted_subtotal) FILTER (WHERE evaluation_type='interview' AND submitted_at IS NOT NULL) AS int_avg
      FROM public.selection_evaluations WHERE application_id=a.id
    ) e
  ),
  drift AS (
    SELECT application_id FROM expected
    WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL)
       OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01)
  )
  SELECT 'M_application_score_consistency'::text,
         'selection_applications.research_score must equal compute_application_scores(application_id) derivation (sync trigger trg_recompute_application_scores).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND offboarded_at IS NULL AND anonymized_at IS NULL
      AND name <> 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'N_terminal_status_offboarded_at_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 defense-in-depth complement to L).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ma.id AS artifact_id FROM public.meeting_artifacts ma
    WHERE ma.event_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = ma.event_id)
  )
  SELECT 'O_meeting_artifact_event_orphan'::text,
         'meeting_artifacts.event_id must point to an existing event when not NULL (FK defense).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  SELECT 'P_tribe_initiative_bridge_complete'::text,
         'tribes.is_active=true must have at least one initiative.legacy_tribe_id pointing to it (V3-V4 bridge; cron leader digest depends).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM public.tribes t
          WHERE t.is_active = true
            AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.legacy_tribe_id = t.id)),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS engagement_id FROM public.engagements
    WHERE status = 'expired' AND end_date > CURRENT_DATE
  )
  SELECT 'Q_expired_engagement_end_date'::text,
         'engagements.status=expired requires end_date <= CURRENT_DATE (impossible to be expired in the future; VEP service_latest_end_date is source of truth).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT a.id AS application_id
    FROM public.selection_applications a
    WHERE a.status = 'approved'
      AND a.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.members m WHERE lower(m.email) = lower(a.email)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.member_emails me WHERE lower(me.email) = lower(a.email)
      )
  )
  SELECT 'R_approved_application_has_member'::text,
         'selection_applications.status=approved must have a matching members row by lower(email). Bypass of approve_selection_application() canonical RPC creates this drift (Issue #180).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT DISTINCT m.id AS member_id
    FROM public.selection_applications a
    JOIN public.members m ON lower(m.email) = lower(a.email)
    WHERE a.status = 'approved' AND m.person_id IS NULL
  )
  SELECT 'S_approved_member_has_person_id'::text,
         'members tied to an approved selection_applications row must have person_id NOT NULL (V4 graph anchor for engagements). Issue #180.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH primary_email_counts AS (
    SELECT m.id AS member_id,
           COUNT(me.id) FILTER (WHERE me.is_primary = true) AS primary_count
    FROM public.members m
    LEFT JOIN public.member_emails me ON me.member_id = m.id
    WHERE m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT member_id FROM primary_email_counts
    WHERE primary_count <> 1
  )
  SELECT 'T_member_has_exactly_one_primary_email'::text,
         'Every member must have exactly one primary email in member_emails (Issue #205).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status = 'pending_proposer_consent'
      AND EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status NOT IN ('withdrawn','superseded')
      )
  )
  SELECT 'V_prime_pending_proposer_consent_no_open_chain'::text,
         'status=pending_proposer_consent must not have non-cancelled approval_chains rows (#315 P0-Q7 + Amendment A2 — pending_proposer_consent precedes any chain).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status IN ('approved','active')
      AND gd.current_ratified_chain_id IS NULL
  )
  SELECT 'V_status_chain_coherence'::text,
         'governance_documents with status approved/active must have current_ratified_chain_id NOT NULL (#315 P0-Q6 + #367 Wave 1b first leaf). NO carve-out: 7 legacy pre-chain docs backfilled with PM-designated synthetic chains via migration 20260805000038 (acknowledge signoffs, metadata.legacy_migration=true, role=migration_attestation).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT cp.id AS product_id
    FROM public.content_products cp
    WHERE
      CASE cp.source_kind
        WHEN 'governance_document_version' THEN
          NOT (cp.source_document_version_id IS NOT NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'board_item' THEN
          NOT (cp.source_board_item_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'publication_idea' THEN
          NOT (cp.source_publication_idea_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'external' THEN
          NOT (cp.source_external_uri IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL)
        WHEN 'none' THEN
          NOT (cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        ELSE TRUE
      END
  )
  SELECT 'W_content_product_source_integrity'::text,
         'content_products row must satisfy chk_content_products_source_integrity CHECK semantics (exactly one source FK populated per source_kind; ADR-0099 §2.2 + §6 step 9). Defense-in-depth complement to the CHECK constraint; mirrors V/V''/T pattern.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(product_id ORDER BY product_id) FROM (SELECT product_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT p.id AS parecer_id
    FROM public.blind_review_pareceres p
    WHERE NOT EXISTS (
      SELECT 1 FROM public.blind_review_assignments a
      WHERE a.session_id = p.session_id
        AND a.reviewer_member_id = p.reviewer_member_id
        AND a.status = 'active'
    )
  )
  SELECT 'X_blind_review_pareceres_session_product_match'::text,
         'blind_review_pareceres.reviewer_member_id must have an active blind_review_assignments row in the same session (assignment-parecer integrity; ADR-0099 §2.7 + §7 step 11). Defense-in-depth complement to FK constraints; catches drift if assignment is withdrawn while parecer remains. #382 PR-B.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(parecer_id ORDER BY parecer_id) FROM (SELECT parecer_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH pe AS (
    SELECT name AS k FROM public.partner_entities
    WHERE entity_type = 'pmi_chapter' AND status = 'active' AND NOT COALESCE(is_international, false)
  ),
  ch AS (
    SELECT 'PMI-' || code AS k FROM public.chapters WHERE status = 'active'
  ),
  drift AS (
    SELECT k FROM pe WHERE k NOT IN (SELECT k FROM ch)
    UNION ALL
    SELECT k FROM ch WHERE k NOT IN (SELECT k FROM pe)
  )
  SELECT 'Y_chapter_pipeline_parity'::text,
         'every active domestic pmi_chapter in partner_entities must have a matching active chapters row (by name = ''PMI-'' || chapters.code) and vice-versa — MEMBERSHIP parity (not just count), so it catches single-table inserts/archives even when row counts coincide. Drift = get_chapter_metrics()->>signed forks from the V4 chapters table (#481).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM drift),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS webinar_id FROM public.webinars
    WHERE status IS NULL OR status NOT IN ('planned','confirmed','completed','cancelled')
  )
  SELECT 'Z_webinar_status_domain'::text,
         'webinars.status must be within planned|confirmed|completed|cancelled (the realized=completed canonical definition depends on it; defense-in-depth complement to webinars_status_check — #479/#481).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(webinar_id ORDER BY webinar_id) FROM (SELECT webinar_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND current_cycle_active = true
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B2_current_cycle_active_terminal_status'::text,
         'members in observer/alumni/inactive must have current_cycle_active=false (#483 sync_member_status_consistency B-trigger; CCA gates the get_gamification_leaderboard/get_public_leaderboard cohort).'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- U (ADR-0104 Wave 3b-ii): members.chapter is now derived as
  -- COALESCE('PMI-'||entry_chapter_code, 'PMI-'||primary affiliation code, legacy chapter).
  -- For the derivation to be deterministic for registry-chaptered active members, each must have
  -- exactly one is_primary=true affiliation. The partial unique index enforces AT MOST one; this
  -- enforces EXACTLY one. Non-registry chapters (Outro/Externo) are excluded — legitimately
  -- unaffiliated, derivation falls through to the legacy value.
  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.person_id IS NOT NULL
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
      AND replace(m.chapter, 'PMI-', '') IN (SELECT chapter_code FROM public.chapter_registry)
      AND NOT (m.operational_role = 'guest' AND m.entry_chapter_code IS NULL)
      AND (SELECT COUNT(*) FROM public.member_chapter_affiliations a
            WHERE a.person_id = m.person_id AND a.is_primary) <> 1
  )
  SELECT 'U_active_person_has_primary_chapter_affiliation'::text,
         'every active registry-chaptered member''s person_id must have exactly one is_primary=true member_chapter_affiliations row, else the members.chapter COALESCE(entry, primary, legacy) derivation breaks silently (ADR-0104 Wave 3b-ii). Excluded: operational_role=''guest'' AND entry_chapter_code IS NULL (pre-onboarding, entry-chapter choice not yet made — affiliation is seeded by set_my_entry_chapter, Wave 3b-i; until then the COALESCE falls through to the legacy default). Non-registry chapters (Outro/Externo) excluded — legitimately unaffiliated.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AA (#766; the discovery dubbed this "invariant T", but T and U are already taken):
  -- the cert-side AFTER trigger (_trg_complete_volunteer_term_on_cert on certificates) and the
  -- seed-side BEFORE guard (_trg_complete_volunteer_term_on_seed on onboarding_progress) together
  -- guarantee that a member holding an issued volunteer_agreement certificate has their
  -- 'volunteer_term' onboarding step marked completed. This invariant codifies that guarantee.
  -- Directional: no volunteer_term row, or a completed step without an issued cert (all certs
  -- rejected/superseded), is NOT a violation.
  RETURN QUERY
  WITH drift AS (
    SELECT op.member_id
    FROM public.onboarding_progress op
    WHERE op.step_key = 'volunteer_term'
      AND op.status <> 'completed'
      AND op.member_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = op.member_id
          AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
      )
  )
  SELECT 'AA_volunteer_term_complete_when_cert_issued'::text,
         'a member holding an issued volunteer_agreement certificate must have their volunteer_term onboarding_progress step at status=completed. Guaranteed by the cert-side AFTER trigger (_trg_complete_volunteer_term_on_cert on certificates) plus the seed-side BEFORE guard (_trg_complete_volunteer_term_on_seed on onboarding_progress), p233 / issue #766. A non-completed step alongside an issued cert means a trigger was bypassed (service_role direct INSERT, or a cert backfill that did not fire the AFTER trigger). Directional: a member with no volunteer_term row, or a completed step without an issued cert (all certs rejected or superseded), is NOT a violation.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;
  -- AB (#766 PR2): a term_signed milestone must have a volunteer_agreement certificate
  -- of ANY status (issued/rejected/superseded) for the same member. Wave-3c-safe: the
  -- milestone persists after a cert is rejected or superseded because the member did
  -- sign once; only a milestone with NO cert ancestry at all is a violation (fabrication
  -- or a bad backfill via service_role direct INSERT). Directional complement to AA.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'term_signed'
      AND NOT EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = mm.member_id
          AND c.type = 'volunteer_agreement'
      )
  )
  SELECT 'AB_term_signed_milestone_has_cert_ancestry'::text,
         'a term_signed member_milestone must have at least one volunteer_agreement certificate of any status (issued/rejected/superseded) for the same member. Wave 3c reject/reissue is valid ancestry — the milestone persists after a cert is rejected or superseded because the member did sign once. A milestone with NO cert in any state indicates fabrication or a bad backfill (service_role direct INSERT into member_milestones; source_id is informational-only without FK). #766 PR2, mig 20260805000202. Directional complement to AA.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AC (#766 PR3): a first_attendance milestone must have at least one present=true
  -- attendance row for the member. source_id is informational-only (no FK), so a milestone
  -- with no present attendance indicates fabrication or a bad backfill (service_role direct
  -- INSERT into member_milestones). Directional, mirrors AA/AB.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'first_attendance'
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.member_id = mm.member_id
          AND a.present = true
      )
  )
  SELECT 'AC_first_attendance_milestone_has_attendance'::text,
         'a first_attendance member_milestone must have at least one present=true attendance row for the same member. source_id is informational-only (no FK), so a milestone with no present attendance indicates fabrication or a bad backfill (service_role direct INSERT into member_milestones). #766 PR3, mig 20260805000203. Directional, mirrors AA/AB.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AD (#766 PR3): a first_deliverable milestone must have at least one tribe_deliverable
  -- with status='completed' assigned to the member. Keyed on status='completed' (the same
  -- signal the trigger fires on, and the XP sibling trg_tribe_deliverable_completed_xp), NOT
  -- completed_at (a derived audit column). Catches a status reverted via service_role after
  -- the milestone fired, a fabricated milestone, or a bad backfill. Directional.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'first_deliverable'
      AND NOT EXISTS (
        SELECT 1 FROM public.tribe_deliverables td
        WHERE td.assigned_member_id = mm.member_id
          AND td.status = 'completed'
      )
  )
  SELECT 'AD_first_deliverable_milestone_has_completed_deliverable'::text,
         'a first_deliverable member_milestone must have at least one tribe_deliverable with status=''completed'' assigned to the same member. Keyed on status=''completed'' (same signal as the trigger and the XP sibling trg_tribe_deliverable_completed_xp; NOT completed_at, a derived audit column). A milestone with no completed deliverable indicates fabrication, a bad backfill, or a status reverted via service_role after the milestone fired. #766 PR3, mig 20260805000203. Directional, mirrors AA/AB.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AE (#766 PR5): a profile_complete milestone must have members.profile_completed_at set.
  -- profile_completed_at is monotonic — only update_my_profile writes it (NULL -> now() once,
  -- via CASE WHEN profile_completed_at IS NULL THEN now() ELSE profile_completed_at END) and no
  -- function ever clears it — so this directional check is false-positive-free, unlike promotion
  -- (PR4 added no invariant: operational_role is a mutable cache with routine demotion). Catches
  -- a fabricated milestone, a bad backfill, or the column cleared via a manual UPDATE after the
  -- milestone fired. Directional, mirrors AA/AB/AC/AD.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'profile_complete'
      AND NOT EXISTS (
        SELECT 1 FROM public.members m
        WHERE m.id = mm.member_id
          AND m.profile_completed_at IS NOT NULL
      )
  )
  SELECT 'AE_profile_complete_milestone_has_profile_completed_at'::text,
         'a profile_complete member_milestone must have members.profile_completed_at set. The column is monotonic — only update_my_profile writes it (NULL -> now() once, never cleared) — so this directional check is false-positive-free, unlike promotion whose mutable operational_role cache demotes routinely (hence PR4 added no invariant). A milestone with a NULL profile_completed_at indicates fabrication, a bad backfill (service_role direct INSERT into member_milestones; source_id is informational-only without FK), or the column cleared via a manual UPDATE after the milestone fired. #766 PR5, mig 20260805000205. Directional, mirrors AA/AB/AC/AD.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AF (D4/D5, mig 20260805000210): a selection_interviews row in an OPEN status (scheduled/rescheduled)
  -- must be the most-recently-created interview row for its application. An open row OLDER than another
  -- interview row of the same application means a reschedule/re-booking created a new row without closing
  -- the prior open one. Guaranteed forward by the AFTER INSERT trigger trg_supersede_prior_open_interviews
  -- (cancels older open siblings on a new open insert — the live root cause:
  -- sync_calendar_booking_to_interview / schedule_interview). KNOWN directional gap (defense-in-depth):
  -- a TERMINAL row inserted newer than an open row (only import_historical_interviews) is not superseded
  -- and would surface here; in production 'completed' is reached by UPDATE in-place
  -- (mark_interview_status/submit_interview_scores), so the live path is covered.
  RETURN QUERY
  WITH drift AS (
    SELECT si.id AS interview_id
    FROM public.selection_interviews si
    WHERE si.status IN ('scheduled','rescheduled')
      AND EXISTS (
        SELECT 1 FROM public.selection_interviews si2
        WHERE si2.application_id = si.application_id
          AND si2.created_at > si.created_at
      )
  )
  SELECT 'AF_open_interview_is_newest_row'::text,
         'a selection_interviews row in an open status (scheduled/rescheduled) must be the most-recently-created interview row for its application. An open row older than another interview row of the same application indicates a reschedule/re-booking that did not close the prior open row (bypass of the AFTER INSERT trigger trg_supersede_prior_open_interviews, or pre-fix legacy drift). Root cause: sync_calendar_booking_to_interview / schedule_interview INSERTing a new scheduled row without superseding the prior open one (D4/D5, mig 20260805000210). KNOWN directional gap (defense-in-depth): a TERMINAL row inserted newer than an open row (only import_historical_interviews) is not superseded by the trigger and would surface here; the live path reaches completed via UPDATE in-place, so it is covered.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(interview_id ORDER BY interview_id) FROM (SELECT interview_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AG (Tribe Selection Híbrida PR1, mig 20260805000216): every active volunteer engagement in a
  -- research_tribe initiative must have member.tribe_id = initiative.legacy_tribe_id. This is the
  -- correctness contract of the bridge trigger trg_sync_tribe_id_from_engagement: admission sets
  -- members.tribe_id from the engagement, and count_tribe_slots reads members.tribe_id, so a divergence
  -- means the bridge was bypassed (service_role direct INSERT into engagements) or a stale tribe_id
  -- from the legacy select_tribe path conflicts with the engagement. Baseline 0 (31 active engagements).
  RETURN QUERY
  WITH drift AS (
    SELECT e.id AS engagement_id
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.kind = 'volunteer' AND e.status = 'active'
      AND m.tribe_id IS DISTINCT FROM i.legacy_tribe_id
  )
  SELECT 'AG_tribe_engagement_has_tribe_id'::text,
         'every active volunteer engagement in a research_tribe initiative must have member.tribe_id = initiative.legacy_tribe_id (the correctness contract of the bridge trigger trg_sync_tribe_id_from_engagement; count_tribe_slots reads members.tribe_id, so a divergence corrupts the slot count). A violation means the bridge was bypassed (service_role direct INSERT into engagements) or a stale legacy tribe_id conflicts with the engagement. Tribe Selection Híbrida PR1, mig 20260805000216. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AH (Tribe Selection Híbrida PR1, mig 20260805000216): a person has at most one active volunteer
  -- engagement across research_tribe initiatives. members.tribe_id is a single scalar and the bridge
  -- trigger's demotion branch ("zero tribe_id only if no other active research_tribe engagement remains")
  -- both assume a single active tribe engagement; two would make tribe_id ambiguous and could leave a
  -- stale tribe_id after one is demoted. Supersedes the SPEC's I_research_tribe_no_dual_pending (which
  -- false-positives on a legitimate tribe-move and whose committed-divergence sibling is already
  -- non-zero from frozen legacy tribe_selections staleness). Baseline 0.
  RETURN QUERY
  WITH drift AS (
    SELECT e.person_id
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    WHERE e.kind = 'volunteer' AND e.status = 'active'
    GROUP BY e.person_id
    HAVING COUNT(*) > 1
  )
  SELECT 'AH_research_tribe_single_active_engagement'::text,
         'a person must have at most one active volunteer engagement across research_tribe initiatives. members.tribe_id is a single scalar and the bridge trigger trg_sync_tribe_id_from_engagement (admission + demotion branch) assumes a single active tribe engagement; two make tribe_id ambiguous and can leave a stale tribe_id after one is demoted. Supersedes the SPEC''s I_research_tribe_no_dual_pending (which false-positives on a legitimate tribe-move and whose committed-divergence sibling is already non-zero from frozen legacy tribe_selections staleness, below the bridge since AG=0). Tribe Selection Híbrida PR1, mig 20260805000216. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(person_id ORDER BY person_id) FROM (SELECT person_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AI (D3 auto-rescue, mig 20260805000219): cap=1 guard.
  RETURN QUERY
  WITH drift AS (
    SELECT id FROM public.selection_applications WHERE interview_auto_rescue_count > 1
  )
  SELECT 'AI_unbooked_rescue_cap_respected'::text,
         'selection_applications with interview_auto_rescue_count > 1 (above cap=1). _selection_unbooked_rescue_cron + selection_rescue_unbooked_invite enforce the cap via a RAISE guard at count>=1; a value >1 means a re-entry bug or a service_role direct UPDATE bypassed the guard. D3 auto-rescue, mig 20260805000219. Baseline 0.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(id ORDER BY id) FROM (SELECT id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

NOTIFY pgrst, 'reload schema';
