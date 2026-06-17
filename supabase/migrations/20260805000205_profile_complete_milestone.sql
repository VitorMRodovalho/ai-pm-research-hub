-- PR 5 of #766 item 2/4 (server-side milestones framework) — the CLOSING milestone.
-- See docs/specs/SPEC_766_SERVER_SIDE_MILESTONES.md §7 (PR5).
--
-- Adds the `profile_complete` milestone: fired when members.profile_completed_at transitions
-- from NULL to NOT NULL (the member's first profile save).
--
-- GROUNDING (execute_sql, 2026-06-17): members.profile_completed_at (timestamptz NULL) is
-- written by ONLY ONE function — update_my_profile(jsonb) — and only as
--   profile_completed_at = CASE WHEN profile_completed_at IS NULL THEN now() ELSE profile_completed_at END
-- i.e. set ONCE on the first profile save (any allowed field) and NEVER cleared (a grep of all
-- pg_proc.prosrc returns only update_my_profile). So the column is MONOTONIC / set-once. The
-- milestone celebrates the member having filled in their profile; the SPEC §2 grounding stands:
-- there is NO "+50pts" award for profile completion (no gamification_rule/gamification_points
-- row references the column), so the FE copy must NOT mention points.
--
-- Invariant AE appended to check_schema_invariants() (31 -> 32), mirroring AA/AB/AC/AD. Unlike
-- promotion (PR4, NO invariant — operational_role is a mutable cache and demotion is routine, so
-- a directional check would permanently false-positive), profile_completed_at is monotonic, so a
-- directional "profile_complete milestone => profile_completed_at IS NOT NULL" check is
-- false-positive-free and consistent with the 4 other source-backed milestones
-- (data-architect GO-with-changes, PR5).
--
-- schema-cache-columns.test gate (ADR-0012): VERIFIED CLEAN — this migration adds NO column to
-- members/engagements/initiatives (trigger-only), so the cache-column contract is not engaged.
--
-- Backfill is SILENT (acknowledged_at = now()) so the 23 members with profile_completed_at set are
-- NOT re-celebrated; only post-deploy first-saves fire a pending milestone. Race-safe: backfill
-- runs BEFORE CREATE TRIGGER (SPEC §6.3). occurred_at = COALESCE(profile_completed_at, created_at,
-- now()) — profile_completed_at is the real event moment (not a proxy); COALESCE only because
-- member_milestones.occurred_at is NOT NULL and the column is nullable in general.
--
-- LGPD note (data-architect): the anonymization cron anonymizes PII columns on members but does
-- NOT delete the row, and does NOT clear member_milestones (CASCADE only fires on DELETE — the
-- Art.18 delete path). A profile_complete milestone surviving on an anonymized member is a
-- non-PII lifecycle timestamp; this is a pre-existing condition shared by all 5 other milestones,
-- acceptable for v1.
--
-- ROLLBACK:
--   DROP TRIGGER IF EXISTS trg_record_profile_complete_milestone ON public.members;
--   DROP FUNCTION IF EXISTS public._trg_record_profile_complete_milestone();
--   DELETE FROM public.member_milestones WHERE milestone_key = 'profile_complete';
--   -- re-apply 20260805000203's check_schema_invariants() body (without the AE block).
--   NOTIFY pgrst, 'reload schema';

-- 1. Trigger function. source_id is NULL (no separate evidence table; source_type='profile' is
--    informational). public.record_milestone is schema-qualified (search_path=''). No inline
--    comment inside the function body — Phase C captures prosrc verbatim (PR2/PR3 sediment).
CREATE OR REPLACE FUNCTION public._trg_record_profile_complete_milestone()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  PERFORM public.record_milestone(
    NEW.id, 'profile_complete', 'profile', NULL::uuid,
    jsonb_build_object('via', 'profile_completed_at_trigger')
  );
  RETURN NEW;
END; $fn$;
REVOKE ALL ON FUNCTION public._trg_record_profile_complete_milestone() FROM PUBLIC;

-- 2. Silent backfill (acknowledged_at=now()). MUST run BEFORE CREATE TRIGGER (SPEC §6.3).
--    Cohort at apply time (live, 2026-06-17): 23 members with profile_completed_at NOT NULL.
INSERT INTO public.member_milestones
  (member_id, milestone_key, occurred_at, source_type, source_id, acknowledged_at, metadata)
SELECT id, 'profile_complete', COALESCE(profile_completed_at, created_at, now()), 'profile', NULL::uuid, now(),
  jsonb_build_object('backfill', true, 'migration', '20260805000205')
FROM public.members
WHERE profile_completed_at IS NOT NULL
ON CONFLICT (member_id, milestone_key) DO NOTHING;

-- 3. Sanity — every member with profile_completed_at set must now hold the milestone (mirror PR2/PR3/PR4).
DO $sanity$
DECLARE v_missing int;
BEGIN
  SELECT count(*) INTO v_missing
  FROM public.members m
  WHERE m.profile_completed_at IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.member_milestones mm
      WHERE mm.member_id = m.id AND mm.milestone_key = 'profile_complete'
    );
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'PR5 #766 profile_complete backfill sanity FAIL: % members with profile_completed_at lack a milestone', v_missing;
  END IF;
  RAISE NOTICE 'PR5 #766 profile_complete backfill sanity OK.';
