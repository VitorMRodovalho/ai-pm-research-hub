-- ============================================================================
-- V4 Phase 4 — Migration 7/7: RLS policy rewrite (operational_role → auth_engagements)
-- ADR: ADR-0007 (Authority as Derived Grant from Active Engagements)
-- Scope: 36 direct-query policies across 24 tables
-- Strategy: Replace members.operational_role checks with rls_can()/rls_is_superadmin()
-- Rollback: See bottom of file for original policy definitions
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY 1: Manager-level admin policies (18 policies)
-- Legacy: is_superadmin OR operational_role IN ('manager','deputy_manager')
-- V4: rls_is_superadmin() OR rls_can('manage_member')
-- Change: adds co_gp (intentional — ADR-0007 grants co_gp all admin actions)
-- ═══════════════════════════════════════════════════════════════════════════

-- board_sla_config
DROP POLICY IF EXISTS "Admins can manage SLA config" ON board_sla_config;
CREATE POLICY "Admins can manage SLA config" ON board_sla_config FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- campaign_sends
DROP POLICY IF EXISTS "Admin manages sends" ON campaign_sends;
CREATE POLICY "Admin manages sends" ON campaign_sends FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- chapter_needs (UPDATE only)
DROP POLICY IF EXISTS "chapter_needs_update_admin" ON chapter_needs;
CREATE POLICY "chapter_needs_update_admin" ON chapter_needs FOR UPDATE TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- data_anomaly_log (SELECT)
DROP POLICY IF EXISTS "admin_read_anomalies" ON data_anomaly_log;
CREATE POLICY "admin_read_anomalies" ON data_anomaly_log FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- data_anomaly_log (ALL)
DROP POLICY IF EXISTS "admin_write_anomalies" ON data_anomaly_log;
CREATE POLICY "admin_write_anomalies" ON data_anomaly_log FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- data_retention_policy
DROP POLICY IF EXISTS "admin_only_retention" ON data_retention_policy;
CREATE POLICY "admin_only_retention" ON data_retention_policy FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- help_journeys
DROP POLICY IF EXISTS "Admin manages help journeys" ON help_journeys;
CREATE POLICY "Admin manages help journeys" ON help_journeys FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- ia_pilots
DROP POLICY IF EXISTS "ia_pilots_admin_write" ON ia_pilots;
CREATE POLICY "ia_pilots_admin_write" ON ia_pilots FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- mcp_usage_log (SELECT)
DROP POLICY IF EXISTS "mcp_usage_log_select_admin" ON mcp_usage_log;
CREATE POLICY "mcp_usage_log_select_admin" ON mcp_usage_log FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- pilots (DELETE)
DROP POLICY IF EXISTS "Admins can delete pilots" ON pilots;
CREATE POLICY "Admins can delete pilots" ON pilots FOR DELETE TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- pilots (UPDATE)
DROP POLICY IF EXISTS "Admins can update pilots" ON pilots;
CREATE POLICY "Admins can update pilots" ON pilots FOR UPDATE TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- portfolio_kpi_targets
DROP POLICY IF EXISTS "admin_write_kpi_targets" ON portfolio_kpi_targets;
CREATE POLICY "admin_write_kpi_targets" ON portfolio_kpi_targets FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- tags
DROP POLICY IF EXISTS "Admins can manage tags" ON tags;
CREATE POLICY "Admins can manage tags" ON tags FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- tribes (ALL — admin manage)
DROP POLICY IF EXISTS "Admins manage tribes" ON tribes;
CREATE POLICY "Admins manage tribes" ON tribes FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- vep_opportunities (UPDATE)
DROP POLICY IF EXISTS "vep_opportunities_update_admin" ON vep_opportunities;
CREATE POLICY "vep_opportunities_update_admin" ON vep_opportunities FOR UPDATE TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- visitor_leads (SELECT)
DROP POLICY IF EXISTS "Admin reads leads" ON visitor_leads;
CREATE POLICY "Admin reads leads" ON visitor_leads FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- visitor_leads (UPDATE)
DROP POLICY IF EXISTS "Admin updates leads" ON visitor_leads;
CREATE POLICY "Admin updates leads" ON visitor_leads FOR UPDATE TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY 2: Leader-level operational policies (4 policies)
-- Legacy: is_superadmin OR operational_role IN ('manager','deputy_manager','tribe_leader')
-- V4: rls_is_superadmin() OR rls_can('write')
-- Change: adds co_gp, comms_leader (intentional — these roles have operational write)
-- ═══════════════════════════════════════════════════════════════════════════

