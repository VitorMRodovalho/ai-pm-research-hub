-- Interim leader grant path for auth_engagements.is_authoritative
-- Context: allow an engagement to be authoritative when metadata->>'interim_grant' is true,
-- so a designated tribe leader can be activated (operational_role=tribe_leader -> leader onboarding
-- + authority) AHEAD of the signed volunteer term. Owner-authorized interim grant, honest & reversible:
-- the metadata flag records granted_by/at/reason; when the real term is signed, agreement_certificate_id
-- is set and the interim flag is removed. Non-lossy (legal_basis untouched). See ADR interim-leader-grant.
CREATE OR REPLACE VIEW public.auth_engagements AS
 SELECT e.id AS engagement_id,
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
    e.status = 'active'::text
      AND e.start_date <= CURRENT_DATE
      AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
      AND (e.agreement_certificate_id IS NOT NULL
           OR NOT COALESCE(ek.requires_agreement, false)
           OR COALESCE((e.metadata ->> 'interim_grant')::boolean, false)) AS is_authoritative,
    p.legacy_member_id,
    p.auth_id,
    i.legacy_tribe_id
   FROM engagements e
     JOIN persons p ON p.id = e.person_id
     JOIN engagement_kinds ek ON ek.slug = e.kind
     LEFT JOIN initiatives i ON i.id = e.initiative_id
  WHERE e.status = ANY (ARRAY['active'::text, 'suspended'::text]);
