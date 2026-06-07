-- #485: explicit timezone selector for event scheduling.
-- Adds p_timezone to create_event + create_recurring_weekly_events (writes events.timezone),
-- and surfaces events.timezone from get_events_with_attendance (so the card badge + edit modal read it).
-- Picker offers slash-containing IANA zones only (events_timezone_check requires '/'; UTC users pick Etc/UTC);
-- the RPCs coerce NULL/PG-unknown zones to the America/Sao_Paulo default (fail-safe). DROP+CREATE per GC-097.
--
-- Signature changes:
--   create_event                    14 -> 15 args (+p_timezone text DEFAULT 'America/Sao_Paulo')
--   create_recurring_weekly_events  12 -> 13 args (+p_timezone text DEFAULT 'America/Sao_Paulo')
--   get_events_with_attendance      RETURNS TABLE gains `timezone text` (return-type change => DROP+CREATE)
--
-- Rollback: recreate the pre-#485 bodies (no p_timezone; events.timezone keeps its column default
-- 'America/Sao_Paulo', so existing rows are unaffected). DROP signatures to recreate from:
--   DROP FUNCTION public.create_event(text,text,date,integer,integer,text,text,text,text,text,text[],uuid[],text,time without time zone,text);
--   DROP FUNCTION public.create_recurring_weekly_events(text,text,date,integer,integer,text,integer,boolean,text,time without time zone,integer,integer,text);
--   DROP FUNCTION public.get_events_with_attendance(integer,integer);  -- recreate WITHOUT the timezone column; restore TO authenticated

DROP FUNCTION IF EXISTS public.create_event(text, text, date, integer, integer, text, text, text, text, text, text[], uuid[], text, time without time zone);

CREATE OR REPLACE FUNCTION public.create_event(p_type text, p_title text, p_date date, p_duration_minutes integer DEFAULT 90, p_tribe_id integer DEFAULT NULL::integer, p_meeting_link text DEFAULT NULL::text, p_nature text DEFAULT 'recorrente'::text, p_visibility text DEFAULT 'all'::text, p_agenda_text text DEFAULT NULL::text, p_agenda_url text DEFAULT NULL::text, p_external_attendees text[] DEFAULT NULL::text[], p_invited_member_ids uuid[] DEFAULT NULL::uuid[], p_audience_level text DEFAULT NULL::text, p_time_start time without time zone DEFAULT NULL::time without time zone, p_timezone text DEFAULT 'America/Sao_Paulo'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_tribe_id integer;
  v_is_admin boolean;
  v_event_id uuid;
  v_audience text;
  v_initiative_id uuid;
  v_time_start time without time zone;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_member_tribe_id
  FROM members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT public.can_by_member(v_member_id, 'manage_event') THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized: requires manage_event permission');
  END IF;

  IF p_type NOT IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN
    RETURN json_build_object('success', false, 'error', 'Invalid event type: ' || p_type);
  END IF;

  IF p_nature NOT IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN
    p_nature := 'avulsa';
  END IF;

  IF p_type IN ('parceria','entrevista','1on1') THEN
    p_visibility := 'gp_only';
  ELSIF p_visibility NOT IN ('all','leadership','gp_only') THEN
    p_visibility := 'all';
  END IF;

  IF p_type = 'tribo' AND p_tribe_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'tribe_id required for tribe events');
  END IF;

  -- #485: coerce NULL/unknown timezone to the default (fail-safe; picker is IANA-constrained, but a
  -- direct/legacy caller could pass anything). pg_timezone_names is the authoritative IANA validity check.
  IF p_timezone IS NULL OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_timezone) THEN
    p_timezone := 'America/Sao_Paulo';
  END IF;

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    IF p_type NOT IN ('tribo') THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe events');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_member_tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
    p_external_attendees := NULL;
    p_invited_member_ids := NULL;
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  v_audience := COALESCE(p_audience_level,
    CASE p_type
      WHEN 'tribo'     THEN 'tribe'
      WHEN 'lideranca' THEN 'leadership'
      WHEN 'comms'     THEN 'leadership'
      ELSE 'all'
    END
  );

  -- Derive time_start: explicit param > tribe slot for ISODOW > tribe first slot > '19:00'
  v_time_start := p_time_start;
  IF v_time_start IS NULL AND p_tribe_id IS NOT NULL THEN
    SELECT time_start INTO v_time_start
    FROM public.tribe_meeting_slots
    WHERE tribe_id = p_tribe_id
      AND day_of_week = EXTRACT(ISODOW FROM p_date)::int
    LIMIT 1;
    IF v_time_start IS NULL THEN
      SELECT time_start INTO v_time_start
      FROM public.tribe_meeting_slots
      WHERE tribe_id = p_tribe_id
      ORDER BY day_of_week
      LIMIT 1;
    END IF;
  END IF;
  v_time_start := COALESCE(v_time_start, '19:00:00'::time);

  INSERT INTO events (
    type, title, date, time_start, duration_minutes,
    initiative_id,
    audience_level, meeting_link,
    nature, visibility, agenda_text, agenda_url,
    external_attendees, invited_member_ids, created_by, timezone
  )
  VALUES (
    p_type, p_title, p_date, v_time_start, p_duration_minutes,
    v_initiative_id,
    v_audience, p_meeting_link,
    p_nature, p_visibility, p_agenda_text, p_agenda_url,
    p_external_attendees, p_invited_member_ids, auth.uid(), p_timezone
  )
  RETURNING id INTO v_event_id;

  IF p_agenda_text IS NOT NULL OR p_agenda_url IS NOT NULL THEN
    UPDATE events SET agenda_posted_at = now(), agenda_posted_by = v_member_id
    WHERE id = v_event_id;
  END IF;

  RETURN json_build_object('success', true, 'event_id', v_event_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_event(text, text, date, integer, integer, text, text, text, text, text, text[], uuid[], text, time without time zone, text) TO anon, authenticated, service_role;


DROP FUNCTION IF EXISTS public.create_recurring_weekly_events(text, text, date, integer, integer, text, integer, boolean, text, time without time zone, integer, integer);

CREATE OR REPLACE FUNCTION public.create_recurring_weekly_events(p_type text, p_title_template text, p_start_date date, p_duration_minutes integer DEFAULT 60, p_n_weeks integer DEFAULT 10, p_meeting_link text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_is_recorded boolean DEFAULT false, p_audience_level text DEFAULT NULL::text, p_time_start time without time zone DEFAULT NULL::time without time zone, p_interval_days integer DEFAULT 7, p_interval_months integer DEFAULT 0, p_timezone text DEFAULT 'America/Sao_Paulo'::text)
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

  -- #485: coerce NULL/unknown timezone to the default (fail-safe; picker is IANA-constrained).
  IF p_timezone IS NULL OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_timezone) THEN
    p_timezone := 'America/Sao_Paulo';
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
       is_recorded, recurrence_group, created_by, audience_level, timezone)
    VALUES
      (p_type, v_title, v_date, v_time_start, p_duration_minutes,
       v_initiative_id, p_meeting_link, p_is_recorded, v_group_id, auth.uid(),
       p_audience_level, p_timezone)
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

