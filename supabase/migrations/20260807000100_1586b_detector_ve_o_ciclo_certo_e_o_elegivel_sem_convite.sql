-- #1586(b) — o detector do funil estava cego por DUAS causas independentes.
--
-- Causa 1: o ciclo errado.
--   `active_cycle` resolvia por `ORDER BY created_at DESC LIMIT 1`. Em 13/07/2026 o ciclo
--   histórico `cycle2-2025` foi carregado no banco (dados de 2025, `created_at` novo) e
--   sequestrou essa seleção. Desde então o detector varre um ciclo FECHADO de 8 candidaturas
--   enquanto o ciclo aberto tem 81. Medido em 06/08: a função devolvia 0/0/0 todo dia.
--   `created_at` é a data em que a LINHA foi escrita, não a data em que o ciclo aconteceu.
--   Correção: selecionar por `status = 'open'`, e por JOIN (não por subselect escalar), para
--   dois ciclos abertos simultâneos não fazerem um sumir em silêncio.
--
-- Causa 2: o anchor.
--   Os dois buckets ancoram em `cutoff_approved_email_sent_at`, que é NULL exatamente para
--   quem nunca recebeu convite. Bucket A exige `IS NOT NULL`; bucket B compara `< now() - grace`
--   contra NULL, o que dá NULL e também exclui. Ou seja: a coorte que mais precisa de atenção
--   é a única invisível às duas. Consertar só a causa 1 continuaria dando zero.
--
-- Bucket C fecha isso ancorando no que EXISTE para essa coorte: o instante em que a candidatura
-- ficou elegível ao convite, isto é, quando a 2ª avaliação caiu (o gate de peer review exige 2)
-- e a nota objetiva já estava calculada.
--
-- Limiar: `eligible_uninvited_grace` = 2 dias. Não é número inventado — é a família "bola do
-- lado da ORGANIZAÇÃO" que já existe em `sla_policies` (`stuck_scheduled_grace` 48h,
-- `reapply_invite_grace` 2 dias). Os 10 dias de `interview_booking_grace` são a família "bola do
-- lado do CANDIDATO" (já convidado, falta ele agendar) e não cabem aqui.
--
-- ESCOPO: este bucket só TORNA VISÍVEL. Não despacha convite. Medido em 06/08, as 4 candidaturas
-- desta coorte não têm análise de IA, logo `_issue_interview_booking_token_core` as recusaria com
-- GATE_NO_AI em modo `full`; e na recusa `selection_rescue_unbooked_invite` não incrementa o
-- contador nem consome o cap, então um despacho automático aqui viraria laço diário de recusa com
-- zero e-mails. O despacho depende da decisão de #1632 (consentimento como condição de avanço) e
-- fica fora desta migration por decisão do PM.
--
-- Rollback: reaplicar o corpo anterior (mig 20260805000219 / captura em p219) e
--   DELETE FROM public.sla_policies WHERE policy_key = 'eligible_uninvited_grace';