END$sanity$;

-- 4. Trigger (created AFTER the backfill, race-safe). The WHEN clause is the integrity guard:
--    fires only on the NULL -> NOT NULL transition. Because the column is monotonic, this fires
--    at most once per member. UPDATE OF profile_completed_at: Postgres fires only when the column
--    is in the UPDATE SET clause (update_my_profile always includes it via its CASE expression).
DROP TRIGGER IF EXISTS trg_record_profile_complete_milestone ON public.members;
CREATE TRIGGER trg_record_profile_complete_milestone
  AFTER UPDATE OF profile_completed_at ON public.members
  FOR EACH ROW
  WHEN (OLD.profile_completed_at IS NULL AND NEW.profile_completed_at IS NOT NULL)
  EXECUTE FUNCTION public._trg_record_profile_complete_milestone();

COMMENT ON FUNCTION public._trg_record_profile_complete_milestone() IS
  '#766 PR5: records the profile_complete member_milestone when members.profile_completed_at transitions NULL -> NOT NULL (AFTER UPDATE OF profile_completed_at, WHEN OLD IS NULL AND NEW IS NOT NULL). The column is monotonic (only update_my_profile sets it, once, never cleared), so the WHEN clause fires at most once per member. First-occurrence also guarded by record_milestone ON CONFLICT DO NOTHING.';

