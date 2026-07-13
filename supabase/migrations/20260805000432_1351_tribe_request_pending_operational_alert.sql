-- #1351 — GP-wide visibility of pending tribe join-requests.
--
-- Today a tribe join-request notifies only that tribe's leader and renders only on that tribe's
-- Members tab (list_tribe_pending_requests). There is no aggregated view, so when a leader does not
-- act (e.g. the tribe is full and the approve raises "Tribo lotada" -> 400) the pending is invisible
-- to the GP and just expires. Anchor: Guilherme -> Tribo 6 (8/8), stuck 4 days until manually declined.
--
-- Fix: add a `tribe_request_pending` alert to detect_operational_alerts() (the manage_platform SSOT of
-- operational alerts). One alert per pending self-request across ALL tribes, with escalated severity:
-- high when the tribe is at cap (un-approvable without GP action) or the request is stale (>5 days),
-- medium at >=3 days, else low. Carries invitation_id so the GP/assistant can act (approve/decline)
-- directly. Slot formula matches review_tribe_request / request_tribe_assignment (#1350).
--
-- Re-captured from the live body (CREATE OR REPLACE on the live function per the drift-safe rule); the
-- only changes vs live are: v_cap in DECLARE + the new alert block before the final RETURN.

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
  v_cap integer := public.tribe_capacity_limit();
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

  -- #1209: Credly badges stuck in the fallback 'badge'/10 bucket — promotion candidates. One aggregate
  -- alert (not one per badge). Never a silent reclassification; the GP reviews via get_credly_unmapped_badges.
  SELECT jsonb_build_object(
    'severity', 'low',
    'type', 'credly_unmapped_badges',
    'distinct_badges', count(*),
    'total_rows', coalesce(sum(u.occurrences), 0),
    'message', count(*) || ' badge(s) Credly em fallback (10 XP), ' || coalesce(sum(u.occurrences), 0)
               || ' atribuição(ões) — revisar em get_credly_unmapped_badges p/ possível promoção de categoria'
  )
  INTO v_tmp
  FROM public._credly_unmapped_rows() u;
  IF v_tmp IS NOT NULL AND (v_tmp->>'distinct_badges')::int > 0 THEN
    v_alerts := v_alerts || v_tmp;
  END IF;

  -- #1209 follow-up: coverage gap — active researchers/leaders/GP with NO Credly link cadastrado.
  SELECT jsonb_build_object(
    'severity', 'medium', 'type', 'credly_missing_link',
    'count', count(*),
    'message', count(*) || ' membro(s) ativo(s) (pesquisador/líder/GP) sem link Credly cadastrado — ver get_credly_health'
  )
  INTO v_tmp
  FROM public._credly_health_rows() WHERE kind = 'missing_link';
  IF v_tmp IS NOT NULL AND (v_tmp->>'count')::int > 0 THEN v_alerts := v_alerts || v_tmp; END IF;

  -- #1209 follow-up: Credly link the sync can't read (404/private, e.g. Tiele) or empty profile (e.g. Marcela).
  SELECT jsonb_build_object(
    'severity', 'low', 'type', 'credly_sync_broken',
    'never_verified', count(*) FILTER (WHERE kind='never_verified'),
    'empty_profile',  count(*) FILTER (WHERE kind='no_badges'),
    'message', (count(*) FILTER (WHERE kind='never_verified')) || ' link(s) Credly não-lidos (404/privado) + '
               || (count(*) FILTER (WHERE kind='no_badges')) || ' perfil(s) Credly sem badges — ver get_credly_health'
  )
  INTO v_tmp
  FROM public._credly_health_rows() WHERE kind IN ('never_verified','no_badges');
  IF v_tmp IS NOT NULL AND ((v_tmp->>'never_verified')::int > 0 OR (v_tmp->>'empty_profile')::int > 0) THEN
    v_alerts := v_alerts || v_tmp;
  END IF;

  -- #1351: pending tribe join-requests, GP-wide (was only visible per-tribe on each tribe's Members tab).
  -- One alert per pending self-request across ALL tribes. Escalate: high when the tribe is at cap
  -- (un-approvable without GP action) or the request is stale (>5d); medium at >=3d; else low. Carries
  -- invitation_id so the GP/assistant can act. Slot formula matches review_tribe_request (#1350).
  SELECT jsonb_agg(jsonb_build_object(
    'severity', CASE WHEN sub.tribe_full OR sub.days_pending > 5 THEN 'high'
                     WHEN sub.days_pending >= 3 THEN 'medium' ELSE 'low' END,
    'type', 'tribe_request_pending',
    'tribe_id', sub.tribe_id, 'tribe_name', sub.tribe_name,
    'requester_name', sub.requester_name, 'invitation_id', sub.invitation_id,
    'days_pending', sub.days_pending, 'expires_at', sub.expires_at,
    'tribe_full', sub.tribe_full, 'slot_count', sub.slot_count, 'cap', sub.cap,
    'message', 'Pedido de ' || sub.requester_name || ' para ' || sub.tribe_name
               || ' pendente há ' || sub.days_pending || ' dia(s)'
               || CASE WHEN sub.tribe_full
                       THEN '. Tribo cheia (' || sub.slot_count || '/' || sub.cap || '), inaprovável sem ação do GP'
                       ELSE '' END
  ))
  INTO v_tmp
  FROM (
    SELECT i.legacy_tribe_id AS tribe_id, i.title AS tribe_name,
      m.name AS requester_name, ii.id AS invitation_id,
      EXTRACT(DAY FROM now() - ii.created_at)::int AS days_pending,
      ii.expires_at, sc.slot_count, v_cap AS cap,
      sc.slot_count >= v_cap AS tribe_full
    FROM initiative_invitations ii
    JOIN initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
    JOIN members m ON m.id = ii.invitee_member_id
    CROSS JOIN LATERAL (
      SELECT count(*)::int AS slot_count FROM members mm
      WHERE mm.tribe_id = i.legacy_tribe_id AND mm.member_status = 'active'
        AND mm.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    ) sc
    WHERE ii.status = 'pending' AND ii.invitee_member_id = ii.inviter_member_id
  ) sub;
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
