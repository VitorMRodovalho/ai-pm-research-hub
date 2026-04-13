-- ============================================================================
-- V4 Phase 5 — Migration 1/3: engagement_kinds lifecycle enrichment
-- ADR: ADR-0008 (Per-Kind Engagement Lifecycle with Explicit LGPD Basis)
-- Rollback: ALTER TABLE engagement_kinds DROP COLUMN IF EXISTS requires_vep,
--           DROP COLUMN IF EXISTS requires_selection, DROP COLUMN IF EXISTS max_duration_days,
--           DROP COLUMN IF EXISTS anonymization_policy, DROP COLUMN IF EXISTS renewable,
--           DROP COLUMN IF EXISTS auto_expire_behavior, DROP COLUMN IF EXISTS notify_before_expiry_days,
--           DROP COLUMN IF EXISTS created_by_role, DROP COLUMN IF EXISTS revocable_by_role,
--           DROP COLUMN IF EXISTS initiative_kinds_allowed, DROP COLUMN IF EXISTS metadata_schema;
-- ============================================================================

-- 1. Expand legal_basis CHECK to cover all engagement types
ALTER TABLE public.engagement_kinds DROP CONSTRAINT IF EXISTS engagement_kinds_legal_basis_check;
ALTER TABLE public.engagement_kinds ADD CONSTRAINT engagement_kinds_legal_basis_check
  CHECK (legal_basis IN (
    'contract_volunteer',    -- Lei 9.608 (voluntariado)
    'contract_course',       -- Execução de contrato de curso/estudo
    'consent',               -- LGPD Art. 7 I
    'legitimate_interest',   -- LGPD Art. 7 IX
    'chapter_delegation'     -- Delegação de capítulo PMI
  ));

-- 2. Add lifecycle columns from ADR-0008
ALTER TABLE public.engagement_kinds
  ADD COLUMN IF NOT EXISTS requires_vep boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS requires_selection boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS max_duration_days integer,
  ADD COLUMN IF NOT EXISTS anonymization_policy text NOT NULL DEFAULT 'anonymize'
    CHECK (anonymization_policy IN ('anonymize', 'delete', 'retain_for_legal')),
  ADD COLUMN IF NOT EXISTS renewable boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_expire_behavior text NOT NULL DEFAULT 'notify_only'
    CHECK (auto_expire_behavior IN ('suspend', 'offboard', 'notify_only')),
  ADD COLUMN IF NOT EXISTS notify_before_expiry_days integer DEFAULT 30,
  ADD COLUMN IF NOT EXISTS created_by_role text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS revocable_by_role text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS initiative_kinds_allowed text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS metadata_schema jsonb;

-- 3. Enrich seed with per-kind lifecycle configuration
-- Reference: ADR-0008 table in Context section

-- volunteer: VEP → Selection → Termo → 6m cycle → renewable → 5yr retention
UPDATE public.engagement_kinds SET
  legal_basis = 'contract_volunteer',
  requires_vep = true,
  requires_selection = true,
  requires_agreement = true,
  default_duration_days = 180,
  max_duration_days = 365,
  retention_days_after_end = 1825,  -- 5 years
  anonymization_policy = 'anonymize',
  renewable = true,
  auto_expire_behavior = 'suspend',
  notify_before_expiry_days = 30,
  created_by_role = ARRAY['manager', 'deputy_manager'],
  revocable_by_role = ARRAY['manager', 'deputy_manager'],
  initiative_kinds_allowed = ARRAY['research_tribe']
WHERE slug = 'volunteer';

-- study_group_owner: VEP fast-track → Termo → 9m → 5yr retention
UPDATE public.engagement_kinds SET
  legal_basis = 'contract_volunteer',
  requires_vep = true,
  requires_selection = false,
  requires_agreement = true,
  default_duration_days = 270,
  max_duration_days = 365,
  retention_days_after_end = 1825,
  anonymization_policy = 'anonymize',
  renewable = true,
  auto_expire_behavior = 'suspend',
  notify_before_expiry_days = 30,
  created_by_role = ARRAY['manager', 'deputy_manager'],
  revocable_by_role = ARRAY['manager', 'deputy_manager'],
  initiative_kinds_allowed = ARRAY['study_group']
WHERE slug = 'study_group_owner';

