-- WHAT: Wave 1a M2 — taxonomy expansion + visibility/status/acknowledgement columns
-- + atomic RLS swap (gd_read + document_versions_read_published) + V' invariant
-- in check_schema_invariants(). V (status/chain coherence) DEFERRED to Wave 1b.
--
-- WHY: P0-Q1/Q2/Q3/Q4/Q6/Q10 + A1/A2 (Wave 0 ratification, #315). Single
-- transaction (apply_migration is transactional) ensures atomic backfill→NOT NULL
-- →RLS swap with zero "NULL → visible" window per P0-Q3.
--
-- SPEC: docs/specs/SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §19.5 (Wave 1a M2)
-- + §19.3 Amendment A1 (acknowledgement_mode per-document) + Amendment A2
-- (status pending_proposer_consent + invariant V' shape).
--
-- SCOPE LOCK (per feedback_wave_1a_scope_confine_governance):
--   IN-SCOPE:  M2.1 doc_type CHECK +2; M2.2 status CHECK 5→8; M2.3 +7 cols;
--              M2.4 backfill uniform active_members + per-A1; M2.5 NOT NULL gate
--              + CHECKs; M2.6 atomic RLS swap (2 policies); M2.7 V' invariant.
--   OUT-OF-SCOPE: Wave 1b first leaf (synthetic-chain backfill + V invariant);
--                 Wave 2 admin UI; Wave 4 document_comments blind columns; etc.
--
-- KNOWN REGRESSION (intentional per PM #3): document_versions_read_published
-- no longer bypasses via `manager`/`deputy_manager` operational_role OR
-- `curate_content` capability. Only `manage_member` is the admin bypass; the
-- locked_at IS NOT NULL is HARD-GATE outside the OR. Effect: 2 curators
-- (Roberto Macêdo, Sarah Faria) who have curate_content but not manage_member
-- lose direct SELECT on UNLOCKED drafts via DocumentVersionEditor. Mitigation:
-- the chain review flow uses get_chain_workflow_detail (SECDEF) — unaffected.
-- Wave 1b will ship dedicated curator-draft-access policy or RPC.
--
-- BODY HASH DRIFT NOTE (Phase C, ADR-0097): The check_schema_invariants() body
-- below is the FULL existing 19-invariant body (cf. 20260802000008_p213_T) PLUS
-- the new V' RETURN QUERY block appended before END. Other invariants are
-- byte-identical to the live body to avoid drift.
--
-- ROLLBACK (idempotent):
--   -- Revert RLS:
--   DROP POLICY gd_read ON public.governance_documents;
--   CREATE POLICY gd_read ON public.governance_documents
--     AS PERMISSIVE FOR SELECT TO authenticated USING (true);
--   DROP POLICY document_versions_read_published ON public.document_versions;
--   CREATE POLICY document_versions_read_published ON public.document_versions
--     AS PERMISSIVE FOR SELECT TO authenticated
--     USING (locked_at IS NOT NULL OR EXISTS (SELECT 1 FROM public.members m
--             WHERE m.auth_id=(SELECT auth.uid())
--               AND (m.operational_role=ANY(ARRAY['manager','deputy_manager'])
--                    OR public.can_by_member(m.id,'curate_content'))));
--   -- Drop new columns:
--   ALTER TABLE public.governance_documents
--     DROP COLUMN closing_gate_signoff_id,
--     DROP COLUMN approved_at,
--     DROP COLUMN effective_until,
--     DROP COLUMN effective_from,
--     DROP COLUMN acknowledgement_mode,
--     DROP COLUMN required_action,
--     DROP COLUMN visibility_class,
--     DROP CONSTRAINT governance_documents_status_check,
--     DROP CONSTRAINT governance_documents_doc_type_check;
--   ALTER TABLE public.governance_documents
--     ADD CONSTRAINT governance_documents_status_check
--       CHECK (status IN ('draft','under_review','approved','active','superseded'));
--   ALTER TABLE public.governance_documents
--     ADD CONSTRAINT governance_documents_doc_type_check
--       CHECK (doc_type IN ('manual','cooperation_agreement','framework_reference',
--         'cooperation_addendum','volunteer_addendum','policy','volunteer_term_template',
--         'executive_summary','project_charter'));
--   -- Restore check_schema_invariants() body to pre-V' (re-apply 20260802000008 body).
--
-- INVARIANTS: 19 → 20 (V' added). V deferred Wave 1b (see ISSUE_REGISTRY #315).
-- CROSS-REF: #315 Wave 0; SPEC §19.5; ADR-0004/0007; session p256.
-- ============================================================================

-- M2.1 — doc_type CHECK extension (P0-Q1 + P1-Q2)
ALTER TABLE public.governance_documents DROP CONSTRAINT governance_documents_doc_type_check;
ALTER TABLE public.governance_documents ADD CONSTRAINT governance_documents_doc_type_check
  CHECK (doc_type IN (
    'manual','cooperation_agreement','framework_reference','cooperation_addendum',
    'volunteer_addendum','policy','volunteer_term_template','executive_summary',
    'project_charter',
    'editorial_guide',         -- NEW per P0-Q1 (Frontiers Editorial Guide)
    'governance_guideline'     -- NEW per P1-Q2 (Wave 1a ships alongside editorial_guide)
  ));

-- M2.2 — status CHECK drop+recreate 5→8 values (P0-Q6 + A2)
ALTER TABLE public.governance_documents DROP CONSTRAINT governance_documents_status_check;
ALTER TABLE public.governance_documents ADD CONSTRAINT governance_documents_status_check
  CHECK (status IN (
    'draft',
    'pending_proposer_consent',  -- NEW per A2
    'under_review',
    'approved',
    'active',
    'superseded',
    'withdrawn',                 -- NEW per A2 (explicit value, was hidden in chain)
    'revoked'                    -- NEW per A2 (post-active revocation distinct from withdrawn)
  ));

-- M2.3 — New columns (nullable for backfill; constraints applied after sanity DO)
ALTER TABLE public.governance_documents
  ADD COLUMN visibility_class     text,
  ADD COLUMN required_action      text,
  ADD COLUMN acknowledgement_mode text,
  ADD COLUMN effective_from       timestamptz,
  ADD COLUMN effective_until      timestamptz,
  ADD COLUMN approved_at          timestamptz,
  ADD COLUMN closing_gate_signoff_id uuid
    REFERENCES public.approval_signoffs(id) ON DELETE RESTRICT;  -- PM #1: RESTRICT not SET NULL

-- M2.4 — Backfill defaults
-- visibility_class: uniform 'active_members' (preserves current gd_read=true semantics;
-- Wave 2 admin UI re-classifies aspirationally per-doc)
UPDATE public.governance_documents
   SET visibility_class = 'active_members'
 WHERE visibility_class IS NULL;

-- acknowledgement_mode: per-A1 table defaults
UPDATE public.governance_documents
   SET acknowledgement_mode = CASE doc_type
     WHEN 'manual'                  THEN 'informational'
     WHEN 'editorial_guide'         THEN 'informational'
     WHEN 'governance_guideline'    THEN 'informational'
     WHEN 'executive_summary'       THEN 'informational'
     WHEN 'framework_reference'     THEN 'informational'
     WHEN 'project_charter'         THEN 'informational'
     WHEN 'cooperation_agreement'   THEN 'legal_signature'
     WHEN 'cooperation_addendum'    THEN 'legal_signature'
     WHEN 'volunteer_term_template' THEN 'binding'
     WHEN 'volunteer_addendum'      THEN 'binding'
     WHEN 'policy'                  THEN 'binding'
     ELSE 'informational'
   END
 WHERE acknowledgement_mode IS NULL;

-- approved_at: derive from first_ratified_at when present, else signed_at, for ratified statuses
UPDATE public.governance_documents
   SET approved_at = COALESCE(first_ratified_at, signed_at)
 WHERE approved_at IS NULL
   AND status IN ('approved','active','superseded');

-- effective_from / effective_until: derive from legacy valid_from / valid_until
UPDATE public.governance_documents
   SET effective_from  = COALESCE(valid_from, approved_at),
       effective_until = valid_until
 WHERE effective_from IS NULL OR effective_until IS NULL;

-- M2.5 — Sanity DO (RAISES if any backfill incomplete) + NOT NULL gates + CHECKs
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.governance_documents WHERE visibility_class IS NULL) THEN
    RAISE EXCEPTION 'p256 M2: visibility_class backfill incomplete';
  END IF;
  IF EXISTS (SELECT 1 FROM public.governance_documents WHERE acknowledgement_mode IS NULL) THEN
    RAISE EXCEPTION 'p256 M2: acknowledgement_mode backfill incomplete';
  END IF;
END $$;

ALTER TABLE public.governance_documents
  ALTER COLUMN visibility_class      SET NOT NULL,
  ALTER COLUMN acknowledgement_mode  SET NOT NULL,
  ADD CONSTRAINT governance_documents_visibility_class_check
    CHECK (visibility_class IN ('public','active_members','legal_scoped','admin_only','audit_restricted')),
  ADD CONSTRAINT governance_documents_acknowledgement_mode_check
    CHECK (acknowledgement_mode IN ('informational','binding','legal_signature'));

-- M2.6 — Atomic RLS swap (drop + create in same migration tx, post NOT NULL gate)

-- 6a) governance_documents.gd_read — class-aware (was USING (true))
DROP POLICY gd_read ON public.governance_documents;
CREATE POLICY gd_read ON public.governance_documents
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    visibility_class IS NOT NULL AND (
      visibility_class = 'public'
      OR (visibility_class = 'active_members' AND EXISTS (
          SELECT 1 FROM public.members m
          WHERE m.auth_id = (SELECT auth.uid()) AND m.is_active = true))
      OR (visibility_class = 'legal_scoped' AND (
          EXISTS (SELECT 1 FROM public.members m
                  WHERE m.auth_id = (SELECT auth.uid())
                    AND public.can_by_member(m.id, 'manage_member'))
          OR EXISTS (SELECT 1 FROM public.member_document_signatures mds
                     JOIN public.members m ON m.id = mds.member_id
                     WHERE m.auth_id = (SELECT auth.uid())
                       AND mds.document_id = governance_documents.id
                       AND mds.is_current = true)))
      OR (visibility_class = 'admin_only' AND EXISTS (
          SELECT 1 FROM public.members m
          WHERE m.auth_id = (SELECT auth.uid())
            AND public.can_by_member(m.id, 'manage_member')))
      OR (visibility_class = 'audit_restricted' AND EXISTS (
          SELECT 1 FROM public.members m
          WHERE m.auth_id = (SELECT auth.uid())
            AND public.can_by_member(m.id, 'manage_platform')))
    )
  );

-- 6b) document_versions.document_versions_read_published — PM #3: locked_at hard-gate, manage_member-only admin
DROP POLICY document_versions_read_published ON public.document_versions;
CREATE POLICY document_versions_read_published ON public.document_versions
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    -- HARD-GATE outside OR: published path requires locked_at NOT NULL.
    locked_at IS NOT NULL
    AND (
      -- Path A: parent doc visibility allows caller (Wave 1a routine path)
      EXISTS (
        SELECT 1 FROM public.governance_documents gd
        WHERE gd.id = document_versions.document_id
          AND gd.visibility_class IS NOT NULL
          AND (
            gd.visibility_class IN ('public','active_members')
            OR (gd.visibility_class = 'legal_scoped' AND EXISTS (
                SELECT 1 FROM public.member_document_signatures mds
                JOIN public.members m ON m.id = mds.member_id
                WHERE m.auth_id = (SELECT auth.uid())
                  AND mds.document_id = gd.id
                  AND mds.is_current = true))
            OR (gd.visibility_class = 'admin_only' AND EXISTS (
                SELECT 1 FROM public.members m
                WHERE m.auth_id = (SELECT auth.uid())
                  AND public.can_by_member(m.id, 'manage_member')))
            OR (gd.visibility_class = 'audit_restricted' AND EXISTS (
                SELECT 1 FROM public.members m
                WHERE m.auth_id = (SELECT auth.uid())
                  AND public.can_by_member(m.id, 'manage_platform')))
          )
      )
      -- Path B: caller is admin (manage_member) — sees all LOCKED versions regardless of visibility
      OR EXISTS (
        SELECT 1 FROM public.members m
        WHERE m.auth_id = (SELECT auth.uid())
          AND public.can_by_member(m.id, 'manage_member')
      )
    )
  );