-- event_showcases
DROP POLICY IF EXISTS "event_showcases_manage" ON event_showcases;
CREATE POLICY "event_showcases_manage" ON event_showcases FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

-- meeting_action_items (two duplicate policies — consolidate into one)
DROP POLICY IF EXISTS "Admins can manage action items" ON meeting_action_items;
DROP POLICY IF EXISTS "Leaders can manage action items" ON meeting_action_items;
CREATE POLICY "action_items_write_v4" ON meeting_action_items FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

-- member_activity_sessions (SELECT)
DROP POLICY IF EXISTS "Superadmin can view all sessions" ON member_activity_sessions;
CREATE POLICY "activity_sessions_read_admin" ON member_activity_sessions FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY 3: Tribe-scoped policies (5 policies)
-- Legacy: is_superadmin OR manager/deputy/co_gp global OR (tribe_leader AND own tribe)
-- V4: rls_is_superadmin() OR rls_can_for_tribe('write_board', TABLE.tribe_id)
-- rls_can_for_tribe checks org-scoped write_board (manager/deputy/co_gp/leader/curator)
-- AND initiative-scoped write_board (researcher/facilitator/communicator for own tribe)
-- ═══════════════════════════════════════════════════════════════════════════

-- board_items
DROP POLICY IF EXISTS "board_items_write" ON board_items;
CREATE POLICY "board_items_write_v4" ON board_items FOR ALL TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can_for_tribe('write_board', (SELECT pb.tribe_id FROM project_boards pb WHERE pb.id = board_items.board_id))
  );

-- project_boards
DROP POLICY IF EXISTS "project_boards_write" ON project_boards;
CREATE POLICY "project_boards_write_v4" ON project_boards FOR ALL TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can_for_tribe('write_board', project_boards.tribe_id)
  );

-- tribe_deliverables
DROP POLICY IF EXISTS "tribe_deliverables_write" ON tribe_deliverables;
CREATE POLICY "tribe_deliverables_write_v4" ON tribe_deliverables FOR ALL TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can_for_tribe('write_board', tribe_deliverables.tribe_id)
  );

-- tribe_meeting_slots
DROP POLICY IF EXISTS "Leaders edit own slots" ON tribe_meeting_slots;
CREATE POLICY "meeting_slots_write_v4" ON tribe_meeting_slots FOR ALL TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can_for_tribe('write', tribe_meeting_slots.tribe_id)
  );

-- tribes (UPDATE — leader own tribe)
DROP POLICY IF EXISTS "Leaders edit own tribe" ON tribes;
CREATE POLICY "leaders_edit_own_tribe_v4" ON tribes FOR UPDATE TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can_for_tribe('write', tribes.id)
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY 4: Manager + co_gp (2 policies)
-- Legacy: is_superadmin OR manager/deputy/co_gp
-- V4: rls_is_superadmin() OR rls_can('manage_member')
-- ═══════════════════════════════════════════════════════════════════════════

-- site_config (SELECT)
DROP POLICY IF EXISTS "site_config_admin_read" ON site_config;
CREATE POLICY "site_config_admin_read" ON site_config FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- volunteer_applications (SELECT)
DROP POLICY IF EXISTS "volunteer_applications_admin_read" ON volunteer_applications;
CREATE POLICY "volunteer_applications_admin_read" ON volunteer_applications FOR SELECT TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_member'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY 5: Designation-based policies (6 policies)
-- Each mapped to specific V4 actions covering the legacy designation roles
-- ═══════════════════════════════════════════════════════════════════════════