-- study_group_participant: Consent + termo uso → curso → certificado → 2yr retention
UPDATE public.engagement_kinds SET
  legal_basis = 'contract_course',
  requires_vep = false,
  requires_selection = false,
  requires_agreement = true,
  default_duration_days = 120,
  max_duration_days = 365,
  retention_days_after_end = 730,  -- 2 years
  anonymization_policy = 'anonymize',
  renewable = false,
  auto_expire_behavior = 'offboard',
  notify_before_expiry_days = 14,
  created_by_role = ARRAY['manager', 'deputy_manager', 'owner'],
  revocable_by_role = ARRAY['manager', 'deputy_manager', 'owner'],
  initiative_kinds_allowed = ARRAY['study_group']
WHERE slug = 'study_group_participant';

-- speaker: Convite → Consent imagem → 30 dias → delete
UPDATE public.engagement_kinds SET
  legal_basis = 'consent',
  requires_vep = false,
  requires_selection = false,
  requires_agreement = false,
  default_duration_days = 1,
  max_duration_days = 30,
  retention_days_after_end = 30,  -- 30 days
  anonymization_policy = 'delete',
  renewable = false,
  auto_expire_behavior = 'offboard',
  notify_before_expiry_days = null,
  created_by_role = ARRAY['manager', 'deputy_manager', 'leader', 'comms_leader'],
  revocable_by_role = ARRAY['manager', 'deputy_manager'],
  initiative_kinds_allowed = ARRAY['research_tribe', 'study_group', 'congress', 'workshop']
WHERE slug = 'speaker';

-- guest: acesso temp → consent → 30 dias → delete
UPDATE public.engagement_kinds SET
  legal_basis = 'consent',
  requires_vep = false,
  requires_selection = false,
  requires_agreement = false,
  default_duration_days = 30,
  max_duration_days = 90,
  retention_days_after_end = 30,
  anonymization_policy = 'delete',
  renewable = false,
  auto_expire_behavior = 'offboard',
  notify_before_expiry_days = 7,
  created_by_role = ARRAY['manager', 'deputy_manager', 'leader'],
  revocable_by_role = ARRAY['manager', 'deputy_manager'],
  initiative_kinds_allowed = ARRAY['research_tribe', 'study_group', 'congress', 'workshop']
WHERE slug = 'guest';

-- candidate: processo seletivo → consent → 90 dias → 2yr retention
UPDATE public.engagement_kinds SET
  legal_basis = 'consent',
  requires_vep = false,
  requires_selection = false,
  requires_agreement = false,
  default_duration_days = 90,
  max_duration_days = 180,
  retention_days_after_end = 730,  -- 2 years (recursal period)
  anonymization_policy = 'anonymize',
  renewable = false,
  auto_expire_behavior = 'offboard',
  notify_before_expiry_days = null,
  created_by_role = ARRAY['manager', 'deputy_manager'],
  revocable_by_role = ARRAY['manager', 'deputy_manager'],
  initiative_kinds_allowed = ARRAY[]::text[]
WHERE slug = 'candidate';

-- observer: sem compromisso → consent → indefinido → 5yr retention
UPDATE public.engagement_kinds SET
  legal_basis = 'consent',
  requires_vep = false,
  requires_selection = false,
  requires_agreement = false,
  default_duration_days = null,
  max_duration_days = null,
  retention_days_after_end = 1825,
  anonymization_policy = 'anonymize',
  renewable = false,
  auto_expire_behavior = 'notify_only',
  notify_before_expiry_days = null,
  created_by_role = ARRAY['manager', 'deputy_manager', 'leader'],
  revocable_by_role = ARRAY['manager', 'deputy_manager'],
  initiative_kinds_allowed = ARRAY['research_tribe', 'study_group']
WHERE slug = 'observer';

-- alumni: ex-membro → legítimo interesse → indefinido → 5yr retention
UPDATE public.engagement_kinds SET
  legal_basis = 'legitimate_interest',
  requires_vep = false,
  requires_selection = false,
  requires_agreement = false,
  default_duration_days = null,
  max_duration_days = null,
  retention_days_after_end = 1825,
  anonymization_policy = 'anonymize',
  renewable = false,
  auto_expire_behavior = 'notify_only',
  notify_before_expiry_days = null,
  created_by_role = ARRAY['manager', 'deputy_manager'],
  revocable_by_role = ARRAY['manager', 'deputy_manager'],
  initiative_kinds_allowed = ARRAY[]::text[]
WHERE slug = 'alumni';

