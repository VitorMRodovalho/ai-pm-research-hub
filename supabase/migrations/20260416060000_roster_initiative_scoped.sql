-- ═══════════════════════════════════════════════════════════════
-- Fix: Smart roster scoping by event context
-- 1) Initiative events → initiative members only
-- 2) Small events (1on1/entrevista/parceria) with attendance → attendees only
-- 3) Liderança events → audience_level fixed to 'leadership'
-- 4) Standard events → audience_level based filtering (unchanged)
-- Rollback: DROP FUNCTION get_tribe_event_roster(uuid);
-- ═══════════════════════════════════════════════════════════════

-- Fix liderança events that were set to 'all' instead of 'leadership'
UPDATE events SET audience_level = 'leadership'
WHERE type = 'lideranca' AND audience_level = 'all';

DROP FUNCTION IF EXISTS get_tribe_event_roster(uuid);

CREATE OR REPLACE FUNCTION public.get_tribe_event_roster(p_event_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller RECORD;
  v_event  RECORD;
  v_result JSON;
  v_has_attendance boolean;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;

  -- Access control
  IF NOT COALESCE(v_caller.is_superadmin, false) THEN
    IF v_caller.operational_role IN ('manager', 'deputy_manager') THEN
      NULL;
    ELSIF v_caller.operational_role = 'tribe_leader' OR 'co_gp' = ANY(COALESCE(v_caller.designations, '{}')) THEN
      IF v_event.tribe_id IS NOT NULL AND v_event.tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
        RETURN json_build_object('error', 'Access denied');
      END IF;
    ELSE
      RETURN json_build_object('error', 'Access denied');
    END IF;
  END IF;

  -- Check if event already has attendance records
  SELECT EXISTS(SELECT 1 FROM attendance WHERE event_id = p_event_id) INTO v_has_attendance;

  SELECT json_agg(row_to_json(q) ORDER BY q.name) INTO v_result
  FROM (
    SELECT
      m.id, m.name, m.photo_url, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations) AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter,
      COALESCE(a.present, false) AS present,
      a.corrected_by IS NOT NULL AS was_corrected
    FROM public.members m
    LEFT JOIN public.attendance a
      ON a.event_id = p_event_id AND a.member_id = m.id
    WHERE
      m.operational_role != 'guest'
      AND (
        -- 1) Initiative events: scope to initiative members
        CASE WHEN v_event.initiative_id IS NOT NULL AND v_event.tribe_id IS NULL THEN
          m.id IN (
            SELECT mm.id FROM members mm
            JOIN engagements eng ON eng.person_id = mm.person_id
            WHERE eng.initiative_id = v_event.initiative_id AND eng.status = 'active'
          )
          OR a.id IS NOT NULL

        -- 2) Small event types with existing attendance: show only attendees
        WHEN v_event.type IN ('1on1', 'entrevista', 'parceria') AND v_has_attendance THEN
          a.id IS NOT NULL

        -- 3) Standard audience-based filtering
        ELSE
          CASE COALESCE(v_event.audience_level, 'all')
            WHEN 'tribe' THEN
              m.current_cycle_active = true
              AND m.tribe_id = v_event.tribe_id
            WHEN 'leadership' THEN
              m.operational_role IN ('manager')
              OR 'sponsor' = ANY(COALESCE(m.designations, '{}'))
              OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
              OR 'founder' = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp' = ANY(COALESCE(m.designations, '{}'))
            WHEN 'curators' THEN
              'curator' = ANY(COALESCE(m.designations, '{}'))
            ELSE
              m.current_cycle_active = true
              OR m.operational_role = 'manager'
              OR 'sponsor' = ANY(COALESCE(m.designations, '{}'))
              OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
              OR 'curator' = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp' = ANY(COALESCE(m.designations, '{}'))
          END
        END
      )
  ) q;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_tribe_event_roster(uuid) TO authenticated;
