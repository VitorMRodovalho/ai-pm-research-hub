-- #785: add the confidential visibility carve-out to board_item_checklists.
--
-- The parent table board_items has a RESTRICTIVE SELECT policy
-- (board_items_confidential_visibility = rls_can_see_board(board_id)) that ANDs on top
-- of its permissive read. board_item_checklists had only the permissive
-- checklists_read_members (rls_is_authoritative_member), so its checklist rows were not
-- covered by the confidential visibility gate the parent board_items carries.
--
-- Fix: a RESTRICTIVE SELECT policy that mirrors the tested sibling board_item_comments
-- pattern — an EXISTS over board_items (whose own RESTRICTIVE policy already hides
-- confidential items), so a checklist row is selectable only when its parent board_item
-- is visible to the caller. RESTRICTIVE ANDs with the permissive read; the confidential
-- gate is inherited transitively through board_items' RLS (no scalar-subquery NULL trap).
--
-- Applied via apply_migration, then registered + NOTIFY per Track Q-C / GC-097.

CREATE POLICY checklists_confidential_visibility
  ON public.board_item_checklists
  AS RESTRICTIVE
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      WHERE bi.id = board_item_checklists.board_item_id
    )
  );

NOTIFY pgrst, 'reload schema';
