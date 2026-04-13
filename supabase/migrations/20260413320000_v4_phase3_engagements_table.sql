-- ============================================================================
-- V4 Phase 3 — Migration 3/3: engagements table + backfill from members
-- ADR: ADR-0006 (Person + Engagement Identity Model)
-- Depends on: 20260413310000_v4_phase3_persons_table.sql
-- Rollback: DROP TABLE public.engagements CASCADE;
-- ============================================================================

-- An engagement represents "Person X participates in Initiative Y with role Z
-- during period P under legal basis B, anchored in governance artifact G."

CREATE TABLE public.engagements (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id               uuid NOT NULL REFERENCES public.persons(id) ON DELETE CASCADE,
  organization_id         uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                          REFERENCES public.organizations(id) ON DELETE RESTRICT,
  initiative_id           uuid REFERENCES public.initiatives(id) ON DELETE SET NULL,
  kind                    text NOT NULL REFERENCES public.engagement_kinds(slug) ON DELETE RESTRICT,
  role                    text NOT NULL DEFAULT 'participant',
  status                  text NOT NULL DEFAULT 'active'
                          CHECK (status IN ('pending', 'active', 'suspended', 'expired', 'offboarded', 'anonymized')),
  start_date              date NOT NULL DEFAULT CURRENT_DATE,
  end_date                date,
  legal_basis             text NOT NULL DEFAULT 'consent'
                          CHECK (legal_basis IN ('contract_volunteer', 'consent', 'legitimate_interest')),
  agreement_certificate_id uuid,
  vep_opportunity_id      uuid,
  granted_by              uuid REFERENCES public.persons(id),
  granted_at              timestamptz DEFAULT now(),
  revoked_at              timestamptz,
  revoked_by              uuid REFERENCES public.persons(id),
  revoke_reason           text,
  metadata                jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.engagements IS 'V4: Temporal-contextual binding between person and initiative/org (ADR-0006). Source of truth for authority (ADR-0007) and lifecycle (ADR-0008).';

CREATE INDEX idx_engagements_person ON public.engagements(person_id);
CREATE INDEX idx_engagements_org ON public.engagements(organization_id);
CREATE INDEX idx_engagements_initiative ON public.engagements(initiative_id) WHERE initiative_id IS NOT NULL;
CREATE INDEX idx_engagements_kind ON public.engagements(kind);
CREATE INDEX idx_engagements_status ON public.engagements(status);
CREATE INDEX idx_engagements_active ON public.engagements(person_id, status) WHERE status = 'active';

ALTER TABLE public.engagements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "engagements_select_authenticated"
  ON public.engagements FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "engagements_org_scope"
  ON public.engagements AS RESTRICTIVE FOR ALL TO authenticated
  USING (organization_id = public.auth_org() OR organization_id IS NULL)
  WITH CHECK (organization_id = public.auth_org());

-- ── Backfill from members ─────────────────────────────────────────────────
-- Step 1: Primary engagement from operational_role
-- Maps: researcher→volunteer, tribe_leader→volunteer, manager→volunteer,
--        observer→observer, alumni→alumni, sponsor→sponsor,
--        chapter_liaison→chapter_board, guest→guest, candidate→candidate

INSERT INTO public.engagements (
  person_id, organization_id, initiative_id, kind, role, status,
  start_date, legal_basis, metadata
)
SELECT
  p.id,
  m.organization_id,
  m.initiative_id,
  -- Map operational_role → engagement kind
  CASE m.operational_role
    WHEN 'researcher'      THEN 'volunteer'
    WHEN 'tribe_leader'    THEN 'volunteer'
    WHEN 'manager'         THEN 'volunteer'
    WHEN 'observer'        THEN 'observer'
    WHEN 'alumni'          THEN 'alumni'
    WHEN 'sponsor'         THEN 'sponsor'
    WHEN 'chapter_liaison' THEN 'chapter_board'
    WHEN 'guest'           THEN 'guest'
    WHEN 'candidate'       THEN 'candidate'
    ELSE 'guest'
  END,
  -- Map operational_role → role within engagement
  CASE m.operational_role
    WHEN 'researcher'      THEN 'researcher'
    WHEN 'tribe_leader'    THEN 'leader'
    WHEN 'manager'         THEN 'manager'
    WHEN 'observer'        THEN 'observer'
    WHEN 'alumni'          THEN 'alumni'
    WHEN 'sponsor'         THEN 'sponsor'
    WHEN 'chapter_liaison' THEN 'liaison'
    WHEN 'guest'           THEN 'guest'
    WHEN 'candidate'       THEN 'candidate'
    ELSE 'guest'
  END,
  -- Map member status
  CASE
    WHEN m.member_status = 'offboarded' THEN 'offboarded'
    WHEN m.member_status = 'anonymized' THEN 'anonymized'
    WHEN m.current_cycle_active THEN 'active'
    ELSE 'expired'
  END,
  COALESCE(m.created_at::date, CURRENT_DATE),
  -- Legal basis from kind
  CASE m.operational_role
    WHEN 'researcher'      THEN 'contract_volunteer'
    WHEN 'tribe_leader'    THEN 'contract_volunteer'
    WHEN 'manager'         THEN 'contract_volunteer'
    WHEN 'sponsor'         THEN 'legitimate_interest'
    WHEN 'chapter_liaison' THEN 'legitimate_interest'
    WHEN 'alumni'          THEN 'legitimate_interest'
    ELSE 'consent'
  END,
  jsonb_build_object(
    'source', 'backfill_v4_phase3',
    'original_operational_role', m.operational_role,
    'legacy_member_id', m.id
  )
FROM public.members m
JOIN public.persons p ON p.legacy_member_id = m.id
ORDER BY m.created_at;

-- Step 2: Additional engagements from designations
-- Only for designations that represent a distinct kind (not a role within volunteer)

-- ambassador designation → ambassador engagement
INSERT INTO public.engagements (
  person_id, organization_id, kind, role, status, start_date, legal_basis, metadata
)
SELECT
  p.id, m.organization_id, 'ambassador', 'ambassador', 'active',
  COALESCE(m.created_at::date, CURRENT_DATE), 'consent',
  jsonb_build_object('source', 'backfill_v4_phase3_designation', 'designation', 'ambassador')
FROM public.members m
JOIN public.persons p ON p.legacy_member_id = m.id
WHERE 'ambassador' = ANY(m.designations)
  AND m.operational_role != 'alumni';

-- chapter_board designation → chapter_board engagement (if not already from chapter_liaison)
INSERT INTO public.engagements (
  person_id, organization_id, kind, role, status, start_date, legal_basis, metadata
)
SELECT
  p.id, m.organization_id, 'chapter_board', 'board_member', 'active',
  COALESCE(m.created_at::date, CURRENT_DATE), 'legitimate_interest',
  jsonb_build_object('source', 'backfill_v4_phase3_designation', 'designation', 'chapter_board')
FROM public.members m
JOIN public.persons p ON p.legacy_member_id = m.id
WHERE 'chapter_board' = ANY(m.designations)
  AND m.operational_role != 'chapter_liaison';

-- founder designation → ambassador engagement with role=founder
INSERT INTO public.engagements (
  person_id, organization_id, kind, role, status, start_date, legal_basis, metadata
)
SELECT
  p.id, m.organization_id, 'ambassador', 'founder', 'active',
  COALESCE(m.created_at::date, CURRENT_DATE), 'consent',
  jsonb_build_object('source', 'backfill_v4_phase3_designation', 'designation', 'founder')
FROM public.members m
JOIN public.persons p ON p.legacy_member_id = m.id
WHERE 'founder' = ANY(m.designations);

-- sponsor designation → sponsor engagement (if not already from operational_role=sponsor)
INSERT INTO public.engagements (
  person_id, organization_id, kind, role, status, start_date, legal_basis, metadata
)
SELECT
  p.id, m.organization_id, 'sponsor', 'sponsor', 'active',
  COALESCE(m.created_at::date, CURRENT_DATE), 'legitimate_interest',
  jsonb_build_object('source', 'backfill_v4_phase3_designation', 'designation', 'sponsor')
FROM public.members m
JOIN public.persons p ON p.legacy_member_id = m.id
WHERE 'sponsor' = ANY(m.designations)
  AND m.operational_role != 'sponsor';

-- Designations that are roles within volunteer (curator, comms_member, comms_leader,
-- deputy_manager, co_gp) are stored in metadata of the primary engagement, not as
-- separate engagements. They will be resolved by authority derivation in Fase 4.

NOTIFY pgrst, 'reload schema';
