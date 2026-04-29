-- Phase B'' batch 13 (p79): admin_list_tribes + admin_list_tribe_lineage V3→V4.
-- V3 baseline (both): superadmin OR ('manager','deputy_manager','tribe_leader') OR co_gp.
-- V4 mapping: can_by_member('manage_member') — covers admin/GP + manager + deputy + co_gp + leader
-- of any V4 initiative (workgroup_member/committee_member/study_group_owner). Wider than V3
-- "tribe_leader" only, but consistent with V4 ladder (any leader manages members of their initiative).
--
-- Both functions are RO admin readers. No business logic change.

CREATE OR REPLACE FUNCTION public.admin_list_tribes(p_include_inactive boolean DEFAULT false)
RETURNS TABLE(id integer, name text, quadrant integer, quadrant_name text, is_active boolean,
              leader_member_id uuid, leader_name text, active_members bigint, total_members bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member permission';
  END IF;

  RETURN QUERY
  SELECT
    t.id,
    t.name,
    t.quadrant,
    t.quadrant_name,
    t.is_active,
    t.leader_member_id,
    lm.name AS leader_name,
    count(m.id) FILTER (WHERE m.current_cycle_active IS true) AS active_members,
    count(m.id) AS total_members
  FROM public.tribes t
  LEFT JOIN public.members lm ON lm.id = t.leader_member_id
  LEFT JOIN public.members m ON m.tribe_id = t.id
  WHERE p_include_inactive OR t.is_active IS true
  GROUP BY t.id, t.name, t.quadrant, t.quadrant_name, t.is_active, t.leader_member_id, lm.name
  ORDER BY t.id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_tribes(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_tribes(boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_tribe_lineage(p_include_inactive boolean DEFAULT false)
RETURNS TABLE(id bigint, legacy_tribe_id integer, legacy_tribe_name text,
              current_tribe_id integer, current_tribe_name text, relation_type text,
              cycle_scope text, notes text, metadata jsonb,
              is_active boolean, updated_at timestamp with time zone)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member permission';
  END IF;

  RETURN QUERY
  SELECT
    tl.id,
    tl.legacy_tribe_id,
    lt.name AS legacy_tribe_name,
    tl.current_tribe_id,
    ct.name AS current_tribe_name,
    tl.relation_type,
    tl.cycle_scope,
    tl.notes,
    tl.metadata,
    tl.is_active,
    tl.updated_at
  FROM public.tribe_lineage tl
  JOIN public.tribes lt ON lt.id = tl.legacy_tribe_id
  JOIN public.tribes ct ON ct.id = tl.current_tribe_id
  WHERE p_include_inactive OR tl.is_active IS true
  ORDER BY tl.updated_at DESC, tl.id DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_tribe_lineage(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_tribe_lineage(boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
