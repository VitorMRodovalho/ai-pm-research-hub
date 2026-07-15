-- #1383 PR-D: apply the confidential-board visibility gate to submit_curation_review,
-- mirroring its sibling assign_curation_reviewer (#785 PR-3). A curator without
-- engagement on a confidential initiative must not act on its board items. Body
-- otherwise unchanged from the live capture.
CREATE OR REPLACE FUNCTION public.submit_curation_review(p_item_id uuid, p_decision text, p_criteria_scores jsonb DEFAULT '{}'::jsonb, p_feedback_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller   members%rowtype;
  v_item     board_items%rowtype;
  v_log_id   uuid;
  v_pub_id   uuid;
  v_origin_board uuid;
  v_required int;
  v_current_round int;
  v_approved_count int;
  v_criteria text[];
  v_key text;
  v_score int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review';
  END IF;

  IF p_decision NOT IN ('approved', 'returned_for_revision', 'rejected') THEN
    RAISE EXCEPTION 'Invalid decision: %', p_decision;
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Board item not found'; END IF;

  -- #785 PR-3 parity (mirror assign_curation_reviewer): a curator without
  -- engagement on a confidential initiative cannot act on its board items.
  IF NOT public.rls_can_see_board(v_item.board_id) THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;

  IF v_item.curation_status <> 'curation_pending' THEN
    RAISE EXCEPTION 'Item is not in curation_pending status';
  END IF;

  IF p_criteria_scores IS NOT NULL AND p_criteria_scores <> '{}'::jsonb THEN
    FOR v_key IN SELECT unnest(ARRAY['clarity','originality','adherence','relevance','ethics'])
    LOOP
      v_score := (p_criteria_scores->>v_key)::int;
      IF v_score IS NULL OR v_score < 1 OR v_score > 5 THEN
        RAISE EXCEPTION 'Invalid score for %: must be 1-5', v_key;
      END IF;
    END LOOP;
  END IF;

  SELECT coalesce(max(review_round), 1) INTO v_current_round
  FROM board_lifecycle_events
  WHERE item_id = p_item_id AND action = 'reviewer_assigned';

  IF EXISTS (
    SELECT 1 FROM curation_review_log
    WHERE board_item_id = p_item_id
      AND curator_id = v_caller.id
      AND review_round = v_current_round
  ) THEN
    RAISE EXCEPTION 'You have already submitted a review for this item in round %', v_current_round;
  END IF;

  SELECT reviewers_required INTO v_required
  FROM board_sla_config WHERE board_id = v_item.board_id;
  v_required := coalesce(v_required, 2);

  INSERT INTO curation_review_log (
    board_item_id, curator_id, criteria_scores, feedback_notes,
    decision, due_date, completed_at, review_round
  ) VALUES (
    p_item_id, v_caller.id, p_criteria_scores, p_feedback_notes,
    p_decision, v_item.curation_due_at, now(), v_current_round
  ) RETURNING id INTO v_log_id;

  INSERT INTO board_lifecycle_events
    (board_id, item_id, action, reason, actor_member_id, review_score, review_round, sla_deadline)
  VALUES
    (v_item.board_id, p_item_id, 'curation_review',
     p_decision || ': ' || coalesce(p_feedback_notes, ''),
     v_caller.id, p_criteria_scores, v_current_round, v_item.curation_due_at);

  IF p_decision = 'approved' THEN
    SELECT count(DISTINCT curator_id) INTO v_approved_count
    FROM curation_review_log
    WHERE board_item_id = p_item_id
      AND decision = 'approved'
      AND review_round = v_current_round;

    IF v_approved_count >= v_required THEN
      v_pub_id := public.publish_board_item_from_curation(p_item_id);
      INSERT INTO board_lifecycle_events
        (board_id, item_id, action, reason, actor_member_id, review_round)
      VALUES
        (v_item.board_id, p_item_id, 'curation_approved',
         v_approved_count || '/' || v_required || ' revisores aprovaram',
         v_caller.id, v_current_round);
    END IF;

  ELSIF p_decision = 'returned_for_revision' THEN
    UPDATE board_items SET
      curation_status = 'draft',
      status = 'review',
      description = coalesce(description, '') ||
        E'\n\n---\n📋 **Feedback do Comitê de Curadoria — Rodada ' || v_current_round || '** (' || to_char(now(), 'DD/MM/YYYY') || E'):\n' ||
        coalesce(p_feedback_notes, 'Sem observações específicas.'),
      updated_at = now()
    WHERE id = p_item_id;

  ELSIF p_decision = 'rejected' THEN
    UPDATE board_items SET
      curation_status = 'draft',
      status = 'archived',
      description = coalesce(description, '') ||
        E'\n\n---\n❌ **Rejeitado pelo Comitê de Curadoria — Rodada ' || v_current_round || '** (' || to_char(now(), 'DD/MM/YYYY') || E'):\n' ||
        coalesce(p_feedback_notes, 'Não atende aos critérios mínimos.'),
      updated_at = now()
    WHERE id = p_item_id;
  END IF;

  RETURN v_log_id;
END;
$function$;
