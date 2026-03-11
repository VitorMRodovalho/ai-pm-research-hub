-- ============================================================================
-- God Mode: Super Admin bypass absoluto em board_items e project_boards
-- auth.uid() IN (SELECT auth_id FROM members WHERE is_superadmin = true)
-- permite ALL sem restrição de tribe_id
-- Date: 2026-03-15
-- ============================================================================

-- project_boards: Super Admin pode tudo
CREATE POLICY "project_boards_superadmin_all"
  ON public.project_boards
  FOR ALL
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_superadmin = true)
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_superadmin = true)
  );

-- board_items: Super Admin pode tudo
CREATE POLICY "board_items_superadmin_all"
  ON public.board_items
  FOR ALL
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_superadmin = true)
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_superadmin = true)
  );
