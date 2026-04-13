-- ============================================================================
-- V4 Phase 4 — Migration 6/7: RLS helper functions + agreement fix
-- ADR: ADR-0007 (Authority as Derived Grant from Active Engagements)
-- Rollback: DROP FUNCTION public.rls_can(text);
--           DROP FUNCTION public.rls_is_superadmin();
--           DROP FUNCTION public.rls_can_for_tribe(text, integer);
--           UPDATE engagement_kinds SET requires_agreement = true WHERE slug IN ('volunteer','study_group_owner');
-- ============================================================================

-- ═══ Fix: Relax requires_agreement for volunteer/study_group_owner ═══
-- Fase 4 decision: "requires_agreement relaxado para false em volunteer/study_group_owner
-- durante shadow mode. Agreement enforcement pertence à Fase 5."
-- Fase 5 prematurely set requires_agreement = true without backfilling
-- agreement_certificate_id on existing engagements → broke is_authoritative
-- for ALL volunteer engagements (34/40 have no certificate).
-- Fix: relax to false until sign_volunteer_agreement() rewrite populates
-- agreement_certificate_id on engagements (Fase 7 cleanup item).
UPDATE public.engagement_kinds
SET requires_agreement = false
WHERE slug IN ('volunteer', 'study_group_owner');

-- Backfill: link 6 existing volunteer_agreement certificates to engagements
UPDATE public.engagements e
SET agreement_certificate_id = c.id
FROM public.certificates c
JOIN public.persons p ON p.legacy_member_id = c.member_id
WHERE e.person_id = p.id
  AND e.kind = 'volunteer'
  AND c.type = 'volunteer_agreement'
  AND e.agreement_certificate_id IS NULL;

-- rls_can(action): checks if current user has an authoritative engagement
-- granting the given action. Resolves auth.uid() → persons → can().
-- Marked STABLE so Postgres evaluates once per statement (not per row).

CREATE OR REPLACE FUNCTION public.rls_can(p_action text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
  SELECT public.can(
    (SELECT p.id FROM public.persons p WHERE p.auth_id = auth.uid() LIMIT 1),
    p_action
  );
$$;

COMMENT ON FUNCTION public.rls_can(text) IS 'V4 RLS helper: checks if current auth.uid() has authoritative engagement granting action (ADR-0007). STABLE = evaluated once per statement.';

GRANT EXECUTE ON FUNCTION public.rls_can(text) TO authenticated;

-- rls_is_superadmin(): safety-net flag from members table.
-- is_superadmin is NOT derived from engagements — it's a separate
-- platform-level flag. Preserved as bridge until Fase 7.

CREATE OR REPLACE FUNCTION public.rls_is_superadmin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
  SELECT COALESCE(
    (SELECT m.is_superadmin FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1),
    false
  );
$$;

COMMENT ON FUNCTION public.rls_is_superadmin() IS 'V4 RLS helper: returns is_superadmin flag from members. Safety net — not engagement-derived. Bridge until Fase 7.';

GRANT EXECUTE ON FUNCTION public.rls_is_superadmin() TO authenticated;

-- rls_can_for_tribe(action, tribe_id): initiative-scoped authority check.
-- For tribe-scoped policies where leaders can only write to their own tribe's
-- resources. Checks auth_engagements directly via auth_id + legacy_tribe_id.

CREATE OR REPLACE FUNCTION public.rls_can_for_tribe(p_action text, p_tribe_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.auth_id = auth.uid()
      AND ae.is_authoritative = true
      AND (
        ekp.scope IN ('organization', 'global')
        OR (ekp.scope = 'initiative' AND ae.legacy_tribe_id = p_tribe_id)
      )
  );
$$;

COMMENT ON FUNCTION public.rls_can_for_tribe(text, integer) IS 'V4 RLS helper: initiative-scoped authority check via legacy_tribe_id bridge. For tribe-scoped write policies (ADR-0007).';

GRANT EXECUTE ON FUNCTION public.rls_can_for_tribe(text, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
