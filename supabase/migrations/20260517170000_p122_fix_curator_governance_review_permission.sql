-- p122 (2026-05-08): Fix member A cannot comment on IP Adendo v2 (regression from ADR-0041 V4 conversion).
--
-- Context:
--   ADR-0041 (migration 20260427233000) converted create_document_comment + 8 sister fns
--   from V3 designation-based gates ('curator' = ANY(designations) OR ...) to V4 catalog-based
--   gate `can_by_member('participate_in_governance_review')`. The seed only granted the action
--   to 4 kind/role combos: volunteer × {manager,deputy_manager,co_gp} + chapter_board × liaison.
--
--   member A (member 19b7ff75-...; designations include 'curator')
--   has none of those engagements. Her active engagements include observer × reviewer, which
--   semantically IS a governance reviewer role but was missing from the seed. Same pattern for
--   observer × curator (member B). Result: member A was returned 'not_authorized' on every
--   create_document_comment call against the v2 (recirculated) chains.
--
-- Scope verification (audit pre-migration):
--   Only 3 active members hold observer × reviewer OR observer × curator engagements:
--     - member C: observer × reviewer  (also covered via volunteer × co_gp)
--     - member B: observer × curator   (also covered via chapter_board × liaison)
--     - member A: observer × reviewer  (NOT covered — this is the bug)
--   All 3 have 'curator' designation. Adding these seeds therefore produces zero blast radius
--   beyond unblocking member A, and improves resilience for member C + member B (defense in depth).
--
-- Rollback: DELETE FROM engagement_kind_permissions WHERE action = 'participate_in_governance_review'
--           AND (kind, role) IN (('observer','reviewer'), ('observer','curator'));

INSERT INTO engagement_kind_permissions (kind, role, action, scope, description)
VALUES
  ('observer', 'reviewer', 'participate_in_governance_review', 'organization',
   'Observer × reviewer engagement is the canonical V4 expression of curator-equivalent governance review authority. Grants comment + sign on document chains org-wide.'),
  ('observer', 'curator', 'participate_in_governance_review', 'organization',
   'Observer × curator engagement is an explicit curator role for governance review. Grants comment + sign on document chains org-wide.')
ON CONFLICT (kind, role, action) DO NOTHING;

-- Smoke: member A should now return TRUE for can_by_member
DO $$
DECLARE
  v_sarah_can boolean;
BEGIN
  SELECT public.can_by_member(
    '19b7ff75-bcb1-4a15-a8e1-006fc6822069'::uuid,
    'participate_in_governance_review'
  ) INTO v_sarah_can;
  IF NOT v_sarah_can THEN
    RAISE EXCEPTION 'Smoke failed: member A still cannot participate_in_governance_review after seed';
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
