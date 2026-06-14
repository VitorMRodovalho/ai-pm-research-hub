-- =====================================================================================
-- #676 Slice 3 (write-path, V4-scoped): edit / create / reconcile recurring rules.
--
-- Authority (PM 2026-06-14): manage_platform (GP) manages ANY rule; the initiative
-- LEADER manages only rules of their own initiative. Leader resolution reuses the
-- canonical v_initiative_roster role='leader' pattern shipped in #666.
--
-- Lands:
--   1. _can_manage_recurring_rule(member, initiative) — shared authority predicate.
--   2. update_recurring_meeting_rule(rule, patch) — patch allowed fields; re-syncs the
--      derived tribe slot; the existing audit trigger records the change.
--   3. create_recurring_meeting_rule(payload) — new rule; scope derived from the
--      initiative's legacy_tribe_id.
--   4. reconcile_recurring_meeting — per-rule gate WIDENED from manage_platform-only to
--      leader-scoped (full body re-captured here so live == latest migration capture).
--      reconcile_all stays GP/cron-only (global job).
-- =====================================================================================

-- ----------------------------------------------------------------------------
-- 1) Shared authority predicate
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._can_manage_recurring_rule(
  p_member_id     uuid,
  p_initiative_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
  SELECT public.can_by_member(p_member_id, 'manage_platform')
      OR (p_initiative_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.v_initiative_roster r
            WHERE r.initiative_id = p_initiative_id
              AND r.member_id = p_member_id
              AND r.role = 'leader'));
$function$;

REVOKE ALL ON FUNCTION public._can_manage_recurring_rule(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._can_manage_recurring_rule(uuid, uuid) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2) Update a rule (patch jsonb of allowed fields); re-sync derived slot.
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
  v_cron := (current_setting('role', true) IN ('service_role','postgres')
             OR current_user IN ('postgres','supabase_admin'));

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

REVOKE ALL ON FUNCTION public.update_recurring_meeting_rule(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_recurring_meeting_rule(uuid, jsonb) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) Create a rule; scope derived from the initiative's legacy_tribe_id.
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
  v_cron := (current_setting('role', true) IN ('service_role','postgres')
             OR current_user IN ('postgres','supabase_admin'));

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

REVOKE ALL ON FUNCTION public.create_recurring_meeting_rule(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_recurring_meeting_rule(jsonb) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4) Reconcile per-rule: WIDEN gate to leader-scoped (re-capture full body).
--    Loads the rule first, then gates via _can_manage_recurring_rule.
--    reconcile_all_recurring_meetings stays GP/cron-only (unchanged).
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
  v_cron := (current_setting('role', true) IN ('service_role','postgres')
             OR current_user IN ('postgres','supabase_admin'));

  SELECT * INTO v_rule FROM public.recurring_meeting_rules WHERE id = p_rule_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recurring rule not found: %', p_rule_id; END IF;

  -- #676 Slice 3: leader-scoped (GP any; initiative leader own). Cron bypasses.
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

NOTIFY pgrst, 'reload schema';
