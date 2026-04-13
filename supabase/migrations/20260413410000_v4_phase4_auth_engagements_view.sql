-- ============================================================================
-- V4 Phase 4 — Migration 2/5: auth_engagements view
-- ADR: ADR-0007 (Authority as Derived Grant from Active Engagements)
-- Rollback: DROP VIEW public.auth_engagements;
-- ============================================================================

-- auth_engagements aggregates active engagements with temporal + agreement
-- validity checks. This is the single source for authority resolution.
-- Used by can() and by RLS policies (future).

CREATE OR REPLACE VIEW public.auth_engagements AS
SELECT
  e.id AS engagement_id,
  e.person_id,
  e.organization_id,
  e.initiative_id,
  e.kind,
  e.role,
  e.status,
  e.start_date,
  e.end_date,
  e.legal_basis,
  e.agreement_certificate_id,
  ek.requires_agreement,
  -- Derived: is this engagement currently valid for authority?
  (
    e.status = 'active'
    AND e.start_date <= CURRENT_DATE
    AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
    AND (
      e.agreement_certificate_id IS NOT NULL
      OR NOT COALESCE(ek.requires_agreement, false)
    )
  ) AS is_authoritative,
  -- Bridge to legacy
  p.legacy_member_id,
  p.auth_id,
  i.legacy_tribe_id
FROM public.engagements e
JOIN public.persons p ON p.id = e.person_id
JOIN public.engagement_kinds ek ON ek.slug = e.kind
LEFT JOIN public.initiatives i ON i.id = e.initiative_id
WHERE e.status IN ('active', 'suspended');

COMMENT ON VIEW public.auth_engagements IS 'V4: Active engagements with authority validity. is_authoritative=true means the engagement grants permissions (ADR-0007).';

NOTIFY pgrst, 'reload schema';
