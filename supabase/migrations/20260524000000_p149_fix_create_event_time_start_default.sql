-- p149 hotfix (2026-05-11) — Bug live: Tribo 2 (Agentes Autônomos) leader could not register attendance during their 19:30 meeting.
--
-- Root cause:
--   * create_event and create_recurring_weekly_events never inserted time_start,
--     leaving the column NULL on 263 of 289 events (91%).
--   * Frontend isInCheckinWindow fell back to '23:59' when time_start was NULL,
--     pushing the self-checkin window to 21:59 local. Researchers saw "Check-in
--     encerrado" all day until almost midnight, even with a meeting at 19:30.
--
-- Fix in this migration:
--   * Both RPCs accept new optional p_time_start parameter (appended at end —
--     existing positional callers in attendance.astro and nucleo-mcp unaffected).
--   * Derivation order when p_time_start is NULL:
--       1. tribe_meeting_slots row matching ISODOW of the event date
--       2. tribe_meeting_slots first slot for the tribe (any day)
--       3. '19:00:00' final fallback
--   * Frontend hotfix in src/pages/attendance.astro: isInCheckinWindow treats
--     NULL time_start as all-day (window opens 00:00, closes 48h after end-of-day).
--
-- Backfill of pre-existing 263 NULL rows already executed via execute_sql in the
-- same session before this DDL:
--   Pass 1 — tribo events with ISODOW match → tribe slot time
--   Pass 2 — tribo events with no ISODOW match → first slot for that tribe
--   Pass 3 — non-tribo events → '19:00:00'
-- Result: 0 NULL time_start rows in events.
--
-- Rollback: drop the new functions and recreate the prior signatures (see
-- supabase/migrations/20260428050000_adr0015_phase3e_events_drop_tribe_id.sql
-- for the previous create_event body, and check pg_get_functiondef snapshot in
-- session log for create_recurring_weekly_events). Restore NULL time_start by
-- replaying the migration backwards is NOT recommended — leave backfilled values
-- in place even if RPC changes are reverted.

DROP FUNCTION IF EXISTS public.create_event(text, text, date, integer, integer, text, text, text, text, text, text[], uuid[], text);

CREATE OR REPLACE FUNCTION public.create_event(
  p_type text, p_title text, p_date date,
  p_duration_minutes integer DEFAULT 90,
  p_tribe_id integer DEFAULT NULL::integer,
  p_meeting_link text DEFAULT NULL::text,
  p_nature text DEFAULT 'recorrente'::text,
  p_visibility text DEFAULT 'all'::text,
  p_agenda_text text DEFAULT NULL::text,
  p_agenda_url text DEFAULT NULL::text,
  p_external_attendees text[] DEFAULT NULL::text[],
  p_invited_member_ids uuid[] DEFAULT NULL::uuid[],
  p_audience_level text DEFAULT NULL::text,
  p_time_start time without time zone DEFAULT NULL::time without time zone
)
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
    external_attendees, invited_member_ids, created_by
  )
  VALUES (
    p_type, p_title, p_date, v_time_start, p_duration_minutes,
    v_initiative_id,
    v_audience, p_meeting_link,
    p_nature, p_visibility, p_agenda_text, p_agenda_url,
    p_external_attendees, p_invited_member_ids, auth.uid()
  )
  RETURNING id INTO v_event_id;

  IF p_agenda_text IS NOT NULL OR p_agenda_url IS NOT NULL THEN
    UPDATE events SET agenda_posted_at = now(), agenda_posted_by = v_member_id
    WHERE id = v_event_id;
  END IF;

  RETURN json_build_object('success', true, 'event_id', v_event_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_event(text, text, date, integer, integer, text, text, text, text, text, text[], uuid[], text, time without time zone) TO authenticated;

DROP FUNCTION IF EXISTS public.create_recurring_weekly_events(text, text, date, integer, integer, text, integer, boolean, text);

CREATE OR REPLACE FUNCTION public.create_recurring_weekly_events(
  p_type text, p_title_template text, p_start_date date,
  p_duration_minutes integer DEFAULT 60,
  p_n_weeks integer DEFAULT 10,
  p_meeting_link text DEFAULT NULL::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_is_recorded boolean DEFAULT false,
  p_audience_level text DEFAULT NULL::text,
  p_time_start time without time zone DEFAULT NULL::time without time zone
)
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

    SELECT time_start INTO v_default_slot
    FROM public.tribe_meeting_slots
    WHERE tribe_id = p_tribe_id
    ORDER BY day_of_week
    LIMIT 1;
  END IF;

  FOR v_week IN 1..p_n_weeks LOOP
    v_date  := p_start_date + ((v_week - 1) * 7);
    v_title := REPLACE(
                 REPLACE(p_title_template, '{n}', v_week::TEXT),
                 '{date}', TO_CHAR(v_date, 'DD/MM')
               );

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

GRANT EXECUTE ON FUNCTION public.create_recurring_weekly_events(text, text, date, integer, integer, text, integer, boolean, text, time without time zone) TO authenticated;

NOTIFY pgrst, 'reload schema';
