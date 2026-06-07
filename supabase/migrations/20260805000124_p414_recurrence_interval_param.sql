-- #414: parametrize recurrence interval (semanal/quinzenal/mensal)
--
-- Adds two trailing optional params to create_recurring_weekly_events:
--   p_interval_days   int DEFAULT 7  -> step in days   (semanal=7, quinzenal=14)
--   p_interval_months int DEFAULT 0  -> step in months (mensal=1; calendar-correct, same day-of-month)
--
-- The per-occurrence date becomes:
--   v_date := (p_start_date + ((v_week-1) * (p_interval_days*INTERVAL '1 day' + p_interval_months*INTERVAL '1 month')))::date
--
-- Defaults (7/0) reproduce the prior weekly behaviour date-identically (backward compatible: every
-- existing named/positional caller that omits the two new args keeps the `+ (v_week-1)*7 days` step).
-- recurrence_group, update_future_events_in_group, and the per-occurrence tribe-slot/ISODOW
-- time_start logic are unchanged.
--
-- Extends issue #414 Option A (`p_interval_days`) with `p_interval_months` so "mensal" is a true
-- calendar month (anchored to the start day, Postgres clamps short months) rather than a drifting
-- 28-day approximation. Both knobs combine in a single interval expression.
--
-- Signature change (param count 10 -> 12) => DROP + CREATE per GC-097 (CREATE OR REPLACE would add a
-- second overload). Verified live (impersonated admin): days=14 -> gap 14d; months=1 -> 01-15/02-15/03-15;
-- defaults -> gap 7d; recurrence_group single per series.
--
-- Rollback: DROP the 12-arg version + recreate the 10-arg body with v_date := p_start_date + ((v_week-1)*7).

DROP FUNCTION IF EXISTS public.create_recurring_weekly_events(text, text, date, integer, integer, text, integer, boolean, text, time without time zone);

CREATE OR REPLACE FUNCTION public.create_recurring_weekly_events(p_type text, p_title_template text, p_start_date date, p_duration_minutes integer DEFAULT 60, p_n_weeks integer DEFAULT 10, p_meeting_link text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_is_recorded boolean DEFAULT false, p_audience_level text DEFAULT NULL::text, p_time_start time without time zone DEFAULT NULL::time without time zone, p_interval_days integer DEFAULT 7, p_interval_months integer DEFAULT 0)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller        RECORD;
  v_group_id      UUID := gen_random_uuid();
  v_week          INTEGER;
  v_date          DATE;
  v_title         TEXT;
  v_ids           UUID[] := '{}';
  v_new_id        UUID;
  v_initiative_id UUID;
  v_time_start    time without time zone;
  v_default_slot  time without time zone;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_caller IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT (v_caller.is_superadmin OR public.can_by_member(v_caller.id, 'manage_event')) THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions: requires manage_event');
  END IF;

  -- #414: a zero net interval would stamp every occurrence on p_start_date. Block it.
  IF COALESCE(p_interval_days, 7) = 0 AND COALESCE(p_interval_months, 0) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Recurrence interval must be non-zero');
  END IF;

  IF v_caller.operational_role = 'tribe_leader' AND NOT v_caller.is_superadmin THEN
    IF p_type NOT IN ('tribo', 'tribe_meeting') THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe meetings');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
  END IF;

  IF p_type = 'tribe_meeting' THEN
    p_type := 'tribo';
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;

    -- Pre-compute the tribe's first slot as fallback when ISODOW does not match
    SELECT time_start INTO v_default_slot
    FROM public.tribe_meeting_slots
    WHERE tribe_id = p_tribe_id
    ORDER BY day_of_week
    LIMIT 1;
  END IF;

  FOR v_week IN 1..p_n_weeks LOOP
    -- #414: step by an arbitrary interval (days and/or calendar months). Defaults 7d/0mo = weekly.
    v_date := (p_start_date
               + ((v_week - 1) * (COALESCE(p_interval_days, 7) * INTERVAL '1 day'
                                  + COALESCE(p_interval_months, 0) * INTERVAL '1 month'))
              )::date;
    v_title := REPLACE(
                 REPLACE(p_title_template, '{n}', v_week::TEXT),
                 '{date}', TO_CHAR(v_date, 'DD/MM')
               );

    -- Per-week time_start: explicit > tribe slot for ISODOW of v_date > tribe first slot > '19:00'
    v_time_start := p_time_start;
    IF v_time_start IS NULL AND p_tribe_id IS NOT NULL THEN
      SELECT time_start INTO v_time_start
      FROM public.tribe_meeting_slots
      WHERE tribe_id = p_tribe_id
        AND day_of_week = EXTRACT(ISODOW FROM v_date)::int
      LIMIT 1;
      v_time_start := COALESCE(v_time_start, v_default_slot);
    END IF;
    v_time_start := COALESCE(v_time_start, '19:00:00'::time);

    INSERT INTO public.events
      (type, title, date, time_start, duration_minutes, initiative_id, meeting_link,
       is_recorded, recurrence_group, created_by, audience_level)
    VALUES
      (p_type, v_title, v_date, v_time_start, p_duration_minutes,
       v_initiative_id, p_meeting_link, p_is_recorded, v_group_id, auth.uid(),
       p_audience_level)
    RETURNING id INTO v_new_id;

    v_ids := array_append(v_ids, v_new_id);
  END LOOP;

  RETURN json_build_object(
    'success',          true,
    'recurrence_group', v_group_id,
    'events_created',   p_n_weeks,
    'event_ids',        v_ids
  );
END;
$function$;

-- Grant matches the sibling event-write RPCs (create_event, update_future_events_in_group): all carry
-- PUBLIC + anon + authenticated + service_role and rely on the fail-closed auth.uid() body gate (anon
-- only ever gets {success:false, Unauthorized}). Restoring the prior-live ACL after the DROP+CREATE;
-- narrowing it here would make this one RPC inconsistent with the rest of the events surface.
GRANT EXECUTE ON FUNCTION public.create_recurring_weekly_events(text, text, date, integer, integer, text, integer, boolean, text, time without time zone, integer, integer) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