-- `category` e NOT NULL e nao tem default; as 8 linhas existentes usam 'sla'.
INSERT INTO public.sla_policies (policy_key, value_interval, category, description)
VALUES (
  'eligible_uninvited_grace',
  interval '2 days',
  'sla',
  'Prazo apos a candidatura ficar ELEGIVEL ao convite de entrevista (2a avaliacao + nota objetiva) sem que convite algum tenha sido despachado, antes de o GP ser alertado (detect_stuck_selection_funnel, bucket eligible_uninvited). Familia "bola do lado da organizacao", como stuck_scheduled_grace.'
)
ON CONFLICT (policy_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.detect_stuck_selection_funnel(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_run_at         timestamptz := now();
  v_booking_grace  interval;
  v_noshow_grace   interval;
  v_uninvited_grace interval;
  v_unbooked_apps  int := 0;
  v_noshow_apps    int := 0;
  v_uninvited_apps int := 0;
  v_notified       int := 0;
BEGIN
  -- Config-driven windows (fallback ao literal se a row sumir) — padrao J4.
  SELECT value_interval INTO v_booking_grace FROM public.sla_policies WHERE policy_key = 'interview_booking_grace';
  IF v_booking_grace IS NULL THEN v_booking_grace := interval '10 days'; END IF;
  SELECT value_interval INTO v_noshow_grace FROM public.sla_policies WHERE policy_key = 'noshow_recovery_grace';
  IF v_noshow_grace IS NULL THEN v_noshow_grace := interval '3 days'; END IF;
  SELECT value_interval INTO v_uninvited_grace FROM public.sla_policies WHERE policy_key = 'eligible_uninvited_grace';
  IF v_uninvited_grace IS NULL THEN v_uninvited_grace := interval '2 days'; END IF;

  WITH active_cycle AS (
    -- Correcao causa 1: por STATUS, nunca por `created_at` (que e data de escrita da linha,
    -- e um backfill historico a torna a mais nova). Sem LIMIT 1: se houver dois ciclos abertos,
    -- os dois sao varridos em vez de um sumir calado.
    SELECT id FROM public.selection_cycles WHERE status = 'open'
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
    JOIN active_cycle ac ON ac.id = a.cycle_id
    WHERE a.status = 'interview_pending'
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
    JOIN active_cycle ac ON ac.id = a.cycle_id
    JOIN LATERAL (
      SELECT max(si.created_at) AS last_noshow_created,
             -- scheduled_at e nullable; fallback p/ created_at (NOT NULL) evita
             -- que um noshow sem horario suma silenciosamente do bucket (review MEDIUM).
             COALESCE(max(si.scheduled_at), max(si.created_at)) AS last_noshow_at
      FROM public.selection_interviews si
      WHERE si.application_id = a.id AND si.status = 'noshow'
    ) ns ON ns.last_noshow_created IS NOT NULL
    WHERE a.status = 'interview_pending'
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

    UNION ALL

    -- Bucket C — eligible_uninvited (#1586(b)): ELEGIVEL ao convite e convite algum foi
    -- despachado. Ancora em `eligible_at` (a 2a avaliacao), nao em `cutoff_approved_email_sent_at`,
    -- que e NULL por definicao nesta coorte. Sem linha de entrevista: quem ja tem entrevista
    -- marcada foi convidado por fora da maquinaria (medido: 24 candidaturas do ciclo 4 tem linha
    -- de entrevista com ZERO log de despacho) e nao esta preso.
    SELECT
      a.id AS application_id,
      'selection_candidate_eligible_uninvited'::text AS n_type,
      'Candidato elegivel a entrevista e nunca convidado'::text AS n_title,
      format(
        '%s esta elegivel ao convite de entrevista ha %s dia%s (2 avaliacoes + nota objetiva) e NUNCA recebeu convite: nao ha despacho registrado nem entrevista marcada. Abra a candidatura em /admin/selection para convidar ou encerrar.',
        COALESCE(NULLIF(trim(a.applicant_name), ''),
                 NULLIF(trim(a.first_name || ' ' || COALESCE(a.last_name, '')), ''),
                 'Candidato'),  -- sem email no body (LGPD minimizacao), igual aos buckets A e B
        EXTRACT(DAY FROM now() - el.eligible_at)::int,
        CASE WHEN EXTRACT(DAY FROM now() - el.eligible_at)::int = 1 THEN '' ELSE 's' END
      ) AS n_body
    FROM public.selection_applications a
    JOIN active_cycle ac ON ac.id = a.cycle_id
    JOIN LATERAL (
      -- Instante em que ficou elegivel = quando a 2a avaliacao caiu. `LIMIT 2` + `max` da
      -- exatamente a 2a por ordem cronologica; avaliacoes posteriores nao adiam o relogio.
      SELECT max(created_at) AS eligible_at, count(*) AS n_eval
      FROM (
        SELECT created_at FROM public.selection_evaluations
        WHERE application_id = a.id ORDER BY created_at LIMIT 2
      ) first_two
    ) el ON el.n_eval >= 2
    WHERE a.status = 'interview_pending'
      AND a.cutoff_approved_email_sent_at IS NULL          -- o anchor que os buckets A e B perdem
      AND a.interview_reschedule_requested_at IS NULL
      AND a.objective_score_avg IS NOT NULL                -- 3o gate do core ja satisfeito
      AND el.eligible_at < now() - v_uninvited_grace
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_dispatch_url_log d WHERE d.application_id = a.id
      )
  ),
  -- Fan-out: 1 nudge por manager (GP). ADR-0011 Amendment A.
  targets AS (
    SELECT s.application_id, s.n_type, s.n_title, s.n_body, m.id AS recipient_id
    FROM stuck s
    CROSS JOIN public.members m
    WHERE m.operational_role = 'manager'
  ),
  -- Idempotencia: 1 nudge por (manager, app) a cada 7 dias, filtrando pelos 3 types.
  to_insert AS (
    SELECT t.*
    FROM targets t
    WHERE NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = t.recipient_id
        AND n.source_type = 'selection_application'
        AND n.source_id   = t.application_id
        AND n.type IN ('selection_candidate_unbooked', 'selection_noshow_unrecovered',
                       'selection_candidate_eligible_uninvited')
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
    (SELECT count(DISTINCT application_id) FROM stuck WHERE n_type = 'selection_candidate_eligible_uninvited')::int,
    (SELECT count(*) FROM inserted)::int
  INTO v_unbooked_apps, v_noshow_apps, v_uninvited_apps, v_notified;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'unbooked_apps', v_unbooked_apps,
    'noshow_apps', v_noshow_apps,
    'eligible_uninvited_apps', v_uninvited_apps,
    'notified', v_notified,
    'booking_grace_days', round(EXTRACT(EPOCH FROM v_booking_grace) / 86400.0, 1),
    'noshow_grace_days', round(EXTRACT(EPOCH FROM v_noshow_grace) / 86400.0, 1),
    'eligible_uninvited_grace_days', round(EXTRACT(EPOCH FROM v_uninvited_grace) / 86400.0, 1),
    'run_at', v_run_at
  );
END;
$function$;
