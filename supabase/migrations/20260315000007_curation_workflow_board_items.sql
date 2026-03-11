-- CXO Task Force Fase 2: Peer-to-Peer Curation Workflow
-- Adiciona reviewer_id e curation_status em board_items; RPCs para o fluxo de curadoria.
-- Status de curadoria: draft -> peer_review -> leader_review -> curation_pending -> published
-- Date: 2026-03-15
-- ============================================================================

-- 1. Coluna reviewer_id em board_items
ALTER TABLE public.board_items
  ADD COLUMN IF NOT EXISTS reviewer_id uuid REFERENCES public.members(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_board_items_reviewer_id
  ON public.board_items(reviewer_id) WHERE reviewer_id IS NOT NULL;

-- 2. Coluna curation_status em board_items (mantém status para retrocompatibilidade)
ALTER TABLE public.board_items
  ADD COLUMN IF NOT EXISTS curation_status text NOT NULL DEFAULT 'draft'
  CHECK (curation_status IN ('draft','peer_review','leader_review','curation_pending','published'));

CREATE INDEX IF NOT EXISTS idx_board_items_curation_status
  ON public.board_items(curation_status) WHERE curation_status IS NOT NULL;

-- 3. RPC: Avançar curadoria (request_review, approve_peer, approve_leader)
CREATE OR REPLACE FUNCTION public.advance_board_item_curation(
  p_item_id    uuid,
  p_action     text,
  p_reviewer_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_curation   text;
  v_assignee   uuid;
  v_reviewer   uuid;
  v_tribe_id   integer;
  v_caller     public.members%rowtype;
  v_designations text[];
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_designations := coalesce(v_caller.designations, array[]::text[]);

  SELECT bi.curation_status, bi.assignee_id, bi.reviewer_id, pb.tribe_id
    INTO v_curation, v_assignee, v_reviewer, v_tribe_id
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;

  IF p_action = 'request_review' THEN
    IF v_curation <> 'draft' THEN
      RAISE EXCEPTION 'Only draft items can request peer review';
    END IF;
    IF v_assignee IS DISTINCT FROM v_caller.id THEN
      RAISE EXCEPTION 'Only the author can request peer review';
    END IF;
    IF p_reviewer_id IS NULL THEN
      RAISE EXCEPTION 'Reviewer is required';
    END IF;
    UPDATE public.board_items
    SET curation_status = 'peer_review', reviewer_id = p_reviewer_id, updated_at = now()
    WHERE id = p_item_id;
    RETURN;
  END IF;

  IF p_action = 'approve_peer' THEN
    IF v_curation <> 'peer_review' THEN
      RAISE EXCEPTION 'Only peer_review items can be peer-approved';
    END IF;
    IF v_reviewer IS DISTINCT FROM v_caller.id THEN
      RAISE EXCEPTION 'Only the assigned reviewer can approve';
    END IF;
    UPDATE public.board_items
    SET curation_status = 'leader_review', updated_at = now()
    WHERE id = p_item_id;
    RETURN;
  END IF;

  IF p_action = 'approve_leader' THEN
    IF v_curation <> 'leader_review' THEN
      RAISE EXCEPTION 'Only leader_review items can be leader-approved';
    END IF;
    IF NOT (
      v_caller.is_superadmin = true
      OR v_caller.operational_role IN ('manager','deputy_manager')
      OR (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = v_tribe_id)
    ) THEN
      RAISE EXCEPTION 'Only tribe leader or management can approve for curation';
    END IF;
    UPDATE public.board_items
    SET curation_status = 'curation_pending', updated_at = now()
    WHERE id = p_item_id;
    RETURN;
  END IF;

  RAISE EXCEPTION 'Unknown action: %', p_action;
END;
$$;

GRANT EXECUTE ON FUNCTION public.advance_board_item_curation(uuid, text, uuid) TO authenticated;

-- 5. RPC: Listar board_items com curation_pending de todas as tribos (para Super-Kanban)
CREATE OR REPLACE FUNCTION public.list_curation_pending_board_items()
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.members%rowtype;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (
    v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager','deputy_manager')
    OR 'curator' = ANY(coalesce(v_caller.designations, array[]::text[]))
    OR 'co_gp' = ANY(coalesce(v_caller.designations, array[]::text[]))
  ) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id,
      bi.title,
      bi.description,
      bi.status,
      bi.curation_status,
      bi.assignee_id,
      bi.reviewer_id,
      bi.due_date,
      bi.board_id,
      pb.tribe_id,
      t.name AS tribe_name,
      am.name AS assignee_name,
      rm.name AS reviewer_name,
      bi.created_at,
      bi.updated_at
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.tribes t ON t.id = pb.tribe_id
    LEFT JOIN public.members am ON am.id = bi.assignee_id
    LEFT JOIN public.members rm ON rm.id = bi.reviewer_id
    WHERE bi.curation_status = 'curation_pending'
      AND bi.status <> 'archived'
      AND pb.is_active = true
    ORDER BY bi.updated_at DESC
  ) r;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_curation_pending_board_items() TO authenticated;

-- 6. RPC: Publicar board_item (move para vitrine; copia para publications board)
CREATE OR REPLACE FUNCTION public.publish_board_item_from_curation(p_item_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller     public.members%rowtype;
  v_item       public.board_items%rowtype;
  v_pub_board  uuid;
  v_new_id     uuid;
  v_pos        int;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (
    v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager','deputy_manager')
    OR 'curator' = ANY(coalesce(v_caller.designations, array[]::text[]))
    OR 'co_gp' = ANY(coalesce(v_caller.designations, array[]::text[]))
  ) THEN
    RAISE EXCEPTION 'Curatorship publish access required';
  END IF;

  SELECT bi.* INTO v_item
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;
  IF v_item.curation_status <> 'curation_pending' THEN
    RAISE EXCEPTION 'Only curation_pending items can be published';
  END IF;

  SELECT id INTO v_pub_board
  FROM public.project_boards
  WHERE coalesce(domain_key, '') = 'publications_submissions'
    AND is_active = true
  ORDER BY updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_pub_board IS NULL THEN
    RAISE EXCEPTION 'Publications board not found';
  END IF;

  SELECT coalesce(max(position), 0) + 1 INTO v_pos
  FROM public.board_items WHERE board_id = v_pub_board;

  INSERT INTO public.board_items (
    board_id, title, description, status, curation_status,
    assignee_id, due_date, position, created_at, updated_at,
    cycle, tags, labels, checklist, attachments, source_board, source_card_id
  ) VALUES (
    v_pub_board, v_item.title, v_item.description, 'done', 'published',
    v_item.assignee_id, v_item.due_date, v_pos, now(), now(),
    v_item.cycle, v_item.tags, v_item.labels, v_item.checklist, v_item.attachments,
    'tribe_curation', v_item.id::text
  )
  RETURNING id INTO v_new_id;

  UPDATE public.board_items
  SET curation_status = 'published', updated_at = now()
  WHERE id = p_item_id;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.publish_board_item_from_curation(uuid) TO authenticated;

-- 7. Atualizar list_board_items para retornar reviewer_id e curation_status
CREATE OR REPLACE FUNCTION public.list_board_items(
  p_board_id uuid,
  p_status   text DEFAULT NULL
)
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
      m.name AS assignee_name,
      m.photo_url AS assignee_photo,
      rm.name AS reviewer_name
    FROM board_items bi
    LEFT JOIN members m ON m.id = bi.assignee_id
    LEFT JOIN members rm ON rm.id = bi.reviewer_id
    WHERE bi.board_id = p_board_id
      AND (p_status IS NULL OR bi.status = p_status)
      AND bi.status <> 'archived'
    ORDER BY bi.position ASC, bi.created_at DESC
  ) r;
END;
$$;

-- 8. RPC: Radar Global (próximos webinars + últimas publicações)
CREATE OR REPLACE FUNCTION public.list_radar_global(
  p_webinars_limit int DEFAULT 5,
  p_publications_limit int DEFAULT 5
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_webinars json;
  v_publications json;
  v_today date := current_date;
BEGIN
  -- Próximos webinars (events type=webinar, date >= today)
  SELECT coalesce(json_agg(row_to_json(w)), '[]'::json) INTO v_webinars
  FROM (
    SELECT e.id, e.title, e.date, e.meeting_link, e.type
    FROM public.events e
    WHERE e.type = 'webinar'
      AND e.date >= v_today
      AND (e.tribe_id IS NULL OR e.tribe_id > 0)
    ORDER BY e.date ASC
    LIMIT p_webinars_limit
  ) w;

  -- Últimas publicações (board_items no publications board com status done)
  SELECT coalesce(json_agg(row_to_json(p)), '[]'::json) INTO v_publications
  FROM (
    SELECT bi.id, bi.title, bi.description, bi.updated_at
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    WHERE coalesce(pb.domain_key, '') = 'publications_submissions'
      AND bi.status = 'done'
      AND pb.is_active = true
    ORDER BY bi.updated_at DESC NULLS LAST
    LIMIT p_publications_limit
  ) p;

  RETURN json_build_object(
    'webinars', coalesce(v_webinars, '[]'::json),
    'publications', coalesce(v_publications, '[]'::json)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_radar_global(int, int) TO authenticated;
