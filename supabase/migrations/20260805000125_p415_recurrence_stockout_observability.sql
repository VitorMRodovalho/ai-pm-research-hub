-- #415: active observability for recurrence "stockout" — a recently-active recurring series whose
-- last scheduled event is within the horizon and has no events beyond it (nobody noticed C3 #4..#N
-- were never created until the meeting hour). No operational_alerts table exists; alerts surface via
--   (a) the computed detect_operational_alerts dashboard (folded below),
--   (b) a daily cron that pushes notifications to manage_platform holders,
--   (c) the dedicated get_recurrence_stockout RPC/MCP tool.
--
-- Stockout predicate (refines the issue pseudocode, which would flood every historical series):
--   >=2 events (has a cadence) AND modal gap 1..92 days AND series ALIVE (last event within 2 cadences
--   of today) AND low buffer (last_date <= today + horizon). The "alive" clause excludes long-dead
--   series (last event years ago) that are NOT meant to continue.
--
-- Live-verified: real data → 8 recently-stuck weekly series flagged (dead/well-stocked excluded);
-- synthetic last_date=today+10 flagged, today+90 not; RPC fail-closed (Not authenticated / manage_event);
-- cron run → 8 stockout, 2 admins notified (idempotent 6-day dedup); fold shows on the dashboard.
--
-- Rollback: DROP the 3 new functions + cron.unschedule('recurrence-stockout-alert') + restore
-- detect_operational_alerts without the #415 block.

-- ── internal helper: stockout rows (PUBLIC revoked; called by the SECURITY DEFINER consumers) ──
CREATE OR REPLACE FUNCTION public._recurrence_stockout_rows(p_horizon_days integer DEFAULT 30)
 RETURNS TABLE(recurrence_group uuid, event_type text, last_date date, occurrences integer,
               modal_gap_days integer, next_expected date, suggested_next_dates date[])
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH grp AS (
    SELECT e.recurrence_group AS rg, e.type AS event_type,
           count(*)::int AS occurrences, max(e.date) AS last_date,
           array_agg(e.date ORDER BY e.date) AS dates
    FROM public.events e
    WHERE e.recurrence_group IS NOT NULL AND (e.status IS NULL OR e.status <> 'cancelled')
    GROUP BY e.recurrence_group, e.type
    HAVING count(*) >= 2
  ),
  gaps AS (
    SELECT w.rg,
           mode() WITHIN GROUP (ORDER BY (w.d - w.lag_d))::int AS modal_gap_days
    FROM (
      SELECT u.rg, u.d, lag(u.d) OVER (PARTITION BY u.rg ORDER BY u.d) AS lag_d
      FROM (SELECT g.rg, unnest(g.dates) AS d FROM grp g) u
    ) w
    WHERE w.lag_d IS NOT NULL
    GROUP BY w.rg
  )
  SELECT g.rg, g.event_type, g.last_date, g.occurrences, gp.modal_gap_days,
         (g.last_date + (gp.modal_gap_days || ' days')::interval)::date AS next_expected,
         ARRAY(SELECT (g.last_date + ((i * gp.modal_gap_days) || ' days')::interval)::date
               FROM generate_series(1, 4) i) AS suggested_next_dates
  FROM grp g
  JOIN gaps gp ON gp.rg = g.rg
  WHERE gp.modal_gap_days BETWEEN 1 AND 92
    AND g.last_date <= CURRENT_DATE + p_horizon_days
    AND g.last_date >= CURRENT_DATE - (gp.modal_gap_days * 2);
$function$;

