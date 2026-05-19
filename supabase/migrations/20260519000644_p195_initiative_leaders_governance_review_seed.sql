-- ============================================================
-- p195: initiative leaders can participate in governance review
-- ============================================================
-- WHAT: seed `participate_in_governance_review` capability for
-- initiative leader engagement kinds:
--   - study_group_owner × study_group_owner
--   - workgroup_coordinator × workgroup_coordinator
--   - committee_coordinator × committee_coordinator
--
-- WHY (PM decision Option A, p195):
-- Herlon (study_group_owner of Preparatório CPMAI) couldn't comment on his
-- own initiative's TAP because the existing seed only covered manager/
-- deputy_manager/co_gp/curator/sponsor/chapter_board liaison/external_reviewer.
--
-- Initiative leaders are natural stakeholders for documents scoped to their
-- initiative. Action is non-destructive (only adds document_comments rows,
-- doesn't sign or approve gates). Org-scope acceptable because:
--   - Governance docs are already RLS-gated (only authorized viewers see them)
--   - Cross-initiative feedback during review is operationally valuable
--   - Less complex than initiative-scoped permission resolution
--
-- This DOES NOT grant sign authority — `_can_sign_gate` is a separate gate
-- mechanism that enumerates eligibles by gate kind (curator/legal_signer/
-- chapter_board), not by capability.
--
-- ROLLBACK: DELETE the 3 seeded rows.
-- ============================================================
--
-- RECOVERY NOTE (BUG-199.B p199-b, 2026-05-19): this migration was applied
-- to DB live during p195 via apply_migration MCP, but the local SQL file
-- was lost when Supabase CLI fork-bomb killed the session (see CR-051).
-- Body recovered from supabase_migrations.schema_migrations.statements
-- on 2026-05-19. The (kind=role) tuples below are INCORRECT relative to
-- actual production engagement role values — they were cleaned up by the
-- companion migration 20260519000734 (seed_fix). Both migrations are
-- preserved here to mirror the historical sequence applied to the DB.
-- Final correct state matches 20260709000000_p195_initiative_leaders_
-- governance_review.sql (which uses ON CONFLICT DO NOTHING and is
-- idempotent against this intermediate state).
-- ============================================================

INSERT INTO public.engagement_kind_permissions
  (kind, role, action, scope, description, organization_id)
VALUES
  ('study_group_owner', 'study_group_owner', 'participate_in_governance_review', 'organization',
   'Study group leaders (owners) review and comment on governance documents — including their own initiative''s TAP/charter and cross-initiative governance docs as stakeholders. Comment-only by design (no sign authority — gate signing is enumerated separately via _can_sign_gate).',
   '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('workgroup_coordinator', 'workgroup_coordinator', 'participate_in_governance_review', 'organization',
   'Workgroup coordinators review and comment on governance documents — same rationale as study_group_owner. Comment-only.',
   '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_coordinator', 'committee_coordinator', 'participate_in_governance_review', 'organization',
   'Committee coordinators review and comment on governance documents — same rationale as study_group_owner. Comment-only.',
   '2b4f58ab-7c45-4170-8718-b77ee69ff906')
ON CONFLICT (kind, role, action) DO NOTHING;
