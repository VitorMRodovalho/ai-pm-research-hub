-- =====================================================================
-- #187 — V4 curation-reviewer picker: expose can_curate from get_board_members
-- =====================================================================
-- PREMISE CORRECTION (live-verified 2026-06-05): the original issue premise
-- ("reviewer picker renders empty for everyone — designations never fetched")
-- was WRONG. CardDetail fetches members via get_board_members(p_board_id), whose
-- RETURNS TABLE already includes designations text[]. The picker is NOT empty.
-- The real (latent, 0-impact today) issue is the V3 filter in MemberPickerMulti:
-- `m.designations?.includes('curator')` instead of V4 curate_content authority.
-- Today designation('curator') == can_curate('curate_content') (3 ≡ 3), so the
-- divergence is unrealized — but a future engagement-derived curator (curate_content
-- without the legacy designation) would be wrongly excluded, and a stale-designation
-- member without curate_content wrongly included.
--
-- FIX: add a canonical V4 `can_curate boolean` column to get_board_members
-- (computed once per distinct member via can_by_member(_,'curate_content')), and
-- the frontend picker filters curation_reviewer candidates by m.can_curate.
--
-- SHAPE CHANGE: RETURNS TABLE gains one column → requires DROP + CREATE (cannot
-- CREATE OR REPLACE a changed return type). Verified: 1 overload, 0 view deps.
-- ADDITIVE for existing consumers (they select named columns / ignore extras).
-- Body otherwise reproduced byte-equivalent from the live capture; no PII added
-- (rpc-acl no-email/phone invariant preserved).
--
-- INVARIANTS: check_schema_invariants() unaffected.
-- ROLLBACK: DROP + re-CREATE the prior 6-column signature (drop can_curate).
-- CROSS-REF: #187, #185/#245 (curate_content gate), ADR-0007 (can()), ADR-0087.
-- =====================================================================

DROP FUNCTION IF EXISTS public.get_board_members(uuid);

CREATE FUNCTION public.get_board_members(p_board_id uuid)
 RETURNS TABLE(id uuid, name text, photo_url text, operational_role text, board_role text, designations text[], can_curate boolean)
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
  SELECT DISTINCT ON (q.id)
    q.id, q.name, q.photo_url, q.operational_role, q.board_role, q.designations,
    public.can_by_member(q.id, 'curate_content') AS can_curate
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
    -- p180 ADR-0011 V4: replaced operational_role IN ('manager','deputy_manager')
    -- with can_by_member(manage_platform) → covers volunteer × {co_gp, deputy_manager,
    -- manager}. Co_gp now visible as 'gp' priority (was already visible via
    -- priority-5 engagement_member if initiative engagement exists).
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'gp'::text, m.designations, 4
    FROM members m
    WHERE m.is_active = true
      AND (m.is_superadmin = true OR public.can_by_member(m.id, 'manage_platform'))
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

GRANT EXECUTE ON FUNCTION public.get_board_members(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
