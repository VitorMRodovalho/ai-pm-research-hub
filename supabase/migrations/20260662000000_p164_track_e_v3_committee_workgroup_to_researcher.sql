-- p164 Track E v3 — Refine sync_operational_role_cache + check_schema_invariants A3
-- Refs:
--   ADR-0023 (parity rule: sync_operational_role_cache ladder MUST mirror check_schema_invariants.A3)
--   ADR-0083 (capability cache + Tier A/B migration to canFor scoped)
--   docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md (PM decision Opção C/D + scope-leak rationale)
--
-- Context: Track E (p162, migration 20260652) extended the CASE chain to map V4-kind leadership
-- (study_group_owner / committee_* / workgroup_*) to 'tribe_leader' — under assumption that
-- ANY leadership = "tribe_leader" tier. PM audit in p163 flagged scope-leak: workgroup/committee
-- leader ≠ tribe leader (TIER_PERMISSIONS.tribe_leader grants cross-tribe admin authority).
-- Opção C (ADR-0083) already migrated 18 V3 exact-match gates to canFor scoped. Now this trigger
-- v3 refines the CASE chain to match institutional intent:
--
--   volunteer.{leader,comms_leader}              → tribe_leader  (research_tribe leadership, genuine)
--   committee_member/workgroup_member/sg_owner.* → researcher    (overlay leadership, scoped via canFor)
--   committee_coordinator/workgroup_coordinator.* → researcher    (idem)
--
-- Authority for those overlay groups continues to flow via can()/canFor scoped (engagement_kind_permissions
-- seeds work unchanged — those grant manage_event/write_board/etc. scope='initiative').
--
-- Impact:
--   - Immediate: 0 cache rows change (trigger fires only on engagement INSERT/UPDATE/DELETE).
--   - Latent risk removed: next trigger fire for 5 mems (Sarah/Roberto/Mayanna/Maria Luiza/Leticia)
--     no longer promotes them to tribe_leader.
--   - Backfill in this migration: 2 mems (Sarah/Roberto) observer → researcher to align with V4
--     engagement reality (curators with committee/workgroup engagements).
--   - A3 invariant drift expected after migration: 6 → 1 (Eder edge case remains; orthogonal).
--
-- Rollback: revert to p162 Track E body (migration 20260652) + UPDATE Sarah/Roberto observer.
-- The 18 gates from ADR-0083 already migrated to canFor — rollback of trigger alone would re-introduce
-- privilege expansion for any new V4-kind leader. So rollback should be coordinated.

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 1 — sync_operational_role_cache() v3
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_operational_role_cache()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_new_role text;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE person_id = COALESCE(NEW.person_id, OLD.person_id);
  IF v_member_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  SELECT CASE
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
      WHEN bool_or(
        (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
        OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
            AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
        OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
            AND ae.role IN ('leader','co_leader','owner','coordinator'))
      ) THEN 'researcher'
      WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
      WHEN bool_or(ae.kind = 'observer') THEN 'observer'
      WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
      WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
      WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
      WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
      ELSE 'guest'
    END INTO v_new_role
  FROM public.auth_engagements ae
  WHERE ae.person_id = COALESCE(NEW.person_id, OLD.person_id) AND ae.is_authoritative = true;

  UPDATE public.members SET operational_role = COALESCE(v_new_role, 'guest'), updated_at = now()
    WHERE id = v_member_id AND operational_role IS DISTINCT FROM COALESCE(v_new_role, 'guest');

  RETURN COALESCE(NEW, OLD);
END;
$function$;

