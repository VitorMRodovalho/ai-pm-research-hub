-- ============================================================================
-- V4 Phase 4.1 — RLS legacy policy sweep (ADR-0007 / ADR-0011 compliance)
--
-- Context:
-- Phase 4 (migration 20260415010000) rewrote 36 direct-query policies covering
-- 24 tables. A subsequent audit (17/Abr p4 guardian) flagged additional policies
-- still referencing `members.operational_role` as auth gate. A full sweep
-- (2026-04-17) counted 42 role-gating policies remaining — a much broader
-- drift than the sample originally surfaced.
--
-- Scope: 42 policies across 27 tables. Strategy mirrors Phase 4:
-- • Admin-only           → rls_is_superadmin() OR rls_can('manage_member')
-- • Leader-level         → rls_is_superadmin() OR rls_can('write')
-- • Tribe-scoped         → rls_is_superadmin() OR rls_can_for_tribe(action, tribe_id)
-- • Stakeholder / sponsor → rls_is_superadmin() OR rls_can('manage_partner')
-- • Curator-adjacent     → rls_is_superadmin() OR rls_can('write_board')
-- • Superadmin-only      → rls_is_superadmin()
--
-- Designations (`comms_member`, `sponsor`, `curator`) are preserved inline
-- where no engagement role maps directly (2 users depend on `comms_member`).
-- Designation cleanup tracked as Fase 4.2 (separate session).
--
-- ADR: ADR-0007 (Authority as Derived Grant), ADR-0011 (V4 Auth Pattern)
-- Contract test: tests/contracts/rls-v4-phase4-1.test.mjs
-- Rollback: See bottom of file for original policy definitions.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY A: Superadmin-only policies (6 policies)
-- Legacy: SELECT r.is_superadmin FROM get_my_member_record() r(...operational_role...)
-- V4: rls_is_superadmin()
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "admin_links_delete" ON public.admin_links;
CREATE POLICY "admin_links_delete" ON public.admin_links FOR DELETE TO authenticated
  USING (public.rls_is_superadmin());

DROP POLICY IF EXISTS "admin_links_insert" ON public.admin_links;
CREATE POLICY "admin_links_insert" ON public.admin_links FOR INSERT TO authenticated
  WITH CHECK (public.rls_is_superadmin());

DROP POLICY IF EXISTS "admin_links_update" ON public.admin_links;
CREATE POLICY "admin_links_update" ON public.admin_links FOR UPDATE TO authenticated
  USING (public.rls_is_superadmin());

DROP POLICY IF EXISTS "templates_manage" ON public.communication_templates;
CREATE POLICY "templates_manage" ON public.communication_templates FOR ALL TO authenticated
  USING (public.rls_is_superadmin());

DROP POLICY IF EXISTS "taxonomy_tags_manage" ON public.taxonomy_tags;
CREATE POLICY "taxonomy_tags_manage" ON public.taxonomy_tags FOR ALL TO authenticated
  USING (public.rls_is_superadmin());

DROP POLICY IF EXISTS "webinars_delete" ON public.webinars;
CREATE POLICY "webinars_delete" ON public.webinars FOR DELETE TO authenticated
  USING (public.rls_is_superadmin());

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY B: Admin + co_gp (is_superadmin OR manager/deputy_manager [+ co_gp]) (14 policies)
-- V4: rls_is_superadmin() OR rls_can('manage_member')
-- manage_member covers: manager, deputy_manager, co_gp
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "admin_links_select" ON public.admin_links;
CREATE POLICY "admin_links_select" ON public.admin_links FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "members_insert_admin" ON public.members;
CREATE POLICY "members_insert_admin" ON public.members FOR INSERT TO authenticated
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "members_select_admin" ON public.members;
CREATE POLICY "members_select_admin" ON public.members FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "members_update_admin" ON public.members;
CREATE POLICY "members_update_admin" ON public.members FOR UPDATE TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "members_delete_superadmin" ON public.members;
CREATE POLICY "members_delete_superadmin" ON public.members FOR DELETE TO authenticated
  USING (public.rls_is_superadmin());

