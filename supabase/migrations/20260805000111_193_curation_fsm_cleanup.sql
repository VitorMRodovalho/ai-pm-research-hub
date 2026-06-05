-- =====================================================================
-- #193 — Clean phantom curation FSM states + dead auto-publish trigger
-- =====================================================================
-- WHAT:
--   (1) DROP the dead auto-publish path: trigger trg_auto_publish_approved
--       on board_items + function auto_publish_approved_article(). The
--       trigger fires `WHEN (new.curation_status = 'approved')`, but
--       'approved' is NOT a member of the board_items_curation_status_check
--       CHECK ({draft,peer_review,leader_review,curation_pending,published}),
--       so the value is unreachable and the trigger never fires. The real
--       publish path is submit_curation_review() -> publish_board_item_from_curation()
--       which sets curation_status='published' directly, bypassing this trigger.
--   (2) Remove the phantom 'revision_requested' value from the items query
--       in get_curation_dashboard(). It is likewise not in the CHECK
--       constraint -> always matches 0 rows. The summary block already uses
--       only 'curation_pending'; this makes the items list consistent.
--       ZERO row-set change (live: 0 rows in 'approved' or 'revision_requested').
--
-- WHY: static grep of the curation FSM did not agree with the live schema.
--   Dead code masks the real state machine and confuses future readers.
--   Both removed paths are provably unreachable (live distinct curation_status
--   = {draft:590, leader_review:2, curation_pending:1}; 0 functions write
--   'approved' or 'revision_requested' to board_items.curation_status).
--
-- CANONICAL FSM (post-cleanup): draft -> peer_review -> leader_review ->
--   curation_pending -> published. Devoluções set curation_status='draft'
--   (submit_curation_review: returned_for_revision -> draft+status='review';
--   rejected -> draft+status='archived').
--
-- SCOPE LOCK: no behavior change (both removed paths are dead). No frontend
--   change. get_curation_dashboard() row-set and gate are byte-equivalent
--   except the dropped phantom value.
--
-- INVARIANTS: check_schema_invariants() stays 0 violations (no invariant
--   touches these objects).
--
-- ROLLBACK:
--   Re-CREATE auto_publish_approved_article() from its latest capture
--   (20260427200000_adr0015_phase3b_drop_4_safe_tables.sql; original source
--   20260312200000_w90_curation_audit_trail.sql) + re-CREATE trg_auto_publish_approved
--   from 20260319100019_w114_public_publications.sql, and restore the items WHERE
--   clause to IN ('curation_pending','revision_requested').
--
-- CROSS-REF: #193, #189 (visual alignment, separate PR), p197 FSM,
--   20260805000098 (#245 prior get_curation_dashboard capture).
-- =====================================================================

-- (1) Drop the dead auto-publish trigger + function (trigger first: it depends on the fn).
DROP TRIGGER IF EXISTS trg_auto_publish_approved ON public.board_items;
DROP FUNCTION IF EXISTS public.auto_publish_approved_article();

-- (2) Rewrite get_curation_dashboard() removing the phantom 'revision_requested'
--     from the items query. Body reproduced from the live 20260805000098 (#245)
--     capture with the additive curate_content OR write_board gate preserved.
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
        'review_count', (SELECT count(*) FROM curation_review_log crl WHERE crl.board_item_id = bi.id),
        'reviews_approved', (SELECT count(*) FROM curation_review_log crl WHERE crl.board_item_id = bi.id AND crl.decision = 'approved'),
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
