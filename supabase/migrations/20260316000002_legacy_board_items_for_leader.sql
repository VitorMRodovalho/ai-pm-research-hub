-- Linhagem de Tribos: RPC para buscar board_items legados de tribos anteriores
-- Permite que um líder (ex: Débora, T6 C2 -> T2 C3) veja o backlog legado
-- integrado na sua visão atual do Kanban.
-- Date: 2026-03-16
-- ============================================================================

CREATE OR REPLACE FUNCTION public.list_legacy_board_items_for_tribe(
  p_current_tribe_id integer
)
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller    public.members%rowtype;
  v_leader_id uuid;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN; END IF;

  SELECT m.id INTO v_leader_id
  FROM public.members m
  WHERE m.tribe_id = p_current_tribe_id
    AND m.operational_role = 'tribe_leader'
    AND m.is_active = true
  LIMIT 1;

  IF v_leader_id IS NULL THEN RETURN; END IF;

  IF NOT (
    v_caller.id = v_leader_id
    OR v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id,
      bi.title,
      bi.description,
      bi.status,
      bi.curation_status,
      bi.reviewer_id,
      bi.tags,
      bi.labels,
      bi.due_date,
      bi.position,
      bi.cycle,
      bi.attachments,
      bi.checklist,
      bi.created_at,
      bi.updated_at,
      am.name AS assignee_name,
      am.photo_url AS assignee_photo,
      rm.name AS reviewer_name,
      pb.tribe_id AS origin_tribe_id,
      t.name AS origin_tribe_name
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.tribes t ON t.id = pb.tribe_id
    LEFT JOIN public.members am ON am.id = bi.assignee_id
    LEFT JOIN public.members rm ON rm.id = bi.reviewer_id
    WHERE pb.tribe_id <> p_current_tribe_id
      AND pb.is_active = true
      AND bi.status <> 'archived'
      AND (
        bi.assignee_id = v_leader_id
        OR pb.tribe_id IN (
          SELECT mch.tribe_id
          FROM public.member_cycle_history mch
          WHERE mch.member_id = v_leader_id
            AND mch.operational_role = 'tribe_leader'
        )
      )
    ORDER BY bi.updated_at DESC NULLS LAST
    LIMIT 50
  ) r;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_legacy_board_items_for_tribe(integer) TO authenticated;
