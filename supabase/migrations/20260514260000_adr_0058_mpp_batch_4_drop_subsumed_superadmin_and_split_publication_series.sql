-- ADR-0058 batch 4 — eliminate redundant superadmin_all policies
-- 1. board_items + project_boards: superadmin_all is strictly subsumed by
--    *_write_v4 USING (rls_is_superadmin() OR rls_can_for_initiative(...)).
--    DROP superadmin_all → -3 WARN per table = -6.
-- 2. publication_series: superadmin_all is the only path for INSERT/UPDATE/
--    DELETE. Split into per-cmd policies (same pattern as batch 3) → -6 WARN.
-- Total: -12 WARN (99 → 87).

-- ============================================================================
-- public.board_items — DROP redundant superadmin_all
-- ============================================================================
DROP POLICY IF EXISTS board_items_superadmin_all ON public.board_items;

-- ============================================================================
-- public.project_boards — DROP redundant superadmin_all
-- ============================================================================
DROP POLICY IF EXISTS project_boards_superadmin_all ON public.project_boards;

-- ============================================================================
-- public.publication_series — split ALL-cmd superadmin_all into per-cmd
-- ============================================================================
DROP POLICY IF EXISTS publication_series_superadmin_all ON public.publication_series;

CREATE POLICY publication_series_admin_insert ON public.publication_series
  AS PERMISSIVE FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND m.is_superadmin = true
    )
  );

CREATE POLICY publication_series_admin_update ON public.publication_series
  AS PERMISSIVE FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND m.is_superadmin = true
    )
  );

CREATE POLICY publication_series_admin_delete ON public.publication_series
  AS PERMISSIVE FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM members m
      WHERE m.auth_id = (SELECT auth.uid())
        AND m.is_superadmin = true
    )
  );

NOTIFY pgrst, 'reload schema';
