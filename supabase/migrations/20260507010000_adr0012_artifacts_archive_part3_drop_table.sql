-- ADR-0012 artifacts archival — Part 3 final: DROP TABLE + remove I_artifacts_frozen invariant.
-- Part 1 (20260504080000): migrate 29 rows → publication_submissions + block trigger
-- Part 2 (20260504080001): remap 8 readers → publication_submissions
-- Part 3 (ESTA): DROP TABLE artifacts CASCADE + remove I_artifacts_frozen RETURN QUERY block
--
-- Janela 48h+ shadow (ADR-0012 Princípio 3): Part 1+2 em 20/Abr 16:10 UTC-4.
-- Janela abriu 22/Abr 16:10 UTC-4. Executando 23/Abr (48h+ cumpridos).
--
-- Pré-checks validados:
-- - 29 rows em artifacts mantidos estáveis (sem drift desde archival)
-- - invariant I_artifacts_frozen violations=0 (hard block trigger funcionando)
-- - tribe_deliverables.artifact_id_fkey: 0/71 rows com artifact_id populado
--   → DROP CASCADE dropa só o FK constraint, zero data loss
-- - 8 readers remapped para publication_submissions (Part 2) — nenhum uso ativo
--
-- Rollback: se algo quebrar, restaurar do backup pre-migration. Archive em
-- publication_submissions preserva 29 rows com reviewer_feedback marker
-- "[Legacy artifact migrated from V3...]" e UUIDs preservados pra cross-ref.

BEGIN;

-- =============================================================================
-- 1. DROP TABLE artifacts CASCADE
-- =============================================================================
-- CASCADE dropa:
-- - tribe_deliverables_artifact_id_fkey (FK constraint, não a coluna)
-- - Triggers (BEFORE INSERT block, updated_at)
-- - Policies RLS
-- - Indexes
-- Comments e column tribe_deliverables.artifact_id permanecem (column virou UUID "solto")

DROP TABLE public.artifacts CASCADE;

-- =============================================================================
-- 2. CREATE OR REPLACE check_schema_invariants SEM I_artifacts_frozen
-- =============================================================================
-- Preserva 10 invariants restantes (A1, A2, A3, B, C, D, E, F, J, K).

CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, violation_count bigint, description text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY SELECT 'A1_alumni_role_consistency'::text, COUNT(*)::bigint, 'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text
    FROM public.members WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni';

  RETURN QUERY SELECT 'A2_observer_role_consistency'::text, COUNT(*)::bigint, 'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text
    FROM public.members WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none');

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
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'observer')      THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni')        THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor')       THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate')     THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status = 'active'
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
    GROUP BY m.id
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         (SELECT COUNT(*)::bigint FROM computed c JOIN public.members m ON m.id = c.member_id WHERE m.operational_role IS DISTINCT FROM c.expected_role),
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text;

  RETURN QUERY SELECT 'B_is_active_status_mismatch'::text, COUNT(*)::bigint, 'members.is_active must match member_status mapping (active=true, terminal=false)'::text
    FROM public.members
    WHERE ((member_status = 'active' AND is_active = false)
        OR (member_status IN ('observer','alumni','inactive') AND is_active = true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)';

  RETURN QUERY SELECT 'C_designations_in_terminal_status'::text, COUNT(*)::bigint, 'members.designations must be empty when member_status is observer/alumni/inactive'::text
    FROM public.members WHERE member_status IN ('observer','alumni','inactive')
      AND designations IS NOT NULL AND array_length(designations, 1) > 0;

  RETURN QUERY SELECT 'D_auth_id_mismatch_person_member'::text, COUNT(*)::bigint, 'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text
    FROM public.members m JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id <> p.auth_id;

  RETURN QUERY SELECT 'E_engagement_active_with_terminal_member'::text, COUNT(*)::bigint, 'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text
    FROM public.auth_engagements ae JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status = 'active' AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact');

  RETURN QUERY SELECT 'F_initiative_legacy_tribe_orphan'::text, COUNT(*)::bigint, 'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text
    FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id);

  -- I_artifacts_frozen: REMOVIDO na Part 3 (artifacts table DROPPED). Invariant
  -- era "artifacts frozen desde V4 cutover" — agora aplicado estruturalmente
  -- pela ausência da tabela. Substituído por legacy_artifacts_migration_marker
  -- em publication_submissions.reviewer_feedback (Part 1).

  RETURN QUERY SELECT 'J_current_version_published'::text, COUNT(*)::bigint, 'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL (Phase IP-1).'::text
    FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL AND (dv.id IS NULL OR dv.locked_at IS NULL);

  RETURN QUERY SELECT 'K_external_signer_integrity'::text, COUNT(*)::bigint, 'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text
    FROM public.members m
    WHERE m.operational_role = 'external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id = m.person_id AND ae.kind = 'external_signer'
          AND ae.status = 'active' AND ae.is_authoritative = true
      );

  RETURN;
END;
$function$;

-- =============================================================================
-- 3. COMPAT VIEW public.artifacts (TECH DEBT — remover após frontend refactor)
-- =============================================================================
-- Descoberto durante smoke pós-DROP: 4 frontend surfaces ainda têm sb.from('artifacts')
-- (profile.astro:367, gamification.astro:1000, tribe/[id].astro:1651, artifacts.astro CRUD).
-- Read-only VIEW preserva SELECTs (29 archived rows via marker). INSERT/UPDATE via
-- /artifacts page falharão (view não-updatable) — deprecate path já sinalizado.
-- Task #9 tracked: refactor proper → publication_submissions em sessão dedicada.

CREATE OR REPLACE VIEW public.artifacts AS
SELECT
  ps.id,
  ps.title,
  COALESCE(ps.abstract, '') AS description,
  CASE ps.status::text
    WHEN 'published'    THEN 'published'
    WHEN 'under_review' THEN 'review'
    WHEN 'draft'        THEN 'draft'
    ELSE ps.status::text
  END AS status,
  ps.primary_author_id AS member_id,
  i.legacy_tribe_id AS tribe_id,
  ps.target_url AS url,
  'publication'::text AS type,
  ps.created_at,
  ps.updated_at,
  ps.acceptance_date
FROM public.publication_submissions ps
LEFT JOIN public.initiatives i ON i.id = ps.initiative_id
WHERE ps.reviewer_feedback LIKE '[Legacy artifact migrated%';

COMMENT ON VIEW public.artifacts IS
'[TECH DEBT — ADR-0012 Part 3 compat] Read-only view mapeando 29 archived rows de publication_submissions para shape legado. Criada 2026-04-23 após DROP TABLE public.artifacts CASCADE. Frontend surfaces ainda usam sb.from("artifacts"): /artifacts, profile.astro, gamification.astro, tribe/[id].astro. Remover esta view após refactor completo dos 4 surfaces para publication_submissions.';

GRANT SELECT ON public.artifacts TO authenticated, service_role;

COMMIT;