DROP POLICY IF EXISTS "project_memberships_write" ON public.project_memberships;
CREATE POLICY "project_memberships_write" ON public.project_memberships FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "Admins can insert pilots" ON public.pilots;
CREATE POLICY "Admins can insert pilots" ON public.pilots FOR INSERT TO authenticated
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "vep_opportunities_insert_admin" ON public.vep_opportunities;
CREATE POLICY "vep_opportunities_insert_admin" ON public.vep_opportunities FOR INSERT TO authenticated
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "trello_import_log_admin" ON public.trello_import_log;
CREATE POLICY "trello_import_log_admin" ON public.trello_import_log FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "data_quality_audit_snapshots_write_mgmt" ON public.data_quality_audit_snapshots;
CREATE POLICY "data_quality_audit_snapshots_write_mgmt" ON public.data_quality_audit_snapshots FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "ingestion_remediation_escalation_write_mgmt" ON public.ingestion_remediation_escalation_matrix;
CREATE POLICY "ingestion_remediation_escalation_write_mgmt" ON public.ingestion_remediation_escalation_matrix FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "ingestion_source_controls_read_mgmt" ON public.ingestion_source_controls;
CREATE POLICY "ingestion_source_controls_read_mgmt" ON public.ingestion_source_controls FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "ingestion_source_controls_write_mgmt" ON public.ingestion_source_controls;
CREATE POLICY "ingestion_source_controls_write_mgmt" ON public.ingestion_source_controls FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "ingestion_source_sla_write_mgmt" ON public.ingestion_source_sla;
CREATE POLICY "ingestion_source_sla_write_mgmt" ON public.ingestion_source_sla FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "tribe_continuity_overrides_write_mgmt" ON public.tribe_continuity_overrides;
CREATE POLICY "tribe_continuity_overrides_write_mgmt" ON public.tribe_continuity_overrides FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "tribe_lineage_write_mgmt" ON public.tribe_lineage;
CREATE POLICY "tribe_lineage_write_mgmt" ON public.tribe_lineage FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "release_readiness_policies_write_mgmt" ON public.release_readiness_policies;
CREATE POLICY "release_readiness_policies_write_mgmt" ON public.release_readiness_policies FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

DROP POLICY IF EXISTS "webinars_insert_v2" ON public.webinars;
CREATE POLICY "webinars_insert_v2" ON public.webinars FOR INSERT TO authenticated
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY C: Admin + chapter_liaison/sponsor (Cat B tables with extra designations)
-- V4: rls_is_superadmin() OR rls_can('manage_member') OR rls_can('manage_partner')
-- manage_partner covers: sponsor, chapter_liaison, manager, deputy_manager, co_gp
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "data_quality_audit_snapshots_read_mgmt" ON public.data_quality_audit_snapshots;
CREATE POLICY "data_quality_audit_snapshots_read_mgmt" ON public.data_quality_audit_snapshots FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member') OR public.rls_can('manage_partner'));

DROP POLICY IF EXISTS "ingestion_remediation_escalation_read_mgmt" ON public.ingestion_remediation_escalation_matrix;
CREATE POLICY "ingestion_remediation_escalation_read_mgmt" ON public.ingestion_remediation_escalation_matrix FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member') OR public.rls_can('manage_partner'));

DROP POLICY IF EXISTS "ingestion_source_sla_read_mgmt" ON public.ingestion_source_sla;
CREATE POLICY "ingestion_source_sla_read_mgmt" ON public.ingestion_source_sla FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member') OR public.rls_can('manage_partner'));

