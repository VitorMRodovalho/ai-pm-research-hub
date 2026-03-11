-- Data Healing: backfill tribe_id in member_cycle_history for legacy cycles
-- Problem: cycles 1, 2, pilot have tribe_id = NULL but tribe_name populated.
-- The list_legacy_board_items_for_tribe RPC uses tribe_id for JOINs, so NULL
-- values cause zero results even when the data exists.
-- Date: 2026-03-16
-- ============================================================================

-- Step 1: Backfill tribe_id from tribe_name using pattern matching
UPDATE public.member_cycle_history mch
SET tribe_id = t.id
FROM public.tribes t
WHERE mch.tribe_id IS NULL
  AND mch.tribe_name IS NOT NULL
  AND (
    mch.tribe_name ILIKE '%' || t.name || '%'
    OR mch.tribe_name ILIKE 'T' || t.id::text || ':%'
  );

-- Step 2: Rebuild the RPC to also handle remaining NULL tribe_id via tribe_name
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
            AND mch.tribe_id IS NOT NULL
        )
        OR pb.tribe_id IN (
          SELECT tr.id
          FROM public.member_cycle_history mch2
          JOIN public.tribes tr ON mch2.tribe_name ILIKE '%' || tr.name || '%'
          WHERE mch2.member_id = v_leader_id
            AND mch2.operational_role = 'tribe_leader'
            AND mch2.tribe_id IS NULL
            AND mch2.tribe_name IS NOT NULL
        )
      )
    ORDER BY bi.updated_at DESC NULLS LAST
    LIMIT 200
  ) r;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_legacy_board_items_for_tribe(integer) TO authenticated;
