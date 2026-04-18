-- ============================================================================
-- Phase IP-1: extensions + invariants
-- - Extend certificates.type CHECK para incluir 'ip_ratification'
-- - Novo engagement_kind 'external_signer' (UX.Q4 Opção C)
-- - Update sync_operational_role_cache para reconhecer external_signer
-- - Add current_version_id cache em governance_documents + sync trigger
-- - 2 invariants novas: I_current_version_published + I_external_signer_integrity
-- Rollback: reverse each ALTER; DROP kind row; drop current_version_id column.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Extend certificates.type CHECK
-- ---------------------------------------------------------------------------
ALTER TABLE public.certificates DROP CONSTRAINT IF EXISTS certificates_type_check;
ALTER TABLE public.certificates ADD CONSTRAINT certificates_type_check
  CHECK (type = ANY (ARRAY[
    'participation'::text,
    'completion'::text,
    'contribution'::text,
    'excellence'::text,
    'volunteer_agreement'::text,
    'institutional_declaration'::text,
    'ip_ratification'::text
  ]));

COMMENT ON CONSTRAINT certificates_type_check ON public.certificates IS
  'ip_ratification adicionado em Phase IP-1 (CR-050). Emitido quando membro completa ratificacao de documento IP via approval_signoff.';

-- ---------------------------------------------------------------------------
-- 2. Novo engagement_kind: external_signer
-- ---------------------------------------------------------------------------
INSERT INTO public.engagement_kinds (
  slug, display_name, description, legal_basis, requires_agreement,
  default_duration_days, retention_days_after_end, is_initiative_scoped,
  organization_id, requires_vep, requires_selection, max_duration_days,
  anonymization_policy, renewable, auto_expire_behavior, notify_before_expiry_days,
  created_by_role, revocable_by_role, initiative_kinds_allowed
) VALUES (
  'external_signer',
  'Signatario Externo',
  'Signatario externo (presidente, parceiro, ambassador) com acesso restrito via magic-link para ratificacao de documentos IP. Nao participa de attendance, XP, gamification ou rosters internos. UX.Q4 Opcao C decision p29.',
  'legitimate_interest',
  false, -- nao requires_agreement no onboarding (ratifica via signoff)
  365, -- 1 ano default (renovavel)
  2555, -- 7 anos post-end (audit trail legal)
  false, -- nao e initiative-scoped
  '2b4f58ab-7c45-4170-8718-b77ee69ff906', -- PMI-GO org id (hardcoded conhecido, eh)
  false, false,
  3650, -- 10 anos max (presidente de capitulo pode assinar por decadas)
  'anonymize',
  true,
  'notify_only',
  60,
  ARRAY['manager','deputy_manager'],
  ARRAY['manager','deputy_manager'],
  ARRAY[]::text[]
)
ON CONFLICT (slug) DO UPDATE
  SET description = EXCLUDED.description,
      updated_at = now();

COMMENT ON TABLE public.engagement_kinds IS
  'Tipos de engajamento (V4 primitivo ADR-0006). external_signer adicionado em Phase IP-1 para representar presidentes/parceiros que ratificam IP via magic-link sem virar member Tier-1.';

-- ---------------------------------------------------------------------------
-- 3. Update sync_operational_role_cache para reconhecer external_signer
-- Note: external_signer tem maior prioridade que observer/guest porque eh
--       papel formalizado com acesso magic-link. Menor prioridade que roles
--       operacionais (manager, leader, etc.).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_operational_role_cache()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_member_id uuid;
  v_new_role text;
