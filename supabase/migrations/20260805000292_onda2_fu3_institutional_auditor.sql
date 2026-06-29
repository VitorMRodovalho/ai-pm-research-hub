-- Onda 2 — FU-3 (#952): institutional_auditor tier + view_aggregate_analytics action. ADR-0111.
-- =============================================================================================
-- WHAT: a new V4 engagement_kind `institutional_auditor` (role `auditor`) for an EXTERNAL
--       institutional reviewer (e.g. PMI LATAM/Global). Seeded with a SINGLE, NEW, genuinely
--       aggregate-only read action `view_aggregate_analytics` — never view_pii / write / manage_*.
--       That action is honored ONLY by 8 RPCs that were live-verified to return ZERO individual
--       PII and perform ZERO writes (see ADR-0111 for the audit that rejected the naive plan of
--       reusing view_internal_analytics, which leaks the member directory + selection PII + 5 writes).
--
-- DORMANT / behavior-neutral: zero institutional_auditor members exist. Grants are additive; the
-- ladder clause only affects future auditor members; the rls_is_authoritative_member carve-out is
-- subtractive for the new role only; the end_date CHECK has zero rows of this kind. Dormancy is
-- guaranteed by there being NO assigned engagement (an auditor is provisioned by GP only, under a
-- cooperation agreement — FU-4 governance). legal_basis=legitimate_interest + requires_agreement=false
-- match the sponsor/observer/chapter_board institutional read-only family (and the catalog invariant
-- that a requires_agreement kind must name an agreement_template).
--
-- APPLY vs FILE: applied to prod via MCP apply_migration using verified replace() transforms of the
-- live pg_get_functiondef bodies (each anchor validated to hit exactly once pre-apply). This FILE is
-- the literal SSOT (replay + role-ladder-parity + rpc-migration-coverage Phase-C drift gates parse the
-- literal CREATE OR REPLACE blocks). Bodies below are the post-apply pg_get_functiondef output, so the
-- file is byte-faithful to live.
--
-- Ritual: apply_migration (done) -> this file -> `supabase migration repair --status applied
--   20260805000292` -> `NOTIFY pgrst, 'reload schema'` (RPC surface changed).
-- =============================================================================================

-- ── Part 1: kind catalog row (config, not code — ADR-0009) ──
INSERT INTO public.engagement_kinds (
  slug, display_name, description,
  legal_basis, requires_agreement, agreement_template,
  default_duration_days, retention_days_after_end, is_initiative_scoped,
  requires_vep, requires_selection, max_duration_days,
  anonymization_policy, renewable, auto_expire_behavior, notify_before_expiry_days,
  created_by_role, revocable_by_role, initiative_kinds_allowed,
  metadata_schema, display_i18n, organization_id
) VALUES (
  'institutional_auditor', 'Auditor Institucional',
  'Revisor institucional externo (ex.: PMI LATAM/Global). Acesso de LEITURA a dashboards AGREGADOS do programa via a action view_aggregate_analytics — zero PII individual, zero escrita. Dormante: provisionado apenas por GP sob acordo de cooperação (FU-4); end_date obrigatório (CHECK). FU-3 / ADR-0111 / #952.',
  'legitimate_interest', false, NULL,
  365, 730, false,
  false, false, 365,
  'anonymize', true, 'notify_only', 30,
  ARRAY['manager','deputy_manager'], ARRAY['manager','deputy_manager'], ARRAY[]::text[],
  NULL, '{"en":"Institutional Auditor","es":"Auditor Institucional"}'::jsonb,
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'
) ON CONFLICT (slug) DO NOTHING;

-- ── Part 2: the single READ action (org scope). New action 'view_aggregate_analytics' is plain text
--    (no enum); honored ONLY by the 8 curated PII-free aggregate RPCs in Part 5. ──
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES ('institutional_auditor', 'auditor', 'view_aggregate_analytics', 'organization')
ON CONFLICT (kind, role, action) DO NOTHING;

-- ── Part 3: end_date mandatory for this kind (mirrors engagements_speaker_role_check) ──
ALTER TABLE public.engagements DROP CONSTRAINT IF EXISTS engagements_institutional_auditor_end_date_check;
ALTER TABLE public.engagements ADD CONSTRAINT engagements_institutional_auditor_end_date_check
  CHECK (kind <> 'institutional_auditor' OR end_date IS NOT NULL);

-- ── Part 4: RLS carve-out — the auditor must NOT pass rls_is_authoritative_member() (which grants
--    the baseline member-directory PII via members_read_by_members). Additive exclusion of the new
--    role only; behavior-neutral (zero such members). ──
CREATE OR REPLACE FUNCTION public.rls_is_authoritative_member()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid()
      AND m.is_active = true
      AND m.operational_role IS NOT NULL
      AND m.operational_role <> 'guest'
      AND m.operational_role <> 'institutional_auditor'
  );
$function$;

