-- Fix: Only count events after member's created_at date
-- Members who joined mid-cycle should not be penalized for earlier meetings
CREATE OR REPLACE FUNCTION public.get_attendance_panel(
  p_cycle_start date DEFAULT '2026-01-01'::date,
  p_cycle_end date DEFAULT '2026-06-30'::date
)
RETURNS TABLE(
  member_id uuid, member_name text, tribe_name text, tribe_id int,
  operational_role text,
  general_mandatory int, general_attended int, general_pct numeric,
  tribe_mandatory int, tribe_attended int, tribe_pct numeric,
  combined_pct numeric, last_attendance date, dropout_risk boolean
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  WITH general_events AS (
    SELECT DISTINCT e.id as event_id, e.date::date as event_date
    FROM public.events e
    JOIN public.event_tag_assignments eta ON eta.event_id = e.id
    JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'general_meeting'
    WHERE e.date::date BETWEEN p_cycle_start AND p_cycle_end
  ),
  tribe_events AS (
    SELECT DISTINCT e.id as event_id, e.date::date as event_date
    FROM public.events e
    JOIN public.event_tag_assignments eta ON eta.event_id = e.id
    JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'tribe_meeting'
    WHERE e.date::date BETWEEN p_cycle_start AND p_cycle_end
  ),
  active AS (
    SELECT m.id, m.name as m_name, tr.name as t_name, m.tribe_id as t_id,
           m.operational_role as op_role, m.created_at::date as member_start
    FROM public.members m LEFT JOIN public.tribes tr ON tr.id = m.tribe_id
    WHERE m.is_active = true
  ),
  gscores AS (
    SELECT a.id as mid,
      count(*) FILTER (WHERE ge.event_date >= a.member_start AND public.is_event_mandatory_for_member(ge.event_id, a.id)) as mand,
      count(*) FILTER (WHERE ge.event_date >= a.member_start AND att.id IS NOT NULL AND public.is_event_mandatory_for_member(ge.event_id, a.id)) as att
    FROM active a CROSS JOIN general_events ge
    LEFT JOIN public.attendance att ON att.event_id = ge.event_id AND att.member_id = a.id AND att.present = true
    GROUP BY a.id
  ),
  tscores AS (
    SELECT a.id as mid,
      count(*) FILTER (WHERE te.event_date >= a.member_start AND public.is_event_mandatory_for_member(te.event_id, a.id)) as mand,
      count(*) FILTER (WHERE te.event_date >= a.member_start AND att.id IS NOT NULL AND public.is_event_mandatory_for_member(te.event_id, a.id)) as att
    FROM active a CROSS JOIN tribe_events te
    LEFT JOIN public.attendance att ON att.event_id = te.event_id AND att.member_id = a.id AND att.present = true
    GROUP BY a.id
  ),
  last_att AS (
    SELECT a.member_id, MAX(e.date::date) as last_date
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    WHERE a.present = true
    GROUP BY a.member_id
  )
  SELECT a.id, a.m_name, a.t_name, a.t_id, a.op_role,
    COALESCE(gs.mand,0)::int, COALESCE(gs.att,0)::int,
    CASE WHEN COALESCE(gs.mand,0)>0 THEN ROUND(gs.att::numeric/gs.mand*100,1) ELSE 0 END,
    COALESCE(ts.mand,0)::int, COALESCE(ts.att,0)::int,
    CASE WHEN COALESCE(ts.mand,0)>0 THEN ROUND(ts.att::numeric/ts.mand*100,1) ELSE 0 END,
    CASE WHEN COALESCE(gs.mand,0)+COALESCE(ts.mand,0)>0
      THEN ROUND((COALESCE(gs.att,0)+COALESCE(ts.att,0))::numeric/(COALESCE(gs.mand,0)+COALESCE(ts.mand,0))*100,1)
      ELSE 0 END,
    la.last_date,
    (COALESCE(gs.mand,0)+COALESCE(ts.mand,0)>0) AND
      ROUND((COALESCE(gs.att,0)+COALESCE(ts.att,0))::numeric/
        NULLIF(COALESCE(gs.mand,0)+COALESCE(ts.mand,0),0)*100,1) < 50
  FROM active a
  LEFT JOIN gscores gs ON gs.mid = a.id
  LEFT JOIN tscores ts ON ts.mid = a.id
  LEFT JOIN last_att la ON la.member_id = a.id
  ORDER BY a.m_name;
END; $$;