BEGIN
  SELECT id INTO v_member_id
  FROM public.members
  WHERE person_id = COALESCE(NEW.person_id, OLD.person_id);

  IF v_member_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  SELECT
    CASE
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager') THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'leader') THEN 'tribe_leader'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp') THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'comms_leader') THEN 'comms_leader'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('researcher', 'facilitator', 'communicator', 'curator')) THEN 'researcher'
      WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
      WHEN bool_or(ae.kind = 'observer') THEN 'observer'
      WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
      WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
      WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
      WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
      ELSE 'guest'
    END INTO v_new_role
  FROM public.auth_engagements ae
  WHERE ae.person_id = COALESCE(NEW.person_id, OLD.person_id)
    AND ae.is_authoritative = true;

  UPDATE public.members
  SET operational_role = COALESCE(v_new_role, 'guest'),
      updated_at = now()
  WHERE id = v_member_id
    AND operational_role IS DISTINCT FROM COALESCE(v_new_role, 'guest');

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Add current_version_id cache em governance_documents
-- ---------------------------------------------------------------------------
ALTER TABLE public.governance_documents
  ADD COLUMN IF NOT EXISTS current_version_id uuid
    REFERENCES public.document_versions(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.governance_documents.current_version_id IS
  'Cache da versao atual (publicada e locked) do documento. Mantido por trigger trg_sync_current_version_on_publish. Pattern ADR-0012 cache+trigger.';

CREATE INDEX IF NOT EXISTS idx_governance_documents_current_version
  ON public.governance_documents(current_version_id) WHERE current_version_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. Trigger: sync current_version_id on publish/lock
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_sync_current_version_on_publish()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  -- Quando version e locked (published), atualiza cache
  IF NEW.locked_at IS NOT NULL AND (OLD.locked_at IS NULL OR TG_OP = 'INSERT') THEN
    UPDATE public.governance_documents
       SET current_version_id = NEW.id,
           updated_at = now()
     WHERE id = NEW.document_id;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_current_version_on_publish ON public.document_versions;
CREATE TRIGGER trg_sync_current_version_on_publish
  AFTER INSERT OR UPDATE OF locked_at ON public.document_versions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sync_current_version_on_publish();

-- ---------------------------------------------------------------------------
-- 6. Invariants: register novas em check_schema_invariants
--    Preserve whitelist "VP Desenvolvimento Profissional (PMI-GO)" (placeholder row) + alias comms_leader -> tribe_leader
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.check_schema_invariants();

CREATE FUNCTION public.check_schema_invariants()
RETURNS TABLE (
  invariant_name text,
  violation_count bigint,
  description text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  RETURN QUERY
  SELECT 'A1_alumni_role_consistency'::text, COUNT(*)::bigint, 'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text
  FROM public.members WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni';

  RETURN QUERY
  SELECT 'A2_observer_role_consistency'::text, COUNT(*)::bigint, 'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text
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

  RETURN QUERY
  SELECT 'B_is_active_status_mismatch'::text, COUNT(*)::bigint, 'members.is_active must match member_status mapping (active=true, terminal=false)'::text
  FROM public.members
  WHERE ((member_status = 'active' AND is_active = false)
      OR (member_status IN ('observer','alumni','inactive') AND is_active = true))
    AND name != 'VP Desenvolvimento Profissional (PMI-GO)';

  -- C: designations in terminal status
  RETURN QUERY
  SELECT
    'C_designations_in_terminal_status'::text,
    COUNT(*)::bigint,
    'members.designations must be empty when member_status is observer/alumni/inactive'::text
  FROM public.members
  WHERE member_status IN ('observer','alumni','inactive')
    AND designations IS NOT NULL
    AND array_length(designations, 1) > 0;

  -- D: auth_id mismatch person vs member
  RETURN QUERY
  SELECT
    'D_auth_id_mismatch_person_member'::text,
    COUNT(*)::bigint,
    'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text
  FROM public.members m
  JOIN public.persons p ON p.id = m.person_id
  WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id <> p.auth_id;

  -- E: engagement active with terminal member
  RETURN QUERY
  SELECT
    'E_engagement_active_with_terminal_member'::text,
    COUNT(*)::bigint,
    'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text
  FROM public.auth_engagements ae
  JOIN public.members m ON m.person_id = ae.person_id
  WHERE ae.status = 'active'
    AND m.member_status IN ('observer','alumni','inactive')
    AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact');

  -- F: initiative legacy tribe orphan
  RETURN QUERY
  SELECT
    'F_initiative_legacy_tribe_orphan'::text,
    COUNT(*)::bigint,
    'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text
  FROM public.initiatives i
  WHERE i.legacy_tribe_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id);

  -- I: artifacts frozen
  RETURN QUERY
  SELECT
    'I_artifacts_frozen'::text,
    COUNT(*)::bigint,
    'artifacts table is frozen since V4 cutover (2026-04-13). New inserts indicate unauthorized write — V4 writers must use board_items + publication_submissions instead.'::text
  FROM public.artifacts
  WHERE created_at > '2026-04-13'::timestamptz;

  -- J (new): current_version_id must point to locked version
  RETURN QUERY
  SELECT
    'J_current_version_published'::text,
    COUNT(*)::bigint,
    'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL (Phase IP-1 invariant).'::text
  FROM public.governance_documents gd
  LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
  WHERE gd.current_version_id IS NOT NULL
    AND (dv.id IS NULL OR dv.locked_at IS NULL);

  -- K (new): external_signer role integrity
  RETURN QUERY
  SELECT
    'K_external_signer_integrity'::text,
    COUNT(*)::bigint,
    'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1 invariant).'::text
  FROM public.members m
  WHERE m.operational_role = 'external_signer'
    AND NOT EXISTS (
      SELECT 1 FROM public.auth_engagements ae
      WHERE ae.person_id = m.person_id
        AND ae.kind = 'external_signer'
        AND ae.status = 'active'
        AND ae.is_authoritative = true
    );

  RETURN;
END;
$function$;

COMMENT ON FUNCTION public.check_schema_invariants() IS
  'Schema invariants (ADR-0012). 9 baseline (A1/A2/A3/B/C/D/E/F/I) + Phase IP-1 (J_current_version_published + K_external_signer_integrity) = 11 total. violation_count=0 em todas indica saude do schema.';

GRANT EXECUTE ON FUNCTION public.check_schema_invariants() TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_schema_invariants() TO service_role;

NOTIFY pgrst, 'reload schema';
