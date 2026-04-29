-- Mayanna report (28/Abr p79): "Adicionar atividade não funciona" + tag/assignment errors.
-- Root cause: 4 RLS policies on card-scoped tables (board_item_checklists, board_item_assignments,
-- board_item_tag_assignments, board_lifecycle_events) only accept rls_can('write') — generic write.
-- Mayanna (comms_leader) has write_board=true but write=false. Cards are board-scoped → write_board
-- is the correct authority.
--
-- Fix: extend USING clauses to accept rls_can('write_board') as alternative.
-- Pattern already exists in public_publications policy (write OR write_board).
-- No regression: rls_can('write') still granted; we ADD an alternative.

DROP POLICY IF EXISTS checklists_write_leaders ON public.board_item_checklists;
CREATE POLICY checklists_write_leaders ON public.board_item_checklists
  FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write') OR public.rls_can('write_board'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('write') OR public.rls_can('write_board'));

DROP POLICY IF EXISTS assignments_write_leaders ON public.board_item_assignments;
CREATE POLICY assignments_write_leaders ON public.board_item_assignments
  FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write') OR public.rls_can('write_board'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('write') OR public.rls_can('write_board'));

DROP POLICY IF EXISTS tag_assignments_write_leaders ON public.board_item_tag_assignments;
CREATE POLICY tag_assignments_write_leaders ON public.board_item_tag_assignments
  FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write') OR public.rls_can('write_board'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('write') OR public.rls_can('write_board'));

DROP POLICY IF EXISTS board_lifecycle_events_read_mgmt ON public.board_lifecycle_events;
CREATE POLICY board_lifecycle_events_read_mgmt ON public.board_lifecycle_events
  FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write') OR public.rls_can('write_board'));

NOTIFY pgrst, 'reload schema';
