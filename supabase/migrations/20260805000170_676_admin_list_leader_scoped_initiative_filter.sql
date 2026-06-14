-- =====================================================================================
-- #676 Slice B — leader-scope the recurring-meeting read RPC with an initiative filter.
--
-- Serves TWO surfaces from one function:
--   - A (GP centralized screen): call with p_initiative_id = NULL → manage_platform only,
--     returns ALL rules (unchanged behavior).
--   - B (leader self-service panel on the initiative page): call with p_initiative_id set →
--     GP OR the leader of that initiative (via _can_manage_recurring_rule), returns that
--     initiative's rules only. RAISES if the caller can manage neither (so the panel self-gates).
--
-- Signature changes (param count) → DROP + CREATE per GC-097. Re-grant after.
-- =====================================================================================

DROP FUNCTION IF EXISTS public.get_recurring_meeting_admin_list(date);

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
      count(*) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled')::int AS fut,
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

REVOKE ALL ON FUNCTION public.get_recurring_meeting_admin_list(date, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_recurring_meeting_admin_list(date, uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
