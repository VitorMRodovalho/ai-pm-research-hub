-- ADR-0056: auth_rls_initplan perf fix — batch 4 (Class E can_by_member subquery)
--
-- Continuation of ADR-0053+0054+0055. Same `(SELECT auth.uid())` InitPlan wrap.
--
-- Batch 4 scope: 7 policies, Class E pattern (simplest subset):
--   `can_by_member((SELECT m.id FROM members m WHERE m.auth_id = auth.uid()), 'action')`
-- The OUTER `(SELECT m.id ...)` is already wrapped. The INNER `auth.uid()`
-- inside the WHERE is bare. Wrap to:
--   `can_by_member((SELECT m.id FROM members m WHERE m.auth_id = (SELECT auth.uid())), 'action')`
--
-- Note: this creates 2-layer InitPlan caching:
--   Outer SELECT: cached as InitPlan, invokes can_by_member once with member id
--   Inner (SELECT auth.uid()): cached as InitPlan, evaluates auth.uid() once
-- Both layers contribute to the per-row → per-query reduction.
--
-- Class E remaining (~5 more): approval_chains/signoffs cluster has
-- EXISTS+can_by_member compositions (more complex, deferred to ADR-0057).
--
-- Cumulative ADR-0053+0054+0055+0056: 49/70 (~70%).

-- =====================================================================
-- Class E: can_by_member subquery (7 policies, all authenticated)
-- =====================================================================

DROP POLICY IF EXISTS "board_item_event_links_write_manage_event" ON public.board_item_event_links;
CREATE POLICY "board_item_event_links_write_manage_event" ON public.board_item_event_links
  FOR ALL TO authenticated
  USING (can_by_member(
    (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid())),
    'manage_event'::text
  ))
  WITH CHECK (can_by_member(
    (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid())),
    'manage_event'::text
  ));

DROP POLICY IF EXISTS "initiative_kinds_delete_admin" ON public.initiative_kinds;
CREATE POLICY "initiative_kinds_delete_admin" ON public.initiative_kinds
  FOR DELETE TO authenticated
  USING (can_by_member(
    (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid())),
    'write'::text
  ));

DROP POLICY IF EXISTS "initiative_kinds_update_admin" ON public.initiative_kinds;
CREATE POLICY "initiative_kinds_update_admin" ON public.initiative_kinds
  FOR UPDATE TO authenticated
  USING (can_by_member(
    (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid())),
    'write'::text
  ))
  WITH CHECK (can_by_member(
    (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid())),
    'write'::text
  ));

DROP POLICY IF EXISTS "initiative_kinds_write_admin" ON public.initiative_kinds;
CREATE POLICY "initiative_kinds_write_admin" ON public.initiative_kinds
  FOR INSERT TO authenticated
  WITH CHECK (can_by_member(
    (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid())),
    'write'::text
  ));

DROP POLICY IF EXISTS "imp_insert_write" ON public.initiative_member_progress;
CREATE POLICY "imp_insert_write" ON public.initiative_member_progress
  FOR INSERT TO authenticated
  WITH CHECK (can_by_member(
    (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid())),
    'write'::text
  ));

DROP POLICY IF EXISTS "pending_mva_select_manage_platform" ON public.pending_manual_version_approvals;
CREATE POLICY "pending_mva_select_manage_platform" ON public.pending_manual_version_approvals
  FOR SELECT TO authenticated
  USING (can_by_member(
    (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid())),
    'manage_platform'::text
  ));

DROP POLICY IF EXISTS "tribe_kpi_contrib_write_manage_platform" ON public.tribe_kpi_contributions;
CREATE POLICY "tribe_kpi_contrib_write_manage_platform" ON public.tribe_kpi_contributions
  FOR ALL TO authenticated
  USING (can_by_member(
    (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid())),
    'manage_platform'::text
  ))
  WITH CHECK (can_by_member(
    (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid())),
    'manage_platform'::text
  ));

NOTIFY pgrst, 'reload schema';
