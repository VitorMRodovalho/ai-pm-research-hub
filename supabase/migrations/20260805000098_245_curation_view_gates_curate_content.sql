-- 20260805000098_245_curation_view_gates_curate_content.sql
--
-- Issue #245 (root cause = #185): curador + ponto focal lockout on /admin/curatorship.
--
-- The three curation-queue VIEW RPCs gated on `write_board` / `write`, but a pure
-- curator's authority is designation-derived (`curator` designation → `curate_content`)
-- and does NOT include `write_board`. So curators with operational_role <> manager
-- (Roberto Macêdo, Sarah Rodovalho — curate_content=true, write_board=false) were denied
-- at the RPC layer ("Curatorship access required"), even though the client gate
-- (hasPermission 'admin.curation' via curator designation) correctly let them through.
-- The only curator who worked (Fabricio Costa) is incidentally also a manager (write_board).
--
-- FIX (additive, zero-regression): gate = curate_content OR (existing write_board/write).
--   - Unblocks the 2 pure curators (curate_content=true).
--   - Nobody loses access: the 6 tribe_leaders + 2 managers who pass today via write_board
--     keep passing. (Whether non-curators *should* see the curation queue is the deliberate
--     tightening tracked in #185 — intentionally NOT done here.)
-- The review WRITE action `submit_curation_review` (live body verified 2026-06-03) gates on
-- `participate_in_governance_review`, which curators hold — so this view-gate fix fully
-- unblocks both viewing and reviewing for curators.
--
-- DEFERRED (tracked on #185, NOT in scope here): `list_curation_board` (the first leg of the
-- island's legacy fallback) still has NO auth gate in its body, and the deliberate "tighten to
-- curate_content-only / remove non-curator write_board access" decision both belong to #185.
--
-- ROLLBACK: re-apply the prior bodies (gate = `write_board` / `write` only) from
--   migration history (pg_get_functiondef pre-098), or drop the curate_content arm of the OR.
-- No signature change (DROP+CREATE not required); SECURITY DEFINER + search_path preserved.

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
  -- #245/#185: curation authority = curate_content (designation-derived) OR write_board (admin/manager/tribe-lead).
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
      WHERE bi.curation_status IN ('curation_pending', 'revision_requested')
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

CREATE OR REPLACE FUNCTION public.list_curation_pending_board_items()
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- #245/#185: curation authority = curate_content (designation-derived) OR write_board (admin/manager/tribe-lead).
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public.can_by_member(v_member_id, 'write_board')) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.curation_status, bi.assignee_id, bi.reviewer_id,
      bi.due_date, bi.curation_due_at, bi.board_id,
      i.legacy_tribe_id AS tribe_id, i.title AS tribe_name,
      am.name AS assignee_name, rm.name AS reviewer_name,
      bi.created_at, bi.updated_at, bi.attachments,
      (SELECT count(*) FROM public.curation_review_log crl WHERE crl.board_item_id = bi.id) AS review_count,
      (SELECT json_agg(json_build_object(
        'id', crl2.id, 'curator_name', cm.name,
        'decision', crl2.decision, 'feedback', crl2.feedback_notes,
        'scores', crl2.criteria_scores, 'completed_at', crl2.completed_at
       ) ORDER BY crl2.completed_at DESC)
       FROM public.curation_review_log crl2
       LEFT JOIN public.members cm ON cm.id = crl2.curator_id
       WHERE crl2.board_item_id = bi.id
      ) AS review_history
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    LEFT JOIN public.members am ON am.id = bi.assignee_id
    LEFT JOIN public.members rm ON rm.id = bi.reviewer_id
    WHERE bi.curation_status = 'curation_pending'
      AND bi.status <> 'archived'
      AND pb.is_active = true
    ORDER BY bi.curation_due_at ASC NULLS LAST, bi.updated_at DESC
  ) r;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_pending_curation(p_table text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; v_result jsonb := '[]'::jsonb; v_resources jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- #245/#185: curation authority = curate_content (designation-derived) OR write.
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public.can_by_member(v_member_id, 'write')) THEN RAISE EXCEPTION 'Insufficient permissions'; END IF;

  -- ADR-0012 archival: artifacts branch removed. publication_submissions flow via approval_chains.
  IF p_table IN ('all', 'hub_resources') THEN
    SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_resources
    FROM (
      SELECT h.id, h.title, h.url, h.asset_type AS type, h.source, h.tags,
             h.curation_status, h.trello_card_id, h.cycle_code AS cycle,
             h.created_at, NULL::text AS author_name,
             i.title AS tribe_name,
             'hub_resources' AS _table,
             public.suggest_tags(h.title, h.asset_type, h.cycle_code) AS suggested_tags
      FROM public.hub_resources h
      LEFT JOIN public.initiatives i ON i.id = h.initiative_id
      WHERE h.source IS DISTINCT FROM 'manual'
        AND h.curation_status IN ('draft','pending_review')
      ORDER BY h.created_at DESC LIMIT 200
    ) r;
    v_result := v_result || COALESCE(v_resources, '[]'::jsonb);
  END IF;
  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
