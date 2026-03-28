-- GC-162: LGPD RLS Hardening — P0 Security
-- Applied via 4 Supabase MCP migrations on 2026-03-28
-- Locks down PII tables, boards, events, content from anon/Ghost access
-- See SPEC_LGPD_RLS_HARDENING_GC162.md for full audit

BEGIN;

-- ═══ M1: Critical PII ═══
DROP POLICY IF EXISTS "Public member listing" ON members;
CREATE POLICY "members_read_by_members" ON members FOR SELECT TO authenticated
  USING (is_active = true AND EXISTS (SELECT 1 FROM get_my_member_record()));

DROP POLICY IF EXISTS "anon_read_attendance" ON attendance;
DROP POLICY IF EXISTS "attendance_select_members" ON attendance;
CREATE POLICY "attendance_read_members" ON attendance FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM get_my_member_record()));

DROP POLICY IF EXISTS "read_all_points" ON gamification_points;
CREATE POLICY "gamification_read_members" ON gamification_points FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM get_my_member_record()));

DROP POLICY IF EXISTS "Public progress" ON course_progress;
DROP POLICY IF EXISTS "anon_read_course_progress" ON course_progress;
CREATE POLICY "course_progress_read_members" ON course_progress FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM get_my_member_record()));

-- ═══ M2: Board Security ═══
DROP POLICY IF EXISTS "Authenticated users can read checklists" ON board_item_checklists;
DROP POLICY IF EXISTS "Authenticated users can insert checklists" ON board_item_checklists;
DROP POLICY IF EXISTS "Authenticated users can update checklists" ON board_item_checklists;
DROP POLICY IF EXISTS "Authenticated users can delete checklists" ON board_item_checklists;
CREATE POLICY "checklists_read_members" ON board_item_checklists FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));
CREATE POLICY "checklists_write_leaders" ON board_item_checklists FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record() r WHERE r.is_superadmin OR r.operational_role IN ('manager','deputy_manager','tribe_leader')));

DROP POLICY IF EXISTS "Authenticated can read assignments" ON board_item_assignments;
DROP POLICY IF EXISTS "Board members can manage assignments" ON board_item_assignments;
CREATE POLICY "assignments_read_members" ON board_item_assignments FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));
CREATE POLICY "assignments_write_leaders" ON board_item_assignments FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record() r WHERE r.is_superadmin OR r.operational_role IN ('manager','deputy_manager','tribe_leader')));

DROP POLICY IF EXISTS "All authenticated can view board item tag assignments" ON board_item_tag_assignments;
DROP POLICY IF EXISTS "Authenticated can manage board item tag assignments" ON board_item_tag_assignments;
CREATE POLICY "tag_assignments_read_members" ON board_item_tag_assignments FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));
CREATE POLICY "tag_assignments_write_leaders" ON board_item_tag_assignments FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record() r WHERE r.is_superadmin OR r.operational_role IN ('manager','deputy_manager','tribe_leader')));

DROP POLICY IF EXISTS "board_items_read" ON board_items;
CREATE POLICY "board_items_read_members" ON board_items FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));

DROP POLICY IF EXISTS "project_boards_read" ON project_boards;
CREATE POLICY "project_boards_read_members" ON project_boards FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));

DROP POLICY IF EXISTS "Members can view audience rules" ON event_audience_rules;
DROP POLICY IF EXISTS "Managers can manage audience rules" ON event_audience_rules;
CREATE POLICY "audience_rules_read_members" ON event_audience_rules FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));
CREATE POLICY "audience_rules_manage_leaders" ON event_audience_rules FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record() r WHERE r.is_superadmin OR r.operational_role IN ('manager','deputy_manager','tribe_leader')));

DROP POLICY IF EXISTS "Members can view invited members" ON event_invited_members;
DROP POLICY IF EXISTS "Managers can manage invited members" ON event_invited_members;
CREATE POLICY "invited_read_members" ON event_invited_members FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));
CREATE POLICY "invited_manage_leaders" ON event_invited_members FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record() r WHERE r.is_superadmin OR r.operational_role IN ('manager','deputy_manager','tribe_leader')));

DROP POLICY IF EXISTS "All authenticated can view event tag assignments" ON event_tag_assignments;
DROP POLICY IF EXISTS "Authenticated can manage event tag assignments" ON event_tag_assignments;
CREATE POLICY "event_tags_read_members" ON event_tag_assignments FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));
CREATE POLICY "event_tags_manage_leaders" ON event_tag_assignments FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record() r WHERE r.is_superadmin OR r.operational_role IN ('manager','deputy_manager','tribe_leader')));

