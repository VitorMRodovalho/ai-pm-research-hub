-- ============================================================================
-- CR-051 Phase 2+: RPCs and data fixes applied during session
-- Captures RPCs that were applied directly via execute_sql during development.
--
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS get_initiative_members(uuid);
--   DROP FUNCTION IF EXISTS get_initiative_board_summary(uuid);
--   DROP FUNCTION IF EXISTS activate_initiative(uuid);
--   DROP FUNCTION IF EXISTS create_initiative_event(uuid, text, date, time, integer, text, text);
--   -- Revert curator separation: manual
-- ============================================================================

-- ─── get_initiative_members ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_initiative_members(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_result jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(row_to_json(m) ORDER BY m.role_order, m.name), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT e.id as engagement_id, e.kind, e.role, e.status, e.start_date,
      p.id as person_id, COALESCE(p.name, mb.name) as name,
      COALESCE(p.photo_url, mb.photo_url) as photo_url, mb.id as member_id,
      CASE e.role WHEN 'leader' THEN 0 WHEN 'coordinator' THEN 1
        WHEN 'participant' THEN 2 WHEN 'observer' THEN 3 ELSE 4 END as role_order
    FROM engagements e
    JOIN persons p ON p.id = e.person_id
    LEFT JOIN members mb ON mb.id = p.legacy_member_id
    WHERE e.initiative_id = p_initiative_id AND e.status = 'active'
  ) m;
  RETURN v_result;
END;
$$;

-- ─── get_initiative_board_summary ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_initiative_board_summary(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_board_id uuid; v_counts jsonb; v_recent jsonb; v_total integer;
BEGIN
  SELECT pb.id INTO v_board_id FROM project_boards pb
  WHERE pb.initiative_id = p_initiative_id AND pb.is_active = true LIMIT 1;
  IF v_board_id IS NULL THEN RETURN jsonb_build_object('error', 'No board linked'); END IF;

  SELECT coalesce(jsonb_object_agg(s.status, s.cnt), '{}'::jsonb), coalesce(sum(s.cnt), 0)
  INTO v_counts, v_total
  FROM (SELECT status, count(*)::int as cnt FROM board_items
    WHERE board_id = v_board_id AND status != 'archived' GROUP BY status) s;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'title', r.title, 'status', r.status,
    'due_date', r.due_date, 'assignee_id', r.assignee_id)), '[]'::jsonb)
  INTO v_recent FROM (SELECT id, title, status, due_date, assignee_id
    FROM board_items WHERE board_id = v_board_id AND status != 'archived'
    ORDER BY created_at DESC LIMIT 10) r;

  RETURN jsonb_build_object('board_id', v_board_id, 'total', v_total,
    'by_status', v_counts, 'recent', v_recent);
END;
$$;

-- ─── activate_initiative ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION activate_initiative(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_caller_person_id uuid; v_initiative record;
BEGIN
  SELECT p.id INTO v_caller_person_id FROM persons p WHERE p.auth_id = auth.uid();
  IF v_caller_person_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF NOT can(v_caller_person_id, 'manage_member', 'initiative', p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  SELECT id, status INTO v_initiative FROM initiatives WHERE id = p_initiative_id;
  IF v_initiative IS NULL THEN RETURN jsonb_build_object('error', 'Initiative not found'); END IF;
  IF v_initiative.status != 'draft' THEN RETURN jsonb_build_object('error', 'Only draft initiatives can be activated'); END IF;
  UPDATE initiatives SET status = 'active', updated_at = now() WHERE id = p_initiative_id;
  RETURN jsonb_build_object('ok', true, 'status', 'active');
END;
$$;

-- ─── create_initiative_event ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION create_initiative_event(
  p_initiative_id uuid, p_title text, p_date date,
  p_time_start time DEFAULT '19:00', p_duration_minutes integer DEFAULT 60,
  p_type text DEFAULT 'geral', p_meeting_link text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_caller_person_id uuid; v_initiative record; v_event_id uuid;
BEGIN
  SELECT p.id INTO v_caller_person_id FROM persons p WHERE p.auth_id = auth.uid();
  IF v_caller_person_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF NOT can(v_caller_person_id, 'manage_event', 'initiative', p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_event permission'); END IF;
  SELECT id, kind, status, legacy_tribe_id INTO v_initiative FROM initiatives WHERE id = p_initiative_id;
  IF v_initiative IS NULL THEN RETURN jsonb_build_object('error', 'Initiative not found'); END IF;
  IF v_initiative.status NOT IN ('active', 'draft') THEN RETURN jsonb_build_object('error', 'Initiative is not active'); END IF;
  INSERT INTO events (title, date, time_start, duration_minutes, type,
    initiative_id, tribe_id, created_by, meeting_link, organization_id)
  VALUES (p_title, p_date, p_time_start, p_duration_minutes, p_type,
    p_initiative_id, v_initiative.legacy_tribe_id, auth.uid(), p_meeting_link,
    '2b4f58ab-7c45-4170-8718-b77ee69ff906')
  RETURNING id INTO v_event_id;
  RETURN jsonb_build_object('ok', true, 'event_id', v_event_id);
END;
$$;

-- ─── Fix get_cpmai_course_dashboard (ev.event_type → ev.type) ───────────────
-- Already applied via execute_sql. Included here for local migration parity.
-- See commit bbb86ca for the fix.

-- ─── study_group permissions ────────────────────────────────────────────────
INSERT INTO engagement_kind_permissions (kind, role, action, scope, description, organization_id)
SELECT * FROM (VALUES
  ('study_group_owner', 'owner', 'manage_member', 'initiative', 'SG owner can manage members', '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid),
  ('study_group_owner', 'owner', 'view_pii', 'initiative', 'SG owner can see contacts', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('study_group_owner', 'leader', 'write', 'initiative', 'SG leader alias', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('study_group_owner', 'leader', 'write_board', 'initiative', 'SG leader alias', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('study_group_owner', 'leader', 'manage_event', 'initiative', 'SG leader alias', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('study_group_owner', 'leader', 'manage_member', 'initiative', 'SG leader alias', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('study_group_owner', 'leader', 'view_pii', 'initiative', 'SG leader alias', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('study_group_participant', 'participant', 'write_board', 'initiative', 'SG participant can use board', '2b4f58ab-7c45-4170-8718-b77ee69ff906')
) AS v(kind, role, action, scope, description, organization_id)
WHERE NOT EXISTS (
  SELECT 1 FROM engagement_kind_permissions ekp
  WHERE ekp.kind = v.kind AND ekp.role = v.role AND ekp.action = v.action
);

-- ─── Curator separation data ────────────────────────────────────────────────
-- Curators offboarded from Comms Hub + Publicacoes (applied via execute_sql)
-- Comite de Curadoria initiative created (applied via execute_sql)

NOTIFY pgrst, 'reload schema';
