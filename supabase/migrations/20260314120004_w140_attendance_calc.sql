-- ============================================================
-- W140 BLOCO 5: Corrected attendance calculation
-- Uses tag-based event classification + audience rules
-- ============================================================

-- Helper: is event mandatory for this member?
CREATE OR REPLACE FUNCTION public.is_event_mandatory_for_member(p_event_id uuid, p_member_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE v_member record; v_rule record;
BEGIN
  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF v_member IS NULL OR v_member.is_active = false THEN RETURN false; END IF;

  FOR v_rule IN SELECT * FROM public.event_audience_rules
    WHERE event_id = p_event_id AND attendance_type = 'mandatory'
  LOOP
    IF v_rule.target_type = 'all_active_operational' THEN
      IF v_member.tribe_id IS NOT NULL OR v_member.operational_role IN ('manager','deputy_manager') THEN
        RETURN true;
      END IF;
    ELSIF v_rule.target_type = 'tribe' THEN
      IF v_member.tribe_id IS NOT NULL AND v_member.tribe_id::text = v_rule.target_value THEN
        RETURN true;
      END IF;
    ELSIF v_rule.target_type = 'role' THEN
      IF v_member.operational_role = v_rule.target_value THEN
        RETURN true;
      END IF;
    ELSIF v_rule.target_type = 'specific_members' THEN
      IF EXISTS (SELECT 1 FROM public.event_invited_members
        WHERE event_id = p_event_id AND member_id = p_member_id AND attendance_type = 'mandatory') THEN
        RETURN true;
      END IF;
    END IF;
  END LOOP;

  -- Also check direct invite (even without specific_members rule)
  IF EXISTS (SELECT 1 FROM public.event_invited_members
    WHERE event_id = p_event_id AND member_id = p_member_id AND attendance_type = 'mandatory') THEN
    RETURN true;
  END IF;
  RETURN false;
END; $$;

-- Main attendance panel (replaces existing calculation)
CREATE OR REPLACE FUNCTION public.get_attendance_panel(
  p_cycle_start date DEFAULT '2025-12-01', p_cycle_end date DEFAULT '2026-06-30'
) RETURNS TABLE (
  member_id uuid, member_name text, tribe_name text, tribe_id integer, operational_role text,
  general_mandatory integer, general_attended integer, general_pct numeric,
  tribe_mandatory integer, tribe_attended integer, tribe_pct numeric,
  combined_pct numeric, last_attendance date, dropout_risk boolean
) LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
  RETURN QUERY
  WITH general_events AS (
    SELECT DISTINCT e.id as event_id
    FROM public.events e
    JOIN public.event_tag_assignments eta ON eta.event_id = e.id
    JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'general_meeting'
    WHERE e.date::date BETWEEN p_cycle_start AND p_cycle_end
  ),
  tribe_events AS (
    SELECT DISTINCT e.id as event_id
    FROM public.events e
    JOIN public.event_tag_assignments eta ON eta.event_id = e.id
    JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'tribe_meeting'
    WHERE e.date::date BETWEEN p_cycle_start AND p_cycle_end
  ),
  active AS (
    SELECT m.id, m.name as m_name, tr.name as t_name, m.tribe_id as t_id, m.operational_role as op_role
    FROM public.members m LEFT JOIN public.tribes tr ON tr.id = m.tribe_id
    WHERE m.is_active = true
  ),
  gscores AS (
    SELECT a.id as mid,
      count(*) FILTER (WHERE public.is_event_mandatory_for_member(ge.event_id, a.id)) as mand,
      count(*) FILTER (WHERE att.id IS NOT NULL AND public.is_event_mandatory_for_member(ge.event_id, a.id)) as att
    FROM active a CROSS JOIN general_events ge
    LEFT JOIN public.attendance att ON att.event_id = ge.event_id AND att.member_id = a.id AND att.present = true
    GROUP BY a.id
  ),
  tscores AS (
    SELECT a.id as mid,
      count(*) FILTER (WHERE public.is_event_mandatory_for_member(te.event_id, a.id)) as mand,
      count(*) FILTER (WHERE att.id IS NOT NULL AND public.is_event_mandatory_for_member(te.event_id, a.id)) as att
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

GRANT EXECUTE ON FUNCTION public.is_event_mandatory_for_member TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_panel TO authenticated;
