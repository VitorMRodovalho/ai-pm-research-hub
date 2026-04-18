-- ============================================================
-- Invariant I — artifacts table frozen post-V4 cutover
-- ADR-0012 B10 extension (council Tier 3 audit 2026-04-18, P0).
--
-- Context: artifacts table is classified C2 in ADR-0015 (not C3).
-- Pre-V4 flow inserted into artifacts; V4 flow uses board_items +
-- publication_submissions. No new rows have been inserted since
-- cutover (2026-04-13). Any new row indicates unauthorized write
-- (e.g., import-trello-legacy EF misfire, or direct service_role
-- bypass of V4 flow).
--
-- Decision: Defer artifacts table disposition (resurrect vs drop)
-- until post-CBGPL. This invariant is the interim safeguard — any
-- drift is detected at next guardian run instead of silently
-- re-populating a frozen table.
--
-- Gate for reopening: Phase 5 A6 (target 2026-05-10). Final
-- disposition (Option A resurrect or Option B drop) requires
-- product-leader decision on what "members_with_published_artifact"
-- funnel metric should mean in V4 (board_items? publication_submissions?).
--
-- Rollback: DROP FUNCTION public.check_schema_invariants();
--           then re-apply 20260425010000_b10_schema_invariants.sql.
-- ============================================================

DROP FUNCTION IF EXISTS public.check_schema_invariants();

CREATE FUNCTION public.check_schema_invariants()
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
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  -- A1. alumni status forces role='alumni'
  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni'
      AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- A2. observer status forces role IN (observer, guest, none)
  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer'
      AND operational_role NOT IN ('observer', 'guest', 'none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- A3. active member's role equals derivation from engagements
  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'leader')         THEN 'tribe_leader'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'comms_leader')   THEN 'tribe_leader'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator')) THEN 'researcher'
        WHEN bool_or(ae.kind = 'observer')      THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni')        THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor')       THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate')     THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae
      ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status = 'active'
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- B. is_active matches member_status
  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status = 'active' AND is_active = false)
        OR (member_status IN ('observer','alumni','inactive') AND is_active = true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- C. designations empty in terminal status
  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND designations IS NOT NULL
      AND array_length(designations, 1) > 0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- D. persons.auth_id ↔ members.auth_id agreement
  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL
      AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text,
         COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- E. engagement.status=active vs member.member_status=terminal
  RETURN QUERY
  WITH drift AS (
    SELECT e.id AS engagement_id FROM public.members m
    JOIN public.engagements e ON e.person_id = m.person_id
    WHERE e.status = 'active'
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND (
        m.member_status = 'inactive'
        OR (m.member_status = 'alumni'   AND e.kind != 'alumni')
        OR (m.member_status = 'observer' AND e.kind != 'observer')
      )
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  -- F. initiatives.legacy_tribe_id orphan
  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text,
         COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  -- ────────────────────────────────────────────────────────────
  -- I. artifacts table frozen post-V4 (2026-04-13)
  -- Any row inserted after freeze date = unauthorized write.
  -- Writers must use board_items + publication_submissions (V4 path).
  -- ────────────────────────────────────────────────────────────
  RETURN QUERY
  WITH drift AS (
    SELECT id AS artifact_id FROM public.artifacts
    WHERE created_at > '2026-04-13 23:59:59+00'::timestamptz
  )
  SELECT 'I_artifacts_frozen'::text,
         'artifacts table is frozen since V4 cutover (2026-04-13). New inserts indicate unauthorized write — V4 writers must use board_items + publication_submissions instead.'::text,
         'high'::text,
         COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$fn$;

COMMENT ON FUNCTION public.check_schema_invariants() IS
  'ADR-0012 B10 + I_artifacts_frozen (2026-04-28): query-based contract invariants. Returns one row per invariant with violation_count + sample_ids. 0 violations = clean. See tests/contracts/schema-invariants.test.mjs.';

GRANT EXECUTE ON FUNCTION public.check_schema_invariants() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
