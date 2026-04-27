-- ADR-0055: auth_rls_initplan perf fix — batch 3 (Class D superadmin EXISTS)
--
-- Continuation of ADR-0053+0054. Same `(SELECT auth.uid())` InitPlan wrap.
--
-- Batch 3 scope: 17 policies, Class D pattern:
--   `EXISTS (SELECT 1 FROM members WHERE auth_id = auth.uid() AND is_superadmin = true)`
-- Wrap inner auth.uid() to:
--   `EXISTS (SELECT 1 FROM members WHERE auth_id = (SELECT auth.uid()) AND is_superadmin = true)`
--
-- 16 simple-pattern policies + 1 complex (offboarding_records_select_authorized
-- has 3 EXISTS clauses + 1 rls_can OR — all auth.uid() references wrapped).
--
-- Cumulative ADR-0053+0054+0055: 42/70 (~60%).

-- =====================================================================
-- Class D: superadmin EXISTS pattern (16 simple policies)
-- =====================================================================

DROP POLICY IF EXISTS "Superadmin can read audit log" ON public.admin_audit_log;
CREATE POLICY "Superadmin can read audit log" ON public.admin_audit_log
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true));

DROP POLICY IF EXISTS "board_items_superadmin_all" ON public.board_items;
CREATE POLICY "board_items_superadmin_all" ON public.board_items
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members m
    WHERE m.auth_id = (SELECT auth.uid()) AND m.is_superadmin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.members m
    WHERE m.auth_id = (SELECT auth.uid()) AND m.is_superadmin = true));

DROP POLICY IF EXISTS "admin_manage_certificates" ON public.certificates;
CREATE POLICY "admin_manage_certificates" ON public.certificates
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true));

DROP POLICY IF EXISTS "chapter_registry_write_superadmin" ON public.chapter_registry;
CREATE POLICY "chapter_registry_write_superadmin" ON public.chapter_registry
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true));

DROP POLICY IF EXISTS "chapters_write_superadmin" ON public.chapters;
CREATE POLICY "chapters_write_superadmin" ON public.chapters
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true));

DROP POLICY IF EXISTS "cycles_admin_write" ON public.cycles;
CREATE POLICY "cycles_admin_write" ON public.cycles
  FOR ALL TO public
  USING (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true));

DROP POLICY IF EXISTS "Superadmin can view webhook events" ON public.email_webhook_events;
CREATE POLICY "Superadmin can view webhook events" ON public.email_webhook_events
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true));

DROP POLICY IF EXISTS "admin_manage_points" ON public.gamification_points;
CREATE POLICY "admin_manage_points" ON public.gamification_points
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true));

DROP POLICY IF EXISTS "offboarding_records_delete_superadmin" ON public.member_offboarding_records;
CREATE POLICY "offboarding_records_delete_superadmin" ON public.member_offboarding_records
  FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members m
    WHERE m.auth_id = (SELECT auth.uid()) AND m.is_superadmin = true));

DROP POLICY IF EXISTS "organizations_write_superadmin" ON public.organizations;
CREATE POLICY "organizations_write_superadmin" ON public.organizations
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true));

DROP POLICY IF EXISTS "Superadmin can manage privacy versions" ON public.privacy_policy_versions;
CREATE POLICY "Superadmin can manage privacy versions" ON public.privacy_policy_versions
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true));

DROP POLICY IF EXISTS "project_boards_superadmin_all" ON public.project_boards;
CREATE POLICY "project_boards_superadmin_all" ON public.project_boards
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members m
    WHERE m.auth_id = (SELECT auth.uid()) AND m.is_superadmin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.members m
    WHERE m.auth_id = (SELECT auth.uid()) AND m.is_superadmin = true));

DROP POLICY IF EXISTS "publication_series_superadmin_all" ON public.publication_series;
CREATE POLICY "publication_series_superadmin_all" ON public.publication_series
  FOR ALL TO public
  USING (EXISTS (SELECT 1 FROM public.members m
    WHERE m.auth_id = (SELECT auth.uid()) AND m.is_superadmin = true));

DROP POLICY IF EXISTS "release_items_write_superadmin" ON public.release_items;
CREATE POLICY "release_items_write_superadmin" ON public.release_items
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.members
    WHERE members.auth_id = (SELECT auth.uid()) AND members.is_superadmin = true));

DROP POLICY IF EXISTS "site_config_superadmin_write" ON public.site_config;
CREATE POLICY "site_config_superadmin_write" ON public.site_config
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members m
    WHERE m.auth_id = (SELECT auth.uid()) AND m.is_superadmin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.members m
    WHERE m.auth_id = (SELECT auth.uid()) AND m.is_superadmin = true));

DROP POLICY IF EXISTS "volunteer_applications_superadmin_write" ON public.volunteer_applications;
CREATE POLICY "volunteer_applications_superadmin_write" ON public.volunteer_applications
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.members m
    WHERE m.auth_id = (SELECT auth.uid()) AND m.is_superadmin = true));

-- =====================================================================
-- Complex multi-OR EXISTS (offboarding_records_select_authorized)
-- 4 OR branches: superadmin EXISTS / member-id match EXISTS / offboarder match EXISTS / rls_can()
-- All auth.uid() references wrapped.
-- =====================================================================

DROP POLICY IF EXISTS "offboarding_records_select_authorized" ON public.member_offboarding_records;
CREATE POLICY "offboarding_records_select_authorized" ON public.member_offboarding_records
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.members m
      WHERE m.auth_id = (SELECT auth.uid()) AND m.is_superadmin = true)
    OR EXISTS (SELECT 1 FROM public.members m
      WHERE m.id = member_offboarding_records.member_id
        AND m.auth_id = (SELECT auth.uid()))
    OR EXISTS (SELECT 1 FROM public.members m
      WHERE m.id = member_offboarding_records.offboarded_by
        AND m.auth_id = (SELECT auth.uid()))
    OR rls_can('manage_member'::text)
  );

NOTIFY pgrst, 'reload schema';
