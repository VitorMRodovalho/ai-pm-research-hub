-- ============================================================================
-- Fix: Distinguish comms_leader from tribe_leader in operational_role cache
-- Purpose: sync_operational_role_cache mapped comms_leader → tribe_leader,
--          causing display ambiguity (comms_leader shown as tribe leader in
--          tribe page header) and incorrect permission grants. Fix: map to
--          'comms_leader' as distinct value. ADR-0007 says operational_role
--          is a cache — this makes the cache more accurate.
-- Rollback: Change WHEN clause back to:
--           WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'comms_leader') THEN 'tribe_leader'
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sync_operational_role_cache()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_member_id uuid;
  v_new_role text;
BEGIN
  SELECT id INTO v_member_id
  FROM public.members
  WHERE person_id = COALESCE(NEW.person_id, OLD.person_id);

  IF v_member_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Compute highest-priority role from active engagements
  -- Priority: manager > deputy_manager > tribe_leader > comms_leader > researcher > observer > alumni > guest
  SELECT
    CASE
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager') THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'leader') THEN 'tribe_leader'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp') THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'comms_leader') THEN 'comms_leader'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('researcher', 'facilitator', 'communicator', 'curator')) THEN 'researcher'
      WHEN bool_or(ae.kind = 'observer') THEN 'observer'
      WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
      WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
      WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
      WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
      ELSE 'guest'
    END INTO v_new_role
  FROM public.auth_engagements ae
  WHERE ae.person_id = COALESCE(NEW.person_id, OLD.person_id)
    AND ae.is_authoritative = true;

  UPDATE public.members
  SET operational_role = COALESCE(v_new_role, 'guest'),
      updated_at = now()
  WHERE id = v_member_id
    AND operational_role IS DISTINCT FROM COALESCE(v_new_role, 'guest');

  RETURN COALESCE(NEW, OLD);
END;
$$;

COMMENT ON FUNCTION public.sync_operational_role_cache() IS 'V4: Recalculates members.operational_role from active engagements. Cache only — can() is source of truth (ADR-0007). comms_leader now maps to distinct value (not tribe_leader).';
