-- Migration: update_future_events_in_group — coerce invalid p_visibility (parity with create_event)
-- Bug (PM-hit 2026-06-11): the attendance edit modal sent p_visibility='public' (a value that never
--   existed in the DB vocab — events_visibility_check allows 'all'|'leadership'|'gp_only') and the
--   whole group update bombed with 400 "violates check constraint events_visibility_check", blocking
--   the PM from reclassifying mistyped events. create_event already coerces unknown→'all' (which is
--   why CREATION with the same bad vocab silently worked); this RPC did not.
-- Frontend vocab is fixed in the same PR (option value 'public'→'all' in both modals + 4 literals in
--   attendance.astro); this server-side coerce is defense-in-depth for stale bundles/legacy callers.
-- Body below is verbatim from live pg_get_functiondef (2026-06-11) + ONLY the coerce block added
--   after the nature validation. Zero-arg-change → CREATE OR REPLACE is safe (args checked via
--   pg_get_function_arguments incl. DEFAULTs).
--
-- ROLLBACK: restore previous body (capture in 20260805000xxx #564 timezone migration / live history)
--   by removing the "coerce visibility" block.
--
-- After apply: NOTIFY pgrst, 'reload schema'.

CREATE OR REPLACE FUNCTION public.update_future_events_in_group(p_event_id uuid, p_new_time_start time without time zone DEFAULT NULL::time without time zone, p_duration_minutes integer DEFAULT NULL::integer, p_meeting_link text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_visibility text DEFAULT NULL::text, p_type text DEFAULT NULL::text, p_nature text DEFAULT NULL::text, p_timezone text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_date date;
  v_rec_group uuid;
  v_updated_count int;
  v_safe_tz text;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid() ORDER BY created_at DESC LIMIT 1;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT i.legacy_tribe_id, e.date, e.recurrence_group
    INTO v_event_tribe, v_event_date, v_rec_group
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;
  IF v_rec_group IS NULL THEN RAISE EXCEPTION 'Event is not part of a recurring series'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  IF p_type IS NOT NULL AND p_type NOT IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN
    RAISE EXCEPTION 'Invalid event type: %', p_type;
  END IF;
  IF p_nature IS NOT NULL AND p_nature NOT IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN
    RAISE EXCEPTION 'Invalid event nature: %', p_nature;
  END IF;

  -- Parity with create_event (PM-hit 2026-06-11): coerce unknown visibility vocab (e.g. legacy
  -- 'public') to 'all' instead of bombing the whole group update on events_visibility_check.
  IF p_visibility IS NOT NULL AND p_visibility NOT IN ('all','leadership','gp_only') THEN
    p_visibility := 'all';
  END IF;

  -- #564: coerce timezone (NULL/'' = keep existing; unknown IANA name -> BRT default; parity with create_event).
  v_safe_tz := CASE
    WHEN p_timezone IS NULL OR p_timezone = '' THEN NULL
    WHEN EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_timezone) THEN p_timezone
    ELSE 'America/Sao_Paulo' END;

  WITH updated AS (
    UPDATE public.events SET
      time_start = COALESCE(p_new_time_start, time_start),
      duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
      meeting_link = COALESCE(p_meeting_link, meeting_link),
      notes = COALESCE(p_notes, notes),
      visibility = COALESCE(p_visibility, visibility),
      type = COALESCE(p_type, type),
      nature = COALESCE(p_nature, nature),
      timezone = COALESCE(v_safe_tz, timezone),
      updated_at = now()
    WHERE recurrence_group = v_rec_group AND date >= v_event_date
    RETURNING id
  )
  SELECT count(*) INTO v_updated_count FROM updated;

  RETURN json_build_object('success', true, 'recurrence_group', v_rec_group, 'anchor_date', v_event_date, 'updated_count', v_updated_count);
END;
$function$;

NOTIFY pgrst, 'reload schema';
