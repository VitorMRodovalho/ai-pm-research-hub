-- =====================================================================================
-- #676 Slice 4 — (A) SECURITY FIX for the recurring-meeting auth gate + (B) reconcile cron.
--
-- (A) SECURITY FIX (HIGH): the v_cron heuristic used in slices 1-3 was
--       (current_setting('role') IN ('service_role','postgres') OR
--        current_user IN ('postgres','supabase_admin'))
--     Inside a SECURITY DEFINER function owned by `postgres`, current_user is ALWAYS
--     'postgres' — for authenticated REST callers too. So `current_user IN (...)` was
--     always true => v_cron always true => the manage_platform / leader gate NEVER ran.
--     Any authenticated member (non-GP, non-leader) could read AND modify recurring rules.
--     Verified live: `SET ROLE authenticated; SELECT get_recurring_meeting_admin_list();`
--     returned rows instead of raising Unauthorized.
--
--     Fix: detect the caller via the REQUEST ROLE GUC (the only reliable discriminator):
--     authenticated/anon => REST end-user (enforce auth); anything else (cron job runs as
--     postgres with role GUC unset; service_role) => trusted backend (bypass). All six
--     gated functions are re-emitted with v_cron := NOT _recurring_request_is_rest().
--
-- (B) Cron: reconcile_recurring_meetings_cron() (logs a run summary) scheduled weekly so
--     the operational calendar rolls forward to the horizon without manual reconcile.
-- =====================================================================================

DROP FUNCTION IF EXISTS public._probe_secdef_ctx();