DROP POLICY IF EXISTS "release_readiness_policies_read_mgmt" ON public.release_readiness_policies;
CREATE POLICY "release_readiness_policies_read_mgmt" ON public.release_readiness_policies FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member') OR public.rls_can('manage_partner'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY D: Leader-level (manager/deputy/tribe_leader) (6 policies)
-- V4: rls_is_superadmin() OR rls_can('write')
-- write covers: manager, deputy_manager, co_gp, leader, comms_leader
-- Change: adds co_gp + comms_leader (intentional per ADR-0007)
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "assignments_write_leaders" ON public.board_item_assignments;
CREATE POLICY "assignments_write_leaders" ON public.board_item_assignments FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

DROP POLICY IF EXISTS "checklists_write_leaders" ON public.board_item_checklists;
CREATE POLICY "checklists_write_leaders" ON public.board_item_checklists FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

DROP POLICY IF EXISTS "tag_assignments_write_leaders" ON public.board_item_tag_assignments;
CREATE POLICY "tag_assignments_write_leaders" ON public.board_item_tag_assignments FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

DROP POLICY IF EXISTS "audience_rules_manage_leaders" ON public.event_audience_rules;
CREATE POLICY "audience_rules_manage_leaders" ON public.event_audience_rules FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

DROP POLICY IF EXISTS "invited_manage_leaders" ON public.event_invited_members;
CREATE POLICY "invited_manage_leaders" ON public.event_invited_members FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

DROP POLICY IF EXISTS "event_tags_manage_leaders" ON public.event_tag_assignments;
CREATE POLICY "event_tags_manage_leaders" ON public.event_tag_assignments FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY E: Lifecycle (manager/deputy + co_gp/tribe_leader designations) (2 policies)
-- V4: rls_is_superadmin() OR rls_can('write')
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "board_lifecycle_events_read_mgmt" ON public.board_lifecycle_events;
CREATE POLICY "board_lifecycle_events_read_mgmt" ON public.board_lifecycle_events FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

DROP POLICY IF EXISTS "board_lifecycle_events_write_mgmt" ON public.board_lifecycle_events;
CREATE POLICY "board_lifecycle_events_write_mgmt" ON public.board_lifecycle_events FOR INSERT TO authenticated
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('write'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY F: Admin/tribe_leader SELECT (1 policy)
-- V4: rls_is_superadmin() OR rls_can('write')
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "templates_select" ON public.communication_templates;
CREATE POLICY "templates_select" ON public.communication_templates FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY G: Tribe-scoped (4 policies)
-- V4: rls_is_superadmin() OR rls_can_for_tribe(action, tribe_id)
-- ═══════════════════════════════════════════════════════════════════════════

-- broadcast_log: tribe leader reads own tribe's broadcasts
DROP POLICY IF EXISTS "broadcast_log_read_tribe_leader" ON public.broadcast_log;
CREATE POLICY "broadcast_log_read_tribe_leader" ON public.broadcast_log FOR SELECT TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can_for_tribe('write', broadcast_log.tribe_id)
  );

-- meeting_artifacts: admin + tribe leader of own tribe
DROP POLICY IF EXISTS "meeting_artifacts_manage" ON public.meeting_artifacts;
CREATE POLICY "meeting_artifacts_manage" ON public.meeting_artifacts FOR ALL TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR public.rls_can_for_tribe('write', meeting_artifacts.tribe_id)
  );

-- meeting_artifacts: SELECT — published OR admin OR any leader
DROP POLICY IF EXISTS "meeting_artifacts_select" ON public.meeting_artifacts;
CREATE POLICY "meeting_artifacts_select" ON public.meeting_artifacts FOR SELECT TO authenticated
  USING (
    is_published = true
    OR public.rls_is_superadmin()
    OR public.rls_can('write')
  );

