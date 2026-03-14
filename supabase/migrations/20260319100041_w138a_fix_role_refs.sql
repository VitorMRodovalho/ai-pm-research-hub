-- W138a: Fix broken RPCs referencing dropped 'role' column → 'operational_role'
-- Only functions that reference members.role are fixed. Functions using
-- board_item_assignments.role (get_board, auto_publish_approved_article) are fine.

-- ============================================================================
-- 1. create_event(text, text, date, integer, integer) — old 5-param overload
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_event(p_type text, p_title text, p_date date, p_duration_minutes integer, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member    RECORD;
  v_event_id  UUID;
BEGIN
  SELECT m.* INTO v_member
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_member IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Permission check (fixed: operational_role instead of role)
  IF v_member.is_superadmin THEN
    NULL;
  ELSIF v_member.operational_role = 'tribe_leader' THEN
    IF p_type = 'general_meeting' THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe events');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_member.tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
  ELSE
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;

  INSERT INTO public.events (type, title, date, duration_minutes, tribe_id, created_by)
  VALUES (p_type, p_title, p_date, p_duration_minutes, p_tribe_id, auth.uid())
  RETURNING id INTO v_event_id;

  RETURN json_build_object('success', true, 'event_id', v_event_id);
END;
$function$;

-- ============================================================================
-- 2. create_event(text, text, date, integer, integer, text) — 6-param overload
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_event(p_type text, p_title text, p_date date, p_duration_minutes integer, p_tribe_id integer DEFAULT NULL::integer, p_audience_level text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member    RECORD;
  v_event_id  UUID;
  v_audience  TEXT;
BEGIN
  SELECT m.* INTO v_member
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_member IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Permission check (fixed: operational_role instead of role)
  IF v_member.is_superadmin THEN
    NULL;
  ELSIF v_member.operational_role = 'tribe_leader' THEN
    IF p_type = 'general_meeting' THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe events');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_member.tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
  ELSE
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;

  v_audience := COALESCE(p_audience_level,
    CASE p_type
      WHEN 'tribe_meeting'   THEN 'tribe'
      WHEN 'general_meeting' THEN 'all'
      WHEN 'webinar'         THEN 'all'
      ELSE 'all'
    END
  );

  INSERT INTO public.events (type, title, date, duration_minutes, tribe_id, audience_level, created_by)
  VALUES (p_type, p_title, p_date, p_duration_minutes, p_tribe_id, v_audience, auth.uid())
  RETURNING id INTO v_event_id;

  RETURN json_build_object('success', true, 'event_id', v_event_id);
END;
$function$;

-- ============================================================================
-- 3. update_event — 7-param overload
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_event(p_event_id uuid, p_title text DEFAULT NULL::text, p_date date DEFAULT NULL::date, p_duration_minutes integer DEFAULT NULL::integer, p_meeting_link text DEFAULT NULL::text, p_is_recorded boolean DEFAULT NULL::boolean, p_youtube_url text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller RECORD;
  v_event  RECORD;
  v_allowed BOOLEAN := false;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_caller IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Event not found');
  END IF;

  -- Permission check (fixed: operational_role instead of role)
  IF v_caller.is_superadmin THEN
    v_allowed := true;
  ELSIF v_caller.operational_role = 'tribe_leader'
    AND v_event.type = 'tribe_meeting'
    AND v_event.tribe_id = v_caller.tribe_id THEN
    v_allowed := true;
  ELSIF v_event.created_by = auth.uid() THEN
    v_allowed := true;
  END IF;

  IF NOT v_allowed THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;

  UPDATE public.events SET
    title            = COALESCE(p_title,            title),
    date             = COALESCE(p_date,             date),
    duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
    meeting_link     = COALESCE(p_meeting_link,     meeting_link),
    is_recorded      = COALESCE(p_is_recorded,      is_recorded),
    youtube_url      = COALESCE(p_youtube_url,      youtube_url),
    updated_at       = now()
  WHERE id = p_event_id;

  RETURN json_build_object('success', true);
END;
$function$;

-- ============================================================================
-- 4. update_event — 8-param overload (with audience_level)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_event(p_event_id uuid, p_title text DEFAULT NULL::text, p_date date DEFAULT NULL::date, p_duration_minutes integer DEFAULT NULL::integer, p_meeting_link text DEFAULT NULL::text, p_is_recorded boolean DEFAULT NULL::boolean, p_youtube_url text DEFAULT NULL::text, p_audience_level text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller  RECORD;
  v_event   RECORD;
  v_allowed BOOLEAN := false;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;

  IF v_caller IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Event not found');
  END IF;

  -- Permission check (fixed: operational_role instead of role)
  IF v_caller.is_superadmin THEN v_allowed := true;
  ELSIF v_caller.operational_role = 'tribe_leader'
    AND v_event.type = 'tribe_meeting'
    AND v_event.tribe_id = v_caller.tribe_id THEN v_allowed := true;
  ELSIF v_event.created_by = auth.uid() THEN v_allowed := true;
  END IF;

  IF NOT v_allowed THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;

  UPDATE public.events SET
    title            = COALESCE(p_title,            title),
    date             = COALESCE(p_date,             date),
    duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
    meeting_link     = COALESCE(p_meeting_link,     meeting_link),
    is_recorded      = COALESCE(p_is_recorded,      is_recorded),
    youtube_url      = COALESCE(p_youtube_url,      youtube_url),
    audience_level   = COALESCE(p_audience_level,   audience_level),
    updated_at       = now()
  WHERE id = p_event_id;

  RETURN json_build_object('success', true);
END;
$function$;

-- ============================================================================
-- 5. create_recurring_weekly_events
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_recurring_weekly_events(p_type text, p_title_template text, p_start_date date, p_duration_minutes integer, p_n_weeks integer, p_meeting_link text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_is_recorded boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller   RECORD;
  v_group_id UUID := gen_random_uuid();
  v_week     INTEGER;
  v_date     DATE;
  v_title    TEXT;
  v_ids      UUID[] := '{}';
  v_new_id   UUID;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_caller IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Permission check (fixed: operational_role instead of role)
  IF v_caller.is_superadmin THEN
    NULL;
  ELSIF v_caller.operational_role = 'tribe_leader' THEN
    IF p_type != 'tribe_meeting' THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe meetings');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
  ELSE
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;

  FOR v_week IN 1..p_n_weeks LOOP
    v_date  := p_start_date + ((v_week - 1) * 7);
    v_title := REPLACE(
                 REPLACE(p_title_template, '{n}', v_week::TEXT),
                 '{date}', TO_CHAR(v_date, 'DD/MM')
               );

    INSERT INTO public.events
      (type, title, date, duration_minutes, tribe_id, meeting_link,
       is_recorded, recurrence_group, created_by)
    VALUES
      (p_type, v_title, v_date, p_duration_minutes,
       p_tribe_id, p_meeting_link, p_is_recorded, v_group_id, auth.uid())
    RETURNING id INTO v_new_id;

    v_ids := array_append(v_ids, v_new_id);
  END LOOP;

  RETURN json_build_object(
    'success',        true,
    'recurrence_group', v_group_id,
    'events_created', p_n_weeks,
    'event_ids',      v_ids
  );
END;
$function$;
