-- #847 — enforce the gp_only/leadership event VISIBILITY TIER in the two read RPCs
-- that #846 only gated for initiative CONFIDENTIALITY (rls_can_see_initiative).
--
-- Gap (pre-existing, orthogonal to #785/#846): standalone events (initiative_id IS NULL)
-- carry a visibility tier ('all' | 'leadership' | 'gp_only') that get_events_with_attendance
-- and list_meetings_with_notes never applied. A regular authenticated member therefore
-- received every gp_only/leadership standalone event — including minutes_text/agenda_text —
-- over the wire (proven live with a non-leader identity). /attendance hid them client-side
-- (cosmetic, not a boundary); /meetings rendered them directly (no client filter).
--
-- Fix: a new helper public.rls_can_see_event_tier(visibility, initiative_id) that mirrors
-- the per-event tier gate already shipped in get_event_detail (#846):
--   * visibility = 'gp_only'    -> requires can_by_member(caller, 'manage_platform')
--   * visibility = 'leadership' -> requires can_by_member(caller, 'manage_event')
--   * a member engaged in the event's CONFIDENTIAL initiative bypasses the tier
--     (sees all of that committee's events, matching get_event_detail)
--   * service_role / cron (auth.uid() IS NULL) bypasses for analytics (invariant m3a D12)
-- Both RPCs AND this helper next to the existing rls_can_see_initiative gate. The tier
-- gate mirrors get_event_detail exactly (no participant override), so the list stays
-- coherent with the detail RPC and /attendance is behaviour-neutral.

CREATE OR REPLACE FUNCTION public.rls_can_see_event_tier(p_visibility text, p_initiative_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    auth.uid() IS NULL
    OR p_visibility IS NULL
    OR p_visibility NOT IN ('gp_only', 'leadership')
    OR (p_visibility = 'leadership'
        AND public.can_by_member((SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()), 'manage_event'))
    OR (p_visibility = 'gp_only'
        AND public.can_by_member((SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()), 'manage_platform'))
    OR (p_initiative_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.initiatives i
          JOIN public.auth_engagements ae ON ae.initiative_id = i.id
          WHERE i.id = p_initiative_id
            AND i.visibility = 'confidential'
            AND ae.auth_id = auth.uid()
            AND ae.is_authoritative = true
       ));
$function$;

REVOKE ALL ON FUNCTION public.rls_can_see_event_tier(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rls_can_see_event_tier(text, uuid) TO authenticated, service_role;

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
  WHERE (public.rls_can_see_initiative(e.initiative_id) OR auth.uid() IS NULL)
    AND public.rls_can_see_event_tier(e.visibility, e.initiative_id)
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
$function$;

CREATE OR REPLACE FUNCTION public.list_meetings_with_notes(p_tribe_id integer DEFAULT NULL::integer, p_type text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_include_empty boolean DEFAULT false, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_total int;
  v_rows jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT count(*) INTO v_total
  FROM events e
  LEFT JOIN initiatives i ON i.id = e.initiative_id
  WHERE (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    AND public.rls_can_see_initiative(e.initiative_id)
    AND public.rls_can_see_event_tier(e.visibility, e.initiative_id)
    AND (p_type IS NULL OR e.type = p_type)
    AND (p_include_empty OR (e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20))
    AND (
      p_search IS NULL OR p_search = ''
      OR to_tsvector('portuguese',
           coalesce(e.title, '') || ' ' ||
           coalesce(e.minutes_text, '') || ' ' ||
           coalesce(e.agenda_text, '')
         ) @@ plainto_tsquery('portuguese', p_search)
    );

  SELECT COALESCE(jsonb_agg(row_to_json(sub) ORDER BY sub.date DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      e.id, e.title, e.date, e.type, i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      e.initiative_id,
      i.title AS initiative_name,
      e.youtube_url, e.recording_url,
      e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20 AS has_minutes,
      length(COALESCE(e.minutes_text, '')) AS minutes_length,
      e.agenda_text IS NOT NULL AS has_agenda,
      (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true) AS attendee_count
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND public.rls_can_see_initiative(e.initiative_id)
      AND public.rls_can_see_event_tier(e.visibility, e.initiative_id)
      AND (p_type IS NULL OR e.type = p_type)
      AND (p_include_empty OR (e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) >= 20))
      AND (
        p_search IS NULL OR p_search = ''
        OR to_tsvector('portuguese',
             coalesce(e.title, '') || ' ' ||
             coalesce(e.minutes_text, '') || ' ' ||
             coalesce(e.agenda_text, '')
           ) @@ plainto_tsquery('portuguese', p_search)
      )
    ORDER BY e.date DESC
    LIMIT p_limit
    OFFSET p_offset
  ) sub;

  RETURN jsonb_build_object(
    'meetings', v_rows,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
