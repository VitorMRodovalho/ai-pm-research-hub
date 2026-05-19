-- p200 (OPP-196.E, ADR-0087, 2026-05-19): seed `curate_content` action
-- in engagement_kind_permissions. Prerequisite for the 4 V4 sweep batches
-- (A board, B cert, C governance, D gate+reviewer).
--
-- Coverage validation (pre-seed): 3 active curators all return false on
--   can_by_member(id, 'curate_content'). Post-seed (+ scope fix in next
--   migration): all 3 return true.
--
-- Tuples:
--   committee_coordinator × coordinator → covers Roberto, Sarah
--   committee_coordinator × leader      → covers Fabricio
--   observer × curator                  → covers Roberto's cross-init curation
--
-- NOTE: initial seed used default scope='initiative' which caused
-- inconsistent results (Roberto=true, Fabricio/Sarah=false) because
-- can() requires either matching p_resource_id OR legacy_tribe_id set
-- on the engagement when scope=initiative + p_resource_id=NULL. See
-- migration 20260519182828 for the scope='organization' correction.
--
-- ROLLBACK:
--   DELETE FROM engagement_kind_permissions WHERE action = 'curate_content';
--   (only after reverting the 4 batch migrations that consume this action)

INSERT INTO engagement_kind_permissions (kind, role, action)
VALUES
  ('committee_coordinator', 'coordinator', 'curate_content'),
  ('committee_coordinator', 'leader',      'curate_content'),
  ('observer',              'curator',     'curate_content')
ON CONFLICT (kind, role, action) DO NOTHING;

NOTIFY pgrst, 'reload schema';
