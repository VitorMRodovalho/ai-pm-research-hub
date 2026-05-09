-- p126 E3 Migration 10/12 — is_returning_member canonical helper + auto-correct trigger
-- Issue C complete fix (Migration 8 was backfill only; this closes drift forward)
-- Wave 1 PM draft
--
-- Approach: helper function compute_is_returning_member(p_email) encapsulates
-- canonical predicate (offboarding record OR active engagement). BEFORE INSERT
-- trigger on selection_applications auto-corrects NEW.is_returning_member from
-- helper, overriding whatever import_vep_applications RPC body computed.
--
-- Why trigger vs RPC body patch:
-- - Decouples canonical predicate from RPC implementation (single source of truth)
-- - Catches all INSERT paths (RPC, manual admin, future bulk imports) — defense-in-depth
-- - Avoids duplicating 200-line import_vep_applications body for one-line change
-- - import_vep_applications body cleanup deferred to future RPC consolidation work
--
-- Rollback:
--   DROP TRIGGER trg_selection_apps_is_returning_member ON selection_applications;
--   DROP FUNCTION trg_set_is_returning_member();
--   DROP FUNCTION compute_is_returning_member(text);

BEGIN;

-- ─── Helper function: canonical is_returning_member predicate ───────────────
CREATE OR REPLACE FUNCTION public.compute_is_returning_member(p_email text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Returns true if email matches an existing member who EITHER has an
  -- offboarding record OR has an active volunteer engagement.
  -- Migration 8 (20260518080000) backfilled existing rows; this fn + trigger
  -- handle forward-only INSERTs.
  SELECT COALESCE(
    (SELECT
      EXISTS (
        SELECT 1
        FROM public.member_offboarding_records mor
        WHERE mor.member_id = m.id
      )
      OR EXISTS (
        SELECT 1
        FROM public.engagements e
        WHERE e.person_id = m.person_id
          AND e.status = 'active'
          AND e.kind LIKE 'volunteer%'
      )
    FROM public.members m
    WHERE lower(m.email) = lower(p_email)
    LIMIT 1),
    false
  );
$$;

COMMENT ON FUNCTION public.compute_is_returning_member(text) IS
  'p126 E3 Issue C canonical predicate for selection_applications.is_returning_member. Returns true if email matches member with offboarding record OR active volunteer engagement. Used by trg_set_is_returning_member trigger (BEFORE INSERT). Single source of truth.';

REVOKE ALL ON FUNCTION public.compute_is_returning_member(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_is_returning_member(text) TO authenticated, service_role;

-- ─── Trigger function: auto-correct on INSERT ──────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_set_is_returning_member()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only on INSERT; UPDATE preserves whatever explicit value caller chose
  -- (e.g., admin overriding for special cases). Skip if email NULL (defensive).
  IF TG_OP = 'INSERT' AND NEW.email IS NOT NULL AND NEW.email != '' THEN
    NEW.is_returning_member := public.compute_is_returning_member(NEW.email);
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_set_is_returning_member() IS
  'p126 E3 Issue C trigger function. BEFORE INSERT on selection_applications auto-corrects is_returning_member using compute_is_returning_member(email). Defense-in-depth — overrides RPC-computed value to enforce canonical predicate.';

-- ─── Install trigger ────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_selection_apps_is_returning_member
  ON public.selection_applications;

CREATE TRIGGER trg_selection_apps_is_returning_member
BEFORE INSERT ON public.selection_applications
FOR EACH ROW EXECUTE FUNCTION public.trg_set_is_returning_member();

COMMIT;

-- Post-apply checklist:
--   1. supabase migration repair --status applied 20260518100000
--   2. NOTIFY pgrst, 'reload schema'
--   3. Smoke test: INSERT row para applicant com active engagement (e.g., João Coelho email)
--      Expected: trigger sets is_returning_member=true even if INSERT statement passes false
--   4. Smoke test: INSERT row para email novo (no member match)
--      Expected: is_returning_member=false (helper returns false on no match)
--   5. Verify trigger active:
--      SELECT trigger_name, event_manipulation, action_timing
--      FROM information_schema.triggers
--      WHERE event_object_table='selection_applications'
--        AND trigger_name='trg_selection_apps_is_returning_member';
