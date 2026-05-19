-- =====================================================================
-- p197 fix B1 + H4 — distinct peer_review_completed action + tighter gate
-- =====================================================================
-- B1: complete_peer_review wrote action='curation_review' to
-- board_lifecycle_events, colliding semantically with the existing usage
-- (analytics queries w118/w119/w122 filter that action for actual
-- curator scoring events). Adds 'peer_review_completed' as distinct
-- value to CHECK constraint + uses it in the RPC.
--
-- H4: complete_peer_review authorized caller if board_items.created_by =
-- caller. But created_by is "who entered the card in the system" (often
-- a GP doing data entry), NOT the article's intellectual author. Removes
-- created_by branch; keeps assignee_id + tribe leader + governance reviewer.
-- =====================================================================

-- B1: expand CHECK to allow distinct action
ALTER TABLE public.board_lifecycle_events
  DROP CONSTRAINT IF EXISTS board_lifecycle_events_action_check;

ALTER TABLE public.board_lifecycle_events
  ADD CONSTRAINT board_lifecycle_events_action_check
  CHECK (action = ANY (ARRAY[
    'board_archived', 'board_restored', 'item_archived', 'item_restored',
    'archived', 'deleted', 'created', 'status_change', 'forecast_update',
    'actual_completion', 'mirror_created', 'assigned', 'member_assigned',
    'member_unassigned', 'submitted_for_curation', 'reviewer_assigned',
    'curation_review', 'curation_approved', 'moved_out', 'moved_in',
    'baseline_set', 'baseline_locked', 'baseline_changed', 'forecast_changed',
    'title_changed', 'portfolio_flag_changed', 'activity_added',
    'activity_completed', 'activity_reopened', 'activity_assigned',
    'comment_added', 'comment_edited', 'comment_deleted',
    -- p197 fix B1: distinct from 'curation_review' (which is for curator scoring)
    'peer_review_completed',
    'leader_review_completed'
  ]));

-- B1 + H4: rewrite complete_peer_review
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

  IF p_waived AND (p_waiver_reason IS NULL OR length(trim(p_waiver_reason)) = 0) THEN
    RAISE EXCEPTION 'Waiver requires a reason (per manual §4.2 adaptações)';
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
$$;

GRANT EXECUTE ON FUNCTION public.complete_peer_review(uuid, text, boolean, text) TO authenticated;
