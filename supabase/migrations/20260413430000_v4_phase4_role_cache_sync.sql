-- ============================================================================
-- V4 Phase 4 — Migration 4/5: operational_role cache sync trigger
-- ADR: ADR-0007 (Authority as Derived Grant from Active Engagements)
-- Rollback: DROP FUNCTION public.sync_operational_role_cache() CASCADE;
-- ============================================================================

-- When engagements change, recalculate members.operational_role as a cache.
-- Priority: manager > deputy_manager > tribe_leader > researcher > observer > alumni > guest
-- This keeps legacy code working while can() is the real source of truth.

CREATE OR REPLACE FUNCTION public.sync_operational_role_cache()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_member_id uuid;
  v_new_role text;
BEGIN
  -- Resolve the member_id from person_id
  SELECT id INTO v_member_id
  FROM public.members
  WHERE person_id = COALESCE(NEW.person_id, OLD.person_id);

  IF v_member_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Compute highest-priority role from active engagements
  SELECT
    CASE
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager') THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'leader') THEN 'tribe_leader'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp') THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'comms_leader') THEN 'tribe_leader'
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

  -- Only update if different (avoid infinite trigger loop)
  UPDATE public.members
  SET operational_role = COALESCE(v_new_role, 'guest'),
      updated_at = now()
  WHERE id = v_member_id
    AND operational_role IS DISTINCT FROM COALESCE(v_new_role, 'guest');

  RETURN COALESCE(NEW, OLD);
END;
$$;

COMMENT ON FUNCTION public.sync_operational_role_cache() IS 'V4: Recalculates members.operational_role from active engagements. Cache only — can() is source of truth (ADR-0007).';

CREATE TRIGGER trg_sync_role_cache
  AFTER INSERT OR UPDATE OR DELETE ON public.engagements
  FOR EACH ROW EXECUTE FUNCTION public.sync_operational_role_cache();

NOTIFY pgrst, 'reload schema';
