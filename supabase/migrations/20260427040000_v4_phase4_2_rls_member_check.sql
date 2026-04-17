-- ============================================================================
-- V4 Phase 4.2 — RLS MEMBER_CHECK decoupling from legacy get_my_member_record()
--
-- Context:
-- Fase 4 (20260415010000) + Fase 4.1 (20260427030000) closed role-gating drift.
-- Remaining debt: 23 SELECT policies still destructure `get_my_member_record()`
-- for pure existence checks ("is current auth.uid() a member?"). This is not
-- an ADR-0007 violation (no role gate), but is structural coupling to the
-- legacy function and makes the RLS layer brittle.
--
-- `get_my_member_record()` retains 70 RPC callers (counted 2026-04-17) and
-- cannot be dropped in this scope. This migration ONLY decouples RLS policies.
--
-- Scope: 23 policies across 22 tables.
-- • 20 MEMBER_CHECK_ONLY  → rls_is_member()
-- • 2 GHOST_CHECK         → NOT rls_is_member()
-- • 1 ROLE_GATE missed in Fase 4.1 (broadcast_log_read_admin) → V4 helpers
--
-- New helper: rls_is_member() — STABLE SECURITY DEFINER EXISTS-check against
-- public.members. Mirrors the shape of rls_is_superadmin() for consistency.
--
-- ADR: ADR-0007 (Authority derivation), ADR-0011 (V4 Auth Pattern)
-- Contract test: tests/contracts/rls-v4-phase4-2.test.mjs
-- Rollback: DROP FUNCTION public.rls_is_member();
--           Restore prior policies via originals section at bottom.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- Helper: rls_is_member()
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.rls_is_member()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid()
  );
$$;

COMMENT ON FUNCTION public.rls_is_member() IS 'V4 RLS helper: checks if current auth.uid() has a member record. Replaces get_my_member_record() destructure pattern in RLS SELECT policies (ADR-0011 Fase 4.2). STABLE = evaluated once per statement.';

GRANT EXECUTE ON FUNCTION public.rls_is_member() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- Category A: Pure MEMBER_CHECK policies (20)
-- Legacy: EXISTS (SELECT 1 FROM get_my_member_record())
-- V4: public.rls_is_member()
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "attendance_read_members" ON public.attendance;
CREATE POLICY "attendance_read_members" ON public.attendance FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "assignments_read_members" ON public.board_item_assignments;
CREATE POLICY "assignments_read_members" ON public.board_item_assignments FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "checklists_read_members" ON public.board_item_checklists;
CREATE POLICY "checklists_read_members" ON public.board_item_checklists FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "tag_assignments_read_members" ON public.board_item_tag_assignments;
CREATE POLICY "tag_assignments_read_members" ON public.board_item_tag_assignments FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "board_items_read_members" ON public.board_items;
CREATE POLICY "board_items_read_members" ON public.board_items FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "cr_read_members" ON public.change_requests;
CREATE POLICY "cr_read_members" ON public.change_requests FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "course_progress_read_members" ON public.course_progress;
CREATE POLICY "course_progress_read_members" ON public.course_progress FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "audience_rules_read_members" ON public.event_audience_rules;
CREATE POLICY "audience_rules_read_members" ON public.event_audience_rules FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "invited_read_members" ON public.event_invited_members;
CREATE POLICY "invited_read_members" ON public.event_invited_members FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "event_tags_read_members" ON public.event_tag_assignments;
CREATE POLICY "event_tags_read_members" ON public.event_tag_assignments FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "events_read_members" ON public.events;
CREATE POLICY "events_read_members" ON public.events FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "gamification_read_members" ON public.gamification_points;
CREATE POLICY "gamification_read_members" ON public.gamification_points FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "members_read_by_members" ON public.members;
CREATE POLICY "members_read_by_members" ON public.members FOR SELECT TO authenticated
  USING (is_active = true AND public.rls_is_member());

