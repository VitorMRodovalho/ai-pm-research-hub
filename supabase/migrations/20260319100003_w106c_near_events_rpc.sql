-- ═══════════════════════════════════════════════════════════════
-- W106 Sprint C — get_near_events RPC for quick-checkin banner
-- Returns events within ±2h window for a given member
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_near_events(
  p_member_id    uuid,
  p_window_hours int DEFAULT 2
)
RETURNS TABLE(
  event_id          uuid,
  event_title       text,
  event_date        date,
  event_type        text,
  duration_minutes  int,
  already_checked_in boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_tribe_id int;
BEGIN
  SELECT m.tribe_id INTO v_tribe_id
  FROM public.members m WHERE m.id = p_member_id;

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.date,
    e.type,
    e.duration_minutes,
    EXISTS(
      SELECT 1 FROM public.attendance a
      WHERE a.event_id = e.id AND a.member_id = p_member_id
    )
  FROM public.events e
  WHERE e.date::timestamptz BETWEEN
        now() - (p_window_hours || ' hours')::interval
    AND now() + (p_window_hours || ' hours')::interval
    AND (e.tribe_id IS NULL OR e.tribe_id::int = v_tribe_id)
  ORDER BY e.date ASC
  LIMIT 3;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_near_events(uuid, int) TO authenticated;