-- artifacts (UPDATE) — was: superadmin/tribe_leader/curator/co_gp
-- V4: write covers leader, write_board covers curator
DROP POLICY IF EXISTS "admin_update_artifacts" ON artifacts;
CREATE POLICY "artifacts_update_v4" ON artifacts FOR UPDATE TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write') OR public.rls_can('write_board'));

-- blog_posts (ALL) — was: manager/deputy/comms_team
-- V4: write covers manager/deputy/co_gp/leader/comms_leader
DROP POLICY IF EXISTS "Admin manages posts" ON blog_posts;
CREATE POLICY "blog_posts_manage_v4" ON blog_posts FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

-- campaign_templates (ALL) — was: manager/deputy/comms_team
-- V4: write covers comms_leader
DROP POLICY IF EXISTS "Admin manages templates" ON campaign_templates;
CREATE POLICY "campaign_templates_manage_v4" ON campaign_templates FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

-- chapter_needs (SELECT) — was: manager/deputy OR (chapter match + chapter_board/sponsor/liaison)
-- V4: manage_member for admins, manage_partner for chapter board/sponsors/liaisons
DROP POLICY IF EXISTS "chapter_needs_select" ON chapter_needs;
CREATE POLICY "chapter_needs_select_v4" ON chapter_needs FOR SELECT TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR public.rls_can('manage_partner')
  );

-- comms_channel_config (ALL) — was: manager/deputy/comms_leader designation
-- V4: write covers comms_leader
DROP POLICY IF EXISTS "comms_channel_config_admin" ON comms_channel_config;
CREATE POLICY "comms_channel_config_v4" ON comms_channel_config FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write'));

-- public_publications (ALL) — was: manager/deputy/curator designation
-- V4: write covers manager/deputy, write_board covers curator
DROP POLICY IF EXISTS "pub_admin_manage" ON public_publications;
CREATE POLICY "pub_admin_manage_v4" ON public_publications FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('write') OR public.rls_can('write_board'));

-- ═══════════════════════════════════════════════════════════════════════════
-- CATEGORY 6: Special policies (2 policies)
-- ═══════════════════════════════════════════════════════════════════════════

-- partner_entities (ALL) — was: manager/deputy (no superadmin!)
-- V4: manage_partner covers manager/deputy/co_gp + sponsor + liaison (ADR-0007 intent)
DROP POLICY IF EXISTS "partner_entities_admin_write" ON partner_entities;
CREATE POLICY "partner_entities_write_v4" ON partner_entities FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_partner'));

