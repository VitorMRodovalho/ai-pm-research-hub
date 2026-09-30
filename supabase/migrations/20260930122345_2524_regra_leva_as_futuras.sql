-- #2524, etapas 1 e 2 (decisão do GP em 30/09/2026): a regra de recorrência leva as mudanças às reuniões
-- futuras, e a divergência que sobrar passa a ser detectada por um cron.
--
-- Medido em 29/09/2026: a liderança da Tribo 5 corrigiu o horário no texto da página da tribo (17h); o card
-- da home seguiu em 18h e as 8 reuniões futuras também. update_recurring_meeting_rule muda a regra e a tabela
-- de horários, mas nunca as reuniões já geradas. get_recurring_meeting_drift já calculava a divergência e
-- nada o chamava (0 jobs em cron.job, 0 consumidores no código).
--
-- (1) update_recurring_meeting_rule ganha p_dry_run (DROP + CREATE: troca de assinatura; o EXECUTE volta só a
--     authenticated e service_role). Depois de atualizar a regra:
--     - hora, duração, link, título e fuso que MUDARAM vão para as reuniões futuras agendadas da série que
--       ainda carregam o valor ANTIGO. Reunião ajustada à mão é exceção e fica; o passado não muda.
--     - mudança de cadência (dia, frequência ou âncora): as reuniões futuras que eram ocorrência da regra
--       antiga e não são da nova saem se não têm registro nenhum; as que têm registro (presença, inclusive
--       justificativa lançada antes, ata, pauta, observação, bloco, ação, card, convidado, artefato, custo,
--       webinar, showcase, certificado, remarcação, arquivo do Drive) ficam intocadas e voltam na resposta
--       para a liderança revisar. Depois o reconcile gera as do dia novo até além da última que saiu.
--       Etiquetas e regras de audiência NÃO contam como registro: os gatilhos as recriam na reunião nova
--       (medido: 79 de 79 reuniões futuras têm etiqueta e 57 têm regra de audiência, todas automáticas).
--     - a tabela de horários desliga o dia antigo, que antes ficava ativo ao lado do novo.
--     - p_dry_run roda exatamente o mesmo bloco e o desfaz no fim: a prévia é o efeito, não uma estimativa.
-- (2) detect_recurring_meeting_drift_cron: toda segunda às 07:00 UTC, depois do reconcile das 06:00. Avisa quem
--     gere a plataforma quando há regra ativa com reunião futura fora do horário ou do link da regra, ou com
--     ocorrência faltando, e quando uma iniciativa ativa se reuniu ao menos 2 vezes nos últimos 90 dias e não
--     tem nenhuma reunião marcada adiante (medido em 30/09: as Tribos 10 e 11; a 10 nunca teve série, então o
--     alerta de estoque, que é por série, não a enxerga). Sem portão de sessão: sob pg_cron não há JWT (#2285);
--     get_recurring_meeting_drift toma o caminho de cron porque o papel da requisição fica vazio. A proteção é
--     o ACL: só postgres e service_role executam.
--
-- ROLLBACK: DROP da assinatura nova e reaplicar update_recurring_meeting_rule de 20260805000167 com o REVOKE e o
--   GRANT de lá; SELECT cron.unschedule('recurring-meeting-drift-weekly'); DROP FUNCTION
--   public.detect_recurring_meeting_drift_cron().

-- ─── (1) ───────────────────────────────────────────────────────────────────────────────────────
DROP FUNCTION public.update_recurring_meeting_rule(uuid, jsonb);
CREATE FUNCTION public.update_recurring_meeting_rule(p_rule_id uuid, p_patch jsonb, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cron       boolean;
  v_member     uuid;
  v_old        public.recurring_meeting_rules%ROWTYPE;
  v_rule       public.recurring_meeting_rules%ROWTYPE;
  v_slot_dow   int;
  v_res        jsonb;
  v_time       int := 0;
  v_duration   int := 0;
  v_link       int := 0;
  v_title      int := 0;
  v_tz         int := 0;
  v_removed    int := 0;
  v_created    int := 0;
  v_kept       jsonb := '[]'::jsonb;
  v_drop_ids   uuid[];
  v_last_stale date;
  v_rec        jsonb;
BEGIN
  v_cron := NOT public._recurring_request_is_rest();

  SELECT * INTO v_old FROM public.recurring_meeting_rules WHERE id = p_rule_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recurring rule not found: %', p_rule_id; END IF;

  IF NOT v_cron THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
    IF v_member IS NULL OR NOT public._can_manage_recurring_rule(v_member, v_old.initiative_id) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_platform or initiative leadership';
    END IF;
  END IF;

  -- Validate enum-ish fields if present (clear errors before the table CHECKs bite).
  IF p_patch ? 'status' AND (p_patch->>'status') NOT IN ('active','paused','archived') THEN
    RAISE EXCEPTION 'Invalid status: %', p_patch->>'status';
  END IF;
  IF p_patch ? 'frequency' AND (p_patch->>'frequency') NOT IN ('weekly','biweekly') THEN
    RAISE EXCEPTION 'Invalid frequency: %', p_patch->>'frequency';
  END IF;
  IF p_patch ? 'day_of_week' AND ((p_patch->>'day_of_week')::int < 1 OR (p_patch->>'day_of_week')::int > 7) THEN
    RAISE EXCEPTION 'Invalid day_of_week: %', p_patch->>'day_of_week';
  END IF;

  -- #2524: p_dry_run runs this same block and undoes it at the end, so the preview IS the effect.
  BEGIN
    UPDATE public.recurring_meeting_rules SET
      title            = COALESCE(p_patch->>'title', title),
      meeting_link     = CASE WHEN p_patch ? 'meeting_link' THEN NULLIF(p_patch->>'meeting_link','') ELSE meeting_link END,
      time_start       = COALESCE((p_patch->>'time_start')::time, time_start),
      duration_minutes = COALESCE((p_patch->>'duration_minutes')::int, duration_minutes),
      day_of_week      = COALESCE((p_patch->>'day_of_week')::smallint, day_of_week),
      frequency        = COALESCE(p_patch->>'frequency', frequency),
      anchor_date      = COALESCE((p_patch->>'anchor_date')::date, anchor_date),
      status           = COALESCE(p_patch->>'status', status),
      audience_level   = COALESCE(p_patch->>'audience_level', audience_level),
      visibility       = COALESCE(p_patch->>'visibility', visibility),
      timezone         = COALESCE(p_patch->>'timezone', timezone),
      notes            = CASE WHEN p_patch ? 'notes' THEN p_patch->>'notes' ELSE notes END
    WHERE id = p_rule_id;

    -- Re-read final state and keep the derived tribe slot consistent with the rule.
    SELECT * INTO v_rule FROM public.recurring_meeting_rules WHERE id = p_rule_id;
    IF v_rule.scope_type = 'tribe' AND v_rule.tribe_id IS NOT NULL THEN
      v_slot_dow := (v_rule.day_of_week % 7);
      INSERT INTO public.tribe_meeting_slots (tribe_id, day_of_week, time_start, time_end, is_active, created_at, updated_at)
      VALUES (
        v_rule.tribe_id, v_slot_dow, v_rule.time_start,
        (v_rule.time_start + make_interval(mins => v_rule.duration_minutes)),
        (v_rule.status = 'active'), now(), now()
      )
      ON CONFLICT (tribe_id, day_of_week) DO UPDATE SET
        time_start = EXCLUDED.time_start,
        time_end   = EXCLUDED.time_end,
        is_active  = EXCLUDED.is_active,
        updated_at = now();
      -- #2524: the old day's slot stops being shown next to the new one.
      IF v_old.day_of_week IS DISTINCT FROM v_rule.day_of_week THEN
        UPDATE public.tribe_meeting_slots SET is_active = false, updated_at = now()
         WHERE tribe_id = v_rule.tribe_id AND day_of_week = (v_old.day_of_week % 7);
      END IF;
    END IF;

    -- #2524 etapa 1: future scheduled occurrences follow the rule. Only fields that changed, only occurrences
    -- that still carry the OLD value (one adjusted by hand is an exception and stays), never the past.
    IF v_rule.time_start IS DISTINCT FROM v_old.time_start THEN
      UPDATE public.events e SET time_start = v_rule.time_start, updated_at = now()
       WHERE e.recurrence_group = v_rule.recurrence_group AND e.date >= current_date AND e.status = 'scheduled'
         AND e.time_start IS NOT DISTINCT FROM v_old.time_start;
      GET DIAGNOSTICS v_time = ROW_COUNT;
    END IF;
    IF v_rule.duration_minutes IS DISTINCT FROM v_old.duration_minutes THEN
      UPDATE public.events e SET duration_minutes = v_rule.duration_minutes,
             duration_actual = CASE WHEN e.duration_actual IS NOT DISTINCT FROM v_old.duration_minutes
                                    THEN v_rule.duration_minutes ELSE e.duration_actual END,
             updated_at = now()
       WHERE e.recurrence_group = v_rule.recurrence_group AND e.date >= current_date AND e.status = 'scheduled'
         AND e.duration_minutes IS NOT DISTINCT FROM v_old.duration_minutes;
      GET DIAGNOSTICS v_duration = ROW_COUNT;
    END IF;
    IF v_rule.meeting_link IS DISTINCT FROM v_old.meeting_link THEN
      UPDATE public.events e SET meeting_link = v_rule.meeting_link, updated_at = now()
       WHERE e.recurrence_group = v_rule.recurrence_group AND e.date >= current_date AND e.status = 'scheduled'
         AND e.meeting_link IS NOT DISTINCT FROM v_old.meeting_link;
      GET DIAGNOSTICS v_link = ROW_COUNT;
    END IF;
    IF v_rule.title IS DISTINCT FROM v_old.title THEN
      UPDATE public.events e SET title = v_rule.title, updated_at = now()
       WHERE e.recurrence_group = v_rule.recurrence_group AND e.date >= current_date AND e.status = 'scheduled'
         AND e.title IS NOT DISTINCT FROM v_old.title;
      GET DIAGNOSTICS v_title = ROW_COUNT;
    END IF;
    IF v_rule.timezone IS DISTINCT FROM v_old.timezone THEN
      UPDATE public.events e SET timezone = v_rule.timezone, updated_at = now()
       WHERE e.recurrence_group = v_rule.recurrence_group AND e.date >= current_date AND e.status = 'scheduled'
         AND e.timezone IS NOT DISTINCT FROM v_old.timezone;
      GET DIAGNOSTICS v_tz = ROW_COUNT;
    END IF;

    -- Cadence changed: the future occurrences of the OLD rule that the NEW rule does not generate leave when
    -- nothing is recorded on them; the ones with a record stay untouched and are reported.
    IF v_rule.day_of_week IS DISTINCT FROM v_old.day_of_week
       OR v_rule.frequency IS DISTINCT FROM v_old.frequency
       OR v_rule.anchor_date IS DISTINCT FROM v_old.anchor_date THEN
      WITH stale AS (
        SELECT e.id, e.date,
          (   EXISTS (SELECT 1 FROM public.attendance x WHERE x.event_id = e.id)
           OR EXISTS (SELECT 1 FROM public.event_agenda_blocks x WHERE x.event_id = e.id)
           OR EXISTS (SELECT 1 FROM public.meeting_action_items x WHERE x.event_id = e.id OR x.carried_to_event_id = e.id)
           OR EXISTS (SELECT 1 FROM public.board_item_event_links x WHERE x.event_id = e.id)
           OR EXISTS (SELECT 1 FROM public.event_invited_members x WHERE x.event_id = e.id)
           OR EXISTS (SELECT 1 FROM public.meeting_artifacts x WHERE x.event_id = e.id)
           OR EXISTS (SELECT 1 FROM public.cost_entries x WHERE x.event_id = e.id)
           OR EXISTS (SELECT 1 FROM public.webinars x WHERE x.event_id = e.id)
           OR EXISTS (SELECT 1 FROM public.event_showcases x WHERE x.event_id = e.id)
           OR EXISTS (SELECT 1 FROM public.event_guest_certificates x WHERE x.event_id = e.id)
           OR EXISTS (SELECT 1 FROM public.events x WHERE x.rescheduled_from = e.id)
           OR EXISTS (SELECT 1 FROM public.drive_file_discoveries x WHERE x.matched_event_id = e.id)
           OR coalesce(btrim(e.minutes_text), '') <> ''
           OR coalesce(btrim(e.agenda_text), '') <> ''
           OR coalesce(btrim(e.notes), '') <> ''
          ) AS has_record
        FROM public.events e
        WHERE e.recurrence_group = v_rule.recurrence_group AND e.date >= current_date AND e.status = 'scheduled'
          -- an occurrence of the OLD rule (a date moved by hand is not one) ...
          AND extract(isodow FROM e.date)::int = v_old.day_of_week
          AND (v_old.frequency = 'weekly' OR (e.date - v_old.anchor_date) % 14 = 0)
          -- ... that the NEW rule does not generate.
          AND NOT (extract(isodow FROM e.date)::int = v_rule.day_of_week
                   AND e.date >= v_rule.anchor_date
                   AND (v_rule.frequency = 'weekly' OR (e.date - v_rule.anchor_date) % 14 = 0))
      )
      SELECT array_agg(s.id) FILTER (WHERE NOT s.has_record),
             coalesce(jsonb_agg(jsonb_build_object('event_id', s.id, 'date', s.date) ORDER BY s.date) FILTER (WHERE s.has_record), '[]'::jsonb),
             max(s.date)
        INTO v_drop_ids, v_kept, v_last_stale
        FROM stale s;
      IF v_drop_ids IS NOT NULL THEN
        DELETE FROM public.events WHERE id = ANY (v_drop_ids);
        GET DIAGNOSTICS v_removed = ROW_COUNT;
      END IF;
      v_rec := public.reconcile_recurring_meeting(v_rule.id, GREATEST(current_date + 60, coalesce(v_last_stale, current_date)));
      v_created := coalesce((v_rec->>'created_events')::int, 0);
    END IF;

    v_res := jsonb_build_object(
      'rule_id', v_rule.id, 'status', v_rule.status, 'updated', true, 'dry_run', p_dry_run,
      'future_events', jsonb_build_object(
        'from', current_date, 'time', v_time, 'duration', v_duration, 'link', v_link, 'title', v_title,
        'timezone', v_tz, 'removed', v_removed, 'created', v_created, 'kept_with_records', v_kept));

    IF p_dry_run THEN
      RAISE EXCEPTION 'dry run' USING ERRCODE = 'RR001';
    END IF;
  EXCEPTION WHEN SQLSTATE 'RR001' THEN
    NULL; -- the whole block was undone; v_res keeps what it would have done
  END;

  RETURN v_res;
END
$function$;

REVOKE ALL ON FUNCTION public.update_recurring_meeting_rule(uuid, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_recurring_meeting_rule(uuid, jsonb, boolean) TO authenticated, service_role;

-- ─── (2) ───────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.detect_recurring_meeting_drift_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_rules    int := 0;
  v_rule_ls  text;
  v_idle     int := 0;
  v_idle_ls  text;
  v_inserted int := 0;
BEGIN
  -- No session gate on purpose: under pg_cron there is no JWT (#2285). The ACL is the gate.
  SELECT count(*), string_agg(d.title, '; ' ORDER BY d.title)
    INTO v_rules, v_rule_ls
    FROM public.get_recurring_meeting_drift(NULL) d
   WHERE d.status = 'active'
     AND (d.time_mismatch > 0 OR d.link_mismatch > 0 OR d.missing_future > 0);

  -- An active initiative that met at least twice in 90 days and has nothing scheduled ahead, with or
  -- without a series (the stockout alert only sees series).
  SELECT count(*), string_agg(i.title, '; ' ORDER BY i.title)
    INTO v_idle, v_idle_ls
    FROM public.initiatives i
   WHERE i.status = 'active'
     AND NOT EXISTS (
       SELECT 1 FROM public.events f
        WHERE f.initiative_id = i.id AND f.date >= current_date AND (f.status IS NULL OR f.status <> 'cancelled'))
     AND (SELECT count(*) FROM public.events e
           WHERE e.initiative_id = i.id AND e.date >= current_date - 90 AND e.date < current_date
             AND (e.status IS NULL OR e.status <> 'cancelled')) >= 2;

  IF v_rules > 0 OR v_idle > 0 THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'recurring_meeting_drift',
           'Agenda recorrente: divergências para revisar',
           concat_ws(' ',
             CASE WHEN v_rules > 0 THEN format('%s regra(s) com reunião futura fora do horário ou do link da regra, ou com ocorrência faltando: %s.', v_rules, v_rule_ls) END,
             CASE WHEN v_idle > 0 THEN format('%s iniciativa(s) ativa(s) que se reuniram nos últimos 90 dias sem nenhuma reunião marcada adiante: %s.', v_idle, v_idle_ls) END,
             'Revise em /admin/agenda-recorrente.'),
           'digest_weekly',
           now()
      FROM public.members m
     WHERE m.is_active = true
       AND public.can_by_member(m.id, 'manage_platform')
       AND NOT EXISTS (
         SELECT 1 FROM public.notifications n
          WHERE n.recipient_id = m.id
            AND n.type = 'recurring_meeting_drift'
            AND n.created_at >= now() - interval '6 days');
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
  END IF;

  -- Every run leaves a line, so "the detector ran and found nothing" is distinguishable from "it never ran".
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (NULL, 'cron.detect_recurring_meeting_drift_run', 'system_event', NULL,
          jsonb_build_object('rules_with_drift', v_rules, 'idle_initiatives', v_idle, 'managers_notified', v_inserted),
          jsonb_build_object('source', 'cron_detect_recurring_meeting_drift'));

  RETURN jsonb_build_object('rules_with_drift', v_rules, 'idle_initiatives', v_idle,
                            'notifications_inserted', v_inserted, 'run_at', now());
END
$function$;

REVOKE ALL ON FUNCTION public.detect_recurring_meeting_drift_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.detect_recurring_meeting_drift_cron() TO service_role;

SELECT cron.schedule('recurring-meeting-drift-weekly', '0 7 * * 1', 'SELECT public.detect_recurring_meeting_drift_cron();');
