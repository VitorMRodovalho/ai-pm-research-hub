-- ADR-0032 Group R: convert admin_list_archived_board_items via Opção A reuse view_internal_analytics
-- See docs/adr/ADR-0032-board-admin-v4-conversion.md
--
-- Privilege expansion (Opção A):
--   legacy = 5 (Fabricio, Mayanna, Roberto, Sarah, Vitor SA)
--   v4 = 10 (legacy minus Sarah/Mayanna + 7 admin/governance)
--   would_gain = 7 admin/governance roles
--   would_lose = [Sarah curator, Mayanna comms_leader] — drift correction (V3 designation sem V4 engagement)
--
-- Note: Sarah loses listing capability em /admin/governance-v2.astro (Bug A's curator-visible page).
-- PM ratified Q3 = Opção A — drift consistent com ADR-0030 precedent.

CREATE OR REPLACE FUNCTION public.admin_list_archived_board_items(
  p_board_id uuid DEFAULT NULL::uuid,
  p_limit integer DEFAULT 200
)
RETURNS TABLE(
  id uuid,
  board_id uuid,
  board_name text,
  board_scope text,
  domain_key text,
  title text,
  assignee_name text,
  due_date date,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Auth required';
  END IF;

  -- V4 gate (Opção B reuse view_internal_analytics — same precedent as ADR-0031)
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Board governance access required';
  END IF;

  RETURN QUERY
  SELECT
    bi.id,
    bi.board_id,
    pb.board_name,
    pb.board_scope,
    COALESCE(pb.domain_key, '') AS domain_key,
    bi.title,
    COALESCE(m.name, '') AS assignee_name,
    bi.due_date,
    bi.updated_at
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  LEFT JOIN public.members m ON m.id = bi.assignee_id
  WHERE bi.status = 'archived'
    AND (p_board_id IS NULL OR bi.board_id = p_board_id)
  ORDER BY bi.updated_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 200), 1000));
END;
$$;
COMMENT ON FUNCTION public.admin_list_archived_board_items(uuid, integer) IS
  'Phase B'' V4 conversion (ADR-0032 Group R Opção A, p66): Opção B reuse view_internal_analytics via can_by_member. Was V3 (SA OR manager/deputy_manager OR designations co_gp/curator/comms_leader). Drift loss: Sarah curator + Mayanna comms_leader (V3 designation sem V4 engagement) — same pattern as ADR-0030.';

NOTIFY pgrst, 'reload schema';