GRANT EXECUTE ON FUNCTION public.create_recurring_weekly_events(text, text, date, integer, integer, text, integer, boolean, text, time without time zone, integer, integer, text) TO anon, authenticated, service_role;


DROP FUNCTION IF EXISTS public.get_events_with_attendance(integer, integer);

CREATE OR REPLACE FUNCTION public.get_events_with_attendance(p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, title text, date date, type text, nature text, duration_minutes integer, time_start time without time zone, timezone text, meeting_link text, youtube_url text, is_recorded boolean, audience_level text, tribe_id integer, attendee_count bigint, agenda_text text, agenda_url text, minutes_text text, minutes_url text, recording_url text, recording_type text, notes text, visibility text, external_attendees text[], recurrence_group uuid, initiative_id uuid, initiative_name text, status text, cancelled_at timestamp with time zone, cancellation_reason text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    e.id, e.title, e.date, e.type, e.nature,
    e.duration_minutes, e.time_start, e.timezone, e.meeting_link,
    e.youtube_url, e.is_recorded, e.audience_level,
    i.legacy_tribe_id AS tribe_id,
    (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id AND a.present = true) AS attendee_count,
    e.agenda_text, e.agenda_url,
    e.minutes_text, e.minutes_url,
    e.recording_url, e.recording_type,
    e.notes, e.visibility,
    e.external_attendees, e.recurrence_group,
    e.initiative_id,
    i.title AS initiative_name,
    e.status, e.cancelled_at, e.cancellation_reason
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
$function$;

-- #485 security (council BLOCKER): get_events_with_attendance is SECURITY DEFINER with NO body auth gate
-- and bypasses RLS — it returns ALL events including external_attendees (PII), meeting_links and gp_only
-- events. It must never be anon/PUBLIC-callable (the sole caller is the authenticated /attendance page).
-- Close the pre-existing PUBLIC/anon exposure (the live ACL carried =X PUBLIC + anon) — restrict to
-- authenticated + service_role. (Unlike the write RPCs above, this reader has no fail-closed auth.uid() gate.)
REVOKE EXECUTE ON FUNCTION public.get_events_with_attendance(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_events_with_attendance(integer, integer) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