REVOKE EXECUTE ON FUNCTION public._recurrence_stockout_rows(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._recurrence_stockout_rows(integer) TO service_role;

-- ── consumer RPC: get_recurrence_stockout (gated manage_event) ───────────────
CREATE OR REPLACE FUNCTION public.get_recurrence_stockout(p_horizon_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_rows jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- gated on manage_event: whoever can create the series (create_recurring_weekly_events) should see
  -- which series need resupplying. Includes tribe leaders for their own meetings.
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.last_date), '[]'::jsonb)
  INTO v_rows
  FROM public._recurrence_stockout_rows(p_horizon_days) r;

  RETURN jsonb_build_object(
    'stockout',     v_rows,
    'total',        jsonb_array_length(v_rows),
    'horizon_days', p_horizon_days,
    'checked_at',   now()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_recurrence_stockout(integer) TO authenticated, service_role;

-- ── cron detector: mirrors detect_stale_events_cron (notifications + audit log) ──
CREATE OR REPLACE FUNCTION public.detect_recurrence_stockout_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_inserted integer := 0;
BEGIN
  SELECT count(*) INTO v_count FROM public._recurrence_stockout_rows(30);

  IF v_count > 0 THEN
    -- push to manage_platform holders (admins) — idempotent: skip recipients already notified in the
    -- last 6 days (weekly reminder cadence, no daily spam). digest_weekly mode batches into the digest.
    INSERT INTO public.notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'recurrence_stockout',
           format('%s série(s) recorrente(s) no fim do estoque', v_count),
           format('%s série(s) recorrente(s) ativa(s) têm a última data dentro de 30 dias e nenhum evento futuro além disso. Crie as próximas ocorrências em /attendance (aba "Criar Recorrente").', v_count),
           'digest_weekly',
           now()
    FROM public.members m
    WHERE m.is_active = true
      AND public.can_by_member(m.id, 'manage_platform')
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = m.id
          AND n.type = 'recurrence_stockout'
          AND n.created_at >= now() - interval '6 days'
      );
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'cron.detect_recurrence_stockout_run', 'system_event', NULL,
      jsonb_build_object('stockout_count', v_count, 'managers_notified', v_inserted, 'horizon_days', 30),
      jsonb_build_object('source', 'cron_detect_recurrence_stockout')
    );
  END IF;

  RETURN jsonb_build_object(
    'stockout_count',        v_count,
    'notifications_inserted', v_inserted,
    'horizon_days',          30,
    'run_at',                now()
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.detect_recurrence_stockout_cron() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.detect_recurrence_stockout_cron() TO service_role;

-- ── daily cron (14:00 UTC — same window as event-stale-attendance-daily) ─────
-- cron.schedule upserts by job name → idempotent on re-apply (no duplicate job registration).
SELECT cron.schedule('recurrence-stockout-alert', '0 14 * * *', 'SELECT public.detect_recurrence_stockout_cron();');

-- ── fold recurrence_stockout into the computed ops-alerts dashboard ──────────
-- (consumed by MCP get_operational_alerts + admin UI). CREATE OR REPLACE preserves grants/owner.
-- Body = the live detect_operational_alerts verbatim + one new alert block (#415) before RETURN.
CREATE OR REPLACE FUNCTION public.detect_operational_alerts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_alerts jsonb := '[]'::jsonb;
  v_tmp jsonb;
  v_cycle_start date;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  SELECT cycle_start::date INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := current_date - 90; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', CASE WHEN sub.last_in_cycle IS NULL THEN 'medium' ELSE 'high' END,
    'type', 'tribe_no_meeting',
    'tribe_id', sub.id, 'tribe_name', sub.name, 'days_since', sub.days_since,
    'message', CASE
      WHEN sub.last_in_cycle IS NULL THEN sub.name || ' sem reunião registrada neste ciclo'
      ELSE sub.name || ' sem reunião há ' || sub.days_since || ' dias'
    END
  ))
  INTO v_tmp
  FROM (
    SELECT t.id, t.name,
      MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) as last_in_cycle,
      EXTRACT(DAY FROM now() - MAX(e.date) FILTER (WHERE e.date >= v_cycle_start)::timestamp)::int as days_since
    FROM tribes t
    LEFT JOIN initiatives i ON i.legacy_tribe_id = t.id
    LEFT JOIN events e ON e.initiative_id = i.id
    WHERE t.is_active = true
    GROUP BY t.id, t.name
    HAVING MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) < current_date - 14
       OR MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) IS NULL
  ) sub;
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'medium', 'type', 'member_absence_streak',
    'member_name', m.name, 'tribe_name', t.name,
    'message', m.name || ' ausente em últimas reuniões da ' || t.name
  ))
  INTO v_tmp
  FROM members m JOIN tribes t ON t.id = m.tribe_id
  WHERE m.is_active AND m.tribe_id IS NOT NULL
  AND m.id NOT IN (
    SELECT DISTINCT a.member_id FROM attendance a
    JOIN events e ON e.id = a.event_id
    LEFT JOIN initiatives i2 ON i2.id = e.initiative_id
    WHERE i2.legacy_tribe_id = m.tribe_id AND e.date >= current_date - 21 AND a.present = true
  );
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'medium', 'type', 'tribe_stagnant_production',
    'tribe_id', t.id, 'tribe_name', t.name,
    'message', t.name || ' sem movimentação de cards em 14+ dias'
  ))
  INTO v_tmp
  FROM tribes t WHERE t.is_active = true
  AND t.id NOT IN (
    SELECT DISTINCT i3.legacy_tribe_id
    FROM board_lifecycle_events ble
    JOIN board_items bi ON bi.id = ble.item_id
    JOIN project_boards pb ON pb.id = bi.board_id
    JOIN initiatives i3 ON i3.id = pb.initiative_id
    WHERE ble.created_at >= now() - interval '14 days' AND i3.legacy_tribe_id IS NOT NULL
  );
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'low', 'type', 'onboarding_overdue',
    'member_name', sa.applicant_name, 'step', op.step_key,
    'message', sa.applicant_name || ' atrasou ' || op.step_key
  ))
  INTO v_tmp
  FROM onboarding_progress op
  JOIN selection_applications sa ON sa.id = op.application_id
  WHERE op.status = 'overdue';
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'high', 'type', 'kpi_at_risk',
    'kpi_name', pkt.metric_key, 'target_value', pkt.target_value,
    'message', pkt.metric_key || ' abaixo de 50% da meta'
  ))
  INTO v_tmp
  FROM portfolio_kpi_targets pkt
  WHERE pkt.target_value > 0 AND pkt.critical_threshold > 0
  AND pkt.critical_threshold < (pkt.target_value * 0.5);
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', CASE WHEN e.type IN ('geral', 'kickoff', 'lideranca') THEN 'high' ELSE 'medium' END,
    'type', 'recorded_event_without_minutes',
    'event_id', e.id, 'event_title', e.title, 'event_type', e.type, 'event_date', e.date,
    'has_youtube', e.youtube_url IS NOT NULL,
    'has_recording', e.recording_url IS NOT NULL,
    'message', 'Evento gravado sem ata: ' || e.title || ' (' || e.date || ')'
  ))
  INTO v_tmp
  FROM events e
  WHERE (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL)
    AND (
      e.minutes_text IS NULL
      OR trim(e.minutes_text) = ''
      OR lower(trim(e.minutes_text)) IN ('teste', 'teste teste', 'test', 'placeholder', '-')
      OR length(trim(e.minutes_text)) < 20
    )
    AND e.date >= v_cycle_start
    AND e.date <= current_date;
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  -- #415: recurring series running out of future events (recently active + low buffer).
  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'high', 'type', 'recurrence_stockout',
    'recurrence_group', r.recurrence_group, 'event_type', r.event_type,
    'last_date', r.last_date, 'modal_gap_days', r.modal_gap_days, 'next_expected', r.next_expected,
    'message', 'Série recorrente (' || r.event_type || ') no fim do estoque: última em ' || r.last_date || ', próxima esperada ~' || r.next_expected
  ))
  INTO v_tmp
  FROM public._recurrence_stockout_rows(30) r;
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  RETURN jsonb_build_object(
    'alerts', v_alerts,
    'total', jsonb_array_length(v_alerts),
    'by_severity', jsonb_build_object(
      'high', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'high'),
      'medium', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'medium'),
      'low', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'low')
    ),
    'checked_at', now()
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
