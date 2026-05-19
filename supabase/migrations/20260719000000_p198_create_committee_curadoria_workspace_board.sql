-- =====================================================================
-- p198 OPP-196.D MVP — Create workspace board for Comitê de Curadoria
-- =====================================================================
-- Context: Comitê de Curadoria initiative (6a93cc94-c4a0-4280-8ea7-452ec6ec48a5)
-- has been decorative since creation (0 boards, 0 events, 0 governance_docs).
-- The 3 active members (Fabricio leader, Sarah + Roberto coordinators) had
-- no workspace to record their meetings, attendance, or internal decisions.
--
-- Per PM directive (sessão p196/p197): the workspace should be ONE PLACE
-- where curators can:
--   • Meet (use existing /initiative/[id] meeting notes via EventMinutesIsland)
--   • Track attendance (existing register_attendance per initiative)
--   • Organize internal work via kanban + checklists
--   • [future p199+] See cross-pipeline curation queue (board_items +
--     governance_docs + manuals + webinars) in dedicated tab
--
-- This migration creates the project_board only. Cross-pipeline RPC and
-- dedicated UI tabs are deferred to p199 OPP-196.D full scope. The
-- existing /admin/curatorship page continues to serve the actual curation
-- queue (will be linked from the workspace later).
--
-- Effect: kindConfig.has_board=true + initiative now has board_id →
-- /initiative/6a93cc94... will render Board tab automatically.
--
-- Rollback: DELETE FROM project_boards WHERE id = (gen'd UUID);
-- =====================================================================

INSERT INTO public.project_boards (
  board_name,
  source,
  columns,
  is_active,
  domain_key,
  cycle_scope,
  board_scope,
  initiative_id,
  organization_id
)
SELECT
  'Comitê de Curadoria — Workspace',
  'manual',
  '["backlog", "todo", "in_progress", "review", "done"]'::jsonb,
  true,
  'curation',
  NULL,
  'global',
  '6a93cc94-c4a0-4280-8ea7-452ec6ec48a5'::uuid,
  organization_id
FROM public.project_boards
WHERE organization_id IS NOT NULL
LIMIT 1
ON CONFLICT DO NOTHING;