-- ═══ M3: Events & Content ═══
DROP POLICY IF EXISTS "anon_read_events" ON events;
DROP POLICY IF EXISTS "events_select_public" ON events;
CREATE POLICY "events_read_anon" ON events FOR SELECT TO anon USING (type IN ('geral', 'webinar'));
CREATE POLICY "events_read_ghost" ON events FOR SELECT TO authenticated USING (NOT EXISTS (SELECT 1 FROM get_my_member_record()) AND type IN ('geral', 'webinar'));
CREATE POLICY "events_read_members" ON events FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));

DROP POLICY IF EXISTS "Public CRs" ON change_requests;
CREATE POLICY "cr_read_members" ON change_requests FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));

DROP POLICY IF EXISTS "Members can view submissions" ON publication_submissions;
CREATE POLICY "submissions_read_members" ON publication_submissions FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));
DROP POLICY IF EXISTS "Members can view submission authors" ON publication_submission_authors;
CREATE POLICY "sub_authors_read_members" ON publication_submission_authors FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));
DROP POLICY IF EXISTS "Members can view submission events" ON publication_submission_events;
CREATE POLICY "sub_events_read_members" ON publication_submission_events FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));

DROP POLICY IF EXISTS "wle_select" ON webinar_lifecycle_events;
CREATE POLICY "wle_read_members" ON webinar_lifecycle_events FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));

DROP POLICY IF EXISTS "webinars_select" ON webinars;
CREATE POLICY "webinars_read_anon" ON webinars FOR SELECT TO anon USING (status IN ('confirmed', 'completed'));
CREATE POLICY "webinars_read_ghost" ON webinars FOR SELECT TO authenticated USING (NOT EXISTS (SELECT 1 FROM get_my_member_record()) AND status IN ('confirmed', 'completed'));
CREATE POLICY "webinars_read_members" ON webinars FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));

DROP POLICY IF EXISTS "partner_entities_read" ON partner_entities;
CREATE POLICY "partners_read_members" ON partner_entities FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM get_my_member_record()));

-- ═══ M4: Public leaderboard ═══
CREATE OR REPLACE FUNCTION get_public_leaderboard(p_limit int DEFAULT 50)
RETURNS TABLE(rank_position int, member_name text, chapter text, tribe_name text, xp_total bigint, level_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
  WITH xp AS (SELECT gp.member_id, SUM(gp.points) as total FROM gamification_points gp GROUP BY gp.member_id)
  SELECT ROW_NUMBER() OVER (ORDER BY COALESCE(xp.total, 0) DESC)::int, m.name, m.chapter, t.name,
    COALESCE(xp.total, 0), CASE WHEN COALESCE(xp.total, 0) >= 401 THEN 'Lenda' WHEN COALESCE(xp.total, 0) >= 201 THEN 'Mestre'
    WHEN COALESCE(xp.total, 0) >= 91 THEN 'Especialista' WHEN COALESCE(xp.total, 0) >= 31 THEN 'Praticante' ELSE 'Explorador' END
  FROM members m LEFT JOIN xp ON xp.member_id = m.id LEFT JOIN tribes t ON t.id = m.tribe_id
  WHERE m.is_active AND m.current_cycle_active ORDER BY COALESCE(xp.total, 0) DESC LIMIT p_limit;
$$;
GRANT EXECUTE ON FUNCTION get_public_leaderboard TO anon;
GRANT EXECUTE ON FUNCTION get_public_leaderboard TO authenticated;

CREATE OR REPLACE FUNCTION get_public_platform_stats() RETURNS json
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
  SELECT json_build_object('active_members', (SELECT COUNT(*) FROM members WHERE is_active AND current_cycle_active),
    'total_tribes', (SELECT COUNT(*) FROM tribes WHERE is_active),
    'total_chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE is_active AND chapter != 'Externo'),
    'total_events', (SELECT COUNT(*) FROM events WHERE date >= '2026-01-01'),
    'total_resources', (SELECT COUNT(*) FROM hub_resources WHERE is_active),
    'retention_rate', (SELECT ROUND(COUNT(*) FILTER (WHERE current_cycle_active)::numeric / NULLIF(COUNT(*) FILTER (WHERE is_active OR member_status = 'alumni'), 0) * 100, 1) FROM members WHERE member_status IN ('active','alumni','observer')));
$$;
GRANT EXECUTE ON FUNCTION get_public_platform_stats TO anon;
GRANT EXECUTE ON FUNCTION get_public_platform_stats TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