-- ambassador: nomeação → consent → indefinido → 5yr retention on revoke
UPDATE public.engagement_kinds SET
  legal_basis = 'consent',
  requires_vep = false,
  requires_selection = false,
  requires_agreement = false,
  default_duration_days = null,
  max_duration_days = null,
  retention_days_after_end = 1825,
  anonymization_policy = 'anonymize',
  renewable = false,
  auto_expire_behavior = 'notify_only',
  notify_before_expiry_days = null,
  created_by_role = ARRAY['manager'],
  revocable_by_role = ARRAY['manager'],
  initiative_kinds_allowed = ARRAY[]::text[]
WHERE slug = 'ambassador';

-- chapter_board: delegação capítulo → legítimo interesse → indefinido
UPDATE public.engagement_kinds SET
  legal_basis = 'chapter_delegation',
  requires_vep = false,
  requires_selection = false,
  requires_agreement = false,
  default_duration_days = null,
  max_duration_days = null,
  retention_days_after_end = 1825,
  anonymization_policy = 'anonymize',
  renewable = false,
  auto_expire_behavior = 'notify_only',
  notify_before_expiry_days = null,
  created_by_role = ARRAY['manager', 'deputy_manager'],
  revocable_by_role = ARRAY['manager', 'deputy_manager'],
  initiative_kinds_allowed = ARRAY[]::text[]
WHERE slug = 'chapter_board';

-- sponsor: apoiador → legítimo interesse → indefinido → delete on request
UPDATE public.engagement_kinds SET
  legal_basis = 'legitimate_interest',
  requires_vep = false,
  requires_selection = false,
  requires_agreement = false,
  default_duration_days = null,
  max_duration_days = null,
  retention_days_after_end = 1825,
  anonymization_policy = 'anonymize',
  renewable = false,
  auto_expire_behavior = 'notify_only',
  notify_before_expiry_days = null,
  created_by_role = ARRAY['manager', 'deputy_manager'],
  revocable_by_role = ARRAY['manager', 'deputy_manager'],
  initiative_kinds_allowed = ARRAY[]::text[]
WHERE slug = 'sponsor';

-- partner_contact: registro manager → legítimo interesse → delete on request
UPDATE public.engagement_kinds SET
  legal_basis = 'legitimate_interest',
  requires_vep = false,
  requires_selection = false,
  requires_agreement = false,
  default_duration_days = null,
  max_duration_days = null,
  retention_days_after_end = 365,  -- 1 year after end
  anonymization_policy = 'delete',
  renewable = false,
  auto_expire_behavior = 'notify_only',
  notify_before_expiry_days = null,
  created_by_role = ARRAY['manager', 'deputy_manager', 'sponsor', 'liaison'],
  revocable_by_role = ARRAY['manager', 'deputy_manager'],
  initiative_kinds_allowed = ARRAY[]::text[]
WHERE slug = 'partner_contact';

COMMENT ON COLUMN public.engagement_kinds.requires_vep IS 'ADR-0008: Kind requires VEP (Volunteer Entry Process) before engagement';
COMMENT ON COLUMN public.engagement_kinds.requires_selection IS 'ADR-0008: Kind requires passing selection process';
COMMENT ON COLUMN public.engagement_kinds.max_duration_days IS 'ADR-0008: Hard cap on engagement duration (null = indefinite)';
COMMENT ON COLUMN public.engagement_kinds.anonymization_policy IS 'ADR-0008: anonymize (scrub PII), delete (full removal), retain_for_legal';
COMMENT ON COLUMN public.engagement_kinds.renewable IS 'ADR-0008: Whether engagement can be renewed at expiration';
COMMENT ON COLUMN public.engagement_kinds.auto_expire_behavior IS 'ADR-0008: suspend (revocable), offboard (final), notify_only (manual)';
COMMENT ON COLUMN public.engagement_kinds.notify_before_expiry_days IS 'ADR-0008: Days before end_date to send expiration notification (null = none)';
COMMENT ON COLUMN public.engagement_kinds.created_by_role IS 'ADR-0008: Which roles can create engagements of this kind';
COMMENT ON COLUMN public.engagement_kinds.revocable_by_role IS 'ADR-0008: Which roles can revoke/offboard engagements of this kind';
COMMENT ON COLUMN public.engagement_kinds.initiative_kinds_allowed IS 'ADR-0008: Which initiative_kinds accept this engagement_kind (empty = org-scoped)';
COMMENT ON COLUMN public.engagement_kinds.metadata_schema IS 'ADR-0008: JSON schema for custom per-engagement metadata';

NOTIFY pgrst, 'reload schema';