-- members.tribe_id: tribe leader sees members of their tribe
DROP POLICY IF EXISTS "members_select_tribe_leader" ON public.members;
CREATE POLICY "members_select_tribe_leader" ON public.members FOR SELECT TO authenticated
  USING (
    members.tribe_id IS NOT NULL
    AND public.rls_can_for_tribe('write', members.tribe_id)
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY H: Sponsor-specific (1 policy)
-- V4: rls_is_superadmin() OR rls_can('manage_partner')
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "cr_approvals_insert_sponsors" ON public.cr_approvals;
CREATE POLICY "cr_approvals_insert_sponsors" ON public.cr_approvals FOR INSERT TO authenticated
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_partner'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY I: Stakeholder designation (sponsor/chapter_liaison) (1 policy)
-- V4: rls_can('manage_partner')
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "members_select_stakeholder" ON public.members;
CREATE POLICY "members_select_stakeholder" ON public.members FOR SELECT TO authenticated
  USING (public.rls_can('manage_partner'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY J: Curation (admin + curator/co_gp) (1 policy)
-- V4: rls_is_superadmin() OR rls_can('manage_member') OR rls_can('write_board')
-- write_board covers curator
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "curation_review_log_write" ON public.curation_review_log;
CREATE POLICY "curation_review_log_write" ON public.curation_review_log FOR INSERT TO authenticated
  WITH CHECK (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR public.rls_can('write_board')
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY K: Selection snapshots (admin + sponsor/curator) (2 policies)
-- V4: rls_is_superadmin() OR rls_can('manage_member') OR rls_can('manage_partner') OR rls_can('write_board')
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "admin_read_membership_snapshots" ON public.selection_membership_snapshots;
CREATE POLICY "admin_read_membership_snapshots" ON public.selection_membership_snapshots FOR SELECT TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR public.rls_can('manage_partner')
    OR public.rls_can('write_board')
  );

DROP POLICY IF EXISTS "admin_read_selection_rankings" ON public.selection_ranking_snapshots;
CREATE POLICY "admin_read_selection_rankings" ON public.selection_ranking_snapshots FOR SELECT TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR public.rls_can('manage_partner')
    OR public.rls_can('write_board')
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY L: Comms (admin + comms_leader + comms_member designation) (4 policies)
-- V4: rls_is_superadmin() OR rls_can('manage_member') OR rls_can('write')
-- write covers comms_leader. comms_member designation preserved inline
-- (no V4 role mapping yet — 2 active users depend on it). Fase 4.2 cleanup.
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "comms_media_items_read" ON public.comms_media_items;
CREATE POLICY "comms_media_items_read" ON public.comms_media_items FOR SELECT TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR public.rls_can('write')
    OR EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND 'comms_member' = ANY(COALESCE(m.designations, '{}'))
    )
  );

DROP POLICY IF EXISTS "comms_media_items_write" ON public.comms_media_items;
CREATE POLICY "comms_media_items_write" ON public.comms_media_items FOR ALL TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR public.rls_can('write')
  );

DROP POLICY IF EXISTS "comms_token_alerts_admin" ON public.comms_token_alerts;
CREATE POLICY "comms_token_alerts_admin" ON public.comms_token_alerts FOR ALL TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR public.rls_can('write')
  );

