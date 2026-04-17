-- ============================================================
-- B5 + B7 — Member invariants: sanitize existing drift + trigger
--
-- Audit 17/Abr (Eixo B) revealed 11 member rows with inconsistent
-- (member_status, operational_role, is_active, designations). Most
-- are pre-2026-04-17 offboards that wrote incomplete state. New
-- offboards go through admin_offboard_member (ADR-0011) and are clean.
--
-- Fix strategy:
--   1. Sanitize (B5) — deterministic coercion of the 11 drift rows
--      to consistent state. "VP Desenvolvimento Profissional (PMI-GO)"
--      kept as-is (flagged for human review; active_engagement=1 +
--      is_active=false is a policy question, not obvious drift).
--   2. Trigger (B7) — BEFORE UPDATE on members enforces invariants
--      going forward. Coerces (not rejects) for smoothness.
--
-- Invariants enforced by trigger:
--   member_status='active'     → is_active=true
--   member_status IN ('observer','alumni','inactive') → is_active=false
--   member_status='alumni'     → operational_role='alumni'
--   member_status='observer' AND operational_role NOT IN
--     ('observer','guest','none') → operational_role='observer'
--   member_status IN ('observer','alumni','inactive')
--     AND array_length(designations,1) > 0 → designations='{}'
--
-- Rollback: revert sanitize UPDATEs manually; DROP TRIGGER.
-- ============================================================

-- ── B5: Sanitize 9 clearly-drifted rows ──
-- Leave "VP Desenvolvimento Profissional" for human review.

-- alumni_st_but_role_mismatch: force operational_role='alumni', clear designations
UPDATE public.members
SET operational_role = 'alumni',
    designations = '{}'::text[],
    updated_at = now()
WHERE member_status = 'alumni' AND operational_role != 'alumni'
  AND name != 'VP Desenvolvimento Profissional (PMI-GO)';

-- observer_st_but_role_mismatch: force operational_role='observer', clear designations
UPDATE public.members
SET operational_role = 'observer',
    designations = '{}'::text[],
    updated_at = now()
WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none')
  AND name != 'VP Desenvolvimento Profissional (PMI-GO)';

-- offboarded with active engagements but member itself already offboarded:
-- close dangling engagements (best-effort; keep going if person_id is NULL)
UPDATE public.engagements e
SET status = 'offboarded',
    end_date = COALESCE(end_date, CURRENT_DATE),
    revoked_at = COALESCE(revoked_at, now()),
    revoke_reason = COALESCE(revoke_reason, 'B5 sanitation — offboarded member 17/Abr/2026'),
    updated_at = now()
FROM public.members m
WHERE m.person_id = e.person_id
  AND m.member_status IN ('observer','alumni','inactive')
  AND e.status = 'active'
  AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)';

-- ── B7: Trigger sync_member_status_consistency ──
CREATE OR REPLACE FUNCTION public.sync_member_status_consistency()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Invariant 1: member_status='active' implies is_active=true
  IF NEW.member_status = 'active' AND NEW.is_active = false THEN
    NEW.is_active := true;
  END IF;

  -- Invariant 2: member_status in terminal states implies is_active=false
  IF NEW.member_status IN ('observer','alumni','inactive') AND NEW.is_active = true THEN
    NEW.is_active := false;
  END IF;

  -- Invariant 3: alumni status coerces role to alumni
  IF NEW.member_status = 'alumni' AND NEW.operational_role IS DISTINCT FROM 'alumni' THEN
    NEW.operational_role := 'alumni';
  END IF;

  -- Invariant 4: observer status coerces role to observer (tolerating guest/none)
  IF NEW.member_status = 'observer'
     AND NEW.operational_role NOT IN ('observer','guest','none') THEN
    NEW.operational_role := 'observer';
  END IF;

  -- Invariant 5: terminal statuses clear designations
  IF NEW.member_status IN ('observer','alumni','inactive')
     AND NEW.designations IS NOT NULL
     AND array_length(NEW.designations, 1) > 0 THEN
    NEW.designations := '{}'::text[];
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_member_status_consistency ON public.members;
CREATE TRIGGER trg_sync_member_status_consistency
BEFORE INSERT OR UPDATE OF member_status, operational_role, is_active, designations ON public.members
FOR EACH ROW EXECUTE FUNCTION public.sync_member_status_consistency();

GRANT EXECUTE ON FUNCTION public.sync_member_status_consistency() TO authenticated;