-- ----------------------------------------------------------------------------
-- Reliable caller discriminator (NOT security definer — must read the caller's role GUC).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._recurring_request_is_rest()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public','pg_temp'
AS $function$
  -- True when the call comes from a PostgREST end-user (role GUC = authenticated/anon).
  -- current_user is ALWAYS the SECDEF owner (postgres) and cannot distinguish callers,
  -- so the request role GUC is the only reliable cron/service-vs-user discriminator.
  SELECT coalesce(current_setting('role', true), '') IN ('authenticated','anon');
$function$;

REVOKE ALL ON FUNCTION public._recurring_request_is_rest() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._recurring_request_is_rest() TO authenticated, anon, service_role;

-- ----------------------------------------------------------------------------
-- (A1) reconcile_recurring_meeting — leader-scoped; v_cron fixed.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reconcile_recurring_meeting(
  p_rule_id      uuid,
  p_horizon_end  date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_rule        public.recurring_meeting_rules%ROWTYPE;
  v_cron        boolean;
  v_member      uuid;
  v_start       date;
  v_horizon     date;
  v_d           date;
  v_created     int := 0;
  v_rc          int;
  v_slot_dow    int;
  v_slot_synced boolean := false;
BEGIN
  v_cron := NOT public._recurring_request_is_rest();

  SELECT * INTO v_rule FROM public.recurring_meeting_rules WHERE id = p_rule_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recurring rule not found: %', p_rule_id; END IF;

  -- #676 Slice 3: leader-scoped (GP any; initiative leader own). Cron/service bypass.
  IF NOT v_cron THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
    IF v_member IS NULL OR NOT public._can_manage_recurring_rule(v_member, v_rule.initiative_id) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_platform or initiative leadership';
    END IF;
  END IF;

  v_horizon := COALESCE(p_horizon_end, (current_date + 60));
  v_start   := GREATEST(v_rule.anchor_date, current_date);

  IF v_rule.status = 'active' THEN
    IF v_rule.frequency = 'weekly' THEN
      FOR v_d IN
        SELECT g::date
        FROM generate_series(v_start, v_horizon, interval '1 day') g
        WHERE extract(isodow FROM g)::int = v_rule.day_of_week
      LOOP
        INSERT INTO public.events (
          type, title, date, duration_minutes, duration_actual, meeting_link,
          recurrence_group, is_recorded, audience_level, source, curation_status,
          visibility, nature, time_start, organization_id, initiative_id, timezone, status
        )
        SELECT v_rule.event_type, v_rule.title, v_d, v_rule.duration_minutes, v_rule.duration_minutes,
               v_rule.meeting_link, v_rule.recurrence_group, false, v_rule.audience_level,
               'manual', 'published', v_rule.visibility, 'recorrente', v_rule.time_start,
               v_rule.organization_id, v_rule.initiative_id, v_rule.timezone, 'scheduled'
        WHERE NOT EXISTS (
          SELECT 1 FROM public.events e
          WHERE e.recurrence_group = v_rule.recurrence_group AND e.date = v_d
        );
        GET DIAGNOSTICS v_rc = ROW_COUNT;
        v_created := v_created + v_rc;
      END LOOP;
    ELSE  -- biweekly: stepping 14 days from anchor preserves both weekday and parity
      FOR v_d IN
        SELECT d::date
        FROM generate_series(v_rule.anchor_date, v_horizon, interval '14 days') d
        WHERE d::date >= v_start
      LOOP
        INSERT INTO public.events (
          type, title, date, duration_minutes, duration_actual, meeting_link,
          recurrence_group, is_recorded, audience_level, source, curation_status,
          visibility, nature, time_start, organization_id, initiative_id, timezone, status
        )
        SELECT v_rule.event_type, v_rule.title, v_d, v_rule.duration_minutes, v_rule.duration_minutes,
               v_rule.meeting_link, v_rule.recurrence_group, false, v_rule.audience_level,
               'manual', 'published', v_rule.visibility, 'recorrente', v_rule.time_start,
               v_rule.organization_id, v_rule.initiative_id, v_rule.timezone, 'scheduled'
        WHERE NOT EXISTS (
          SELECT 1 FROM public.events e
          WHERE e.recurrence_group = v_rule.recurrence_group AND e.date = v_d
        );
        GET DIAGNOSTICS v_rc = ROW_COUNT;
        v_created := v_created + v_rc;
      END LOOP;
    END IF;
  END IF;

  -- Derived slot sync (PM decision: tribe_meeting_slots reflects the rule).
  IF v_rule.scope_type = 'tribe' AND v_rule.tribe_id IS NOT NULL THEN
    v_slot_dow := (v_rule.day_of_week % 7);   -- ISO -> pg dow (7 Sun -> 0)
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
    v_slot_synced := true;
  END IF;

  INSERT INTO public.recurring_meeting_rule_audit(rule_id, action, actor_id, new_row)
  VALUES (v_rule.id, 'reconcile', auth.uid(),
          jsonb_build_object('created_events', v_created, 'horizon_end', v_horizon, 'slot_synced', v_slot_synced));

  RETURN jsonb_build_object(
    'rule_id', v_rule.id,
    'status', v_rule.status,
    'created_events', v_created,
    'horizon_end', v_horizon,
    'slot_synced', v_slot_synced
  );
END
$function$;

-- ----------------------------------------------------------------------------
-- (A2) reconcile_all_recurring_meetings — GP/cron; v_cron fixed.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reconcile_all_recurring_meetings(
  p_horizon_end date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_cron   boolean;
  v_r      record;
  v_one    jsonb;
  v_total  int := 0;
  v_rules  int := 0;
BEGIN
  v_cron := NOT public._recurring_request_is_rest();
  IF NOT v_cron THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    PERFORM 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND public.can_by_member(m.id, 'manage_platform');
    IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized: requires manage_platform'; END IF;
  END IF;

  FOR v_r IN SELECT id FROM public.recurring_meeting_rules WHERE status = 'active' LOOP
    v_one   := public.reconcile_recurring_meeting(v_r.id, p_horizon_end);
    v_total := v_total + COALESCE((v_one->>'created_events')::int, 0);
    v_rules := v_rules + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'rules_processed', v_rules,
    'events_created', v_total,
    'horizon_end', COALESCE(p_horizon_end, (current_date + 60))
  );
END
$function$;

-- ----------------------------------------------------------------------------
-- (A3) get_recurring_meeting_drift — manage_platform; v_cron fixed.
-- ----------------------------------------------------------------------------
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
      count(*) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled')::int AS fut,
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

-- ----------------------------------------------------------------------------
-- (A4) get_recurring_meeting_admin_list — manage_platform; v_cron fixed.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_recurring_meeting_admin_list(
  p_horizon_end date DEFAULT NULL
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
  ORDER BY (r.status <> 'active'), r.scope_type, r.title;
END
$function$;

-- ----------------------------------------------------------------------------
-- (A5) update_recurring_meeting_rule — leader-scoped; v_cron fixed.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_recurring_meeting_rule(
  p_rule_id uuid,
  p_patch   jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_cron     boolean;
  v_member   uuid;
  v_rule     public.recurring_meeting_rules%ROWTYPE;
  v_slot_dow int;
BEGIN
  v_cron := NOT public._recurring_request_is_rest();

  SELECT * INTO v_rule FROM public.recurring_meeting_rules WHERE id = p_rule_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recurring rule not found: %', p_rule_id; END IF;

  IF NOT v_cron THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
    IF v_member IS NULL OR NOT public._can_manage_recurring_rule(v_member, v_rule.initiative_id) THEN
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
  END IF;

  RETURN jsonb_build_object('rule_id', v_rule.id, 'status', v_rule.status, 'updated', true);
END
$function$;

-- ----------------------------------------------------------------------------
-- (A6) create_recurring_meeting_rule — leader-scoped; v_cron fixed.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_recurring_meeting_rule(
  p_payload jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_cron       boolean;
  v_member     uuid;
  v_init       uuid := (p_payload->>'initiative_id')::uuid;
  v_tribe      integer;
  v_scope      text;
  v_new_id     uuid;
BEGIN
  v_cron := NOT public._recurring_request_is_rest();

  IF v_init IS NULL THEN RAISE EXCEPTION 'initiative_id is required'; END IF;

  IF NOT v_cron THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
    IF v_member IS NULL OR NOT public._can_manage_recurring_rule(v_member, v_init) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_platform or initiative leadership';
    END IF;
  END IF;

  SELECT legacy_tribe_id INTO v_tribe FROM public.initiatives WHERE id = v_init;
  v_scope := CASE WHEN v_tribe IS NOT NULL THEN 'tribe' ELSE 'initiative' END;

  IF (p_payload->>'frequency') NOT IN ('weekly','biweekly') THEN
    RAISE EXCEPTION 'Invalid frequency: %', p_payload->>'frequency';
  END IF;
  IF (p_payload->>'day_of_week')::int < 1 OR (p_payload->>'day_of_week')::int > 7 THEN
    RAISE EXCEPTION 'Invalid day_of_week: %', p_payload->>'day_of_week';
  END IF;

  INSERT INTO public.recurring_meeting_rules (
    scope_type, initiative_id, tribe_id, title, event_type, audience_level, visibility,
    day_of_week, time_start, duration_minutes, frequency, anchor_date, meeting_link, timezone,
    status, created_by
  ) VALUES (
    v_scope, v_init, v_tribe,
    COALESCE(NULLIF(p_payload->>'title',''), 'Reunião recorrente'),
    COALESCE(NULLIF(p_payload->>'event_type',''), CASE WHEN v_scope = 'tribe' THEN 'tribo' ELSE 'comms' END),
    COALESCE(NULLIF(p_payload->>'audience_level',''), CASE WHEN v_scope = 'tribe' THEN 'tribe' ELSE 'initiative' END),
    COALESCE(NULLIF(p_payload->>'visibility',''), 'all'),
    (p_payload->>'day_of_week')::smallint,
    (p_payload->>'time_start')::time,
    COALESCE((p_payload->>'duration_minutes')::int, 60),
    p_payload->>'frequency',
    COALESCE((p_payload->>'anchor_date')::date, current_date),
    NULLIF(p_payload->>'meeting_link',''),
    COALESCE(NULLIF(p_payload->>'timezone',''), 'America/Sao_Paulo'),
    COALESCE(NULLIF(p_payload->>'status',''), 'active'),
    v_member
  ) RETURNING id INTO v_new_id;

  RETURN v_new_id;
END
$function$;

-- ----------------------------------------------------------------------------
-- (B) Cron wrapper + weekly schedule.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reconcile_recurring_meetings_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_res jsonb;
BEGIN
  -- Runs under pg_cron (postgres, role GUC unset) → reconcile_all's cron path applies.
  v_res := public.reconcile_all_recurring_meetings();  -- default horizon = current_date + 60

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (NULL, 'recurring_meeting.cron_reconcile', 'system_event', NULL,
          v_res, jsonb_build_object('source', 'cron'));

  RETURN v_res;
END
$function$;

-- Not callable from REST (cron runs as postgres/owner). Defense in depth.
REVOKE ALL ON FUNCTION public.reconcile_recurring_meetings_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_recurring_meetings_cron() TO service_role;

-- Weekly, Mondays 06:00 UTC (03:00 BRT) — clear of the 12-14 UTC weekly cluster.
SELECT cron.schedule(
  'reconcile-recurring-meetings-weekly',
  '0 6 * * 1',
  $cron$SELECT public.reconcile_recurring_meetings_cron();$cron$
);

NOTIFY pgrst, 'reload schema';
