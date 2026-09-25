-- #2470: get_recurring_meeting_drift e get_recurring_meeting_admin_list comparavam janelas diferentes.
-- expected_future conta ocorrencias ate v_horizon; future_events contava TODO evento futuro agendado,
-- sem teto. Uma regra materializada alem do horizonte (ex.: ate o fim do ano) aparecia como
-- "materializadas > esperadas" (serie duplicada) sem ter duplicata. Agora future_events tambem para em
-- v_horizon. So a linha do fut muda; corpo, assinatura, SECURITY DEFINER, search_path e grants preservados
-- (CREATE OR REPLACE mantem os privilegios). Corpos de origem: 20260805000167 (drift) e
-- 20260805000170 (admin_list), identicos ao vivo por md5 normalizado em 25/09/2026.

CREATE OR REPLACE FUNCTION public.get_recurring_meeting_drift(
  p_horizon_end date DEFAULT NULL
)
RETURNS TABLE (
  rule_id          uuid,
  scope_type       text,
  title            text,
  status           text,
  frequency        text,
  day_of_week      smallint,
  time_start       time,
  next_occurrence  date,
  future_events    int,
  expected_future  int,
  missing_future   int,
  time_mismatch    int,
  link_mismatch    int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_cron    boolean;
  v_horizon date;
BEGIN
  v_cron := NOT public._recurring_request_is_rest();
  IF NOT v_cron THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    PERFORM 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND public.can_by_member(m.id, 'manage_platform');
    IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized: requires manage_platform'; END IF;
  END IF;

  v_horizon := COALESCE(p_horizon_end, (current_date + 60));

  RETURN QUERY
  WITH expected AS (
    SELECT r.id AS rule_id,
      CASE WHEN r.frequency = 'weekly' THEN (
        SELECT count(*)::int
        FROM generate_series(GREATEST(r.anchor_date, current_date), v_horizon, interval '1 day') g
        WHERE extract(isodow FROM g)::int = r.day_of_week
      ) ELSE (
        SELECT count(*)::int
        FROM generate_series(r.anchor_date, v_horizon, interval '14 days') d
        WHERE d::date >= current_date
      ) END AS expected_cnt
    FROM public.recurring_meeting_rules r
    WHERE r.status = 'active'
  ),
  ev AS (
    SELECT r.id AS rule_id,
      count(*) FILTER (WHERE e.date >= current_date AND e.date <= v_horizon AND e.status = 'scheduled')::int AS fut,
      min(e.date) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled') AS nxt,
      count(*) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled'
                         AND e.time_start IS DISTINCT FROM r.time_start)::int AS tmm,
      count(*) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled'
                         AND e.meeting_link IS DISTINCT FROM r.meeting_link)::int AS lmm
    FROM public.recurring_meeting_rules r
    LEFT JOIN public.events e ON e.recurrence_group = r.recurrence_group
    GROUP BY r.id
  )
  SELECT r.id, r.scope_type, r.title, r.status, r.frequency, r.day_of_week, r.time_start,
         ev.nxt,
         COALESCE(ev.fut, 0),
         COALESCE(ex.expected_cnt, 0),
         GREATEST(COALESCE(ex.expected_cnt, 0) - COALESCE(ev.fut, 0), 0),
         COALESCE(ev.tmm, 0),
         COALESCE(ev.lmm, 0)
  FROM public.recurring_meeting_rules r
  LEFT JOIN expected ex ON ex.rule_id = r.id
  LEFT JOIN ev        ON ev.rule_id = r.id
  ORDER BY r.scope_type, r.title;
END
$function$;

