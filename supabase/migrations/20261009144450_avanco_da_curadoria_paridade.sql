-- =====================================================================================
-- advance_board_item_curation: paridade com as demais RPCs da curadoria
--
-- Alinha advance_board_item_curation as demais RPCs da curadoria (#785, ADR-0105; #2447).
--
-- Corpo montado sobre o vivo (md5 normalizado == captura 20260428100000, conferido em 09/10).
-- Assinatura, SECURITY DEFINER, search_path e grants nao mudam (CREATE OR REPLACE).
-- ROLLBACK: reaplicar a captura 20260428100000 de advance_board_item_curation.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.advance_board_item_curation(p_item_id uuid, p_action text, p_reviewer_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_curation   text;
  v_assignee   uuid;
  v_reviewer   uuid;
  v_tribe_id   integer;
  v_board_id   uuid;
  v_caller     public.members%rowtype;
  v_designations text[];
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_designations := coalesce(v_caller.designations, array[]::text[]);

  SELECT bi.curation_status, bi.assignee_id, bi.reviewer_id, i.legacy_tribe_id, bi.board_id
    INTO v_curation, v_assignee, v_reviewer, v_tribe_id, v_board_id
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
  WHERE bi.id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;

  -- Paridade com as demais RPCs da curadoria (#785, #2447).
  IF NOT public.rls_can_see_board(v_board_id) THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;

  IF p_action IN ('request_review', 'approve_peer', 'approve_leader')
     AND NOT public._board_item_needs_curation(p_item_id) THEN
    RAISE EXCEPTION 'Revisão e curadoria valem só para artefato publicável: marque o card como entregável de portfólio e escolha um tipo de publicação.';
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
      OR public.can_by_member(v_caller.id, 'manage_member')
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
$function$;
