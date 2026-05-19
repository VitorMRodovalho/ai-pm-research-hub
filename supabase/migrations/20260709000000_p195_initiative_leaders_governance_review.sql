-- ============================================================
-- p195: initiative leaders can participate in governance review
-- ============================================================
-- WHAT: seed `participate_in_governance_review` capability for actual
-- (kind, role) tuples present in production engagements:
--   study_group_owner × leader        (1 active — Herlon)
--   workgroup_coordinator × coordinator (1 active)
--   committee_coordinator × coordinator (2 active)
--   committee_coordinator × leader      (1 active)
--
-- WHY (PM decision Option A, p195 Bug 1 carry)
-- Herlon (study_group_owner of Preparatório CPMAI) couldn't comment on his
-- own initiative's TAP because the existing seed only covered manager/
-- deputy_manager/co_gp/curator/sponsor/chapter_board liaison/external_reviewer
-- — no initiative leader kinds.
--
-- Initiative leaders are natural stakeholders for documents scoped to their
-- initiative. Action is non-destructive (only adds document_comments rows,
-- doesn't sign or approve gates). Org-scope acceptable because:
--   - Governance docs are RLS-gated (only authorized viewers see them)
--   - Cross-initiative feedback during review is operationally valuable
--   - Less complex than initiative-scoped permission resolution
--
-- This DOES NOT grant sign authority — `_can_sign_gate` is a separate
-- gate mechanism that enumerates eligibles by gate kind.
--
-- DEPENDENCY (operational)
-- Capability resolution requires `auth_engagements.is_authoritative=true`,
-- which requires `agreement_certificate_id IS NOT NULL` when
-- `engagement_kinds.requires_agreement=true` (true for study_group_owner +
-- workgroup_coordinator + committee_coordinator). PM must counter-sign the
-- Volunteer Term for each leader before they can comment. Herlon's
-- counter-sign is part of the 9 pending in /admin/certificates per p195
-- handoff. This migration unlocks the path; the operational completion is
-- a separate human step.
--
-- ROLLBACK: DELETE the 4 seeded rows by (kind, role, action).
-- ============================================================

INSERT INTO public.engagement_kind_permissions
  (kind, role, action, scope, description, organization_id)
VALUES
  ('study_group_owner', 'leader', 'participate_in_governance_review', 'organization',
   'p195: Study group leaders review and comment on governance documents — including their own initiative''s TAP/charter and cross-initiative governance docs as stakeholders. Comment-only by design (no sign authority — _can_sign_gate is enumerated separately).',
   '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('workgroup_coordinator', 'coordinator', 'participate_in_governance_review', 'organization',
   'p195: Workgroup coordinators review and comment on governance documents. Comment-only.',
   '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_coordinator', 'coordinator', 'participate_in_governance_review', 'organization',
   'p195: Committee coordinators review and comment on governance documents. Comment-only.',
   '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_coordinator', 'leader', 'participate_in_governance_review', 'organization',
   'p195: Committee leaders (alternate role naming for committee_coordinator kind) review and comment on governance documents. Comment-only.',
   '2b4f58ab-7c45-4170-8718-b77ee69ff906')
ON CONFLICT (kind, role, action) DO NOTHING;
