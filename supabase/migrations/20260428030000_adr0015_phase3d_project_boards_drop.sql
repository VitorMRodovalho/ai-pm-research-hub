-- ADR-0015 Phase 3d — DROP COLUMN project_boards.tribe_id
--
-- Policies dependent on project_boards.tribe_id must be rewritten first, then
-- column can be dropped. RPC refactors live in sibling migration 20260428040000.
--
-- Row state pre-migration (14 rows):
--   0 tribe_only, 3 init_only, 9 both, 2 neither (global). Safe for drop.

-- ── 1. Policy board_items_write_v4 — subquery via pb.initiative_id ──
DROP POLICY IF EXISTS board_items_write_v4 ON public.board_items;

CREATE POLICY board_items_write_v4 ON public.board_items
  FOR ALL TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can_for_initiative('write_board'::text, (
      SELECT pb.initiative_id FROM public.project_boards pb WHERE pb.id = board_items.board_id
    ))
  );

-- ── 2. Policy project_boards_write_v4 — via rls_can_for_initiative ──
DROP POLICY IF EXISTS project_boards_write_v4 ON public.project_boards;

CREATE POLICY project_boards_write_v4 ON public.project_boards
  FOR ALL TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can_for_initiative('write_board'::text, initiative_id)
  );

-- ── 3. DROP COLUMN project_boards.tribe_id ──
ALTER TABLE public.project_boards DROP COLUMN tribe_id;

NOTIFY pgrst, 'reload schema';
