-- ADR-0058 batch 3 — split ALL-cmd admin policies into per-cmd policies
-- Class C: each PERMISSIVE policy with cmd=ALL overlapped on SELECT with the
-- existing read policy. Splitting into 3 cmds (INSERT/UPDATE/DELETE) leaves
-- SELECT covered only by read_all, eliminating SELECT overlap.
-- Net policy count: same number of effective grants; -12 mpp WARN (111 → 99).

-- ============================================================================
-- public.cycles
-- ============================================================================

DROP POLICY IF EXISTS cycles_admin_write ON public.cycles;

CREATE POLICY cycles_admin_insert ON public.cycles
  AS PERMISSIVE FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM members
      WHERE members.auth_id = (SELECT auth.uid())
        AND members.is_superadmin = true
    )
  );

CREATE POLICY cycles_admin_update ON public.cycles
  AS PERMISSIVE FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM members
      WHERE members.auth_id = (SELECT auth.uid())
        AND members.is_superadmin = true
    )
  );

CREATE POLICY cycles_admin_delete ON public.cycles
  AS PERMISSIVE FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM members
      WHERE members.auth_id = (SELECT auth.uid())
        AND members.is_superadmin = true
    )
  );

-- ============================================================================
-- public.tribe_deliverables
-- ============================================================================

DROP POLICY IF EXISTS tribe_deliverables_write_v4 ON public.tribe_deliverables;

CREATE POLICY tribe_deliverables_insert_v4 ON public.tribe_deliverables
  AS PERMISSIVE FOR INSERT
  WITH CHECK (
    rls_is_superadmin()
    OR rls_can_for_initiative('write_board'::text, initiative_id)
  );

CREATE POLICY tribe_deliverables_update_v4 ON public.tribe_deliverables
  AS PERMISSIVE FOR UPDATE
  USING (
    rls_is_superadmin()
    OR rls_can_for_initiative('write_board'::text, initiative_id)
  );

CREATE POLICY tribe_deliverables_delete_v4 ON public.tribe_deliverables
  AS PERMISSIVE FOR DELETE
  USING (
    rls_is_superadmin()
    OR rls_can_for_initiative('write_board'::text, initiative_id)
  );

NOTIFY pgrst, 'reload schema';
