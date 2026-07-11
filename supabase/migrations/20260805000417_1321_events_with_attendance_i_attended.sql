-- #1321 — get_events_with_attendance returns i_attended (per-caller) so the check-in
-- button reflects the member's OWN state. The frontend (attendance.astro) already branches
-- on ev.i_attended, but the RPC never returned it -> the field was always undefined ->
-- the "Check-In" button stayed active even after checking in (UX noise).
-- New return column = signature change -> DROP + CREATE (CREATE OR REPLACE cannot change
-- the return type). Grants preserved: authenticated + service_role (no anon/public), per
-- the pre-change ACL.

DROP FUNCTION IF EXISTS public.get_events_with_attendance(integer, integer);

CREATE FUNCTION public.get_events_with_attendance(p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, title text, date date, type text, nature text, duration_minutes integer, time_start time without time zone, timezone text, meeting_link text, youtube_url text, is_recorded boolean, audience_level text, tribe_id integer, attendee_count bigint, agenda_text text, agenda_url text, minutes_text text, minutes_url text, recording_url text, recording_type text, notes text, visibility text, external_attendees text[], recurrence_group uuid, initiative_id uuid, initiative_name text, status text, cancelled_at timestamp with time zone, cancellation_reason text, i_attended boolean)
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
    e.status, e.cancelled_at, e.cancellation_reason,
    -- #1321: did the CURRENT caller mark present for this event? (anon -> false)
    EXISTS (
      SELECT 1 FROM public.attendance a
      WHERE a.event_id = e.id
        AND a.present = true
        AND a.member_id = (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid())
    ) AS i_attended
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE (public.rls_can_see_initiative(e.initiative_id) OR auth.uid() IS NULL)
    AND public.rls_can_see_event_tier(e.visibility, e.initiative_id)
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
$function$;

REVOKE ALL ON FUNCTION public.get_events_with_attendance(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_events_with_attendance(integer, integer) TO authenticated, service_role;
