-- #190 — curation_queue_state semantic layer (board-only first; PM Option A)
--
-- A single normalized read envelope over the board_items curation pipeline (the
-- 5-state FSM frozen by ADR-0086: draft -> peer_review -> leader_review ->
-- curation_pending -> published). get_curation_dashboard exists but only surfaces
-- the curation_pending admin queue and has no per-caller action affordance. This
-- adds get_curation_queue_state(p_status) returning, per actionable item:
--   - explicit origin_type='board_item' + origin_id (forward-compat for the
--     deferred cross-pipeline expansion that an ADR will reconcile with
--     content_products / ADR-0099 — out of scope here),
--   - normalized status + SLA + review round/count/approved/required,
--   - peer/leader review state,
--   - caller_reviewed_this_round + an `eligible_actions` array computed from the
--     caller's V4 capabilities (curate_content / write_board /
--     participate_in_governance_review per ADR-0007) and the item state.
-- Plus a summary (total / by_status / overdue) and a `caller` capability block.
--
-- Read gate mirrors get_curation_dashboard (curate_content OR write_board) and
-- additionally admits participate_in_governance_review so curators (who review via
-- submit_curation_review, gated on that action) can see their queue.
--
-- This is the stable envelope #188's curator MCP tools wrap (avoids inventing the
-- envelope twice). Cross-pipeline origin types are a deferred ADR follow-up.
--
-- New function (no signature collision) -> CREATE OR REPLACE. Rollback: DROP FUNCTION.

CREATE OR REPLACE FUNCTION public.get_curation_queue_state(p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_can_curate boolean;
  v_can_write_board boolean;
  v_can_govern boolean;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  v_can_curate := public.can_by_member(v_member_id, 'curate_content');
  v_can_write_board := public.can_by_member(v_member_id, 'write_board');
  v_can_govern := public.can_by_member(v_member_id, 'participate_in_governance_review');
  IF NOT (v_can_curate OR v_can_write_board OR v_can_govern) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  WITH q AS (
    SELECT bi.id, bi.title, bi.curation_status, bi.curation_due_at, bi.board_id,
           bi.reviewer_id, bi.leader_reviewer_id, bi.created_by, bi.created_at,
           bi.peer_review_completed_at, bi.peer_review_waived,
           bi.leader_review_completed_at, bi.leader_review_decision,
           pb.board_name, i.legacy_tribe_id AS tribe_id, i.title AS tribe_name,
           COALESCE(sc.reviewers_required, 2) AS reviewers_required,
           (SELECT COALESCE(max(ble.review_round), 1) FROM public.board_lifecycle_events ble
              WHERE ble.item_id = bi.id AND ble.action = 'reviewer_assigned') AS current_round
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    LEFT JOIN public.board_sla_config sc ON sc.board_id = bi.board_id
    WHERE bi.status <> 'archived' AND pb.is_active = true
      AND bi.curation_status IN ('peer_review', 'leader_review', 'curation_pending')
      AND (p_status IS NULL OR bi.curation_status = p_status)
  )
  SELECT jsonb_build_object(
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'origin_type', 'board_item',
        'origin_id', q.id,
        'id', q.id, 'title', q.title,
        'curation_status', q.curation_status,
        'board_id', q.board_id, 'board_name', q.board_name,
        'tribe_id', q.tribe_id, 'tribe_name', q.tribe_name,
        'reviewer_id', q.reviewer_id, 'reviewer_name', rm.name,
        'leader_reviewer_id', q.leader_reviewer_id,
        'review_round', q.current_round,
        'review_count', (SELECT count(*) FROM public.curation_review_log crl WHERE crl.board_item_id = q.id AND crl.review_round = q.current_round),
        'reviews_approved', (SELECT count(DISTINCT crl.curator_id) FROM public.curation_review_log crl WHERE crl.board_item_id = q.id AND crl.decision = 'approved' AND crl.review_round = q.current_round),
        'reviewers_required', q.reviewers_required,
        'peer_review_completed_at', q.peer_review_completed_at,
        'leader_review_completed_at', q.leader_review_completed_at,
        'due_at', q.curation_due_at,
        'sla_status', CASE
          WHEN q.curation_due_at IS NULL THEN 'no_sla'
          WHEN q.curation_due_at < now() THEN 'overdue'
          WHEN q.curation_due_at < now() + interval '2 days' THEN 'warning'
          ELSE 'on_time' END,
        'caller_reviewed_this_round', EXISTS (SELECT 1 FROM public.curation_review_log crl WHERE crl.board_item_id = q.id AND crl.curator_id = v_member_id AND crl.review_round = q.current_round),
        'eligible_actions', (
          SELECT COALESCE(jsonb_agg(a.act), '[]'::jsonb) FROM (
            SELECT 'submit_review'::text AS act
              WHERE v_can_govern
                AND NOT EXISTS (SELECT 1 FROM public.curation_review_log crl WHERE crl.board_item_id = q.id AND crl.curator_id = v_member_id AND crl.review_round = q.current_round)
            UNION ALL SELECT 'assign_reviewer' WHERE v_can_write_board
            UNION ALL SELECT 'publish' WHERE q.curation_status = 'curation_pending' AND (v_can_curate OR v_can_write_board)
          ) a
        )
      ) ORDER BY
        CASE
          WHEN q.curation_due_at IS NOT NULL AND q.curation_due_at < now() THEN 0
          WHEN q.curation_due_at IS NOT NULL AND q.curation_due_at < now() + interval '2 days' THEN 1
          ELSE 2 END,
        q.curation_due_at ASC NULLS LAST)
      FROM q LEFT JOIN public.members rm ON rm.id = q.reviewer_id
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total', (SELECT count(*) FROM q),
      'by_status', (SELECT COALESCE(jsonb_object_agg(s.curation_status, s.c), '{}'::jsonb) FROM (SELECT curation_status, count(*) c FROM q GROUP BY curation_status) s),
      'overdue', (SELECT count(*) FROM q WHERE curation_due_at < now())
    ),
    'caller', jsonb_build_object(
      'member_id', v_member_id,
      'can_curate', v_can_curate,
      'can_write_board', v_can_write_board,
      'can_govern', v_can_govern
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_curation_queue_state(text) TO authenticated;
