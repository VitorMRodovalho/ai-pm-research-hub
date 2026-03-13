-- ═══════════════════════════════════════════════════════════════
-- W106 Sprint D — Add streak count to get_member_attendance_hours
-- Counts consecutive events with attendance (most recent streak)
-- ═══════════════════════════════════════════════════════════════

-- Drop first to change return type (adds current_streak column)
DROP FUNCTION IF EXISTS public.get_member_attendance_hours(uuid, text);

CREATE OR REPLACE FUNCTION public.get_member_attendance_hours(
  p_member_id  uuid,
  p_cycle_code text DEFAULT 'cycle_3'
)
RETURNS TABLE(total_hours numeric, total_events int, avg_hours_per_event numeric, current_streak int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_cycle_start date;
  v_streak int := 0;
  v_rec record;
BEGIN
  SELECT cycle_start INTO v_cycle_start
  FROM public.cycles WHERE cycle_code = p_cycle_code;

  IF v_cycle_start IS NULL THEN
    RETURN QUERY SELECT 0::numeric, 0::int, 0::numeric, 0::int;
    RETURN;
  END IF;

  -- Calculate streak: count consecutive events where member was present
  -- walking backwards from most recent event
  FOR v_rec IN
    SELECT e.id,
           EXISTS(SELECT 1 FROM public.attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id) AS was_present
    FROM public.events e
    WHERE e.date >= v_cycle_start
      AND e.date <= current_date
      AND (e.tribe_id IS NULL
           OR e.tribe_id = (SELECT m.tribe_id FROM public.members m WHERE m.id = p_member_id))
    ORDER BY e.date DESC
  LOOP
    IF v_rec.was_present THEN
      v_streak := v_streak + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;

  RETURN QUERY
  SELECT
    COALESCE(SUM(e.duration_minutes / 60.0), 0)::numeric          AS total_hours,
    COUNT(DISTINCT a.event_id)::int                                AS total_events,
    CASE WHEN COUNT(DISTINCT a.event_id) > 0
      THEN (COALESCE(SUM(e.duration_minutes / 60.0), 0) / COUNT(DISTINCT a.event_id))::numeric
      ELSE 0::numeric
    END                                                            AS avg_hours_per_event,
    v_streak                                                       AS current_streak
  FROM public.attendance a
  JOIN public.events e ON e.id = a.event_id
  WHERE a.member_id = p_member_id
    AND e.date >= v_cycle_start;
END;
$$;
