-- =====================================================================
-- p197 fix H1 + H2 — leader_review notification signature + peer state reset
-- =====================================================================
-- H1: complete_leader_review notification on returned passed board_id::text
-- as p_source_type. The 7-arg overload expects p_source_type as semantic
-- string like 'board_item'. Frontend deep-link rendering breaks.
--
-- H2: returned branch reset peer_review_completed_at but kept
-- peer_review_waived + peer_review_waived_reason + peer_review_summary.
-- Author who waived peer review → received return → would have stale
-- waiver state on next cycle, potentially skipping peer review again.
--
-- Also: use distinct action 'leader_review_completed' (added in B1
-- migration CHECK expansion) for analytics clarity.
-- =====================================================================

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
      'leader_review_completed',
      'Leader review ' || p_decision || ' → submetido à curadoria' || COALESCE(' — ' || p_notes, ''),
      v_caller.id
    );
  ELSIF p_decision = 'returned' THEN
    -- p197 fix H2: ALSO reset waiver state when returning. Without this,
    -- author who waived peer review then got returned would have stale
    -- "waived" flag persisting and potentially skip peer review on retry.
    UPDATE public.board_items
    SET curation_status = 'draft',
        leader_review_completed_at = now(),
        leader_review_decision = p_decision,
        leader_review_notes = p_notes,
        leader_reviewer_id = v_caller.id,
        peer_review_completed_at = NULL,
        peer_review_summary = NULL,
        peer_review_waived = false,
        peer_review_waived_reason = NULL,
        updated_at = now()
    WHERE id = p_item_id;

    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      p_item_id,
      'leader_review_completed',
      'Leader review devolvido ao autor' || COALESCE(' — ' || p_notes, ''),
      v_caller.id
    );

    -- p197 fix H1: pass 'board_item' literal as p_source_type
    -- (NOT board_id::text — frontend needs semantic type for deep link)
    IF v_item.assignee_id IS NOT NULL THEN
      PERFORM public.create_notification(
        v_item.assignee_id,
        'card_moved',
        'board_item',
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
