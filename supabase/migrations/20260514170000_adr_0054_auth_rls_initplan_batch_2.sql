-- ADR-0054: auth_rls_initplan perf fix — batch 2 (#82 P1)
--
-- Continuation of ADR-0053. Same InitPlan wrap pattern:
--   `auth.uid()` → `(SELECT auth.uid())`
--
-- Batch 2 scope: 12 policies across 8 tables. Two pattern classes:
--   * Class B: `(auth.uid() IS NOT NULL)` (existence check) — 2 policies
--   * Class C: `WHERE auth_id = auth.uid()` inside subquery — 6 policies
--   * Class A continuation: simple `(auth_id = auth.uid())` — 4 policies on members
--
-- All preserve role grants (mix of `authenticated` and `public`).
--
-- Out of scope (deferred to ADR-0055+):
--   * Class D: superadmin EXISTS subqueries (~15 policies)
--   * Class E: can_by_member/rls_can with subquery member-id (~10 policies)
--   * Class F: multi-clause OR with helper-call composition (~12 policies)

-- =====================================================================
-- members (4 policies, authenticated, simple `(auth_id = auth.uid())`)
-- =====================================================================

DROP POLICY IF EXISTS "Members can update own notification preferences" ON public.members;
CREATE POLICY "Members can update own notification preferences" ON public.members
  FOR UPDATE TO authenticated
  USING (auth_id = (SELECT auth.uid()))
  WITH CHECK (auth_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "member_update_own_profile" ON public.members;
CREATE POLICY "member_update_own_profile" ON public.members
  FOR UPDATE TO authenticated
  USING (auth_id = (SELECT auth.uid()))
  WITH CHECK (auth_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "members_select_own" ON public.members;
CREATE POLICY "members_select_own" ON public.members
  FOR SELECT TO authenticated
  USING (auth_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "members_update_own" ON public.members;
CREATE POLICY "members_update_own" ON public.members
  FOR UPDATE TO authenticated
  USING (auth_id = (SELECT auth.uid()))
  WITH CHECK (auth_id = (SELECT auth.uid()));

-- =====================================================================
-- change_requests (1 policy, public role, IS NOT NULL pattern)
-- =====================================================================

DROP POLICY IF EXISTS "Auth create CRs" ON public.change_requests;
CREATE POLICY "Auth create CRs" ON public.change_requests
  FOR INSERT TO public
  WITH CHECK ((SELECT auth.uid()) IS NOT NULL);

-- =====================================================================
-- webinar_lifecycle_events (1 policy, authenticated, IS NOT NULL pattern)
-- =====================================================================

DROP POLICY IF EXISTS "wle_insert" ON public.webinar_lifecycle_events;
CREATE POLICY "wle_insert" ON public.webinar_lifecycle_events
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) IS NOT NULL);

-- =====================================================================
-- notification_preferences (1 policy, authenticated, ALL with qual only)
-- =====================================================================

DROP POLICY IF EXISTS "notifpref_own" ON public.notification_preferences;
CREATE POLICY "notifpref_own" ON public.notification_preferences
  FOR ALL TO authenticated
  USING (member_id = (SELECT members.id FROM public.members WHERE members.auth_id = (SELECT auth.uid())));

-- =====================================================================
-- notifications (1 policy, authenticated, SELECT only)
-- =====================================================================

DROP POLICY IF EXISTS "notif_select_own" ON public.notifications;
CREATE POLICY "notif_select_own" ON public.notifications
  FOR SELECT TO authenticated
  USING (recipient_id = (SELECT members.id FROM public.members WHERE members.auth_id = (SELECT auth.uid())));

-- =====================================================================
-- course_progress (1 policy, authenticated, ALL with qual + with_check)
-- =====================================================================

DROP POLICY IF EXISTS "Auth update progress" ON public.course_progress;
CREATE POLICY "Auth update progress" ON public.course_progress
  FOR ALL TO authenticated
  USING (member_id IN (SELECT members.id FROM public.members WHERE members.auth_id = (SELECT auth.uid())))
  WITH CHECK (member_id IN (SELECT members.id FROM public.members WHERE members.auth_id = (SELECT auth.uid())));

-- =====================================================================
-- tribe_selections (2 policies, public role, IN subquery pattern)
-- =====================================================================

DROP POLICY IF EXISTS "Auth insert selection" ON public.tribe_selections;
CREATE POLICY "Auth insert selection" ON public.tribe_selections
  FOR INSERT TO public
  WITH CHECK (member_id IN (SELECT members.id FROM public.members WHERE members.auth_id = (SELECT auth.uid())));

DROP POLICY IF EXISTS "Auth update selection" ON public.tribe_selections;
CREATE POLICY "Auth update selection" ON public.tribe_selections
  FOR UPDATE TO public
  USING (member_id IN (SELECT members.id FROM public.members WHERE members.auth_id = (SELECT auth.uid())));

-- =====================================================================
-- member_document_signatures (1 policy, authenticated, INSERT with check)
-- =====================================================================

DROP POLICY IF EXISTS "member_doc_sigs_insert_self_or_rpc" ON public.member_document_signatures;
CREATE POLICY "member_doc_sigs_insert_self_or_rpc" ON public.member_document_signatures
  FOR INSERT TO authenticated
  WITH CHECK (member_id IN (SELECT members.id FROM public.members WHERE members.auth_id = (SELECT auth.uid())));

NOTIFY pgrst, 'reload schema';