-- pii_access_log (SELECT) — was: manager/deputy OR own log
DROP POLICY IF EXISTS "pii_log_admin_read" ON pii_access_log;
CREATE POLICY "pii_log_admin_read_v4" ON pii_access_log FOR SELECT TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member')
    OR target_member_id = (SELECT m.id FROM members m WHERE m.auth_id = auth.uid() LIMIT 1)
  );

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLLBACK: Original policy definitions (copy-paste to restore)
-- ═══════════════════════════════════════════════════════════════════════════
/*
-- CATEGORY 1: Manager-level
CREATE POLICY "Admins can manage SLA config" ON board_sla_config FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "Admin manages sends" ON campaign_sends FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "chapter_needs_update_admin" ON chapter_needs FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "admin_read_anomalies" ON data_anomaly_log FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "admin_write_anomalies" ON data_anomaly_log FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "admin_only_retention" ON data_retention_policy FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "Admin manages help journeys" ON help_journeys FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "ia_pilots_admin_write" ON ia_pilots FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "mcp_usage_log_select_admin" ON mcp_usage_log FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "Admins can delete pilots" ON pilots FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "Admins can update pilots" ON pilots FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "admin_write_kpi_targets" ON portfolio_kpi_targets FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "Admins can manage tags" ON tags FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "Admins manage tribes" ON tribes FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "vep_opportunities_update_admin" ON vep_opportunities FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "Admin reads leads" ON visitor_leads FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));
CREATE POLICY "Admin updates leads" ON visitor_leads FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))));

-- CATEGORY 2: Leader-level
CREATE POLICY "event_showcases_manage" ON event_showcases FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.is_superadmin = true OR members.operational_role = ANY (ARRAY['manager','deputy_manager','tribe_leader']))));
CREATE POLICY "Admins can manage action items" ON meeting_action_items FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager','tribe_leader']))));
CREATE POLICY "Leaders can manage action items" ON meeting_action_items FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager','tribe_leader']))));
CREATE POLICY "Superadmin can view all sessions" ON member_activity_sessions FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.is_superadmin = true OR members.operational_role = 'manager')));

-- CATEGORY 3: Tribe-scoped
CREATE POLICY "board_items_write" ON board_items FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM project_boards pb JOIN members m ON m.auth_id = auth.uid() WHERE pb.id = board_items.board_id AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager','co_gp']) OR (m.operational_role = 'tribe_leader' AND m.tribe_id = pb.tribe_id))));
CREATE POLICY "project_boards_write" ON project_boards FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager','co_gp']) OR (m.operational_role = 'tribe_leader' AND m.tribe_id = project_boards.tribe_id))));
CREATE POLICY "tribe_deliverables_write" ON tribe_deliverables FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.is_superadmin = true OR members.operational_role = ANY (ARRAY['manager','deputy_manager']) OR (members.operational_role = 'tribe_leader' AND members.tribe_id = tribe_deliverables.tribe_id))));
CREATE POLICY "Leaders edit own slots" ON tribe_meeting_slots FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']) OR (m.operational_role = 'tribe_leader' AND m.tribe_id = tribe_meeting_slots.tribe_id))));
CREATE POLICY "Leaders edit own tribe" ON tribes FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']) OR (m.operational_role = 'tribe_leader' AND m.tribe_id = tribes.id))));

-- CATEGORY 4: Manager + co_gp
CREATE POLICY "site_config_admin_read" ON site_config FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager','co_gp']))));
CREATE POLICY "volunteer_applications_admin_read" ON volunteer_applications FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager','co_gp']))));

-- CATEGORY 5: Designation-based
CREATE POLICY "admin_update_artifacts" ON artifacts FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.is_superadmin = true OR members.operational_role = 'tribe_leader' OR 'curator' = ANY(COALESCE(members.designations,'{}')) OR 'co_gp' = ANY(COALESCE(members.designations,'{}')))));
CREATE POLICY "Admin manages posts" ON blog_posts FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY (ARRAY['manager','deputy_manager']) OR 'comms_team' = ANY(m.designations))));
CREATE POLICY "Admin manages templates" ON campaign_templates FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin OR m.operational_role = ANY (ARRAY['manager','deputy_manager']) OR 'comms_team' = ANY(m.designations))));
CREATE POLICY "chapter_needs_select" ON chapter_needs FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']) OR (m.chapter = chapter_needs.chapter AND m.designations && ARRAY['chapter_board','sponsor','chapter_liaison']))));
CREATE POLICY "comms_channel_config_admin" ON comms_channel_config FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.is_superadmin OR members.operational_role = ANY (ARRAY['manager','deputy_manager']) OR members.designations && ARRAY['comms_leader'])));
CREATE POLICY "pub_admin_manage" ON public_publications FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members WHERE members.auth_id = auth.uid() AND (members.is_superadmin OR members.operational_role = ANY (ARRAY['manager','deputy_manager']) OR members.designations && ARRAY['curator'])));

-- CATEGORY 6: Special
CREATE POLICY "partner_entities_admin_write" ON partner_entities FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND m.operational_role = ANY (ARRAY['manager','deputy_manager'])));
CREATE POLICY "pii_log_admin_read" ON pii_access_log FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.operational_role = ANY (ARRAY['manager','deputy_manager']))) OR target_member_id = (SELECT id FROM members WHERE auth_id = auth.uid()));
*/
