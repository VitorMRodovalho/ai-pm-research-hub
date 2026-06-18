-- ÉPICO D (funil de seleção sem enterrados) — detecção + nudge ao GP do stuck
-- pós-convite. #766 follow-up. PR DB-first. SPEC: docs/specs/SPEC_D_STUCK_FUNNEL_DETECTION.md.
--
-- Problema (aterrado cycle4-2026, 2026-06-18): o cron de overdue (job48) só vê
-- entrevistas COM linha selection_interviews em status scheduled/rescheduled atrasada.
-- Logo dois grupos caem num buraco invisível: (A) convidado que nunca agendou (sem linha
-- de entrevista) e (B) no-show sem recuperação (linha status=noshow). Coorte viva:
-- Hector(86d) / Djeimiys(57d) sem linha; Edinan(86d) no-show; Bruna(66d) 3 falhas.
--
-- Solução: cron diário classifica esses dois buckets no ciclo ativo e NOTIFICA os
-- managers (GP) — sem agir sobre o candidato (auto-rescue = D3, PR posterior).
--
-- Decisões council (data-architect 2026-06-18): destinatário = só managers (ADR-0011
-- Amendment A: fan-out direto por operational_role); booking_grace=10d; bucket
-- cancelado-sem-rebooking ADIADO; source_type='selection_application'.
--
-- Sem invariante de schema (detecção/notificação efêmera, como detect_inactive_members).
-- Guard = idempotência 7d por (manager, app, type) + escopo do ciclo ativo.
--
-- ROLLBACK:
--   SELECT cron.unschedule('detect-stuck-selection-funnel-daily');
--   -- remover a função de detecção:
--   --   DROP FUNCTION IF EXISTS public.detect_stuck_selection_funnel(boolean);
--   DELETE FROM public.sla_policies WHERE policy_key IN ('interview_booking_grace','noshow_recovery_grace');
--   NOTIFY pgrst, 'reload schema';

-- 1. Config: 2 janelas de SLA novas (reusa a tabela do J4; a UI admin as exibe sozinha).
--    ON CONFLICT DO NOTHING preserva valores já tunados pelo GP em reruns.
INSERT INTO public.sla_policies (policy_key, value_interval, category, description) VALUES
  ('interview_booking_grace', interval '10 days', 'sla',
   'Prazo apos o convite (cutoff approved) sem agendar antes de o GP ser alertado (detect_stuck_selection_funnel, bucket invited_never_booked).'),
  ('noshow_recovery_grace', interval '3 days', 'sla',
   'Prazo apos um no-show de entrevista sem recuperacao antes de o GP ser alertado (detect_stuck_selection_funnel, bucket noshow_not_recovered).')
ON CONFLICT (policy_key) DO NOTHING;

-- 2. RPC de detecção + nudge. Cron-only (sem auth gate de usuário): enumera managers
--    para fan-out — fast-path stakeholder fan-out per ADR-0011 Amendment A (consulta
--    operational_role sem can_by_member, excecao aprovada; nao grava decisao autoritativa).
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

-- 3. Grants: cron-only (service_role). Authenticated nao dispara fan-out de admin.
REVOKE ALL ON FUNCTION public.detect_stuck_selection_funnel(boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.detect_stuck_selection_funnel(boolean) TO service_role;

-- 4. Cron diario as 16:00 UTC (apos overdue 14:00 e stuck-rescue 15:00). Idempotente.
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'detect-stuck-selection-funnel-daily') THEN
    PERFORM cron.unschedule('detect-stuck-selection-funnel-daily');
  END IF;
  PERFORM cron.schedule(
    'detect-stuck-selection-funnel-daily',
    '0 16 * * *',
    $$SELECT public.detect_stuck_selection_funnel(p_dry_run := false)$$
  );
END;
$cron$;

NOTIFY pgrst, 'reload schema';
