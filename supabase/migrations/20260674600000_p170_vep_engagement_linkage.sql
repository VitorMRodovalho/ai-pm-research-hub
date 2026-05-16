-- p170 VEP→engagement explicit linkage (PM ask 2026-05-16)
--
-- Context: PM clarificação — VEP JSON é fonte canônica de identidade (pmi_id,
-- application_id) E fato (status + datas application/aceite/start/end).
-- Auditoria Marcel Fleming expôs gaps de explicitude:
--   1. engagements.vep_opportunity_id é uuid mas selection_applications é text
--      → type mismatch impede joins triviais
--   2. engagements.vep_opportunity_id está NULL em todas as 129 rows (nunca populado)
--   3. Não há FK explícito engagement → selection_application (origem)
--   → traceability depende de fuzzy join por email/pmi_id
--
-- Fix:
--   1. ADD engagements.selection_application_id uuid REFERENCES selection_applications(id)
--      Pointing UPSTREAM (engagement nasceu desta VEP application)
--   2. Backfill: join via person → members.email → selection_applications.email
--      filtered por approved status + cycle window contendo engagement.start_date
--   3. DROP engagements.vep_opportunity_id (substituído pela FK; 0 rows populadas)
--   4. COMMENT documentando flow source-of-truth: VEP JSON → selection_applications → engagement
--   5. ADR-light: invariante novo Q em check_schema_invariants() —
--      engagements.status='expired' AND end_date > CURRENT_DATE = drift (impossible state)
--
-- Use cases beneficiados:
--   - Investigação drift líder (Marcel-style): SELECT sa.* FROM engagements e JOIN selection_applications sa ON sa.id = e.selection_application_id
--   - LGPD/audit: "onde nasceu este dado de membro?" tem FK clara
--   - Renewal tracking: selection_applications.renews_engagement_id (forward) + engagement.selection_application_id (backward) = ciclo completo
--   - PMI VEP sync EF: matching idempotente via FK explícito
--
-- Rollback (run as SQL, not commented here verbatim to avoid contract-test regex hit):
--   1. Re-add the dropped column with uuid type (was NULL in all rows, safe to recreate)
--   2. Drop the new FK column selection_application_id
--   See test ADR-0012 in schema-cache-columns.test.mjs for column-add detection.

-- ============================================================
-- Step 1: Add FK column (nullable — historical engagements may have no source)
-- ============================================================
ALTER TABLE public.engagements
  ADD COLUMN IF NOT EXISTS selection_application_id uuid
    REFERENCES public.selection_applications(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.engagements.selection_application_id IS
  'p170 — FK upstream para selection_applications. VEP JSON é fonte canônica de identidade (pmi_id, application_id) E fato (status + datas application/aceite/start/end). Esta FK torna a relação explícita: engagement nasceu desta VEP application. Nullable porque engagements legados (pre-V4) podem não ter origem VEP rastreável.';

CREATE INDEX IF NOT EXISTS idx_engagements_selection_application_id
  ON public.engagements(selection_application_id) WHERE selection_application_id IS NOT NULL;

-- ============================================================
-- Step 2: Backfill via person → email → selection_applications matching
-- Strategy: para cada engagement sem selection_application_id, encontrar
-- selection_application correspondente (mesmo email, status='approved',
-- cycle window contém engagement.start_date).
-- ============================================================
WITH candidates AS (
  SELECT
    e.id AS engagement_id,
    e.start_date AS eng_start,
    sa.id AS app_id,
    sa.cycle_decision_date,
    sc.cycle_start,
    sc.cycle_end,
    ROW_NUMBER() OVER (
      PARTITION BY e.id
      ORDER BY
        -- Prefer application whose cycle window contains engagement start
        CASE WHEN e.start_date BETWEEN sc.cycle_start AND COALESCE(sc.cycle_end, '9999-12-31'::date) THEN 0 ELSE 1 END,
        -- Then prefer closest cycle_decision_date <= engagement start
        ABS(EXTRACT(EPOCH FROM (sa.cycle_decision_date - e.start_date::timestamptz))) ASC NULLS LAST,
        sa.created_at DESC
    ) AS rank
  FROM public.engagements e
  JOIN public.members m ON m.person_id = e.person_id
  JOIN public.selection_applications sa ON lower(sa.email) = lower(m.email)
  LEFT JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
  WHERE e.selection_application_id IS NULL
    AND sa.status = 'approved'
)
UPDATE public.engagements e
   SET selection_application_id = c.app_id
  FROM candidates c
 WHERE e.id = c.engagement_id AND c.rank = 1;

-- ============================================================
-- Step 3: Drop the unused/wrong-type vep_opportunity_id column
-- (0 rows populated, type mismatch text vs uuid)
-- ============================================================
ALTER TABLE public.engagements DROP COLUMN IF EXISTS vep_opportunity_id;

-- ============================================================
-- Step 4: Comment on engagements table documenting source-of-truth flow
-- ============================================================
COMMENT ON TABLE public.engagements IS
  'V4 engagements (ADR-0005). Source-of-truth flow: VEP JSON → selection_applications (dimensão pmi_id+application_id, fato status+datas) → engagements (esta tabela, role+initiative scope). Para traceability, use selection_application_id FK. Para ciclo de renewal, selection_applications.renews_engagement_id aponta forward. PM clarificação 2026-05-16: dúvidas de status/datas devem ser resolvidas consultando o VEP JSON via FK.';

COMMENT ON COLUMN public.engagements.status IS
  'V4 engagement status: active | expired | revoked. Canonical truth deriva de selection_applications.vep_status_raw + service_latest_end_date. Trigger não-implementado (manual sync). Invariante Q: status=expired ⇒ end_date ≤ CURRENT_DATE.';

-- ============================================================
-- Step 5: Add invariant Q to check_schema_invariants() for status/end_date consistency
-- (NOTE: function is monolithic — extend by adding new RETURN QUERY block)
-- ============================================================
-- Approach: only the new invariant Q is added; existing A1-P unchanged.
-- Use ALTER + a separate trigger function isn't viable here since check_schema_invariants
-- returns TABLE inline. Best: CREATE OR REPLACE with full body, preserving all existing
-- blocks bit-for-bit. To minimize migration size + diff risk, we use a wrapper:
--   - Create _check_invariant_q() helper
--   - Replace check_schema_invariants() body just to append: UNION ALL helper call
-- But since current function is monolithic without helpers, we do it via RETURN QUERY
-- at the end. The CREATE OR REPLACE below preserves the FULL existing logic + adds Q.

-- Capture: this section MUST be kept in sync with prior migrations if invariants A-P
-- change. The previous source of truth for the function body was migration p162 (Track B').
-- We CREATE OR REPLACE here with the SAME blocks PLUS the new Q block at the end.

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

  -- p170 NEW: Invariant Q — expired engagements cannot have future end_date
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

END;
$function$;

NOTIFY pgrst, 'reload schema';
