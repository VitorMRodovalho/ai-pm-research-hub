-- =====================================================================
-- p197 Fase B — RPCs: complete_peer_review + complete_leader_review
-- =====================================================================
-- Implements manual §4.2 etapas 5 (Peer Review colegiado) + 6 (Leader
-- Review nominal) as structured transitions with metadata capture.
--
-- complete_peer_review:
--   • Gate: card author/assignee OR tribe leader of card's initiative
--           OR can_by_member('participate_in_governance_review')
--   • Validates curation_status IN ('draft', 'peer_review')
--   • Optional waiver (for collaborative articles per §4.2 adaptações)
--   • Transitions curation_status → 'leader_review'
--   • Sets peer_review_* metadata
--
-- complete_leader_review:
--   • Gate: tribe leader of card's initiative
--           OR can_by_member('participate_in_governance_review')
--   • p_decision ∈ ('approved', 'returned', 'waived')
--   • approved/waived: transitions → curation_pending, sets SLA via
--                      existing trg_set_curation_due_date
--   • returned: reverts to 'draft', creates notification for assignee
--   • Sets leader_review_* metadata + leader_reviewer_id
--
-- Existing 8 RPCs (advance_board_item_curation, submit_for_curation,
-- assign_curation_reviewer, etc.) remain functional — these are
-- additive for the manual §4.2 structured path.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.complete_peer_review(
  p_item_id uuid,
  p_summary text DEFAULT NULL,
  p_waived boolean DEFAULT false,
  p_waiver_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
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

  IF v_item.curation_status NOT IN ('draft', 'peer_review') THEN
    RAISE EXCEPTION 'Peer review can only be completed from draft or peer_review status (current: %)', v_item.curation_status;
  END IF;

  -- Waiver validation
  IF p_waived AND (p_waiver_reason IS NULL OR length(trim(p_waiver_reason)) = 0) THEN
    RAISE EXCEPTION 'Waiver requires a reason (per manual §4.2 adaptações)';
  END IF;

  -- Authority check: card author/assignee, tribe leader of initiative, or governance reviewer
  SELECT pb.initiative_id INTO v_initiative_id
    FROM public.project_boards pb WHERE pb.id = v_item.board_id;

  IF v_item.assignee_id = v_caller.id OR v_item.created_by = v_caller.id THEN
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
    RAISE EXCEPTION 'Requires card authorship, tribe leadership, or governance reviewer authority';
  END IF;

  -- Apply transition + metadata
  UPDATE public.board_items
  SET curation_status = 'leader_review',
      peer_review_completed_at = now(),
      peer_review_summary = COALESCE(p_summary, peer_review_summary),
      peer_review_waived = p_waived,
      peer_review_waived_reason = CASE WHEN p_waived THEN p_waiver_reason ELSE NULL END,
      updated_at = now()
  WHERE id = p_item_id;

  INSERT INTO public.board_lifecycle_events
    (board_id, item_id, action, reason, actor_member_id)
  VALUES (
    v_item.board_id,
    p_item_id,
    'curation_review',
    CASE WHEN p_waived
         THEN 'Peer review dispensado: ' || p_waiver_reason
         ELSE 'Peer review concluído (colegiado §4.2 etapa 5)' || COALESCE(' — ' || p_summary, '')
    END,
    v_caller.id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_peer_review(uuid, text, boolean, text) TO authenticated;

-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.complete_leader_review(
  p_item_id uuid,
  p_decision text,
  p_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller members%ROWTYPE;
  v_item   board_items%ROWTYPE;
  v_initiative_id uuid;
  v_is_leader boolean := false;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_decision NOT IN ('approved', 'returned', 'waived') THEN
    RAISE EXCEPTION 'Decision must be one of: approved, returned, waived (got: %)', p_decision;
  END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

  IF v_item.curation_status NOT IN ('leader_review', 'draft') THEN
    RAISE EXCEPTION 'Leader review can only be completed from leader_review or draft (current: %)', v_item.curation_status;
  END IF;

  -- Authority: tribe leader of card's initiative OR governance reviewer
  SELECT pb.initiative_id INTO v_initiative_id
    FROM public.project_boards pb WHERE pb.id = v_item.board_id;

  IF v_initiative_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    WHERE e.initiative_id = v_initiative_id
      AND e.status = 'active'
      AND e.role = 'leader'
      AND p.auth_id = auth.uid()
  ) THEN
    v_is_leader := true;
  ELSIF public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    v_is_leader := true;
  END IF;

  IF NOT v_is_leader THEN
    RAISE EXCEPTION 'Leader review requires tribe leadership of card''s initiative or governance reviewer authority';
  END IF;

  -- Apply decision
  IF p_decision IN ('approved', 'waived') THEN
    UPDATE public.board_items
    SET curation_status = 'curation_pending',
        leader_review_completed_at = now(),
        leader_review_decision = p_decision,
        leader_review_notes = p_notes,
        leader_reviewer_id = v_caller.id,
        updated_at = now()
    WHERE id = p_item_id;

    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      p_item_id,
      'submitted_for_curation',
      'Leader review ' || p_decision || ' → submetido à curadoria' || COALESCE(' — ' || p_notes, ''),
      v_caller.id
    );
  ELSIF p_decision = 'returned' THEN
    UPDATE public.board_items
    SET curation_status = 'draft',
        leader_review_completed_at = now(),
        leader_review_decision = p_decision,
        leader_review_notes = p_notes,
        leader_reviewer_id = v_caller.id,
        -- Reset peer review state — author needs to redo
        peer_review_completed_at = NULL,
        updated_at = now()
    WHERE id = p_item_id;

    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      p_item_id,
      'status_change',
      'Leader review devolvido ao autor' || COALESCE(' — ' || p_notes, ''),
      v_caller.id
    );

    -- Notify card assignee/author
    IF v_item.assignee_id IS NOT NULL THEN
      PERFORM public.create_notification(
        v_item.assignee_id,
        'card_moved',
        v_item.board_id::text,
        v_item.id,
        v_item.title,
        v_caller.id,
        'Líder devolveu sua peça para revisão' || COALESCE(': ' || p_notes, '')
      );
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_leader_review(uuid, text, text) TO authenticated;
