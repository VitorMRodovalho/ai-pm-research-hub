-- =====================================================================
-- #192 (companion) — make get_curation_dashboard counters round-aware
-- =====================================================================
-- WHAT: after #192 (mig 113) partitioned curation_review_log by review_round
--   and changed the publish-consensus to count(DISTINCT curator_id) in the
--   CURRENT round, the admin dashboard's display counters still counted ROWS
--   across ALL rounds:
--     'review_count'     = count(*) over all rounds
--     'reviews_approved' = count(*) approved over all rounds
--   Once an item reaches round 2 this diverges from the enforcing logic (e.g.
--   shows "3 of 2 approved" after round-2 quorum already published). This makes
--   both counters round-scoped and aligns 'reviews_approved' with the gate:
--   count(DISTINCT curator_id) in the current round.
--
-- WHY: ADR-0012 schema-contract — a metric on the /admin/curatorship dashboard
--   must match the logic it represents (caught by data-architect on PR #535).
--
-- SCOPE LOCK: only the two item sub-selects change; the rest of
--   get_curation_dashboard (gate, ORDER BY, review_history, summary) is
--   reproduced byte-equivalent from mig 20260805000111 (#193). Zero inline
--   body comments (Phase-C safe). Current round derived the same way as
--   submit_curation_review: max(review_round) over board_lifecycle_events
--   action='reviewer_assigned', coalesce 1.
--
-- INVARIANTS: check_schema_invariants() unaffected.
-- ROLLBACK: restore the two sub-selects to count(*) over all rounds
--   (mig 20260805000111 form).
-- CROSS-REF: #192, #193 (prior get_curation_dashboard capture), ADR-0012.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_curation_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public.can_by_member(v_member_id, 'write_board')) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  SELECT jsonb_build_object(
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id, 'title', bi.title, 'description', bi.description,
        'status', bi.status, 'curation_status', bi.curation_status,
        'curation_due_at', bi.curation_due_at, 'board_id', bi.board_id,
        'board_name', pb.board_name, 'tribe_id', i.legacy_tribe_id, 'tribe_name', i.title,
        'assignee_id', bi.assignee_id, 'assignee_name', am.name,
        'reviewer_id', bi.reviewer_id, 'reviewer_name', rm.name,
        'tags', bi.tags, 'attachments', bi.attachments,
        'created_at', bi.created_at, 'updated_at', bi.updated_at,
        'review_count', (SELECT count(*) FROM curation_review_log crl WHERE crl.board_item_id = bi.id AND crl.review_round = (SELECT coalesce(max(ble.review_round), 1) FROM board_lifecycle_events ble WHERE ble.item_id = bi.id AND ble.action = 'reviewer_assigned')),
        'reviews_approved', (SELECT count(DISTINCT crl.curator_id) FROM curation_review_log crl WHERE crl.board_item_id = bi.id AND crl.decision = 'approved' AND crl.review_round = (SELECT coalesce(max(ble.review_round), 1) FROM board_lifecycle_events ble WHERE ble.item_id = bi.id AND ble.action = 'reviewer_assigned')),
        'reviewers_required', COALESCE(sc.reviewers_required, 2),
        'sla_status', CASE
          WHEN bi.curation_due_at IS NULL THEN 'no_sla'
          WHEN bi.curation_due_at < now() THEN 'overdue'
          WHEN bi.curation_due_at < now() + interval '2 days' THEN 'warning'
          ELSE 'on_time'
        END,
        'review_history', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', crl2.id, 'curator_name', cm.name, 'decision', crl2.decision,
            'feedback', crl2.feedback_notes, 'scores', crl2.criteria_scores,
            'completed_at', crl2.completed_at
          ) ORDER BY crl2.completed_at DESC), '[]'::jsonb)
          FROM curation_review_log crl2
          LEFT JOIN members cm ON cm.id = crl2.curator_id
          WHERE crl2.board_item_id = bi.id
        )
      ) ORDER BY
        CASE
          WHEN bi.curation_due_at IS NOT NULL AND bi.curation_due_at < now() THEN 0
          WHEN bi.curation_due_at IS NOT NULL AND bi.curation_due_at < now() + interval '2 days' THEN 1
          ELSE 2
        END,
        bi.curation_due_at ASC NULLS LAST
      )
      FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      LEFT JOIN initiatives i ON i.id = pb.initiative_id
      LEFT JOIN members am ON am.id = bi.assignee_id
      LEFT JOIN members rm ON rm.id = bi.reviewer_id
      LEFT JOIN board_sla_config sc ON sc.board_id = bi.board_id
      WHERE bi.curation_status = 'curation_pending'
        AND bi.status <> 'archived'
        AND pb.is_active = true
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total_pending', (SELECT count(*) FROM board_items bi2 JOIN project_boards pb2 ON pb2.id = bi2.board_id WHERE bi2.curation_status = 'curation_pending' AND bi2.status <> 'archived' AND pb2.is_active = true),
      'overdue', (SELECT count(*) FROM board_items bi3 JOIN project_boards pb3 ON pb3.id = bi3.board_id WHERE bi3.curation_status = 'curation_pending' AND bi3.curation_due_at < now() AND bi3.status <> 'archived' AND pb3.is_active = true)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
