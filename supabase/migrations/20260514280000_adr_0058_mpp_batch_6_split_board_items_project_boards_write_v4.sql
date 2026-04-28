-- ADR-0058 batch 6 — split board_items + project_boards write_v4 ALL → per-cmd
-- Same pattern as batch 3: ALL-cmd write policy overlapped on SELECT with
-- a separate read policy. Splitting into 3 per-cmd policies leaves SELECT
-- covered only by read_members. -2 WARN (77 → 75).

-- ============================================================================
-- public.board_items
-- ============================================================================

DROP POLICY IF EXISTS board_items_write_v4 ON public.board_items;

CREATE POLICY board_items_insert_v4 ON public.board_items
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (
    rls_is_superadmin()
    OR rls_can_for_initiative(
      'write_board'::text,
      (SELECT pb.initiative_id FROM project_boards pb WHERE pb.id = board_items.board_id)
    )
  );

CREATE POLICY board_items_update_v4 ON public.board_items
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can_for_initiative(
      'write_board'::text,
      (SELECT pb.initiative_id FROM project_boards pb WHERE pb.id = board_items.board_id)
    )
  );

CREATE POLICY board_items_delete_v4 ON public.board_items
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can_for_initiative(
      'write_board'::text,
      (SELECT pb.initiative_id FROM project_boards pb WHERE pb.id = board_items.board_id)
    )
  );

-- ============================================================================
-- public.project_boards
-- ============================================================================

DROP POLICY IF EXISTS project_boards_write_v4 ON public.project_boards;

CREATE POLICY project_boards_insert_v4 ON public.project_boards
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (
    rls_is_superadmin()
    OR rls_can_for_initiative('write_board'::text, initiative_id)
  );

CREATE POLICY project_boards_update_v4 ON public.project_boards
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can_for_initiative('write_board'::text, initiative_id)
  );

CREATE POLICY project_boards_delete_v4 ON public.project_boards
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can_for_initiative('write_board'::text, initiative_id)
  );

NOTIFY pgrst, 'reload schema';
