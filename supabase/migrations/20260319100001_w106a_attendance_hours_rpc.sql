-- ═══════════════════════════════════════════════════════════════
-- W106 Sprint A — get_member_attendance_hours RPC
-- Returns real attendance hours for a member in a given cycle
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_member_attendance_hours(
  p_member_id  uuid,
  p_cycle_code text DEFAULT 'cycle_3'
)
RETURNS TABLE(total_hours numeric, total_events int, avg_hours_per_event numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_cycle_start date;
BEGIN
  SELECT cycle_start INTO v_cycle_start
  FROM public.cycles WHERE cycle_code = p_cycle_code;

  IF v_cycle_start IS NULL THEN
    RETURN QUERY SELECT 0::numeric, 0::int, 0::numeric;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    COALESCE(SUM(e.duration_minutes / 60.0), 0)::numeric          AS total_hours,
    COUNT(DISTINCT a.event_id)::int                                AS total_events,
    CASE WHEN COUNT(DISTINCT a.event_id) > 0
      THEN (COALESCE(SUM(e.duration_minutes / 60.0), 0) / COUNT(DISTINCT a.event_id))::numeric
      ELSE 0::numeric
    END                                                            AS avg_hours_per_event
  FROM public.attendance a
  JOIN public.events e ON e.id = a.event_id
  WHERE a.member_id = p_member_id
    AND e.date >= v_cycle_start;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_member_attendance_hours(uuid, text) TO authenticated;