-- M2.7 — check_schema_invariants() extension with V' (V deferred Wave 1b)
-- Body is verbatim copy of pre-existing 19 invariants (cf 20260802000008) + V' appended.

CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
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
      AND name NOT LIKE '%_synthetic%'
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
      AND name NOT LIKE '%_synthetic%'
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
      AND m.name NOT LIKE '%_synthetic%'
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
      AND name NOT LIKE '%_synthetic%'
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
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
      AND NOT EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status IN ('review','approved','activated')
          AND ac.closed_at IS NULL
      )
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL — unless an open approval_chain (review/approved/activated, closed_at NULL) is in flight that will lock the version on close (Phase IP-1, chain-aware).'::text,
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

  RETURN QUERY
  WITH drift AS (
    SELECT id AS engagement_id FROM public.engagements
    WHERE status = 'expired' AND end_date > CURRENT_DATE
  )
  SELECT 'Q_expired_engagement_end_date'::text,
         'engagements.status=expired requires end_date <= CURRENT_DATE (impossible to be expired in the future; VEP service_latest_end_date is source of truth).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT a.id AS application_id
    FROM public.selection_applications a
    WHERE a.status = 'approved'
      AND a.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.members m WHERE lower(m.email) = lower(a.email)
      )
  )
  SELECT 'R_approved_application_has_member'::text,
         'selection_applications.status=approved must have a matching members row by lower(email). Bypass of approve_selection_application() canonical RPC creates this drift (Issue #180).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT DISTINCT m.id AS member_id
    FROM public.selection_applications a
    JOIN public.members m ON lower(m.email) = lower(a.email)
    WHERE a.status = 'approved' AND m.person_id IS NULL
  )
  SELECT 'S_approved_member_has_person_id'::text,
         'members tied to an approved selection_applications row must have person_id NOT NULL (V4 graph anchor for engagements). Issue #180.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- T (p212, #205): Member has exactly one primary email in member_emails
  RETURN QUERY
  WITH primary_email_counts AS (
    SELECT m.id AS member_id,
           COUNT(me.id) FILTER (WHERE me.is_primary = true) AS primary_count
    FROM public.members m
    LEFT JOIN public.member_emails me ON me.member_id = m.id
    WHERE m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT member_id FROM primary_email_counts
    WHERE primary_count <> 1
  )
  SELECT 'T_member_has_exactly_one_primary_email'::text,
         'Every member must have exactly one primary email in member_emails (Issue #205).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- V' (p256, #315 Wave 1a M2 — A2 + P0-Q7): status=pending_proposer_consent
  -- must not have any non-cancelled approval_chains rows. Per Amendment A2:
  -- pending_proposer_consent documents are NOT eligible for under_review until
  -- the proposer signs (in-app) OR GP records offline attestation.
  --
  -- V (status=approved/active → current_ratified_chain_id IS NOT NULL) is
  -- DEFERRED to Wave 1b first leaf. 7 legacy pre-chain docs need synthetic-chain
  -- backfill with PM-designated signer-of-record convention BEFORE V can enforce.
  -- See ISSUE_REGISTRY #315 cluster narrative + handoff_p256.
  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status = 'pending_proposer_consent'
      AND EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status NOT IN ('withdrawn','superseded')
      )
  )
  SELECT 'V_prime_pending_proposer_consent_no_open_chain'::text,
         'status=pending_proposer_consent must not have non-cancelled approval_chains rows (#315 P0-Q7 + Amendment A2 — pending_proposer_consent precedes any chain).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

COMMENT ON FUNCTION public.check_schema_invariants() IS
'20 schema invariants (A1-A3, B-F, J-Q, R-T, V_prime — last extended p256 Wave 1a M2 for #315). V (status/chain coherence) deferred to Wave 1b first leaf — 7 legacy pre-chain docs need synthetic-chain backfill before V can enforce.';

NOTIFY pgrst, 'reload schema';