DROP POLICY IF EXISTS "comms_metrics_admin_read" ON public.comms_metrics_daily;
CREATE POLICY "comms_metrics_admin_read" ON public.comms_metrics_daily FOR SELECT TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR public.rls_can('write')
    OR EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND 'comms_member' = ANY(COALESCE(m.designations, '{}'))
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY M: Webinars UPDATE (organizer/co-manager + admin) (1 policy)
-- V4: organizer check inline + rls_is_superadmin() OR rls_can('manage_member')
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "webinars_update_v2" ON public.webinars;
CREATE POLICY "webinars_update_v2" ON public.webinars FOR UPDATE TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR webinars.organizer_id = (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1)
    OR (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1) = ANY(webinars.co_manager_ids)
  );

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLLBACK: Original policy definitions (copy-paste to restore)
-- ═══════════════════════════════════════════════════════════════════════════
/*
-- CATEGORY A: Superadmin-only (via get_my_member_record destructure)
CREATE POLICY "admin_links_delete" ON admin_links FOR DELETE TO authenticated USING ((SELECT r.is_superadmin FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations)));
CREATE POLICY "admin_links_insert" ON admin_links FOR INSERT TO authenticated WITH CHECK ((SELECT r.is_superadmin FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations)));
CREATE POLICY "admin_links_update" ON admin_links FOR UPDATE TO authenticated USING ((SELECT r.is_superadmin FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations)));
CREATE POLICY "templates_manage" ON communication_templates FOR ALL TO authenticated USING ((SELECT r.is_superadmin FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations)));
CREATE POLICY "taxonomy_tags_manage" ON taxonomy_tags FOR ALL TO authenticated USING ((SELECT r.is_superadmin FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations)));
CREATE POLICY "webinars_delete" ON webinars FOR DELETE TO authenticated USING ((SELECT r.is_superadmin FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations)));

-- CATEGORY B: Admin + co_gp
CREATE POLICY "admin_links_select" ON admin_links FOR SELECT TO authenticated USING ((SELECT (r.is_superadmin OR r.operational_role = ANY(ARRAY['manager','deputy_manager','co_gp'])) FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations)));
CREATE POLICY "members_insert_admin" ON members FOR INSERT TO authenticated WITH CHECK (((SELECT is_superadmin FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = true) OR ((SELECT operational_role FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = ANY(ARRAY['manager','deputy_manager'])));
CREATE POLICY "members_select_admin" ON members FOR SELECT TO authenticated USING (((SELECT is_superadmin FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = true) OR ((SELECT operational_role FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = ANY(ARRAY['manager','deputy_manager'])));
CREATE POLICY "members_update_admin" ON members FOR UPDATE TO authenticated USING (((SELECT is_superadmin FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = true) OR ((SELECT operational_role FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = ANY(ARRAY['manager','deputy_manager']))) WITH CHECK (((SELECT is_superadmin FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = true) OR ((SELECT operational_role FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = ANY(ARRAY['manager','deputy_manager'])));
CREATE POLICY "members_delete_superadmin" ON members FOR DELETE TO authenticated USING ((SELECT is_superadmin FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)) = true);
CREATE POLICY "project_memberships_write" ON project_memberships FOR ALL TO authenticated USING (EXISTS(SELECT 1 FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations) WHERE r.is_superadmin IS TRUE OR r.operational_role = ANY(ARRAY['manager','deputy_manager']))) WITH CHECK (EXISTS(SELECT 1 FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations) WHERE r.is_superadmin IS TRUE OR r.operational_role = ANY(ARRAY['manager','deputy_manager'])));
CREATE POLICY "Admins can insert pilots" ON pilots FOR INSERT TO authenticated WITH CHECK (EXISTS(SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY(ARRAY['manager','deputy_manager']))));
CREATE POLICY "vep_opportunities_insert_admin" ON vep_opportunities FOR INSERT TO public WITH CHECK (EXISTS(SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.is_superadmin OR members.operational_role = ANY(ARRAY['manager','deputy_manager']))));
CREATE POLICY "trello_import_log_admin" ON trello_import_log FOR ALL TO authenticated USING ((SELECT (r.is_superadmin OR r.operational_role = ANY(ARRAY['manager','deputy_manager'])) FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations)));
CREATE POLICY "data_quality_audit_snapshots_write_mgmt" ON data_quality_audit_snapshots FOR ALL TO authenticated USING (EXISTS(SELECT 1 FROM get_my_member_record() r(...) WHERE r.is_superadmin OR r.operational_role = ANY(ARRAY['manager','deputy_manager']) OR 'co_gp' = ANY(r.designations)));
CREATE POLICY "ingestion_remediation_escalation_write_mgmt" ON ingestion_remediation_escalation_matrix FOR ALL TO authenticated USING (...);
CREATE POLICY "ingestion_source_controls_read_mgmt" ON ingestion_source_controls FOR SELECT TO authenticated USING (...);
CREATE POLICY "ingestion_source_controls_write_mgmt" ON ingestion_source_controls FOR ALL TO authenticated USING (...);
CREATE POLICY "ingestion_source_sla_write_mgmt" ON ingestion_source_sla FOR ALL TO authenticated USING (...);
CREATE POLICY "tribe_continuity_overrides_write_mgmt" ON tribe_continuity_overrides FOR ALL TO authenticated USING (...);
CREATE POLICY "tribe_lineage_write_mgmt" ON tribe_lineage FOR ALL TO authenticated USING (...);
CREATE POLICY "release_readiness_policies_write_mgmt" ON release_readiness_policies FOR ALL TO authenticated USING (...);
CREATE POLICY "webinars_insert_v2" ON webinars FOR INSERT TO authenticated WITH CHECK ((SELECT (operational_role = ANY(ARRAY['manager','deputy_manager']) OR is_superadmin) FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)));

-- CATEGORY C: Admin + chapter_liaison/sponsor
CREATE POLICY "data_quality_audit_snapshots_read_mgmt" ON data_quality_audit_snapshots FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM get_my_member_record() r(...) WHERE r.is_superadmin OR r.operational_role = ANY(ARRAY['manager','deputy_manager']) OR 'co_gp' = ANY(r.designations) OR 'chapter_liaison' = ANY(r.designations)));
CREATE POLICY "ingestion_remediation_escalation_read_mgmt" ON ingestion_remediation_escalation_matrix FOR SELECT TO authenticated USING (...);
CREATE POLICY "ingestion_source_sla_read_mgmt" ON ingestion_source_sla FOR SELECT TO authenticated USING (...);
CREATE POLICY "release_readiness_policies_read_mgmt" ON release_readiness_policies FOR SELECT TO authenticated USING (...);

-- CATEGORY D: Leader-level
CREATE POLICY "assignments_write_leaders" ON board_item_assignments FOR ALL TO authenticated USING (EXISTS(SELECT 1 FROM get_my_member_record() r(...) WHERE r.is_superadmin OR r.operational_role = ANY(ARRAY['manager','deputy_manager','tribe_leader'])));
-- (similar for checklists_write_leaders, tag_assignments_write_leaders, audience_rules_manage_leaders, invited_manage_leaders, event_tags_manage_leaders)

-- CATEGORY E: Lifecycle
CREATE POLICY "board_lifecycle_events_read_mgmt" ON board_lifecycle_events FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM get_my_member_record() r(...) WHERE r.is_superadmin OR r.operational_role = ANY(ARRAY['manager','deputy_manager']) OR 'co_gp' = ANY(r.designations) OR 'tribe_leader' = ANY(r.designations)));
CREATE POLICY "board_lifecycle_events_write_mgmt" ON board_lifecycle_events FOR INSERT TO authenticated WITH CHECK (...);

-- CATEGORY F: Admin/tribe_leader SELECT
CREATE POLICY "templates_select" ON communication_templates FOR SELECT TO authenticated USING ((SELECT (r.operational_role = ANY(ARRAY['manager','deputy_manager','tribe_leader']) OR r.is_superadmin) FROM get_my_member_record() r(id, tribe_id, operational_role, is_superadmin, designations)));

-- CATEGORY G: Tribe-scoped
CREATE POLICY "broadcast_log_read_tribe_leader" ON broadcast_log FOR SELECT TO authenticated USING (tribe_id = (SELECT g.tribe_id FROM get_my_member_record() g(...) WHERE g.operational_role = 'tribe_leader'));
CREATE POLICY "meeting_artifacts_manage" ON meeting_artifacts FOR ALL TO authenticated USING ((SELECT r.is_superadmin FROM get_my_member_record() r(...)) OR (SELECT r.operational_role = ANY(ARRAY['manager','deputy_manager']) FROM get_my_member_record() r(...)) OR ((SELECT r.operational_role FROM get_my_member_record() r(...)) = 'tribe_leader' AND tribe_id = (SELECT r.tribe_id FROM get_my_member_record() r(...))));
CREATE POLICY "meeting_artifacts_select" ON meeting_artifacts FOR SELECT TO authenticated USING (is_published = true OR (SELECT r.is_superadmin FROM get_my_member_record() r(...)) OR (SELECT r.operational_role = ANY(ARRAY['manager','deputy_manager','tribe_leader']) FROM get_my_member_record() r(...)));
CREATE POLICY "members_select_tribe_leader" ON members FOR SELECT TO authenticated USING (tribe_id IS NOT NULL AND tribe_id = (SELECT g.tribe_id FROM get_my_member_record() g(...) WHERE g.operational_role = 'tribe_leader'));

-- CATEGORY H: Sponsor-specific
CREATE POLICY "cr_approvals_insert_sponsors" ON cr_approvals FOR INSERT TO authenticated WITH CHECK (EXISTS(SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.operational_role = 'sponsor' OR members.is_superadmin)));

-- CATEGORY I: Stakeholder designation
CREATE POLICY "members_select_stakeholder" ON members FOR SELECT TO public USING (EXISTS(SELECT 1 FROM get_my_member_record() g(...) WHERE g.designations && ARRAY['sponsor','chapter_liaison']));

-- CATEGORY J: Curation
CREATE POLICY "curation_review_log_write" ON curation_review_log FOR INSERT TO authenticated WITH CHECK (EXISTS(SELECT 1 FROM get_my_member_record() r(...) WHERE r.is_superadmin OR r.operational_role = ANY(ARRAY['manager','deputy_manager']) OR 'curator' = ANY(r.designations) OR 'co_gp' = ANY(r.designations)));

-- CATEGORY K: Selection
CREATE POLICY "admin_read_membership_snapshots" ON selection_membership_snapshots FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY(ARRAY['manager','deputy_manager']) OR m.designations && ARRAY['sponsor','curator'])));
CREATE POLICY "admin_read_selection_rankings" ON selection_ranking_snapshots FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY(ARRAY['manager','deputy_manager']) OR m.designations && ARRAY['sponsor','curator'])));

-- CATEGORY L: Comms
CREATE POLICY "comms_media_items_read" ON comms_media_items FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.is_superadmin OR members.operational_role = ANY(ARRAY['manager','deputy_manager']) OR members.designations && ARRAY['comms_leader','comms_member'])));
CREATE POLICY "comms_media_items_write" ON comms_media_items FOR ALL TO authenticated USING (EXISTS(SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.is_superadmin OR members.operational_role = ANY(ARRAY['manager','deputy_manager']) OR members.designations && ARRAY['comms_leader'])));
CREATE POLICY "comms_token_alerts_admin" ON comms_token_alerts FOR ALL TO authenticated USING (EXISTS(SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.is_superadmin OR members.operational_role = ANY(ARRAY['manager','deputy_manager']) OR members.designations && ARRAY['comms_leader'])));
CREATE POLICY "comms_metrics_admin_read" ON comms_metrics_daily FOR SELECT TO authenticated USING (((SELECT is_superadmin FROM get_my_member_record() gmr(...)) = true) OR ((SELECT operational_role FROM get_my_member_record() gmr(...)) = ANY(ARRAY['manager','deputy_manager'])) OR ((SELECT designations FROM get_my_member_record() gmr(...)) @> ARRAY['comms_leader']) OR ((SELECT designations FROM get_my_member_record() gmr(...)) @> ARRAY['comms_member']));

-- CATEGORY M: Webinars UPDATE
CREATE POLICY "webinars_update_v2" ON webinars FOR UPDATE TO authenticated USING (((SELECT id FROM get_my_member_record() gmr(...)) = organizer_id) OR ((SELECT id FROM get_my_member_record() gmr(...)) = ANY(co_manager_ids)) OR (SELECT (operational_role = ANY(ARRAY['manager','deputy_manager']) OR is_superadmin) FROM get_my_member_record() gmr(id, tribe_id, operational_role, is_superadmin, designations)));
*/