DROP POLICY IF EXISTS "partners_read_members" ON public.partner_entities;
CREATE POLICY "partners_read_members" ON public.partner_entities FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "project_boards_read_members" ON public.project_boards;
CREATE POLICY "project_boards_read_members" ON public.project_boards FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "sub_authors_read_members" ON public.publication_submission_authors;
CREATE POLICY "sub_authors_read_members" ON public.publication_submission_authors FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "sub_events_read_members" ON public.publication_submission_events;
CREATE POLICY "sub_events_read_members" ON public.publication_submission_events FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "submissions_read_members" ON public.publication_submissions;
CREATE POLICY "submissions_read_members" ON public.publication_submissions FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "wle_read_members" ON public.webinar_lifecycle_events;
CREATE POLICY "wle_read_members" ON public.webinar_lifecycle_events FOR SELECT TO authenticated
  USING (public.rls_is_member());

DROP POLICY IF EXISTS "webinars_read_members" ON public.webinars;
CREATE POLICY "webinars_read_members" ON public.webinars FOR SELECT TO authenticated
  USING (public.rls_is_member());

-- ═══════════════════════════════════════════════════════════════════════════
-- Category B: GHOST_CHECK (2 policies)
-- Legacy: NOT EXISTS (SELECT 1 FROM get_my_member_record()) AND ...
-- V4: NOT public.rls_is_member() AND ...
-- Semantics: unauthenticated/ghost users see limited public rows
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "events_read_ghost" ON public.events;
CREATE POLICY "events_read_ghost" ON public.events FOR SELECT TO authenticated
  USING (
    NOT public.rls_is_member()
    AND type = ANY (ARRAY['geral'::text, 'webinar'::text])
  );

DROP POLICY IF EXISTS "webinars_read_ghost" ON public.webinars;
CREATE POLICY "webinars_read_ghost" ON public.webinars FOR SELECT TO authenticated
  USING (
    NOT public.rls_is_member()
    AND status = ANY (ARRAY['confirmed'::text, 'completed'::text])
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- Category C: Fase 4.1 miss — broadcast_log_read_admin (1 policy)
-- This was a ROLE_GATE that my earlier regex missed due to newline/paren
-- placement between operational_role and =ANY. Fixing inline.
-- Legacy: is_superadmin OR operational_role IN (manager, deputy_manager)
-- V4: rls_is_superadmin() OR rls_can('manage_member')
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "broadcast_log_read_admin" ON public.broadcast_log;
CREATE POLICY "broadcast_log_read_admin" ON public.broadcast_log FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLLBACK: Original policy definitions (copy-paste to restore)
-- ═══════════════════════════════════════════════════════════════════════════
/*
-- DROP FUNCTION public.rls_is_member();

-- Category A: MEMBER_CHECK (20 — all same pattern)
CREATE POLICY "attendance_read_members" ON attendance FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record() get_my_member_record(id, tribe_id, operational_role, is_superadmin, designations)));
-- (repeat for the other 19 with same EXISTS pattern; add (is_active = true) AND ... for members_read_by_members)

-- Category B: GHOST_CHECK (2)
CREATE POLICY "events_read_ghost" ON events FOR SELECT TO authenticated USING ((NOT (EXISTS (SELECT 1 FROM get_my_member_record() get_my_member_record(id, tribe_id, operational_role, is_superadmin, designations)))) AND (type = ANY (ARRAY['geral','webinar'])));
CREATE POLICY "webinars_read_ghost" ON webinars FOR SELECT TO authenticated USING ((NOT (EXISTS (SELECT 1 FROM get_my_member_record() get_my_member_record(id, tribe_id, operational_role, is_superadmin, designations)))) AND (status = ANY (ARRAY['confirmed','completed'])));

-- Category C: ROLE_GATE miss
CREATE POLICY "broadcast_log_read_admin" ON broadcast_log FOR SELECT TO authenticated USING (((SELECT get_my_member_record.is_superadmin FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = true) OR ((SELECT get_my_member_record.operational_role FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = ANY (ARRAY['manager','deputy_manager'])));
*/