-- 5. check_schema_invariants() with AE appended (31 -> 32). The body below is reproduced verbatim
--    from 20260805000203 (31 invariants, byte-equal) with the AE RETURN QUERY block added before
--    END. This file is the canonical capture for the rpc-migration-coverage Phase C gate (file body
--    == live prosrc, normalized) — the whole CREATE OR REPLACE is applied to live so file and live
--    are identical by construction.
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
      AND NOT EXISTS (
        SELECT 1 FROM public.member_emails me WHERE lower(me.email) = lower(a.email)
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

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status IN ('approved','active')
      AND gd.current_ratified_chain_id IS NULL
  )
  SELECT 'V_status_chain_coherence'::text,
         'governance_documents with status approved/active must have current_ratified_chain_id NOT NULL (#315 P0-Q6 + #367 Wave 1b first leaf). NO carve-out: 7 legacy pre-chain docs backfilled with PM-designated synthetic chains via migration 20260805000038 (acknowledge signoffs, metadata.legacy_migration=true, role=migration_attestation).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT cp.id AS product_id
    FROM public.content_products cp
    WHERE
      CASE cp.source_kind
        WHEN 'governance_document_version' THEN
          NOT (cp.source_document_version_id IS NOT NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'board_item' THEN
          NOT (cp.source_board_item_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'publication_idea' THEN
          NOT (cp.source_publication_idea_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'external' THEN
          NOT (cp.source_external_uri IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL)
        WHEN 'none' THEN
          NOT (cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        ELSE TRUE
      END
  )
  SELECT 'W_content_product_source_integrity'::text,
         'content_products row must satisfy chk_content_products_source_integrity CHECK semantics (exactly one source FK populated per source_kind; ADR-0099 §2.2 + §6 step 9). Defense-in-depth complement to the CHECK constraint; mirrors V/V''/T pattern.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(product_id ORDER BY product_id) FROM (SELECT product_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT p.id AS parecer_id
    FROM public.blind_review_pareceres p
    WHERE NOT EXISTS (
      SELECT 1 FROM public.blind_review_assignments a
      WHERE a.session_id = p.session_id
        AND a.reviewer_member_id = p.reviewer_member_id
        AND a.status = 'active'
    )
  )
  SELECT 'X_blind_review_pareceres_session_product_match'::text,
         'blind_review_pareceres.reviewer_member_id must have an active blind_review_assignments row in the same session (assignment-parecer integrity; ADR-0099 §2.7 + §7 step 11). Defense-in-depth complement to FK constraints; catches drift if assignment is withdrawn while parecer remains. #382 PR-B.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(parecer_id ORDER BY parecer_id) FROM (SELECT parecer_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH pe AS (
    SELECT name AS k FROM public.partner_entities
    WHERE entity_type = 'pmi_chapter' AND status = 'active' AND NOT COALESCE(is_international, false)
  ),
  ch AS (
    SELECT 'PMI-' || code AS k FROM public.chapters WHERE status = 'active'
  ),
  drift AS (
    SELECT k FROM pe WHERE k NOT IN (SELECT k FROM ch)
    UNION ALL
    SELECT k FROM ch WHERE k NOT IN (SELECT k FROM pe)
  )
  SELECT 'Y_chapter_pipeline_parity'::text,
         'every active domestic pmi_chapter in partner_entities must have a matching active chapters row (by name = ''PMI-'' || chapters.code) and vice-versa — MEMBERSHIP parity (not just count), so it catches single-table inserts/archives even when row counts coincide. Drift = get_chapter_metrics()->>signed forks from the V4 chapters table (#481).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM drift),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS webinar_id FROM public.webinars
    WHERE status IS NULL OR status NOT IN ('planned','confirmed','completed','cancelled')
  )
  SELECT 'Z_webinar_status_domain'::text,
         'webinars.status must be within planned|confirmed|completed|cancelled (the realized=completed canonical definition depends on it; defense-in-depth complement to webinars_status_check — #479/#481).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(webinar_id ORDER BY webinar_id) FROM (SELECT webinar_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND current_cycle_active = true
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B2_current_cycle_active_terminal_status'::text,
         'members in observer/alumni/inactive must have current_cycle_active=false (#483 sync_member_status_consistency B-trigger; CCA gates the get_gamification_leaderboard/get_public_leaderboard cohort).'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- U (ADR-0104 Wave 3b-ii): members.chapter is now derived as
  -- COALESCE('PMI-'||entry_chapter_code, 'PMI-'||primary affiliation code, legacy chapter).
  -- For the derivation to be deterministic for registry-chaptered active members, each must have
  -- exactly one is_primary=true affiliation. The partial unique index enforces AT MOST one; this
  -- enforces EXACTLY one. Non-registry chapters (Outro/Externo) are excluded — legitimately
  -- unaffiliated, derivation falls through to the legacy value.
  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.person_id IS NOT NULL
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
      AND replace(m.chapter, 'PMI-', '') IN (SELECT chapter_code FROM public.chapter_registry)
      AND NOT (m.operational_role = 'guest' AND m.entry_chapter_code IS NULL)
      AND (SELECT COUNT(*) FROM public.member_chapter_affiliations a
            WHERE a.person_id = m.person_id AND a.is_primary) <> 1
  )
  SELECT 'U_active_person_has_primary_chapter_affiliation'::text,
         'every active registry-chaptered member''s person_id must have exactly one is_primary=true member_chapter_affiliations row, else the members.chapter COALESCE(entry, primary, legacy) derivation breaks silently (ADR-0104 Wave 3b-ii). Excluded: operational_role=''guest'' AND entry_chapter_code IS NULL (pre-onboarding, entry-chapter choice not yet made — affiliation is seeded by set_my_entry_chapter, Wave 3b-i; until then the COALESCE falls through to the legacy default). Non-registry chapters (Outro/Externo) excluded — legitimately unaffiliated.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AA (#766; the discovery dubbed this "invariant T", but T and U are already taken):
  -- the cert-side AFTER trigger (_trg_complete_volunteer_term_on_cert on certificates) and the
  -- seed-side BEFORE guard (_trg_complete_volunteer_term_on_seed on onboarding_progress) together
  -- guarantee that a member holding an issued volunteer_agreement certificate has their
  -- 'volunteer_term' onboarding step marked completed. This invariant codifies that guarantee.
  -- Directional: no volunteer_term row, or a completed step without an issued cert (all certs
  -- rejected/superseded), is NOT a violation.
  RETURN QUERY
  WITH drift AS (
    SELECT op.member_id
    FROM public.onboarding_progress op
    WHERE op.step_key = 'volunteer_term'
      AND op.status <> 'completed'
      AND op.member_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = op.member_id
          AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
      )
  )
  SELECT 'AA_volunteer_term_complete_when_cert_issued'::text,
         'a member holding an issued volunteer_agreement certificate must have their volunteer_term onboarding_progress step at status=completed. Guaranteed by the cert-side AFTER trigger (_trg_complete_volunteer_term_on_cert on certificates) plus the seed-side BEFORE guard (_trg_complete_volunteer_term_on_seed on onboarding_progress), p233 / issue #766. A non-completed step alongside an issued cert means a trigger was bypassed (service_role direct INSERT, or a cert backfill that did not fire the AFTER trigger). Directional: a member with no volunteer_term row, or a completed step without an issued cert (all certs rejected or superseded), is NOT a violation.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;
  -- AB (#766 PR2): a term_signed milestone must have a volunteer_agreement certificate
  -- of ANY status (issued/rejected/superseded) for the same member. Wave-3c-safe: the
  -- milestone persists after a cert is rejected or superseded because the member did
  -- sign once; only a milestone with NO cert ancestry at all is a violation (fabrication
  -- or a bad backfill via service_role direct INSERT). Directional complement to AA.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'term_signed'
      AND NOT EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = mm.member_id
          AND c.type = 'volunteer_agreement'
      )
  )
  SELECT 'AB_term_signed_milestone_has_cert_ancestry'::text,
         'a term_signed member_milestone must have at least one volunteer_agreement certificate of any status (issued/rejected/superseded) for the same member. Wave 3c reject/reissue is valid ancestry — the milestone persists after a cert is rejected or superseded because the member did sign once. A milestone with NO cert in any state indicates fabrication or a bad backfill (service_role direct INSERT into member_milestones; source_id is informational-only without FK). #766 PR2, mig 20260805000202. Directional complement to AA.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AC (#766 PR3): a first_attendance milestone must have at least one present=true
  -- attendance row for the member. source_id is informational-only (no FK), so a milestone
  -- with no present attendance indicates fabrication or a bad backfill (service_role direct
  -- INSERT into member_milestones). Directional, mirrors AA/AB.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'first_attendance'
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.member_id = mm.member_id
          AND a.present = true
      )
  )
  SELECT 'AC_first_attendance_milestone_has_attendance'::text,
         'a first_attendance member_milestone must have at least one present=true attendance row for the same member. source_id is informational-only (no FK), so a milestone with no present attendance indicates fabrication or a bad backfill (service_role direct INSERT into member_milestones). #766 PR3, mig 20260805000203. Directional, mirrors AA/AB.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AD (#766 PR3): a first_deliverable milestone must have at least one tribe_deliverable
  -- with status='completed' assigned to the member. Keyed on status='completed' (the same
  -- signal the trigger fires on, and the XP sibling trg_tribe_deliverable_completed_xp), NOT
  -- completed_at (a derived audit column). Catches a status reverted via service_role after
  -- the milestone fired, a fabricated milestone, or a bad backfill. Directional.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'first_deliverable'
      AND NOT EXISTS (
        SELECT 1 FROM public.tribe_deliverables td
        WHERE td.assigned_member_id = mm.member_id
          AND td.status = 'completed'
      )
  )
  SELECT 'AD_first_deliverable_milestone_has_completed_deliverable'::text,
         'a first_deliverable member_milestone must have at least one tribe_deliverable with status=''completed'' assigned to the same member. Keyed on status=''completed'' (same signal as the trigger and the XP sibling trg_tribe_deliverable_completed_xp; NOT completed_at, a derived audit column). A milestone with no completed deliverable indicates fabrication, a bad backfill, or a status reverted via service_role after the milestone fired. #766 PR3, mig 20260805000203. Directional, mirrors AA/AB.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AE (#766 PR5): a profile_complete milestone must have members.profile_completed_at set.
  -- profile_completed_at is monotonic — only update_my_profile writes it (NULL -> now() once,
  -- via CASE WHEN profile_completed_at IS NULL THEN now() ELSE profile_completed_at END) and no
  -- function ever clears it — so this directional check is false-positive-free, unlike promotion
  -- (PR4 added no invariant: operational_role is a mutable cache with routine demotion). Catches
  -- a fabricated milestone, a bad backfill, or the column cleared via a manual UPDATE after the
  -- milestone fired. Directional, mirrors AA/AB/AC/AD.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'profile_complete'
      AND NOT EXISTS (
        SELECT 1 FROM public.members m
        WHERE m.id = mm.member_id
          AND m.profile_completed_at IS NOT NULL
      )
  )
  SELECT 'AE_profile_complete_milestone_has_profile_completed_at'::text,
         'a profile_complete member_milestone must have members.profile_completed_at set. The column is monotonic — only update_my_profile writes it (NULL -> now() once, never cleared) — so this directional check is false-positive-free, unlike promotion whose mutable operational_role cache demotes routinely (hence PR4 added no invariant). A milestone with a NULL profile_completed_at indicates fabrication, a bad backfill (service_role direct INSERT into member_milestones; source_id is informational-only without FK), or the column cleared via a manual UPDATE after the milestone fired. #766 PR5, mig 20260805000205. Directional, mirrors AA/AB/AC/AD.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

NOTIFY pgrst, 'reload schema';
