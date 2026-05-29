-- p277 — get_event_champion_suggestions: actually SUGGEST (derive from attendance + contribution)
-- (gamification rule-wiring probe, Feature 3).
--
-- WHAT: get_event_champion_suggestions was a pure pass-through of events.suggested_champion_ids —
--   it "suggested" nothing (0/95 events ever had that array populated), so it always returned
--   empty and the champion-of-the-night nudge in the grant modal never showed candidates.
--
--   Now it DERIVES candidates when no manual override exists: the members who were PRESENT at the
--   event (the only members award_champion(general) can recognize anyway), ranked by their
--   current-cycle contribution (XP earned this cycle) so the most active present members surface
--   first. The manual-override path (a curator pre-setting suggested_champion_ids via meeting_close)
--   is preserved and still takes precedence.
--
-- WHY: turns the "champions da noite" recognition the team already does verbally into a usable
--   shortlist at award time, without requiring anyone to type member UUIDs. Same signature + return
--   shape (member_id, member_name, designation_summary) → CREATE OR REPLACE, no consumer break.
--
-- ROLLBACK: re-CREATE the prior pass-through body (return only the suggested_champion_ids list).

CREATE OR REPLACE FUNCTION public.get_event_champion_suggestions(p_event_id uuid)
 RETURNS TABLE(member_id uuid, member_name text, designation_summary text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event_org uuid;
  v_suggestions uuid[];
  v_cycle_start date;
BEGIN
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event')
     AND NOT public.can_by_member(v_caller_id, 'award_champion') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event or award_champion';
  END IF;

  SELECT e.suggested_champion_ids, e.organization_id INTO v_suggestions, v_event_org
  FROM public.events e WHERE e.id = p_event_id;

  IF v_event_org IS NULL THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;
  IF v_event_org != v_caller_org THEN
    RAISE EXCEPTION 'event_not_in_caller_org';
  END IF;

  -- Manual override: a curator pre-set the champions-of-the-night via meeting_close → honor it.
  IF v_suggestions IS NOT NULL AND cardinality(v_suggestions) > 0 THEN
    RETURN QUERY
    SELECT
      m.id, m.name,
      CASE WHEN cardinality(m.designations) > 0
        THEN array_to_string(m.designations, ', ')
        ELSE COALESCE(m.operational_role, '—')
      END
    FROM public.members m
    WHERE m.id = ANY(v_suggestions)
      AND m.organization_id = v_caller_org
    ORDER BY m.name;
    RETURN;
  END IF;

  -- Derived suggestion: members PRESENT at the event (award_champion can only recognize present
  -- members), ranked by current-cycle contribution so the most active surface first. Top 12.
  SELECT cycle_start INTO v_cycle_start FROM public.cycles WHERE is_current = true LIMIT 1;

  RETURN QUERY
  SELECT
    m.id, m.name,
    CASE WHEN cardinality(m.designations) > 0
      THEN array_to_string(m.designations, ', ')
      ELSE COALESCE(m.operational_role, '—')
    END
  FROM public.attendance a
  JOIN public.members m ON m.id = a.member_id
  LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(gp.points), 0) AS cyc_pts
    FROM public.gamification_points gp
    WHERE gp.member_id = m.id
      AND gp.created_at >= COALESCE(v_cycle_start, DATE '2026-01-01')
  ) sig ON true
  WHERE a.event_id = p_event_id
    AND a.present = true
    AND m.organization_id = v_caller_org
    AND m.id <> v_caller_id          -- self-award is blocked by award_champion anyway
  ORDER BY sig.cyc_pts DESC, m.name
  LIMIT 12;
END;
$function$;

NOTIFY pgrst, 'reload schema';
