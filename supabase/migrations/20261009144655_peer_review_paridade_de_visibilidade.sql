-- =====================================================================================
-- complete_peer_review: paridade com as demais RPCs da curadoria (#785, ADR-0105)
--
-- Corpo montado sobre o vivo (md5 normalizado == captura 20260924151234, conferido em 09/10).
-- Assinatura, SECURITY DEFINER, search_path e grants nao mudam (CREATE OR REPLACE).
-- ROLLBACK: reaplicar a captura 20260924151234 de complete_peer_review.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.complete_peer_review(p_item_id uuid, p_summary text DEFAULT NULL::text, p_waived boolean DEFAULT false, p_waiver_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_item   board_items%ROWTYPE;
  v_initiative_id uuid;
  v_is_authorized boolean := false;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

  -- Paridade com as demais RPCs da curadoria (#785).
  IF NOT public.rls_can_see_board(v_item.board_id) THEN
    RAISE EXCEPTION 'Item not found: %', p_item_id;
  END IF;

  IF v_item.curation_status NOT IN ('draft', 'peer_review') THEN
    RAISE EXCEPTION 'Peer review can only be completed from draft or peer_review status (current: %)', v_item.curation_status;
  END IF;

  IF p_waived AND (p_waiver_reason IS NULL OR length(trim(p_waiver_reason)) = 0) THEN
    RAISE EXCEPTION 'Waiver requires a reason (per manual §4.2 adaptações)';
  END IF;

  -- #2447: peer review, revisao do lider e curadoria valem so para artefato publicavel.
  IF NOT public._board_item_needs_curation(p_item_id) THEN
    RAISE EXCEPTION 'Revisão e curadoria valem só para artefato publicável: marque o card como entregável de portfólio e escolha um tipo de publicação.';
  END IF;

  -- p197 fix H4: gate by assignee (intellectual author), tribe leader, or governance reviewer.
  -- Dropped board_items.created_by branch (often GP doing data entry, not author).
  SELECT pb.initiative_id INTO v_initiative_id
    FROM public.project_boards pb WHERE pb.id = v_item.board_id;

  IF v_item.assignee_id = v_caller.id THEN
    v_is_authorized := true;
  ELSIF EXISTS (
    SELECT 1 FROM public.board_item_assignments bia
    WHERE bia.item_id = p_item_id
      AND bia.member_id = v_caller.id
      AND bia.role IN ('author', 'contributor')
  ) THEN
    v_is_authorized := true;
  ELSIF v_initiative_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    WHERE e.initiative_id = v_initiative_id
      AND e.status = 'active'
      AND e.role = 'leader'
      AND p.auth_id = auth.uid()
  ) THEN
    v_is_authorized := true;
  ELSIF public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    v_is_authorized := true;
  END IF;

  IF NOT v_is_authorized THEN
    RAISE EXCEPTION 'Requires authorship (assignee or assignments role author/contributor), tribe leadership, or governance reviewer authority';
  END IF;

  UPDATE public.board_items
  SET curation_status = 'leader_review',
      peer_review_completed_at = now(),
      peer_review_summary = COALESCE(p_summary, peer_review_summary),
      peer_review_waived = p_waived,
      peer_review_waived_reason = CASE WHEN p_waived THEN p_waiver_reason ELSE NULL END,
      updated_at = now()
  WHERE id = p_item_id;

  -- p197 fix B1: use distinct action 'peer_review_completed' (NOT 'curation_review')
  INSERT INTO public.board_lifecycle_events
    (board_id, item_id, action, reason, actor_member_id)
  VALUES (
    v_item.board_id,
    p_item_id,
    'peer_review_completed',
    CASE WHEN p_waived
         THEN 'Peer review dispensado: ' || p_waiver_reason
         ELSE 'Peer review concluído (colegiado §4.2 etapa 5)' || COALESCE(' — ' || p_summary, '')
    END,
    v_caller.id
  );
END;
$function$;