CREATE OR REPLACE FUNCTION public.get_recurring_meeting_admin_list(
  p_horizon_end   date DEFAULT NULL,
  p_initiative_id uuid DEFAULT NULL
)
RETURNS TABLE (
  rule_id            uuid,
  scope_type         text,
  scope_name         text,
  title              text,
  event_type         text,
  day_of_week        smallint,
  time_start         time,
  duration_minutes   integer,
  frequency          text,
  timezone           text,
  status             text,
  meeting_link       text,
  anchor_date        date,
  next_occurrence    date,
  future_events      int,
  expected_future    int,
  missing_future     int,
  time_mismatch      int,
  link_mismatch      int,
  last_reconciled_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_cron    boolean;
  v_member  uuid;
  v_horizon date;
BEGIN
  v_cron := NOT public._recurring_request_is_rest();
  IF NOT v_cron THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
    IF v_member IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    IF p_initiative_id IS NOT NULL THEN
      -- B surface (scoped): GP or the leader of THIS initiative.
      IF NOT public._can_manage_recurring_rule(v_member, p_initiative_id) THEN
        RAISE EXCEPTION 'Unauthorized: requires manage_platform or initiative leadership';
      END IF;
    ELSE
      -- A surface (global): GP only.
      IF NOT public.can_by_member(v_member, 'manage_platform') THEN
        RAISE EXCEPTION 'Unauthorized: requires manage_platform';
      END IF;
    END IF;
  END IF;

  v_horizon := COALESCE(p_horizon_end, (current_date + 60));

  RETURN QUERY
  WITH ev AS (
    SELECT r.id AS rule_id,
      count(*) FILTER (WHERE e.date >= current_date AND e.date <= v_horizon AND e.status = 'scheduled')::int AS fut,
      min(e.date) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled') AS nxt,
      count(*) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled'
                         AND e.time_start IS DISTINCT FROM r.time_start)::int AS tmm,
      count(*) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled'
                         AND e.meeting_link IS DISTINCT FROM r.meeting_link)::int AS lmm
    FROM public.recurring_meeting_rules r
    LEFT JOIN public.events e ON e.recurrence_group = r.recurrence_group
    GROUP BY r.id
  ),
  recon AS (
    SELECT a.rule_id, max(a.changed_at) AS last_at
    FROM public.recurring_meeting_rule_audit a
    WHERE a.action = 'reconcile'
    GROUP BY a.rule_id
  )
  SELECT
    r.id,
    r.scope_type,
    COALESCE(i.title, initcap(r.scope_type)) AS scope_name,
    r.title,
    r.event_type,
    r.day_of_week,
    r.time_start,
    r.duration_minutes,
    r.frequency,
    r.timezone,
    r.status,
    r.meeting_link,
    r.anchor_date,
    ev.nxt,
    COALESCE(ev.fut, 0),
    -- expected future occurrences only meaningful while active
    CASE WHEN r.status = 'active' THEN (
      CASE WHEN r.frequency = 'weekly' THEN (
        SELECT count(*)::int
        FROM generate_series(GREATEST(r.anchor_date, current_date), v_horizon, interval '1 day') g
        WHERE extract(isodow FROM g)::int = r.day_of_week
      ) ELSE (
        SELECT count(*)::int
        FROM generate_series(r.anchor_date, v_horizon, interval '14 days') d
        WHERE d::date >= current_date
      ) END
    ) ELSE 0 END AS expected_future,
    CASE WHEN r.status = 'active' THEN GREATEST(
      (CASE WHEN r.frequency = 'weekly' THEN (
        SELECT count(*)::int FROM generate_series(GREATEST(r.anchor_date, current_date), v_horizon, interval '1 day') g
        WHERE extract(isodow FROM g)::int = r.day_of_week
      ) ELSE (
        SELECT count(*)::int FROM generate_series(r.anchor_date, v_horizon, interval '14 days') d
        WHERE d::date >= current_date
      ) END) - COALESCE(ev.fut, 0), 0)
    ELSE 0 END AS missing_future,
    COALESCE(ev.tmm, 0),
    COALESCE(ev.lmm, 0),
    recon.last_at
  FROM public.recurring_meeting_rules r
  LEFT JOIN public.initiatives i ON i.id = r.initiative_id
  LEFT JOIN ev    ON ev.rule_id = r.id
  LEFT JOIN recon ON recon.rule_id = r.id
  WHERE (p_initiative_id IS NULL OR r.initiative_id = p_initiative_id)
  ORDER BY (r.status <> 'active'), r.scope_type, r.title;
END
$function$;
