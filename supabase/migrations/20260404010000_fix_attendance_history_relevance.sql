-- Fix get_my_attendance_history: show only events relevant to the member
-- Previously showed ALL events → misleading absence count
-- Now filters: general/kickoff + member's tribe + events with attendance record + invited + mandatory

BEGIN;

CREATE OR REPLACE FUNCTION get_my_attendance_history(p_limit int DEFAULT 30)
RETURNS TABLE(
  event_id uuid, event_title text, event_type text, event_date date,
  duration_minutes int, present boolean, excused boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
DECLARE
  v_member_id uuid;
  v_tribe_id int;
BEGIN
  SELECT m.id, m.tribe_id INTO v_member_id, v_tribe_id
  FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  IF v_member_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.type,
    e.date::date,
    e.duration_minutes,
    COALESCE(a.present, false),
    COALESCE(a.excused, false)
  FROM events e
  LEFT JOIN attendance a ON a.event_id = e.id AND a.member_id = v_member_id
  WHERE e.date <= CURRENT_DATE
    AND (
      -- General meetings (relevant to all)
      e.type IN ('geral', 'kickoff')
      -- Tribe meetings for MY tribe only
      OR (e.type = 'tribo' AND e.tribe_id = v_tribe_id)
      -- Events where I have an attendance record (1:1, leadership, etc.)
      OR a.id IS NOT NULL
      -- Events where I'm explicitly invited
      OR EXISTS (SELECT 1 FROM event_invited_members eim WHERE eim.event_id = e.id AND eim.member_id = v_member_id)
      -- Events mandatory for me via audience rules
      OR is_event_mandatory_for_member(e.id, v_member_id)
    )
  ORDER BY e.date DESC
  LIMIT p_limit;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
