-- p125 E1 Migration 4/5 — check_schema_invariants extension with 3 new p125 invariants
-- ADR-0076 Princípio 10 + Risk 3 do pre-mortem (drift detection)
-- Wave 1 draft (council review pending Wave 2)
--
-- Adds 5 invariants to detect:
--   I_VEP_IMPORT_COLUMNS_COMPLETE — applicant_city populated for non-private apps after E2 ship
--   I_PMI_MEMBERSHIPS_SNAPSHOT_CONSISTENCY — pmi_memberships JSONB present when status='approved' AND not profilePrivate
--   I_SERVICE_HISTORY_ORPHANS — service_history rows referencing non-existent applications (cascade race detection)
--
-- Wave 2 council watch-out: integrate into main check_schema_invariants() body
-- via CREATE OR REPLACE? Or keep as separate `check_schema_invariants_p125()` that
-- can be called in addition? Decision pending Wave 2 review.
--
-- Wave 1 approach: separate function for clarity. Easy to revert + integrate post-review.
--
-- Rollback: DROP FUNCTION public.check_schema_invariants_p125();

BEGIN;

DROP FUNCTION IF EXISTS public.check_schema_invariants_p125();

CREATE FUNCTION public.check_schema_invariants_p125()
RETURNS TABLE (
  invariant_name  text,
  description     text,
  severity        text,
  violation_count integer,
  sample_ids      uuid[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  -- Gate: same as base check_schema_invariants
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants_p125 requires authentication';
  END IF;

  -- ────────────────────────────────────────────────────────────
  -- I_VEP_IMPORT_COLUMNS_COMPLETE
  -- After E2 worker deploy, all non-private apps with Phase B fetched should
  -- have applicant_city populated. Detects RPC drift in import_vep_applications
  -- (Risk 3 do pre-mortem — 4ª iteração drift).
  -- Wave 2 fix (data-architect/platform-guardian): use pmi_data_fetched_at IS NOT NULL
  -- as the proxy for "Phase B happened" — date-agnostic; works regardless of E2 deploy date.
  -- ────────────────────────────────────────────────────────────
  RETURN QUERY
  WITH drift AS (
    SELECT id
    FROM public.selection_applications
    WHERE pmi_data_fetched_at IS NOT NULL
      AND community_profile_private = false
      AND applicant_city IS NULL
  )
  SELECT
    'I_VEP_IMPORT_COLUMNS_COMPLETE'::text,
    'Apps with Phase B fetched (pmi_data_fetched_at NOT NULL) and community_profile_private=false should have applicant_city populated. NULL implies import_vep_applications RPC body drift or mapper E2 silent failure.'::text,
    'WARNING'::text,
    (SELECT COUNT(*)::integer FROM drift),
    ARRAY(SELECT id FROM drift LIMIT 10)::uuid[];

  -- ────────────────────────────────────────────────────────────
  -- I_PMI_MEMBERSHIPS_SNAPSHOT_CONSISTENCY
  -- For apps approved + community_profile_private=false + Phase B fetched,
  -- pmi_memberships JSONB should be populated (snapshot at submission).
  -- NULL implies mapper E2 issue or Phase B fetch silently failed.
  -- ────────────────────────────────────────────────────────────
  RETURN QUERY
  WITH drift AS (
    SELECT id
    FROM public.selection_applications
    WHERE status IN ('approved','active')
      AND community_profile_private = false
      AND pmi_data_fetched_at IS NOT NULL
      AND pmi_memberships IS NULL
  )
  SELECT
    'I_PMI_MEMBERSHIPS_SNAPSHOT_CONSISTENCY'::text,
    'Approved/active apps with Phase B fetched and not profilePrivate should have pmi_memberships snapshot. NULL implies mapper drift or fetch silent failure.'::text,
    'WARNING'::text,
    (SELECT COUNT(*)::integer FROM drift),
    ARRAY(SELECT id FROM drift LIMIT 10)::uuid[];

  -- ────────────────────────────────────────────────────────────
  -- I_SERVICE_HISTORY_ORPHANS
  -- selection_application_service_history rows must reference live application
  -- (FK CASCADE ON DELETE should guarantee, but defense in depth detects races).
  -- ────────────────────────────────────────────────────────────
  RETURN QUERY
  WITH drift AS (
    SELECT sh.id
    FROM public.selection_application_service_history sh
    LEFT JOIN public.selection_applications sa ON sa.id = sh.application_id
    WHERE sa.id IS NULL
  )
  SELECT
    'I_SERVICE_HISTORY_ORPHANS'::text,
    'service_history rows with no parent selection_applications. FK CASCADE should prevent — orphans indicate race condition or RLS bypass.'::text,
    'CRITICAL'::text,
    (SELECT COUNT(*)::integer FROM drift),
    ARRAY(SELECT id FROM drift LIMIT 10)::uuid[];

  -- ────────────────────────────────────────────────────────────
  -- I_PMI_CHAPTER_MEMBERSHIPS_ORPHANS
  -- pmi_chapter_memberships rows must reference live person (FK CASCADE).
  -- Defense in depth — Risk 2 pre-mortem (anonymize CASCADE coverage).
  -- ────────────────────────────────────────────────────────────
  RETURN QUERY
  WITH drift AS (
    SELECT pcm.id
    FROM public.pmi_chapter_memberships pcm
    LEFT JOIN public.persons p ON p.id = pcm.person_id
    WHERE p.id IS NULL
  )
  SELECT
    'I_PMI_CHAPTER_MEMBERSHIPS_ORPHANS'::text,
    'pmi_chapter_memberships rows with no parent persons. FK CASCADE should prevent — orphans indicate anonymize cron gap or RLS bypass.'::text,
    'CRITICAL'::text,
    (SELECT COUNT(*)::integer FROM drift),
    ARRAY(SELECT id FROM drift LIMIT 10)::uuid[];

  -- ────────────────────────────────────────────────────────────
  -- I_LGPD_ERASURE_COMPLETENESS
  -- Anonymized members (email LIKE 'anon_%') should not have lingering
  -- pmi_chapter_memberships rows. If they do, Risk 2 do pre-mortem materialized.
  -- ────────────────────────────────────────────────────────────
  RETURN QUERY
  WITH anon_persons AS (
    SELECT m.person_id
    FROM public.members m
    WHERE m.email LIKE 'anon_%@removed.local'
      AND m.person_id IS NOT NULL
  ),
  drift AS (
    SELECT pcm.id
    FROM public.pmi_chapter_memberships pcm
    JOIN anon_persons ap ON ap.person_id = pcm.person_id
  )
  SELECT
    'I_LGPD_ERASURE_COMPLETENESS'::text,
    'Anonymized members (email anon_%) should not have lingering pmi_chapter_memberships. Indicates anonymize cron gap.'::text,
    'CRITICAL'::text,
    (SELECT COUNT(*)::integer FROM drift),
    ARRAY(SELECT id FROM drift LIMIT 10)::uuid[];

  RETURN;
END;
$fn$;

COMMENT ON FUNCTION public.check_schema_invariants_p125() IS
  'p125 spec invariants (PMI 3-dimensional model). Standalone for Wave 1 draft. Wave 2 council decides whether to merge into base check_schema_invariants(). ADR-0076.';

REVOKE ALL ON FUNCTION public.check_schema_invariants_p125() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.check_schema_invariants_p125() TO authenticated, service_role;

COMMIT;

-- Post-apply checklist:
--   1. supabase migration repair --status applied 20260518030000
--   2. NOTIFY pgrst, 'reload schema'
--   3. Test: SELECT * FROM check_schema_invariants_p125()
--   4. Wave 2 review: integrate into base check_schema_invariants() Y/N?
--      If Y: separate migration that does CREATE OR REPLACE on base function.
