-- ============================================================
-- p195 fix: correct (kind, role) tuples for initiative leader governance review
-- ============================================================
-- WHAT: previous seed used kind=role pattern (e.g. study_group_owner × study_group_owner)
-- but actual DB engagements have role values 'leader' / 'coordinator'. Replace
-- with correct tuples present in production.
--
-- Empirical role inventory at p195:
--   study_group_owner × leader (1 active — Herlon)
--   committee_coordinator × coordinator (2 active) + × leader (1 active)
--   workgroup_coordinator × coordinator (1 active)
-- ============================================================
--
-- RECOVERY NOTE (BUG-199.B p199-b, 2026-05-19): companion to 20260519000644.
-- Both migrations were applied to DB live but lost from FS during the
-- Supabase fork-bomb (CR-051). Body recovered from schema_migrations.
-- Final correct state is preserved by 20260709000000_p195_initiative_
-- leaders_governance_review.sql (uses ON CONFLICT DO NOTHING) — that
-- file replays the 4 correct INSERTs idempotently against this state.
-- ============================================================

-- Clean up previous incorrect seeds
DELETE FROM public.engagement_kind_permissions
WHERE action = 'participate_in_governance_review'
  AND (kind, role) IN (
    ('study_group_owner', 'study_group_owner'),
    ('committee_coordinator', 'committee_coordinator'),
    ('workgroup_coordinator', 'workgroup_coordinator')
  );

-- Insert correct (kind, role) combos covering all 4 real production tuples.
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