COMMENT ON FUNCTION public.sync_operational_role_cache() IS
'V4 engagement → operational_role cache sync (Track E v3, p164). Restricts tribe_leader mapping to volunteer.{leader,comms_leader} only (genuine research_tribe leadership). committee_*/workgroup_*/study_group_owner leadership maps to researcher — real authority flows via canFor() scoped (ADR-0083). See ADR-0023 Amendment B + docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 2 — check_schema_invariants() A3 ladder parity (ADR-0023 rule)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_schema_invariants()
RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
        WHEN bool_or(
          (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
              AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
          OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
              AND ae.role IN ('leader','co_leader','owner','coordinator'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'observer') THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status='active' AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status='active' AND is_active=false) OR (member_status IN ('observer','alumni','inactive') AND is_active=true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND designations IS NOT NULL AND array_length(designations,1)>0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status='active' AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL AND (dv.id IS NULL OR dv.locked_at IS NULL)
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role='external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id=m.person_id AND ae.kind='external_signer' AND ae.status='active' AND ae.is_authoritative=true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive') AND m.anonymized_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id=m.id)
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected AS (
    SELECT a.id AS application_id, a.research_score AS cached,
      CASE
        WHEN e.obj_avg IS NOT NULL AND e.int_avg IS NOT NULL THEN round(e.obj_avg + e.int_avg, 2)
        WHEN e.obj_avg IS NOT NULL THEN round(e.obj_avg, 2)
        ELSE NULL
      END AS expected
    FROM public.selection_applications a
    CROSS JOIN LATERAL (
      SELECT AVG(weighted_subtotal) FILTER (WHERE evaluation_type='objective' AND submitted_at IS NOT NULL) AS obj_avg,
        AVG(weighted_subtotal) FILTER (WHERE evaluation_type='interview' AND submitted_at IS NOT NULL) AS int_avg
      FROM public.selection_evaluations WHERE application_id=a.id
    ) e
  ),
  drift AS (
    SELECT application_id FROM expected
    WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL)
       OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01)
  )
  SELECT 'M_application_score_consistency'::text,
         'selection_applications.research_score must equal compute_application_scores(application_id) derivation (sync trigger trg_recompute_application_scores).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND offboarded_at IS NULL AND anonymized_at IS NULL
      AND name <> 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'N_terminal_status_offboarded_at_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 defense-in-depth complement to L).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ma.id AS artifact_id FROM public.meeting_artifacts ma
    WHERE ma.event_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = ma.event_id)
  )
  SELECT 'O_meeting_artifact_event_orphan'::text,
         'meeting_artifacts.event_id must point to an existing event when not NULL (FK defense).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  SELECT 'P_tribe_initiative_bridge_complete'::text,
         'tribes.is_active=true must have at least one initiative.legacy_tribe_id pointing to it (V3-V4 bridge; cron leader digest depends).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM public.tribes t
          WHERE t.is_active = true
            AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.legacy_tribe_id = t.id)),
         NULL::uuid[];

END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 3 — Backfill seletivo Sarah + Roberto (PM-approved 2026-05-15)
-- ─────────────────────────────────────────────────────────────────────────────
-- Sarah Faria: curator (designation) + ambassador + founder. 4 V4 engagements (committee/workgroup/observer).
--              cache observer (revert p163) → researcher reflete realidade de curadora ativa.
-- Roberto Macêdo: curator + chapter_liaison + ambassador. 5 V4 engagements (chapter_board/committee/workgroup/observer/speaker).
--                 cache observer (revert p163) → researcher reflete realidade de curador PMI-CE.
-- Privilege delta: workspace.access + board.view_own_tribe + event.view_own_tribe + gamification.* + content.submit_publication.
-- No scope-leak risk (canFor scoped after ADR-0083 Tier A/B).
WITH backfill AS (
  SELECT id, name, operational_role AS old_role
  FROM public.members
  WHERE name IN ('Sarah Faria Alcantara Macedo Rodovalho','Roberto Macêdo')
    AND operational_role = 'observer'
    AND member_status = 'active'
),
upd AS (
  UPDATE public.members
  SET operational_role = 'researcher', updated_at = now()
  WHERE id IN (SELECT id FROM backfill)
  RETURNING id, name
)
INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
SELECT
  NULL::uuid,
  'backfill_operational_role'::text,
  'members'::text,
  u.id,
  jsonb_build_object('from', b.old_role, 'to', 'researcher'),
  jsonb_build_object(
    'name', u.name,
    'migration', '20260662000000_p164_track_e_v3_committee_workgroup_to_researcher',
    'pm_approved_at', '2026-05-15',
    'rationale', 'Track E v3 + selective backfill — researcher reflete realidade institucional pós-Opção C (canFor scoped).'
  )
FROM upd u
JOIN backfill b ON b.id = u.id;

NOTIFY pgrst, 'reload schema';

-- Rollback path:
-- 1. CREATE OR REPLACE FUNCTION public.sync_operational_role_cache() — revert to body of migration
--    20260652000000 (p162 Track E v2). The CASE chain includes V4-kind leadership → tribe_leader.
-- 2. CREATE OR REPLACE FUNCTION public.check_schema_invariants() — revert A3 CASE to v2 (parity rule).
-- 3. UPDATE public.members SET operational_role = 'observer', updated_at = now()
--      WHERE name IN ('Sarah Faria Alcantara Macedo Rodovalho','Roberto Macêdo')
--        AND operational_role = 'researcher';
-- Note: ADR-0083 Tier A/B gates already migrated to canFor — rollback of trigger alone re-introduces
-- privilege expansion for any new V4-kind leader. Coordinate rollback with frontend revert if needed.