-- ── Part 5a: ladder — sync_operational_role_cache + check_schema_invariants A3 byte-parity (ADR-0023
--    Amendment C). New clause `WHEN bool_or(ae.kind='institutional_auditor') THEN 'institutional_auditor'`
--    inserted after external_signer (read-only external persona; below operational roles). ──
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
      -- Wave 1 fix: sponsor outranks researcher (committee/workgroup) so a sponsor who also sits on a
      -- committee (e.g. the governance committee) shows as a sponsor, not a researcher.
      WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
      -- Wave 2 WS-1 (PM 2026-06-28 'governança vence'): chapter_board (chapter director) outranks
      -- researcher/observer so a chapter director who also sits on a committee or observes a
      -- tribe still shows as 'Ponto Focal do Capítulo' (chapter_liaison). Stays BELOW sponsor
      -- and operational leaders (manager/deputy/tribe_leader) — those who lead operationally keep that role.
      WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
      WHEN bool_or(
        (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
        OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
            AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
        OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
            AND ae.role IN ('leader','co_leader','owner','coordinator'))
      ) THEN 'researcher'
      WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
      WHEN bool_or(ae.kind = 'institutional_auditor') THEN 'institutional_auditor'
      WHEN bool_or(ae.kind = 'observer') THEN 'observer'
      WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
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
        -- Wave 1 fix: sponsor outranks researcher (committee/workgroup) so a sponsor who also sits on a
        -- committee (e.g. the governance committee) shows as a sponsor, not a researcher.
        WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
        -- Wave 2 WS-1 (PM 2026-06-28 'governança vence'): chapter_board (chapter director) outranks
        -- researcher/observer so a chapter director who also sits on a committee or observes a
        -- tribe still shows as 'Ponto Focal do Capítulo' (chapter_liaison). Stays BELOW sponsor
        -- and operational leaders (manager/deputy/tribe_leader) — those who lead operationally keep that role.
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(
          (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
              AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
          OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
              AND ae.role IN ('leader','co_leader','owner','coordinator'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'institutional_auditor') THEN 'institutional_auditor'
        WHEN bool_or(ae.kind = 'observer') THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
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

  RETURN QUERY
  WITH drift AS (
    SELECT si.id AS interview_id
    FROM public.selection_interviews si
    WHERE si.status IN ('scheduled','rescheduled')
      AND EXISTS (
        SELECT 1 FROM public.selection_interviews si2
        WHERE si2.application_id = si.application_id
          AND si2.created_at > si.created_at
      )
  )
  SELECT 'AF_open_interview_is_newest_row'::text,
         'a selection_interviews row in an open status (scheduled/rescheduled) must be the most-recently-created interview row for its application. An open row older than another interview row of the same application indicates a reschedule/re-booking that did not close the prior open row (bypass of the AFTER INSERT trigger trg_supersede_prior_open_interviews, or pre-fix legacy drift). Root cause: sync_calendar_booking_to_interview / schedule_interview INSERTing a new scheduled row without superseding the prior open one (D4/D5, mig 20260805000210). KNOWN directional gap (defense-in-depth): a TERMINAL row inserted newer than an open row (only import_historical_interviews) is not superseded by the trigger and would surface here; the live path reaches completed via UPDATE in-place, so it is covered.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(interview_id ORDER BY interview_id) FROM (SELECT interview_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT e.id AS engagement_id
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.kind = 'volunteer' AND e.status = 'active'
      AND m.tribe_id IS DISTINCT FROM i.legacy_tribe_id
  )
  SELECT 'AG_tribe_engagement_has_tribe_id'::text,
         'every active volunteer engagement in a research_tribe initiative must have member.tribe_id = initiative.legacy_tribe_id (the correctness contract of the bridge trigger trg_sync_tribe_id_from_engagement; count_tribe_slots reads members.tribe_id, so a divergence corrupts the slot count). A violation means the bridge was bypassed (service_role direct INSERT into engagements) or a stale legacy tribe_id conflicts with the engagement. Tribe Selection Híbrida PR1, mig 20260805000216. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT e.person_id
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    WHERE e.kind = 'volunteer' AND e.status = 'active'
    GROUP BY e.person_id
    HAVING COUNT(*) > 1
  )
  SELECT 'AH_research_tribe_single_active_engagement'::text,
         'a person must have at most one active volunteer engagement across research_tribe initiatives. members.tribe_id is a single scalar and the bridge trigger trg_sync_tribe_id_from_engagement (admission + demotion branch) assumes a single active tribe engagement; two make tribe_id ambiguous and can leave a stale tribe_id after one is demoted. Supersedes the SPEC''s I_research_tribe_no_dual_pending (which false-positives on a legitimate tribe-move and whose committed-divergence sibling is already non-zero from frozen legacy tribe_selections staleness, below the bridge since AG=0). Tribe Selection Híbrida PR1, mig 20260805000216. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(person_id ORDER BY person_id) FROM (SELECT person_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id FROM public.selection_applications WHERE interview_auto_rescue_count > 1
  )
  SELECT 'AI_unbooked_rescue_cap_respected'::text,
         'selection_applications with interview_auto_rescue_count > 1 (above cap=1). _selection_unbooked_rescue_cron + selection_rescue_unbooked_invite enforce the cap via a RAISE guard at count>=1; a value >1 means a re-entry bug or a service_role direct UPDATE bypassed the guard. D3 auto-rescue, mig 20260805000219. Baseline 0.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(id ORDER BY id) FROM (SELECT id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected(tbl) AS (
    VALUES ('initiatives'),('events'),('project_boards'),('board_items'),
           ('meeting_artifacts'),('tribe_deliverables'),('recurring_meeting_rules'),('governance_documents')
  ),
  drift AS (
    SELECT e.tbl FROM expected e
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_policies p
      WHERE p.schemaname = 'public'
        AND p.tablename = e.tbl
        AND p.permissive = 'RESTRICTIVE'
        AND p.cmd IN ('SELECT','ALL')
        AND p.qual ILIKE '%rls_can_see_%'
    )
  )
  SELECT 'AJ_confidential_visibility_gate_present'::text,
         'each of the 8 initiative-dependent tables (initiatives/events/project_boards/board_items/meeting_artifacts/tribe_deliverables/recurring_meeting_rules/governance_documents) must carry a RESTRICTIVE SELECT policy whose USING calls a rls_can_see_* helper — the confidential-initiative visibility gate (#785 PR-2, mig 20260805000232). A missing policy means the gate was dropped and a confidential initiative''s rows leak to non-engaged members. Structural catalog check (pg_policies); baseline 0.'::text,
         'high'::text,
         (SELECT COUNT(*)::integer FROM drift),
         NULL::uuid[];


  -- #333 (Wave 4, #221/#218): voice-biometric consent enforcement — periodic detector that
  -- complements the write-time trigger trg_pmi_video_screening_voice_consent.
  RETURN QUERY
  WITH ack AS (
    -- Applications with a documented LGPD Art.18 retroactive-notification retention basis
    -- (the #332 acknowledged pre-block row). The application id is parsed from the pii_access_log
    -- audit record so NO candidate identifier is hardcoded in this migration; the exclusion IS the
    -- documented retention, and it self-heals to nothing if the row is eventually deleted.
    SELECT (substring(pal.reason FROM 'application_id=([0-9a-fA-F-]+)'))::uuid AS application_id
    FROM public.pii_access_log pal
    WHERE pal.context = 'lgpd_art_18_retroactive_notification'
      AND pal.reason ~ 'application_id='
  ),
  drift AS (
    SELECT vs.id
    FROM public.pmi_video_screenings vs
    WHERE vs.transcription IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_applications sa
        WHERE sa.id = vs.application_id
          AND sa.consent_voice_biometric_at IS NOT NULL
          AND sa.consent_voice_biometric_revoked_at IS NULL
      )
      AND NOT EXISTS (
        SELECT 1 FROM ack WHERE ack.application_id = vs.application_id
      )
  )
  SELECT 'AK_voice_biometric_consent_enforcement'::text,
         'every pmi_video_screenings row with transcription IS NOT NULL must have a matching selection_applications row where consent_voice_biometric_at IS NOT NULL AND consent_voice_biometric_revoked_at IS NULL (voice-biometric consent, LGPD Art.11), UNLESS its application has a documented Art.18 retroactive-notification retention basis logged in pii_access_log. The BEFORE INSERT/UPDATE trigger trg_pmi_video_screening_voice_consent is the write-time moat; this invariant is the periodic detector for any NEW drift (trigger disabled, consent revoked without deleting the row, raw SQL bypass). #333/#221/#218 Wave 4. The 1 acknowledged pre-block row (#332, tacit Art.18 retention; PM path (b) 2026-06-27) is EXCLUDED via its retention record, so baseline is 0; a new non-consented transcription with no retention basis is flagged. Named AK because the U_ code is already held by U_active_person_has_primary_chapter_affiliation.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(id ORDER BY id) FROM (SELECT id FROM drift LIMIT 10) s)
  FROM drift;

  -- #209 / ADR-0107: Drive offboarding revocation queue state-machine integrity.
  RETURN QUERY
  WITH drift AS (
    SELECT id AS audit_id FROM public.drive_offboarding_audit
    WHERE
      (status = 'revoked' AND (approved_by IS NULL OR revoked_at IS NULL))
      OR (status IN ('pending_revoke','approved') AND EXISTS (
            SELECT 1 FROM public.members m
            WHERE m.id = drive_offboarding_audit.member_id
              AND (m.member_status = 'active' OR m.offboarded_at IS NULL)))
  )
  SELECT 'AL_drive_revocation_terminal_consistency'::text,
         'drive_offboarding_audit (#209/ADR-0107): a revoked row must carry approved_by AND revoked_at (proof it went through the approve_drive_revocation + mark_drive_revocation_done RPC path), and no OPEN row (pending_revoke/approved) may reference a member who is active / not offboarded — a reversed offboarding must clear the revocation queue. A violation means a service_role direct write bypassed the RPC path, or an offboarding was reversed without clearing pending grants. Baseline 0.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(audit_id ORDER BY audit_id) FROM (SELECT audit_id FROM drift LIMIT 10) s)
  FROM drift;

  -- #301 / ADR-0108: curation temporary Drive grant state-machine integrity.
  RETURN QUERY
  WITH drift AS (
    SELECT id AS grant_id FROM public.drive_curation_grants
    WHERE (status = 'granted' AND (permission_id IS NULL OR granted_at IS NULL))
       OR (status = 'granted' AND revoked_at IS NOT NULL)
       OR (status = 'revoked' AND revoked_at IS NULL)
  )
  SELECT 'AM_drive_curation_grant_terminal_consistency'::text,
         'drive_curation_grants (#301/ADR-0108): a granted row must carry permission_id AND granted_at (proof the Drive POST succeeded) and must NOT carry revoked_at; a revoked row must carry revoked_at. The grant/revoke EF mark RPCs (mark_curation_grant_done/mark_curation_grant_revoked) are the only legitimate writers of these terminal states; a violation means a service_role direct write bypassed them. Named AM (AL is the #209 sibling). Baseline 0.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(grant_id ORDER BY grant_id) FROM (SELECT grant_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

