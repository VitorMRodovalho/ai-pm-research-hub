-- p276 — Fix #1: alinhar roster leadership com event_audience_rules (manager + tribe_leader + deputy_manager + co_gp)
--
-- WHAT: Rewrite the WHEN 'leadership' branch of public.get_tribe_event_roster
--       to match the audience the platform actually inserts via
--       _auto_audience_rule_on_meeting_tag for tag='leadership_meeting'
--       (manager + deputy_manager + tribe_leader as mandatory roles).
--
-- WHY:  The pre-fix branch listed sponsor + ambassador + founder + co_gp +
--       manager — pulling Chapter Board sponsors and any historical
--       ambassador/founder into the leadership-meeting grid while excluding
--       the actual tribe_leaders the platform considers mandatory. For
--       Reunião de Liderança #4 (2026-05-28) the bad branch returned 11
--       people, 4 of whom were Chapter Board externos and 0 tribe_leaders.
--
-- HOW:  CREATE OR REPLACE FUNCTION (signature unchanged: p_event_id uuid,
--       returns json). SECDEF + search_path=public preserved. Only the
--       WHEN 'leadership' THEN sub-expression inside the CASE COALESCE(
--       v_event.audience_level, 'all') changes; every other branch (tribe,
--       curators, ELSE) is byte-identical to the pre-fix body. NOTIFY pgrst.
--
-- ROLLBACK: re-run CREATE OR REPLACE with the prior branch body:
--   WHEN 'leadership' THEN
--     m.operational_role IN ('manager')
--     OR 'sponsor'    = ANY(COALESCE(m.designations, '{}'))
--     OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
--     OR 'founder'    = ANY(COALESCE(m.designations, '{}'))
--     OR 'co_gp'      = ANY(COALESCE(m.designations, '{}'))

CREATE OR REPLACE FUNCTION public.get_tribe_event_roster(p_event_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller RECORD;
  v_event  RECORD;
  v_event_tribe_id int;
  v_result JSON;
  v_has_attendance boolean;
  v_event_cancelled boolean;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);
  v_event_cancelled := (v_event.status = 'cancelled');

  -- Access control: V4 baseline manage_event + residual tribe scope for tribe_leader
  IF NOT public.can_by_member(v_caller.id, 'manage_event') THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;
  IF v_caller.operational_role = 'tribe_leader'
     AND v_event_tribe_id IS NOT NULL
     AND v_event_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;

  SELECT EXISTS(SELECT 1 FROM attendance WHERE event_id = p_event_id) INTO v_has_attendance;

  SELECT json_agg(row_to_json(q) ORDER BY q.name) INTO v_result
  FROM (
    SELECT
      m.id, m.name, m.photo_url, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations) AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter,
      COALESCE(a.present, false) AS present,
      a.corrected_by IS NOT NULL AS was_corrected,
      v_event_cancelled AS event_cancelled
    FROM public.members m
    LEFT JOIN public.attendance a
      ON a.event_id = p_event_id AND a.member_id = m.id
    WHERE
      m.operational_role != 'guest'
      AND (
        CASE WHEN v_event.initiative_id IS NOT NULL AND v_event_tribe_id IS NULL THEN
          m.id IN (
            SELECT mm.id FROM members mm
            JOIN engagements eng ON eng.person_id = mm.person_id
            WHERE eng.initiative_id = v_event.initiative_id AND eng.status = 'active'
          )
          OR a.id IS NOT NULL

        WHEN v_event.type IN ('1on1', 'entrevista', 'parceria') AND v_has_attendance THEN
          a.id IS NOT NULL

        ELSE
          CASE COALESCE(v_event.audience_level, 'all')
            WHEN 'tribe' THEN
              m.current_cycle_active = true
              AND m.tribe_id = v_event_tribe_id
            WHEN 'leadership' THEN
              -- p276 fix: align with event_audience_rules (manager + tribe_leader + deputy_manager + co_gp)
              m.operational_role IN ('manager','tribe_leader')
              OR 'deputy_manager' = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp'          = ANY(COALESCE(m.designations, '{}'))
            WHEN 'curators' THEN
              'curator' = ANY(COALESCE(m.designations, '{}'))
            ELSE
              m.current_cycle_active = true
              OR m.operational_role = 'manager'
              OR 'sponsor'    = ANY(COALESCE(m.designations, '{}'))
              OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
              OR 'curator'    = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp'      = ANY(COALESCE(m.designations, '{}'))
          END
        END
      )
  ) q;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

NOTIFY pgrst, 'reload schema';
