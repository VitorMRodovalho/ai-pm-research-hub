-- Mayanna Item 02 — assignee dropdown was missing comms team.
-- Fix: get_board_members now includes members with active engagement on
-- the board's initiative (workgroup_member, committee_member, etc).
--
-- Pre-fix returned only: legacy tribe members + board_members + curators + GP.
-- For workgroups (Hub Comunicação, Newsletter, etc) com legacy_tribe_id NULL,
-- isso excluía workgroup_member engagements → dropdown só mostrava curators+GP.
--
-- Post-fix: 5th UNION cobre engagement-derived membership. board_role='engagement_member'
-- distingue de tribe/board_admin/curator/gp para UI groupings.

CREATE OR REPLACE FUNCTION public.get_board_members(p_board_id uuid)
RETURNS TABLE(id uuid, name text, photo_url text, operational_role text, board_role text, designations text[])
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_board record;
  v_board_legacy_tribe_id int;
BEGIN
  SELECT pb.* INTO v_board FROM project_boards pb WHERE pb.id = p_board_id;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT i.legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives i WHERE i.id = v_board.initiative_id;

  RETURN QUERY
  SELECT DISTINCT ON (q.id) q.id, q.name, q.photo_url, q.operational_role, q.board_role, q.designations
  FROM (
    -- Priority 1: tribe members (legacy tribe_id match — applies to research_tribe boards)
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'tribe_member'::text as board_role, m.designations, 1 as priority
    FROM members m
    WHERE v_board_legacy_tribe_id IS NOT NULL
      AND m.tribe_id = v_board_legacy_tribe_id
      AND m.is_active = true
      AND m.member_status = 'active'
    UNION ALL
    -- Priority 2: explicitly added to board_members
    SELECT bm.member_id, m.name, m.photo_url, m.operational_role, bm.board_role, m.designations, 2
    FROM board_members bm
    JOIN members m ON m.id = bm.member_id
    WHERE bm.board_id = p_board_id
      AND m.is_active = true
    UNION ALL
    -- Priority 3: all curators
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'curator'::text, m.designations, 3
    FROM members m
    WHERE 'curator' = ANY(m.designations)
      AND m.is_active = true
    UNION ALL
    -- Priority 4: GP / superadmin
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'gp'::text, m.designations, 4
    FROM members m
    WHERE m.is_active = true
      AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager'))
    UNION ALL
    -- Priority 5: NEW — members with active engagement on the board's initiative
    -- Closes Mayanna Item 02: workgroup/committee/study_group members were
    -- invisible because legacy_tribe_id NULL skipped priority 1.
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'engagement_member'::text, m.designations, 5
    FROM members m
    JOIN persons p ON p.id = m.person_id
    JOIN engagements e ON e.person_id = p.id
    WHERE e.initiative_id = v_board.initiative_id
      AND e.status = 'active'
      AND m.is_active = true
      AND m.member_status = 'active'
  ) q
  ORDER BY q.id, q.priority;
END;
$function$;

NOTIFY pgrst, 'reload schema';