-- ── Part 5b: the 8 verified PII-free / write-free aggregate RPCs honor view_aggregate_analytics.
--    Each gate gains `OR (public.)can_by_member(<caller>, 'view_aggregate_analytics')`. ──
CREATE OR REPLACE FUNCTION public.get_cycle_report(p_cycle integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_result := jsonb_build_object(
    'cycle', p_cycle,
    'generated_at', now(),
    'members', (SELECT jsonb_build_object(
      'total', count(*),
      'active', (SELECT count(*) FROM public.v_active_members),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'by_role', (SELECT coalesce(jsonb_object_agg(operational_role, cnt), '{}') FROM (SELECT operational_role, count(*) as cnt FROM public.v_active_members GROUP BY operational_role) r)
    ) FROM public.members),
    'tribes', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'name', t.name,
      'member_count', (SELECT count(*) FROM public.members WHERE tribe_id = t.id AND is_active),
      'board_progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE bi.status = 'done') / count(*)) END FROM public.project_boards pb JOIN public.initiatives i ON i.id = pb.initiative_id JOIN public.board_items bi ON bi.board_id = pb.id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived')
    ) ORDER BY t.id), '[]') FROM public.tribes t WHERE t.is_active),
    'events', (SELECT jsonb_build_object(
      'total', count(*),
      'total_impact_hours', (SELECT * FROM public.get_homepage_stats())->'impact_hours'
    ) FROM public.events WHERE date >= '2026-01-01'),
    'boards', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', pb.id, 'title', pb.board_name,
      'total_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status != 'archived'),
      'done_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status = 'done'),
      'progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE status = 'done') / count(*)) END FROM public.board_items WHERE board_id = pb.id AND status != 'archived')
    )), '[]') FROM public.project_boards pb WHERE pb.is_active),
    'kpis', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'name', k.kpi_label_pt, 'name_en', k.kpi_label_en,
      'target', k.target_value, 'current', k.current_value,
      'pct', CASE WHEN k.target_value > 0 THEN round(100.0 * k.current_value / k.target_value) ELSE 0 END
    )), '[]') FROM public.annual_kpi_targets k WHERE k.year = 2026),
    'platform', jsonb_build_object(
      'releases_count', (SELECT count(*) FROM public.releases),
      'governance_entries', 125,
      'zero_cost', true,
      'stack', 'Astro 5 + React 19 + Tailwind 4 + Supabase + Cloudflare Pages'
    )
  );
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_annual_kpis(p_cycle integer DEFAULT 4, p_year integer DEFAULT 2026)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_auto_values jsonb;
  v_kpis jsonb;
  v_cycle_start date := '2025-12-01';
  v_cycle_end date := '2026-06-30';
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_auto_values := jsonb_build_object(
    'pilots_active_or_completed', (SELECT count(*) FROM public.pilots WHERE status IN ('active', 'completed')),
    'publications_submitted_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'publicacao' AND bi.status IN ('done', 'review')),
    'articles_academic_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'artigo_academico' AND bi.status IN ('done', 'review')),
    'frameworks_delivered_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name IN ('framework', 'ferramenta') AND bi.status IN ('done', 'review')),
    'webinars_realized_count', public.get_webinars_count(v_cycle_start, LEAST(v_cycle_end, CURRENT_DATE), 'realized'),
    'attendance_general_avg_pct', public.calc_attendance_pct(),
    -- #692: members_retained now reads the canonical cohort-survival headline (was a degenerate
    -- is_active∧current/is_active ratio that read ~98.7).
    'retention_pct', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
    'events_total_count', (SELECT count(*) FROM public.events e WHERE e.date BETWEEN v_cycle_start AND LEAST(v_cycle_end, CURRENT_DATE) AND NOT EXISTS (SELECT 1 FROM public.event_tag_assignments eta JOIN public.tags t ON t.id = eta.tag_id WHERE eta.event_id = e.id AND t.name = 'interview')),
    'trail_completion_pct', public.calc_trail_completion_pct(),
    'cpmai_certified_count', public.get_cpmai_certified_goal_count(),
    'active_members_count', (SELECT count(*) FROM public.members WHERE is_active = true AND current_cycle_active = true),
    'infra_cost_current', (SELECT COALESCE(SUM(ce.amount_brl), 0) FROM public.cost_entries ce JOIN public.cost_categories cc ON cc.id = ce.category_id WHERE cc.name = 'infrastructure' AND ce.date >= date_trunc('month', now())::date AND ce.date < (date_trunc('month', now()) + interval '1 month')::date)
  );

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', k.id, 'kpi_key', k.kpi_key, 'label_pt', k.kpi_label_pt, 'label_en', k.kpi_label_en,
      'category', k.category, 'target', k.target_value, 'baseline', k.baseline_value,
      'current', CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END,
      'unit', k.target_unit, 'icon', k.icon,
      'progress_pct', CASE
        WHEN k.target_value > 0 THEN ROUND(COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) / k.target_value * 100, 1)
        WHEN k.target_value = 0 THEN 100
        ELSE 0
      END,
      'health', CASE
        WHEN k.target_value = 0 AND COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) = 0 THEN 'achieved'
        WHEN k.target_value = 0 THEN 'at_risk'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value THEN 'achieved'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value * 0.7 THEN 'on_track'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value * 0.4 THEN 'at_risk'
        ELSE 'behind'
      END,
      'notes', k.notes,
      'auto_query', k.auto_query
    ) ORDER BY k.display_order
  ) INTO v_kpis
  FROM public.annual_kpi_targets k
  WHERE k.cycle = p_cycle AND k.year = p_year;

  v_result := jsonb_build_object(
    'cycle', p_cycle, 'year', p_year, 'generated_at', now(),
    'kpis', COALESCE(v_kpis, '[]'::jsonb),
    'summary', jsonb_build_object(
      'total', jsonb_array_length(COALESCE(v_kpis, '[]'::jsonb)),
      'achieved', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'achieved'),
      'on_track', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'on_track'),
      'at_risk', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'at_risk'),
      'behind', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'behind')
    )
  );
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_diversity_dashboard(p_cycle_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_by_gender jsonb;
  v_by_chapter jsonb;
  v_by_sector jsonb;
  v_by_seniority jsonb;
  v_by_region jsonb;
  v_applicants_total int;
  v_approved_total int;
  v_snapshots jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  v_cycle_id := COALESCE(p_cycle_id, (SELECT id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1));
  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'no_cycle_found');
  END IF;

  SELECT COUNT(*) INTO v_applicants_total FROM public.selection_applications WHERE cycle_id = v_cycle_id;
  SELECT COUNT(*) INTO v_approved_total FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted');

  SELECT jsonb_agg(jsonb_build_object('gender', gender_label, 'applicants', applicants, 'approved', approved))
  INTO v_by_gender
  FROM (
    SELECT CASE sa.gender
      WHEN 'M' THEN 'Masculino'
      WHEN 'F' THEN 'Feminino'
      ELSE COALESCE(sa.gender, 'Não informado')
    END as gender_label,
    COUNT(*) AS applicants,
    COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY gender_label ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('chapter', COALESCE(chapter, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_chapter
  FROM (
    SELECT sa.chapter, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.chapter ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('sector', COALESCE(sector, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_sector
  FROM (
    SELECT sa.sector, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.sector ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('band', band, 'applicants', applicants, 'approved', approved))
  INTO v_by_seniority
  FROM (
    SELECT CASE
      WHEN sa.seniority_years IS NULL THEN 'Não informado'
      WHEN sa.seniority_years < 3 THEN '0-2 anos'
      WHEN sa.seniority_years < 6 THEN '3-5 anos'
      WHEN sa.seniority_years < 11 THEN '6-10 anos'
      WHEN sa.seniority_years < 16 THEN '11-15 anos'
      ELSE '16+ anos'
    END AS band,
    COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY band ORDER BY band
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('region', COALESCE(region, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_region
  FROM (
    SELECT CASE
      WHEN sa.country IS NULL OR sa.country = '' THEN COALESCE(sa.state, 'Não informado')
      WHEN sa.country IN ('Brazil', 'BR', 'Brasil') THEN COALESCE(sa.state, 'Brasil')
      WHEN sa.state IS NOT NULL AND sa.state != '' THEN sa.state || ' (' || sa.country || ')'
      ELSE sa.country
    END AS region,
    COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY region ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('snapshot_type', sds.snapshot_type, 'metrics', sds.metrics, 'created_at', sds.created_at) ORDER BY sds.created_at DESC)
  INTO v_snapshots
  FROM public.selection_diversity_snapshots sds WHERE sds.cycle_id = v_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'applicants_total', v_applicants_total,
    'approved_total', v_approved_total,
    'by_gender', COALESCE(v_by_gender, '[]'::jsonb),
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'by_sector', COALESCE(v_by_sector, '[]'::jsonb),
    'by_seniority', COALESCE(v_by_seniority, '[]'::jsonb),
    'by_region', COALESCE(v_by_region, '[]'::jsonb),
    'snapshots', COALESCE(v_snapshots, '[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_selection_pipeline_metrics(p_cycle_id uuid DEFAULT NULL::uuid, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_funnel jsonb;
  v_by_chapter jsonb;
  v_conversion_rate numeric;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- V4: view_internal_analytics covers admin/GP + sponsor + chapter_liaison
  IF NOT (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  IF p_cycle_id IS NOT NULL THEN
    v_cycle_id := p_cycle_id;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles
    ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'no_cycle_found');
  END IF;

  SELECT jsonb_build_object(
    'total_applications', COUNT(*),
    'screening', COUNT(*) FILTER (WHERE status = 'screening'),
    'objective_eval', COUNT(*) FILTER (WHERE status = 'objective_eval'),
    'passed_cutoff', COUNT(*) FILTER (WHERE status NOT IN ('submitted', 'screening', 'objective_eval', 'objective_cutoff', 'rejected', 'withdrawn', 'cancelled')),
    'interview_pending', COUNT(*) FILTER (WHERE status = 'interview_pending'),
    'interview_scheduled', COUNT(*) FILTER (WHERE status = 'interview_scheduled'),
    'interview_done', COUNT(*) FILTER (WHERE status = 'interview_done'),
    'interview_noshow', COUNT(*) FILTER (WHERE status = 'interview_noshow'),
    'final_eval', COUNT(*) FILTER (WHERE status = 'final_eval'),
    'approved', COUNT(*) FILTER (WHERE status = 'approved'),
    'rejected', COUNT(*) FILTER (WHERE status = 'rejected'),
    'waitlist', COUNT(*) FILTER (WHERE status = 'waitlist'),
    'converted', COUNT(*) FILTER (WHERE status = 'converted'),
    'withdrawn', COUNT(*) FILTER (WHERE status = 'withdrawn')
  ) INTO v_funnel
  FROM public.selection_applications
  WHERE cycle_id = v_cycle_id
    AND (p_chapter IS NULL OR chapter = p_chapter);

  SELECT jsonb_agg(
    jsonb_build_object(
      'chapter', chapter,
      'total', total,
      'approved', approved,
      'rejected', rejected,
      'waitlist', waitlist,
      'converted', converted,
      'avg_score', avg_score
    )
  ) INTO v_by_chapter
  FROM (
    SELECT
      sa.chapter,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE sa.status = 'approved') AS approved,
      COUNT(*) FILTER (WHERE sa.status = 'rejected') AS rejected,
      COUNT(*) FILTER (WHERE sa.status = 'waitlist') AS waitlist,
      COUNT(*) FILTER (WHERE sa.status = 'converted') AS converted,
      ROUND(AVG(sa.final_score), 2) AS avg_score
    FROM public.selection_applications sa
    WHERE sa.cycle_id = v_cycle_id
      AND (p_chapter IS NULL OR sa.chapter = p_chapter)
    GROUP BY sa.chapter
    ORDER BY sa.chapter
  ) sub;

  v_conversion_rate := CASE
    WHEN (v_funnel->>'total_applications')::int > 0
    THEN ROUND(((v_funnel->>'approved')::int + (v_funnel->>'converted')::int)::numeric /
         (v_funnel->>'total_applications')::int * 100, 1)
    ELSE 0
  END;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'chapter_filter', p_chapter,
    'funnel', v_funnel,
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'conversion_rate', v_conversion_rate
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_in_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (can_by_member(v_member_id, 'view_internal_analytics') OR can_by_member(v_member_id, 'manage_partner') OR can_by_member(v_member_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Access denied — requires view_internal_analytics or manage_partner';
  END IF;

  WITH stages AS (
    SELECT mou_stage, count(*) AS n
    FROM partner_entities
    WHERE entity_type = 'pmi_chapter'
    GROUP BY mou_stage
  ),
  chapters AS (
    SELECT id, name, mou_stage, next_action, follow_up_date, last_interaction_at
    FROM partner_entities
    WHERE entity_type = 'pmi_chapter'
    ORDER BY
      CASE mou_stage
        WHEN 'active' THEN 1
        WHEN 'mou_signed' THEN 2
        WHEN 'mou_sent' THEN 3
        WHEN 'mou_drafted' THEN 4
        WHEN 'agreed' THEN 5
        WHEN 'prospecting' THEN 6
        ELSE 9
      END, name
  )
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM partner_entities WHERE entity_type='pmi_chapter'),
    'by_stage', (SELECT jsonb_object_agg(coalesce(mou_stage,'unset'), n) FROM stages),
    'chapters', (SELECT jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'mou_stage', mou_stage,
      'next_action', next_action, 'follow_up_date', follow_up_date,
      'last_interaction_at', last_interaction_at
    )) FROM chapters),
    'computed_at', now()
  ) INTO v_result;

  RETURN v_result;
END $function$;

CREATE OR REPLACE FUNCTION public.get_portfolio_items(p_tribe_id integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_cycle_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, title text, status text, tribe_id integer, initiative_id uuid, baseline_date date, baseline_locked_at timestamp with time zone, forecast_date date, due_date date, is_portfolio_item boolean, portfolio_kpi_refs text[], cycle_code text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (can_by_member(v_member_id, 'view_internal_analytics') OR can_by_member(v_member_id, 'view_chapter_dashboards') OR can_by_member(v_member_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Access denied — requires view_internal_analytics or view_chapter_dashboards';
  END IF;

  RETURN QUERY
  SELECT bi.id, bi.title, bi.status,
         i.legacy_tribe_id AS tribe_id,
         pb.initiative_id,
         bi.baseline_date, bi.baseline_locked_at,
         bi.forecast_date, bi.due_date,
         bi.is_portfolio_item, bi.portfolio_kpi_refs,
         pb.cycle_code,
         bi.updated_at
  FROM board_items bi
  JOIN project_boards pb ON pb.id = bi.board_id
  LEFT JOIN initiatives i ON i.id = pb.initiative_id
  WHERE bi.is_portfolio_item = true
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    AND (p_status IS NULL OR bi.status = p_status)
    AND (p_cycle_code IS NULL OR pb.cycle_code = p_cycle_code)
    AND public.rls_can_see_initiative(pb.initiative_id)
  ORDER BY bi.due_date NULLS LAST, bi.updated_at DESC;
END $function$;

CREATE OR REPLACE FUNCTION public.get_comms_to_adoption_funnel(p_period_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id   uuid;
  v_period      interval := (greatest(p_period_days, 1) || ' days')::interval;
  v_since_ts    timestamptz := now() - v_period;
  v_since_date  date        := current_date - greatest(p_period_days, 1);
  v_social      jsonb;
  v_engagement  jsonb;
  v_apps        jsonb;
  v_approved    jsonb;
  v_top_content jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT (public.can_by_member(v_caller_id, 'view_internal_analytics')
       OR public.can_by_member(v_caller_id, 'manage_platform') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ── Stage 1: Social reach (latest snapshot per channel within period) ──
  WITH latest_per_channel AS (
    SELECT DISTINCT ON (channel)
      channel, audience, reach, engagement_rate, metric_date
    FROM public.comms_metrics_daily
    WHERE metric_date >= v_since_date
    ORDER BY channel, metric_date DESC
  ),
  period_reach AS (
    SELECT channel, sum(reach) AS reach_sum
    FROM public.comms_metrics_daily
    WHERE metric_date >= v_since_date
    GROUP BY channel
  )
  SELECT jsonb_build_object(
    'total_audience_latest', coalesce((SELECT sum(audience) FROM latest_per_channel), 0),
    'total_reach_period',    coalesce((SELECT sum(reach_sum) FROM period_reach), 0),
    'by_channel', coalesce(jsonb_agg(jsonb_build_object(
      'channel',           l.channel,
      'audience_latest',   l.audience,
      'reach_period',      coalesce(p.reach_sum, 0),
      'engagement_rate',   l.engagement_rate
    ) ORDER BY l.audience DESC NULLS LAST), '[]'::jsonb)
  ) INTO v_social
  FROM latest_per_channel l
  LEFT JOIN period_reach p ON p.channel = l.channel;

  -- ── Stage 2: Site engagement on content pages (logged-in proxy) ──
  WITH grouped AS (
    SELECT
      CASE
        WHEN first_page LIKE '/blog/%' THEN 'blog'
        WHEN first_page LIKE '/cpmai%' THEN 'cpmai'
        WHEN first_page LIKE '/trail%' THEN 'trail'
        WHEN first_page LIKE '/presentations%' THEN 'presentations'
        WHEN first_page LIKE '/gamification%' THEN 'gamification'
        WHEN first_page = '/' OR first_page LIKE '/en/%' OR first_page LIKE '/es/%' THEN 'home'
        ELSE 'other'
      END AS landing_group,
      member_id
    FROM public.member_activity_sessions
    WHERE session_date >= v_since_date
  ),
  agg AS (
    SELECT landing_group, count(*) AS sessions, count(DISTINCT member_id) AS members
    FROM grouped
    GROUP BY landing_group
  )
  SELECT jsonb_build_object(
    'content_sessions',      coalesce((SELECT sum(sessions) FROM agg WHERE landing_group IN ('blog','cpmai','trail','presentations','gamification')), 0),
    'content_unique_members', coalesce((SELECT sum(members)  FROM agg WHERE landing_group IN ('blog','cpmai','trail','presentations','gamification')), 0),
    'home_sessions',         coalesce((SELECT sessions FROM agg WHERE landing_group='home'), 0),
    'home_unique_members',   coalesce((SELECT members  FROM agg WHERE landing_group='home'), 0),
    'by_landing_group', coalesce(jsonb_agg(jsonb_build_object(
      'group',           a.landing_group,
      'sessions',        a.sessions,
      'unique_members',  a.members
    ) ORDER BY a.sessions DESC), '[]'::jsonb)
  ) INTO v_engagement
  FROM agg a;

  -- ── Stage 3: Applications submitted in period ──
  SELECT jsonb_build_object(
    'total',     count(*),
    'via_vep',   count(*) FILTER (WHERE referral_source = 'vep'),
    'other',     count(*) FILTER (WHERE referral_source IS DISTINCT FROM 'vep'),
    'by_role',   coalesce(jsonb_object_agg(role_applied, role_count), '{}'::jsonb)
  ) INTO v_apps
  FROM (
    SELECT
      role_applied,
      count(*) AS role_count,
      referral_source
    FROM public.selection_applications
    WHERE created_at >= v_since_ts
    GROUP BY role_applied, referral_source
  ) a
  GROUP BY ();

  IF v_apps IS NULL THEN
    v_apps := jsonb_build_object('total', 0, 'via_vep', 0, 'other', 0, 'by_role', '{}'::jsonb);
  END IF;

  -- ── Stage 4: Approved + converted in period ──
  SELECT jsonb_build_object(
    'total',         count(*),
    'approved',      count(*) FILTER (WHERE status = 'approved'),
    'converted',     count(*) FILTER (WHERE status = 'converted'),
    'approval_rate', CASE
      WHEN (SELECT count(*) FROM public.selection_applications WHERE created_at >= v_since_ts) > 0
      THEN round(count(*)::numeric * 100.0 / (SELECT count(*) FROM public.selection_applications WHERE created_at >= v_since_ts), 1)
      ELSE NULL
    END
  ) INTO v_approved
  FROM public.selection_applications
  WHERE status IN ('approved', 'converted')
    AND updated_at >= v_since_ts;

  -- ── Top content (engagement signal, NOT attribution) ──
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'channel',      m.channel,
    'media_type',   m.media_type,
    'permalink',    m.permalink,
    'caption_excerpt', left(coalesce(m.caption, ''), 80),
    'views',        m.views,
    'likes',        m.likes,
    'comments',     m.comments,
    'published_at', m.published_at
  ) ORDER BY (coalesce(m.likes,0) + coalesce(m.comments,0) + coalesce(m.views,0)) DESC), '[]'::jsonb)
  INTO v_top_content
  FROM (
    SELECT *
    FROM public.comms_media_items
    WHERE published_at >= v_since_ts
    ORDER BY (coalesce(likes,0) + coalesce(comments,0) + coalesce(views,0)) DESC
    LIMIT 6
  ) m;

  RETURN jsonb_build_object(
    'period_days',  p_period_days,
    'period_since', v_since_ts,
    'generated_at', now(),
    'caveat',       'Correlation, not attribution. Pre-login pageviews + UTM tracking infrastructure pending (Phase B backlog). PMI VEP external form does not pass UTM. Funnel reflects what is measurable today: post-login engagement + total application counts in period.',
    'stages', jsonb_build_object(
      'social_reach',    v_social,
      'site_engagement', v_engagement,
      'applications',    v_apps,
      'approved',        v_approved
    ),
    'top_content', v_top_content
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.exec_role_transitions(p_cycle_code text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
begin
  if not (public.can_read_internal_analytics() or public.can_by_member((select id from public.members where auth_id = auth.uid()), 'view_aggregate_analytics')) then
    raise exception 'Internal analytics access required';
  end if;

  with history_rows as (
    select
      mch.member_id,
      mch.cycle_code,
      coalesce(mch.cycle_label, c.cycle_label, mch.cycle_code) as cycle_label,
      coalesce(c.sort_order, 9999) as sort_order,
      coalesce(mch.chapter, m.chapter) as chapter,
      coalesce(mch.tribe_id, m.tribe_id) as tribe_id,
      public.analytics_role_bucket(mch.operational_role, mch.designations) as role_bucket,
      public.analytics_is_leadership_role(mch.operational_role, mch.designations) as is_leadership
    from public.member_cycle_history mch
    left join public.cycles c on c.cycle_code = mch.cycle_code
    left join public.members m on m.id = mch.member_id
    where mch.member_id is not null
  ),
  ordered_transitions as (
    select
      hr.*,
      lag(hr.cycle_code) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_cycle_code,
      lag(hr.cycle_label) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_cycle_label,
      lag(hr.role_bucket) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_role_bucket,
      lag(hr.is_leadership) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_is_leadership
    from history_rows hr
  ),
  filtered_transitions as (
    select *
    from ordered_transitions
    where from_cycle_code is not null
      and (p_cycle_code is null or cycle_code = p_cycle_code)
      and (p_tribe_id is null or tribe_id = p_tribe_id)
      and (p_chapter is null or chapter = p_chapter)
  ),
  conversion_cycles as (
    select
      cycle_code,
      max(cycle_label) as cycle_label,
      count(distinct member_id)::integer as promoted_members
    from filtered_transitions
    where coalesce(from_is_leadership, false) is false
      and is_leadership is true
    group by cycle_code
  )
  select jsonb_build_object(
    'cycle_code', p_cycle_code,
    'summary', jsonb_build_object(
      'tracked_transitions', coalesce((select count(*) from filtered_transitions), 0),
      'promoted_members', coalesce((
        select sum(promoted_members)::integer from conversion_cycles
      ), 0),
      'leadership_roles', jsonb_build_array(
        'tribe_leader',
        'ambassador',
        'manager',
        'deputy_manager',
        'chapter_liaison',
        'sponsor'
      )
    ),
    'conversions_by_cycle', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.cycle_code)
      from conversion_cycles c
    ), '[]'::jsonb),
    'transition_matrix', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.transitions desc, m.from_role_bucket, m.to_role_bucket)
      from (
        select
          from_role_bucket,
          role_bucket as to_role_bucket,
          count(*)::integer as transitions
        from filtered_transitions
        group by from_role_bucket, role_bucket
      ) m
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'summary', jsonb_build_object(
      'tracked_transitions', 0,
      'promoted_members', 0,
      'leadership_roles', jsonb_build_array(
        'tribe_leader',
        'ambassador',
        'manager',
        'deputy_manager',
        'chapter_liaison',
        'sponsor'
      )
    ),
    'conversions_by_cycle', '[]'::jsonb,
    'transition_matrix', '[]'::jsonb
  ));
end;
$function$;

-- ── Part 6: fail-closed verification (same checks the apply ran in-tx) ──
DO $verify$
DECLARE v_a3 int; v_bad text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.engagement_kinds WHERE slug='institutional_auditor') THEN
    RAISE EXCEPTION 'FU-3 verify: engagement_kinds row missing'; END IF;
  IF (SELECT count(*) FROM public.engagement_kind_permissions WHERE kind='institutional_auditor') <> 1 THEN
    RAISE EXCEPTION 'FU-3 verify: auditor must hold EXACTLY one action'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='engagements_institutional_auditor_end_date_check') THEN
    RAISE EXCEPTION 'FU-3 verify: end_date CHECK missing'; END IF;
  IF (SELECT count(*) FROM public.members WHERE operational_role='institutional_auditor') <> 0 THEN
    RAISE EXCEPTION 'FU-3 verify: dormancy violated'; END IF;
  SELECT string_agg(p.proname, ', ') INTO v_bad
  FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
    AND p.proname IN ('get_cycle_report','get_annual_kpis','get_diversity_dashboard','get_selection_pipeline_metrics','get_in_dashboard','get_portfolio_items','get_comms_to_adoption_funnel','exec_role_transitions')
    AND position('view_aggregate_analytics' in p.prosrc) = 0;
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'FU-3 verify: RPCs missing gate: %', v_bad; END IF;
  SELECT violation_count INTO v_a3 FROM public.check_schema_invariants() WHERE invariant_name LIKE 'A3%';
  IF v_a3 <> 0 THEN RAISE EXCEPTION 'FU-3 verify: A3 violations = % (expected 0)', v_a3; END IF;
END $verify$;
