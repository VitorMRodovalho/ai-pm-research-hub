-- #785 — Gate ungated SECURITY DEFINER content readers behind the confidential
-- initiative visibility gate (rls_can_see_initiative / rls_can_see_board / rls_can_see_item).
--
-- Closes the live leak where ~22 SECDEF readers returned a confidential
-- initiative's board/items/events to non-engaged members (enumeration + detail).
-- PR-3 (#838) gated some readers via rls_can_see_board; PR-4 (#236/#237) gated
-- the event/roster RPCs. This migration covers the remaining content readers.
--
-- The gate is BEHAVIOR-NEUTRAL for every non-confidential / org-level initiative
-- and for engaged members + GP (manage_platform). It only excludes the 1
-- confidential initiative's rows for non-engaged non-GP callers.
--
-- Scoped readers use an early-return guard; enumerators add a per-row predicate.
-- Bodies are byte-minimal deltas vs the live definitions (guard only).
-- Allowlisted as already-safe (no change): get_board, get_card_detail,
-- get_board_item_drive_access, list_initiative_boards, search_initiative_board_items,
-- get_weekly_initiative_digest, get_global_research_pipeline.

-- ---------------------------------------------------------------------------
-- Helper: item-level visibility (mirrors rls_can_see_board). Created FIRST so
-- the readers below resolve it at creation time (check_function_bodies).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rls_can_see_item(p_item_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT public.rls_can_see_board(
    (SELECT bi.board_id FROM public.board_items bi WHERE bi.id = p_item_id)
  );
$function$;

-- ---------------------------------------------------------------------------
-- Guarded content readers (22) — verified minimal-diff + adversarially reviewed.
-- ---------------------------------------------------------------------------
-- get_board_activities(p_board_id uuid, p_limit integer)
CREATE OR REPLACE FUNCTION public.get_board_activities(p_board_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_result jsonb;
BEGIN
  SELECT id, tribe_id, is_superadmin, operational_role
  INTO v_member FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(evt)::jsonb ORDER BY evt.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      ble.id,
      ble.action,
      ble.previous_status,
      ble.new_status,
      ble.reason,
      ble.created_at,
      ble.review_round,
      bi.title as item_title,
      m.name as actor_name
    FROM board_lifecycle_events ble
    JOIN board_items bi ON bi.id = ble.item_id
    LEFT JOIN members m ON m.id = ble.actor_member_id
    WHERE (p_board_id IS NULL OR ble.board_id = p_board_id)
      AND public.rls_can_see_board(bi.board_id)
    ORDER BY ble.created_at DESC
    LIMIT p_limit
  ) evt;

  RETURN jsonb_build_object(
    'activities', v_result,
    'count', jsonb_array_length(v_result)
  );
END;
$function$;

-- get_board_activities(p_board_id uuid, p_assignee_filter uuid, p_status_filter text, p_period_filter text)
CREATE OR REPLACE FUNCTION public.get_board_activities(p_board_id uuid, p_assignee_filter uuid DEFAULT NULL::uuid, p_status_filter text DEFAULT 'all'::text, p_period_filter text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_result jsonb;
  v_total bigint;
  v_completed bigint;
  v_pending bigint;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- #785 PR-3: confidential gate (board→initiative)
  IF NOT public.rls_can_see_board(p_board_id) THEN
    RETURN jsonb_build_object('activities', '[]'::jsonb, 'total', 0, 'completed', 0, 'pending', 0);
  END IF;

  SELECT jsonb_agg(row_data ORDER BY card_title, position) INTO v_result
  FROM (
    SELECT
      jsonb_build_object(
        'id', c.id,
        'card_id', bi.id,
        'card_title', bi.title,
        'card_status', bi.status,
        'card_baseline', bi.baseline_date,
        'card_forecast', bi.forecast_date,
        'is_portfolio_item', bi.is_portfolio_item,
        'text', c.text,
        'done', c.is_completed,
        'assignee_id', c.assigned_to,
        'assignee_name', (SELECT name FROM members WHERE id = c.assigned_to),
        'target_date', c.target_date,
        'completed_at', c.completed_at,
        'completed_by_name', (SELECT name FROM members WHERE id = c.completed_by),
        'position', c.position
      ) as row_data,
      bi.title as card_title,
      c.position
    FROM board_item_checklists c
    JOIN board_items bi ON bi.id = c.board_item_id
    WHERE bi.board_id = p_board_id
      AND bi.status != 'archived'
      AND (p_assignee_filter IS NULL OR c.assigned_to = p_assignee_filter)
      AND (p_status_filter = 'all'
        OR (p_status_filter = 'pending' AND c.is_completed = false)
        OR (p_status_filter = 'completed' AND c.is_completed = true))
      AND (p_period_filter = 'all'
        OR (p_period_filter = 'overdue' AND c.target_date < CURRENT_DATE AND c.is_completed = false)
        OR (p_period_filter = 'week' AND c.target_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 7)
        OR (p_period_filter = 'month' AND c.target_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30))
  ) sub;

  SELECT count(*), count(*) FILTER (WHERE is_completed), count(*) FILTER (WHERE NOT is_completed)
  INTO v_total, v_completed, v_pending
  FROM board_item_checklists c
  JOIN board_items bi ON bi.id = c.board_item_id
  WHERE bi.board_id = p_board_id AND bi.status != 'archived';

  RETURN jsonb_build_object(
    'activities', COALESCE(v_result, '[]'::jsonb),
    'total', v_total,
    'completed', v_completed,
    'pending', v_pending
  );
END;
$function$;

-- get_board_tags(p_board_id uuid)
CREATE OR REPLACE FUNCTION public.get_board_tags(p_board_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  -- First try tags from this specific board
  SELECT jsonb_agg(DISTINCT tag ORDER BY tag) INTO v_result
  FROM (SELECT unnest(tags) as tag FROM board_items WHERE board_id = p_board_id AND public.rls_can_see_board(board_id) AND tags IS NOT NULL AND array_length(tags, 1) > 0) sub
  WHERE tag IS NOT NULL AND tag != '';
  
  -- If empty, fallback to tags from ALL active boards (global suggestions)
  IF v_result IS NULL OR jsonb_array_length(v_result) = 0 THEN
    SELECT jsonb_agg(DISTINCT tag ORDER BY tag) INTO v_result
    FROM (
      SELECT unnest(tags) as tag FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      WHERE pb.is_active = true AND public.rls_can_see_board(pb.id) AND bi.tags IS NOT NULL AND array_length(bi.tags, 1) > 0
    ) sub
    WHERE tag IS NOT NULL AND tag != '';
  END IF;
  
  RETURN COALESCE(v_result, '[]'::jsonb);
END; $function$;

-- get_board_drive_links(p_board_id uuid)
CREATE OR REPLACE FUNCTION public.get_board_drive_links(p_board_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- #785: confidential initiative visibility gate
  IF NOT public.rls_can_see_board(p_board_id) THEN
    RETURN jsonb_build_object('board_id', p_board_id, 'drive_links', '[]'::jsonb, 'fetched_at', now());
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'linked_by_name', m.name,
    'linked_at', l.linked_at
  ) ORDER BY l.linked_at DESC), '[]'::jsonb)
  INTO v_result
  FROM public.board_drive_links l
  LEFT JOIN public.members m ON m.id = l.linked_by
  WHERE l.board_id = p_board_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object(
    'board_id', p_board_id,
    'drive_links', v_result,
    'fetched_at', now()
  );
END;
$function$;

-- list_board_items(p_board_id uuid, p_status text)
CREATE OR REPLACE FUNCTION public.list_board_items(p_board_id uuid, p_status text DEFAULT NULL::text)
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.rls_can_see_board(p_board_id) THEN RETURN; END IF;  -- #785
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id,
      bi.title,
      bi.description,
      bi.status,
      bi.curation_status,
      bi.reviewer_id,
      bi.tags,
      bi.labels,
      bi.due_date,
      bi.position,
      bi.cycle,
      bi.attachments,
      bi.checklist,
      bi.created_at,
      bi.updated_at,
      m.name AS assignee_name,
      m.photo_url AS assignee_photo,
      rm.name AS reviewer_name
    FROM board_items bi
    LEFT JOIN members m ON m.id = bi.assignee_id
    LEFT JOIN members rm ON rm.id = bi.reviewer_id
    WHERE bi.board_id = p_board_id
      AND (p_status IS NULL OR bi.status = p_status)
      AND bi.status <> 'archived'
    ORDER BY bi.position ASC, bi.created_at DESC
  ) r;
END;
$function$;

-- get_mirror_target_boards(p_source_board_id uuid)
CREATE OR REPLACE FUNCTION public.get_mirror_target_boards(p_source_board_id uuid)
 RETURNS TABLE(board_id uuid, board_name text, board_scope text, item_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    pb.id,
    pb.board_name,
    pb.board_scope,
    (SELECT count(*) FROM public.board_items bi WHERE bi.board_id = pb.id AND bi.status != 'archived')
  FROM public.project_boards pb
  WHERE pb.id != p_source_board_id
    AND pb.is_active = true
    AND public.rls_can_see_board(pb.id)  -- #785
  ORDER BY pb.board_scope, pb.board_name;
END;
$function$;

-- admin_list_archived_board_items(p_board_id uuid, p_limit integer)
CREATE OR REPLACE FUNCTION public.admin_list_archived_board_items(p_board_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 200)
 RETURNS TABLE(id uuid, board_id uuid, board_name text, board_scope text, domain_key text, title text, assignee_name text, due_date date, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Auth required';
  END IF;

  -- V4 gate (Opção B reuse view_internal_analytics — same precedent as ADR-0031)
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Board governance access required';
  END IF;

  RETURN QUERY
  SELECT
    bi.id,
    bi.board_id,
    pb.board_name,
    pb.board_scope,
    COALESCE(pb.domain_key, '') AS domain_key,
    bi.title,
    COALESCE(m.name, '') AS assignee_name,
    bi.due_date,
    bi.updated_at
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  LEFT JOIN public.members m ON m.id = bi.assignee_id
  WHERE bi.status = 'archived'
    AND (p_board_id IS NULL OR bi.board_id = p_board_id)
    AND public.rls_can_see_board(bi.board_id)  -- #785
  ORDER BY bi.updated_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 200), 1000));
END;
$function$;

-- get_card_full_history(p_card_id uuid)
CREATE OR REPLACE FUNCTION public.get_card_full_history(p_card_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_card record;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  SELECT bi.id, bi.title, bi.description, bi.status, bi.curation_status,
         bi.board_id, bi.assignee_id, bi.created_at, bi.updated_at
  INTO v_card FROM public.board_items bi WHERE bi.id = p_card_id;
  IF v_card.id IS NULL THEN
    RETURN jsonb_build_object('error', 'card_not_found');
  END IF;

  -- #785: confidential gate (board->initiative; same not_found shape to avoid leaking existence)
  IF NOT public.rls_can_see_board(v_card.board_id) THEN
    RETURN jsonb_build_object('error', 'card_not_found');
  END IF;

  v_result := jsonb_build_object(
    'card', jsonb_build_object(
      'id', v_card.id,
      'title', v_card.title,
      'description', v_card.description,
      'status', v_card.status,
      'curation_status', v_card.curation_status,
      'board_id', v_card.board_id,
      'assignee_id', v_card.assignee_id,
      'created_at', v_card.created_at,
      'updated_at', v_card.updated_at
    ),
    'lifecycle_events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ble.id,
        'action', ble.action,
        'reason', ble.reason,
        'actor_member_id', ble.actor_member_id,
        'actor_name', am.name,
        'created_at', ble.created_at,
        'review_round', ble.review_round,
        'review_score', ble.review_score
      ) ORDER BY ble.created_at DESC)
      FROM public.board_lifecycle_events ble
      LEFT JOIN public.members am ON am.id = ble.actor_member_id
      WHERE ble.item_id = p_card_id
    ), '[]'::jsonb),
    'meeting_links', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', biel.id,
        'event_id', biel.event_id,
        'event_title', e.title,
        'event_date', e.date,
        'link_type', biel.link_type,
        'note', biel.note,
        'author_id', biel.author_id,
        'author_name', am.name,
        'created_at', biel.created_at
      ) ORDER BY biel.created_at DESC)
      FROM public.board_item_event_links biel
      LEFT JOIN public.events e ON e.id = biel.event_id
      LEFT JOIN public.members am ON am.id = biel.author_id
      WHERE biel.board_item_id = p_card_id
    ), '[]'::jsonb),
    'action_items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', mai.id,
        'event_id', mai.event_id,
        'event_title', e.title,
        'event_date', e.date,
        'description', mai.description,
        'kind', mai.kind,
        'status', mai.status,
        'assignee_name', mai.assignee_name,
        'due_date', mai.due_date,
        'resolved_at', mai.resolved_at,
        'resolution_note', mai.resolution_note
      ) ORDER BY mai.created_at DESC)
      FROM public.meeting_action_items mai
      LEFT JOIN public.events e ON e.id = mai.event_id
      WHERE mai.board_item_id = p_card_id
    ), '[]'::jsonb),
    'showcases', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', es.id,
        'event_id', es.event_id,
        'event_title', e.title,
        'event_date', e.date,
        'member_id', es.member_id,
        'member_name', m.name,
        'showcase_type', es.showcase_type,
        'title', es.title,
        'notes', es.notes,
        'duration_min', es.duration_min,
        'xp_awarded', es.xp_awarded
      ) ORDER BY es.created_at DESC)
      FROM public.event_showcases es
      LEFT JOIN public.events e ON e.id = es.event_id
      LEFT JOIN public.members m ON m.id = es.member_id
      WHERE es.board_item_id = p_card_id
    ), '[]'::jsonb),
    'curation_reviews', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', crl.id,
        'curator_id', crl.curator_id,
        'curator_name', cm.name,
        'decision', crl.decision,
        'criteria_scores', crl.criteria_scores,
        'feedback_notes', crl.feedback_notes,
        'completed_at', crl.completed_at,
        'due_date', crl.due_date
      ) ORDER BY crl.completed_at DESC NULLS LAST)
      FROM public.curation_review_log crl
      LEFT JOIN public.members cm ON cm.id = crl.curator_id
      WHERE crl.board_item_id = p_card_id
    ), '[]'::jsonb),
    'generated_at', now()
  );

  RETURN v_result;
END;
$function$;

-- get_card_timeline(p_item_id uuid)
CREATE OR REPLACE FUNCTION public.get_card_timeline(p_item_id uuid)
 RETURNS TABLE(id bigint, action text, previous_status text, new_status text, reason text, actor_name text, created_at timestamp with time zone, review_score jsonb, review_round integer, sla_deadline timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- #785: confidential gate (item->board->initiative)
  IF NOT public.rls_can_see_item(p_item_id) THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    e.id,
    e.action,
    e.previous_status,
    e.new_status,
    e.reason,
    m.name AS actor_name,
    e.created_at,
    e.review_score,
    e.review_round,
    e.sla_deadline
  FROM board_lifecycle_events e
  LEFT JOIN members m ON m.id = e.actor_member_id
  WHERE e.item_id = p_item_id
  ORDER BY e.created_at DESC;
END;
$function$;

-- get_item_assignments(p_item_id uuid)
CREATE OR REPLACE FUNCTION public.get_item_assignments(p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_has_junction boolean;
BEGIN
  -- #785: confidential gate (item->board->initiative)
  IF NOT public.rls_can_see_item(p_item_id) THEN RETURN '[]'::jsonb; END IF;
  SELECT EXISTS(SELECT 1 FROM board_item_assignments WHERE item_id = p_item_id)
  INTO v_has_junction;

  IF v_has_junction THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', bia.id,
      'member_id', bia.member_id,
      'name', m.name,
      'avatar_url', m.photo_url,
      'role', bia.role,
      'assigned_at', bia.assigned_at
    ) ORDER BY
      CASE bia.role
        WHEN 'author' THEN 0
        WHEN 'reviewer' THEN 1
        WHEN 'curation_reviewer' THEN 2
        WHEN 'contributor' THEN 3
      END,
      bia.assigned_at
    ), '[]'::jsonb) INTO v_result
    FROM board_item_assignments bia
    JOIN members m ON m.id = bia.member_id
    WHERE bia.item_id = p_item_id;
  ELSE
    -- Fallback: read from legacy assignee_id / reviewer_id
    SELECT coalesce(jsonb_agg(x ORDER BY x->>'role'), '[]'::jsonb) INTO v_result
    FROM (
      SELECT jsonb_build_object(
        'id', null,
        'member_id', bi.assignee_id,
        'name', am.name,
        'avatar_url', am.photo_url,
        'role', 'author',
        'assigned_at', bi.updated_at
      ) AS x
      FROM board_items bi
      LEFT JOIN members am ON am.id = bi.assignee_id
      WHERE bi.id = p_item_id AND bi.assignee_id IS NOT NULL
      UNION ALL
      SELECT jsonb_build_object(
        'id', null,
        'member_id', bi.reviewer_id,
        'name', rm.name,
        'avatar_url', rm.photo_url,
        'role', 'reviewer',
        'assigned_at', bi.updated_at
      )
      FROM board_items bi
      LEFT JOIN members rm ON rm.id = bi.reviewer_id
      WHERE bi.id = p_item_id AND bi.reviewer_id IS NOT NULL
    ) sub;
  END IF;

  RETURN v_result;
END;
$function$;

-- get_item_curation_history(p_item_id uuid)
CREATE OR REPLACE FUNCTION public.get_item_curation_history(p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  -- #785: confidential gate (item->board->initiative)
  IF NOT public.rls_can_see_item(p_item_id) THEN
    RETURN jsonb_build_object('reviews', '[]'::jsonb, 'assignments', '[]'::jsonb, 'sla_config', '{}'::jsonb);
  END IF;
  SELECT jsonb_build_object(
    'reviews', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', crl.id,
        'curator_name', m.name,
        'curator_id', crl.curator_id,
        'decision', crl.decision,
        'criteria_scores', crl.criteria_scores,
        'feedback_notes', crl.feedback_notes,
        'completed_at', crl.completed_at
      ) ORDER BY crl.completed_at DESC)
      FROM curation_review_log crl
      LEFT JOIN members m ON m.id = crl.curator_id
      WHERE crl.board_item_id = p_item_id
    ), '[]'::jsonb),
    'assignments', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'reviewer_name', m.name,
        'reviewer_id', ble.actor_member_id,
        'round', ble.review_round,
        'assigned_at', ble.created_at,
        'sla_deadline', ble.sla_deadline
      ) ORDER BY ble.created_at DESC)
      FROM board_lifecycle_events ble
      LEFT JOIN members m ON m.id = ble.actor_member_id
      WHERE ble.item_id = p_item_id AND ble.action = 'reviewer_assigned'
    ), '[]'::jsonb),
    'sla_config', coalesce((
      SELECT jsonb_build_object(
        'sla_days', sc.sla_days,
        'reviewers_required', sc.reviewers_required,
        'max_review_rounds', sc.max_review_rounds,
        'rubric_criteria', sc.rubric_criteria
      )
      FROM board_sla_config sc
      JOIN board_items bi ON bi.board_id = sc.board_id
      WHERE bi.id = p_item_id
    ), '{}'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- list_card_comments(p_board_item_id uuid)
CREATE OR REPLACE FUNCTION public.list_card_comments(p_board_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Anyone authenticated who can SELECT board_items can read comments
  IF NOT EXISTS (SELECT 1 FROM public.board_items WHERE id = p_board_item_id) THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  -- #785: confidential initiative visibility gate
  IF NOT public.rls_can_see_item(p_board_item_id) THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'author_id', c.author_id,
    'author_name', m.name,
    'author_photo_url', m.photo_url,
    'body', c.body,
    'parent_comment_id', c.parent_comment_id,
    'mentioned_member_ids', c.mentioned_member_ids,
    'edited_at', c.edited_at,
    'created_at', c.created_at
  ) ORDER BY c.created_at ASC), '[]'::jsonb)
  INTO v_result
  FROM public.board_item_comments c
  LEFT JOIN public.members m ON m.id = c.author_id
  WHERE c.board_item_id = p_board_item_id
    AND c.deleted_at IS NULL;

  RETURN jsonb_build_object('card_id', p_board_item_id, 'comments', v_result);
END;
$function$;

-- list_card_drive_files(p_board_item_id uuid)
CREATE OR REPLACE FUNCTION public.list_card_drive_files(p_board_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_files jsonb;
  v_initiative_folders jsonb;
  v_board_folders jsonb;
  v_board_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT bi.board_id, pb.initiative_id
    INTO v_board_id, v_initiative_id
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.id = p_board_item_id;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  -- #785: confidential initiative visibility gate
  IF NOT public.rls_can_see_board(v_board_id) THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  -- Card-level files
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id,
    'drive_file_id', f.drive_file_id,
    'drive_file_url', f.drive_file_url,
    'filename', f.filename,
    'mime_type', f.mime_type,
    'size_bytes', f.size_bytes,
    'uploaded_by_name', m.name,
    'uploaded_via', f.uploaded_via,
    'created_at', f.created_at
  ) ORDER BY f.created_at DESC), '[]'::jsonb)
  INTO v_files
  FROM public.board_item_files f
  LEFT JOIN public.members m ON m.id = f.uploaded_by
  WHERE f.board_item_id = p_board_item_id AND f.deleted_at IS NULL;

  -- Initiative-level folder links (Hub de Comunicacao folder + Atas)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'link_purpose', l.link_purpose,
    'linked_at', l.linked_at
  ) ORDER BY l.link_purpose NULLS LAST, l.linked_at), '[]'::jsonb)
  INTO v_initiative_folders
  FROM public.initiative_drive_links l
  WHERE l.initiative_id = v_initiative_id AND l.unlinked_at IS NULL;

  -- Board-level folder links (rare but supported)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'linked_at', l.linked_at
  ) ORDER BY l.linked_at), '[]'::jsonb)
  INTO v_board_folders
  FROM public.board_drive_links l
  WHERE l.board_id = v_board_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object(
    'board_item_id', p_board_item_id,
    'files', v_files,
    'initiative_folders', v_initiative_folders,
    'board_folders', v_board_folders,
    'fetched_at', now()
  );
END;
$function$;

-- get_tribe_housekeeping(p_initiative_id uuid, p_legacy_tribe_id integer)
CREATE OR REPLACE FUNCTION public.get_tribe_housekeeping(p_initiative_id uuid DEFAULT NULL::uuid, p_legacy_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_initiative record;
  v_current_cycle text;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF p_initiative_id IS NOT NULL THEN
    SELECT id, title, kind, legacy_tribe_id
    INTO v_initiative FROM public.initiatives WHERE id = p_initiative_id;
  ELSIF p_legacy_tribe_id IS NOT NULL THEN
    SELECT id, title, kind, legacy_tribe_id
    INTO v_initiative FROM public.initiatives
    WHERE legacy_tribe_id = p_legacy_tribe_id
    LIMIT 1;
  END IF;

  IF v_initiative.id IS NULL THEN
    RETURN jsonb_build_object('error', 'initiative_not_found',
      'hint', 'Provide p_initiative_id or p_legacy_tribe_id');
  END IF;

  -- #785: confidential initiative visibility gate
  IF NOT public.rls_can_see_initiative(v_initiative.id) THEN
    RETURN jsonb_build_object('error', 'initiative_not_found',
      'hint', 'Provide p_initiative_id or p_legacy_tribe_id');
  END IF;

  SELECT cycle_code INTO v_current_cycle
  FROM public.tribe_deliverables
  WHERE initiative_id = v_initiative.id
    AND status NOT IN ('cancelled')
  ORDER BY created_at DESC LIMIT 1;
  v_current_cycle := COALESCE(v_current_cycle, 'cycle3-2026');

  v_result := jsonb_build_object(
    'initiative', jsonb_build_object(
      'id', v_initiative.id,
      'title', v_initiative.title,
      'kind', v_initiative.kind,
      'legacy_tribe_id', v_initiative.legacy_tribe_id
    ),
    'current_cycle', v_current_cycle,

    'kpis_contributed', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'kpi_target_id', akt.id,
        'kpi_key', akt.kpi_key,
        'kpi_label_pt', akt.kpi_label_pt,
        'category', akt.category,
        'target_value', akt.target_value,
        'current_value', akt.current_value,
        'baseline_value', akt.baseline_value,
        'attainment_pct', CASE WHEN akt.target_value IS NOT NULL AND akt.target_value <> 0
          THEN ROUND((COALESCE(akt.current_value, 0) / akt.target_value * 100)::numeric, 1)
          ELSE NULL END,
        'status_color', CASE
          WHEN akt.target_value IS NULL OR akt.target_value = 0 THEN 'gray'
          WHEN COALESCE(akt.current_value, 0) >= akt.target_value * 0.9 THEN 'green'
          WHEN COALESCE(akt.current_value, 0) >= akt.target_value * 0.7 THEN 'yellow'
          ELSE 'red' END,
        'weight', tkc.weight,
        'contribution_query', tkc.contribution_query,
        'icon', akt.icon
      ) ORDER BY akt.display_order)
      FROM public.tribe_kpi_contributions tkc
      JOIN public.annual_kpi_targets akt ON akt.id = tkc.kpi_target_id
      WHERE tkc.initiative_id = v_initiative.id
    ), '[]'::jsonb),

    'cards_linked_to_kpis', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'card_id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'assignee_id', bi.assignee_id,
        'assignee_name', am.name,
        'tags', bi.tags,
        'due_date', bi.due_date,
        'matched_kpi_keys', (
          SELECT COALESCE(jsonb_agg(akt.kpi_key), '[]'::jsonb)
          FROM public.tribe_kpi_contributions tkc2
          JOIN public.annual_kpi_targets akt ON akt.id = tkc2.kpi_target_id
          WHERE tkc2.initiative_id = v_initiative.id
            AND akt.kpi_key = ANY(COALESCE(bi.tags, ARRAY[]::text[]))
        )
      ) ORDER BY bi.updated_at DESC)
      FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.members am ON am.id = bi.assignee_id
      WHERE pb.initiative_id = v_initiative.id
        AND pb.is_active = true
        AND bi.status NOT IN ('archived')
        AND EXISTS (
          SELECT 1 FROM public.tribe_kpi_contributions tkc3
          JOIN public.annual_kpi_targets akt2 ON akt2.id = tkc3.kpi_target_id
          WHERE tkc3.initiative_id = v_initiative.id
            AND akt2.kpi_key = ANY(COALESCE(bi.tags, ARRAY[]::text[]))
        )
      LIMIT 100
    ), '[]'::jsonb),

    'cycle_deliverables', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', td.id,
        'title', td.title,
        'cycle_code', td.cycle_code,
        'status', td.status,
        'assigned_member_id', td.assigned_member_id,
        'assignee_name', tdm.name,
        'due_date', td.due_date,
        'days_to_due', CASE WHEN td.due_date IS NOT NULL
          THEN (td.due_date - CURRENT_DATE) ELSE NULL END,
        'has_artifact', td.artifact_id IS NOT NULL
      ) ORDER BY
        CASE WHEN td.status = 'done' THEN 1 ELSE 0 END,
        td.due_date NULLS LAST)
      FROM public.tribe_deliverables td
      LEFT JOIN public.members tdm ON tdm.id = td.assigned_member_id
      WHERE td.initiative_id = v_initiative.id
        AND td.cycle_code = v_current_cycle
    ), '[]'::jsonb),

    'rollup', jsonb_build_object(
      'kpis_total', (SELECT COUNT(*) FROM public.tribe_kpi_contributions WHERE initiative_id = v_initiative.id),
      'kpis_red', (SELECT COUNT(*) FROM public.tribe_kpi_contributions tkc4
        JOIN public.annual_kpi_targets akt3 ON akt3.id = tkc4.kpi_target_id
        WHERE tkc4.initiative_id = v_initiative.id
          AND akt3.target_value > 0
          AND COALESCE(akt3.current_value, 0) < akt3.target_value * 0.7),
      'kpis_yellow', (SELECT COUNT(*) FROM public.tribe_kpi_contributions tkc5
        JOIN public.annual_kpi_targets akt4 ON akt4.id = tkc5.kpi_target_id
        WHERE tkc5.initiative_id = v_initiative.id
          AND akt4.target_value > 0
          AND COALESCE(akt4.current_value, 0) >= akt4.target_value * 0.7
          AND COALESCE(akt4.current_value, 0) < akt4.target_value * 0.9),
      'cycle_deliverables_total', (SELECT COUNT(*) FROM public.tribe_deliverables
        WHERE initiative_id = v_initiative.id AND cycle_code = v_current_cycle),
      'cycle_deliverables_done', (SELECT COUNT(*) FROM public.tribe_deliverables
        WHERE initiative_id = v_initiative.id AND cycle_code = v_current_cycle AND status = 'done')
    ),

    'generated_at', now()
  );

  RETURN v_result;
END;
$function$;

-- list_active_boards()
CREATE OR REPLACE FUNCTION public.list_active_boards()
 RETURNS TABLE(id uuid, board_name text, tribe_id integer, domain_key text, board_scope text, source text, item_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    b.id,
    b.board_name,
    public.resolve_tribe_id(b.initiative_id) AS tribe_id,
    b.domain_key,
    b.board_scope,
    b.source,
    (SELECT count(*) FROM board_items bi WHERE bi.board_id = b.id) AS item_count
  FROM project_boards b
  WHERE b.is_active = true
    AND public.rls_can_see_initiative(b.initiative_id)
  ORDER BY b.board_scope, public.resolve_tribe_id(b.initiative_id) NULLS FIRST, b.board_name;
END;
$function$;

-- get_portfolio_items(p_tribe_id integer, p_status text, p_cycle_code text)
CREATE OR REPLACE FUNCTION public.get_portfolio_items(p_tribe_id integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_cycle_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, title text, status text, tribe_id integer, initiative_id uuid, baseline_date date, baseline_locked_at timestamp with time zone, forecast_date date, due_date date, is_portfolio_item boolean, portfolio_kpi_refs text[], cycle_code text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (can_by_member(v_member_id, 'view_internal_analytics') OR can_by_member(v_member_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Access denied — requires view_internal_analytics or view_chapter_dashboards';
  END IF;

  RETURN QUERY
  SELECT bi.id, bi.title, bi.status,
         i.legacy_tribe_id AS tribe_id,
         pb.initiative_id,
         bi.baseline_date, bi.baseline_locked_at,
         bi.forecast_date, bi.due_date,
         bi.is_portfolio_item, bi.portfolio_kpi_refs,
         pb.cycle_code,
         bi.updated_at
  FROM board_items bi
  JOIN project_boards pb ON pb.id = bi.board_id
  LEFT JOIN initiatives i ON i.id = pb.initiative_id
  WHERE bi.is_portfolio_item = true
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    AND (p_status IS NULL OR bi.status = p_status)
    AND (p_cycle_code IS NULL OR pb.cycle_code = p_cycle_code)
    AND public.rls_can_see_initiative(pb.initiative_id)
  ORDER BY bi.due_date NULLS LAST, bi.updated_at DESC;
END $function$;

-- list_radar_global(p_webinars_limit integer, p_publications_limit integer)
CREATE OR REPLACE FUNCTION public.list_radar_global(p_webinars_limit integer DEFAULT 5, p_publications_limit integer DEFAULT 5)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_webinars json;
  v_publications json;
  v_today date := current_date;
BEGIN
  SELECT coalesce(json_agg(row_to_json(w)), '[]'::json) INTO v_webinars
  FROM (
    SELECT e.id, e.title, e.date, e.meeting_link, e.type
    FROM public.events e
    WHERE e.type = 'webinar'
      AND e.date >= v_today
      AND public.rls_can_see_initiative(e.initiative_id)
    ORDER BY e.date ASC
    LIMIT p_webinars_limit
  ) w;

  SELECT coalesce(json_agg(row_to_json(p)), '[]'::json) INTO v_publications
  FROM (
    SELECT bi.id, bi.title, bi.description, bi.updated_at
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    WHERE coalesce(pb.domain_key, '') = 'publications_submissions'
      AND bi.status = 'done'
      AND pb.is_active = true
      AND public.rls_can_see_initiative(pb.initiative_id)
    ORDER BY bi.updated_at DESC NULLS LAST
    LIMIT p_publications_limit
  ) p;

  RETURN json_build_object(
    'webinars', coalesce(v_webinars, '[]'::json),
    'publications', coalesce(v_publications, '[]'::json)
  );
END;
$function$;

-- list_partner_cards(p_partner_entity_id uuid)
CREATE OR REPLACE FUNCTION public.list_partner_cards(p_partner_entity_id uuid)
 RETURNS TABLE(link_id uuid, link_role text, link_notes text, linked_at timestamp with time zone, linked_by_name text, board_item_id uuid, board_item_title text, board_item_status text, board_item_due_date date, board_item_assignee_name text, board_id uuid, board_name text, partner_entity_id uuid, partner_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    pc.id,
    pc.link_role,
    pc.notes,
    pc.created_at,
    cm.name,
    bi.id,
    bi.title,
    bi.status,
    bi.due_date,
    am.name,
    bi.board_id,
    pb.board_name,
    pe.id,
    pe.name
  FROM public.partner_cards pc
  JOIN public.partner_entities pe ON pe.id = pc.partner_entity_id
  JOIN public.board_items bi ON bi.id = pc.board_item_id
  LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
  LEFT JOIN public.members am ON am.id = bi.assignee_id
  LEFT JOIN public.members cm ON cm.id = pc.created_by
  WHERE pc.partner_entity_id = p_partner_entity_id
    AND public.rls_can_see_board(bi.board_id)
  ORDER BY pc.created_at DESC;
END;
$function$;

-- list_orphan_card_assignments(p_tribe_id integer, p_chapter text, p_limit integer)
CREATE OR REPLACE FUNCTION public.list_orphan_card_assignments(p_tribe_id integer DEFAULT NULL::integer, p_chapter text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member permission');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'alert_id', a.id,
    'board_id', a.board_id,
    'board_name', pb.board_name,
    'board_domain_key', pb.domain_key,
    'item_id', (a.payload->>'board_item_id')::uuid,
    'item_title', a.payload->>'item_title',
    'item_status', bi.status,
    'item_updated_at', bi.updated_at,
    'assignee_id', (a.payload->>'assignee_id')::uuid,
    'assignee_name', a.payload->>'assignee_name',
    'assignee_status', a.payload->>'assignee_status',
    'assignee_chapter', m.chapter,
    'assignee_tribe_id', m.tribe_id,
    'detected_at', a.created_at,
    'severity', a.severity
  ) ORDER BY a.created_at DESC), '[]'::jsonb) INTO v_result
  FROM public.board_taxonomy_alerts a
  LEFT JOIN public.project_boards pb ON pb.id = a.board_id
  LEFT JOIN public.board_items bi ON bi.id = (a.payload->>'board_item_id')::uuid
  LEFT JOIN public.members m ON m.id = (a.payload->>'assignee_id')::uuid
  WHERE a.alert_code = 'orphan_assignee_offboard'
    AND a.resolved_at IS NULL
    AND public.rls_can_see_board(a.board_id)
    AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
    AND (p_chapter IS NULL OR m.chapter = p_chapter)
  LIMIT p_limit;

  RETURN jsonb_build_object(
    'orphan_cards', v_result,
    'total_shown', jsonb_array_length(v_result),
    'filters', jsonb_build_object('tribe_id', p_tribe_id, 'chapter', p_chapter, 'limit', p_limit)
  );
END;
$function$;

-- list_legacy_board_items_for_tribe(p_current_tribe_id integer)
CREATE OR REPLACE FUNCTION public.list_legacy_board_items_for_tribe(p_current_tribe_id integer)
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_leader_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_caller_id IS NULL THEN RETURN; END IF;

  SELECT m.id INTO v_leader_id
  FROM public.members m
  WHERE m.tribe_id = p_current_tribe_id
    AND m.operational_role = 'tribe_leader'
    AND m.is_active = true
  LIMIT 1;

  IF v_leader_id IS NULL THEN RETURN; END IF;

  IF NOT (
    v_caller_id = v_leader_id
    OR public.can_by_member(v_caller_id, 'manage_member')
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.curation_status, bi.reviewer_id,
      bi.tags, bi.labels, bi.due_date, bi.position,
      bi.cycle, bi.attachments, bi.checklist,
      bi.created_at, bi.updated_at,
      am.name AS assignee_name, am.photo_url AS assignee_photo,
      rm.name AS reviewer_name,
      i.legacy_tribe_id AS origin_tribe_id,
      i.title AS origin_tribe_name
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    LEFT JOIN public.members am ON am.id = bi.assignee_id
    LEFT JOIN public.members rm ON rm.id = bi.reviewer_id
    WHERE i.legacy_tribe_id <> p_current_tribe_id
      AND pb.is_active = true
      AND bi.status <> 'archived'
      AND public.rls_can_see_board(bi.board_id)
      AND (
        bi.assignee_id = v_leader_id
        OR i.legacy_tribe_id IN (
          SELECT mch.tribe_id
          FROM public.member_cycle_history mch
          WHERE mch.member_id = v_leader_id
            AND mch.operational_role = 'tribe_leader'
            AND mch.tribe_id IS NOT NULL
        )
        OR i.legacy_tribe_id IN (
          SELECT tr.id
          FROM public.member_cycle_history mch2
          JOIN public.tribes tr ON mch2.tribe_name ILIKE '%' || tr.name || '%'
          WHERE mch2.member_id = v_leader_id
            AND mch2.operational_role = 'tribe_leader'
            AND mch2.tribe_id IS NULL
            AND mch2.tribe_name IS NOT NULL
        )
      )
    ORDER BY bi.updated_at DESC NULLS LAST
    LIMIT 200
  ) r;
END;
$function$;

-- list_meeting_action_items(p_event_id uuid, p_status text, p_assignee_id uuid, p_kind text, p_unresolved_only boolean)
CREATE OR REPLACE FUNCTION public.list_meeting_action_items(p_event_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_assignee_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT NULL::text, p_unresolved_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- Authenticated only — any member can see action items.
  -- Privacy is enforced by event visibility (events RLS) when frontend
  -- joins; raw access here is read-only metadata about meetings.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', mai.id,
    'event_id', mai.event_id,
    'event_title', e.title,
    'event_date', e.date,
    'description', mai.description,
    'assignee_id', mai.assignee_id,
    'assignee_name', mai.assignee_name,
    'due_date', mai.due_date,
    'kind', mai.kind,
    'status', mai.status,
    'board_item_id', mai.board_item_id,
    'board_item_title', bi.title,
    'checklist_item_id', mai.checklist_item_id,
    'carried_to_event_id', mai.carried_to_event_id,
    'resolved_at', mai.resolved_at,
    'resolved_by', mai.resolved_by,
    'resolved_by_name', rm.name,
    'resolution_note', mai.resolution_note,
    'created_by', mai.created_by,
    'created_at', mai.created_at
  ) ORDER BY
    CASE WHEN mai.resolved_at IS NULL THEN 0 ELSE 1 END,  -- unresolved first
    mai.due_date NULLS LAST, mai.created_at DESC), '[]'::jsonb) INTO v_result
  FROM public.meeting_action_items mai
  LEFT JOIN public.events e ON e.id = mai.event_id
  LEFT JOIN public.board_items bi ON bi.id = mai.board_item_id
  LEFT JOIN public.members rm ON rm.id = mai.resolved_by
  WHERE (p_event_id IS NULL OR mai.event_id = p_event_id)
    AND (p_status IS NULL OR mai.status = p_status)
    AND (p_assignee_id IS NULL OR mai.assignee_id = p_assignee_id)
    AND (p_kind IS NULL OR mai.kind = p_kind)
    AND (NOT p_unresolved_only OR mai.resolved_at IS NULL)
    AND (mai.event_id IS NULL OR public.rls_can_see_initiative(e.initiative_id))
    AND (mai.board_item_id IS NULL OR public.rls_can_see_item(mai.board_item_id))
  LIMIT 200;

  RETURN v_result;
END;
$function$;

-- get_content_product_reader(p_product_id uuid)
CREATE OR REPLACE FUNCTION public.get_content_product_reader(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_is_admin boolean := false;
  v_caller_is_curator boolean := false;
  v_is_proposer boolean := false;
  v_product public.content_products%ROWTYPE;
  v_source_summary jsonb;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;

  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE = '42501';
  END IF;

  v_caller_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
  v_caller_is_curator := public.can_by_member(v_caller_member_id, 'curate_content');

  SELECT * INTO v_product
  FROM public.content_products
  WHERE id = p_product_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'product', NULL, 'source_summary', NULL);
  END IF;

  IF NOT public.rls_can_see_initiative(v_product.initiative_id) THEN
    RETURN jsonb_build_object('ok', true, 'product', NULL, 'source_summary', NULL);
  END IF;

  v_is_proposer := (v_product.proposer_member_id IS NOT NULL
                    AND v_product.proposer_member_id = v_caller_member_id);

  IF NOT (v_caller_is_admin OR v_caller_is_curator OR v_is_proposer) THEN
    IF v_product.status NOT IN (
      'published'::public.content_product_status,
      'approved'::public.content_product_status
    ) THEN
      RETURN jsonb_build_object('ok', true, 'product', NULL, 'source_summary', NULL);
    END IF;
  END IF;

  v_source_summary := CASE v_product.source_kind
    WHEN 'governance_document_version' THEN (
      SELECT jsonb_build_object(
        'kind', 'governance_document_version',
        'document_id', gd.id,
        'document_title', gd.title,
        'version_id', dv.id,
        'version_number', dv.version_number
      )
      FROM public.document_versions dv
      LEFT JOIN public.governance_documents gd ON gd.id = dv.document_id
      WHERE dv.id = v_product.source_document_version_id
    )
    WHEN 'board_item' THEN (
      SELECT jsonb_build_object(
        'kind', 'board_item',
        'board_item_id', bi.id,
        'board_item_title', bi.title
      )
      FROM public.board_items bi
      WHERE bi.id = v_product.source_board_item_id
    )
    WHEN 'publication_idea' THEN (
      SELECT jsonb_build_object(
        'kind', 'publication_idea',
        'publication_idea_id', pi.id,
        'publication_idea_title', pi.title
      )
      FROM public.publication_ideas pi
      WHERE pi.id = v_product.source_publication_idea_id
    )
    WHEN 'external' THEN jsonb_build_object(
      'kind', 'external',
      'external_uri', v_product.source_external_uri
    )
    WHEN 'none' THEN jsonb_build_object('kind', 'none')
    ELSE NULL
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'product', jsonb_build_object(
      'id', v_product.id,
      'organization_id', v_product.organization_id,
      'title', v_product.title,
      'summary', v_product.summary,
      'source_kind', v_product.source_kind,
      'source_document_version_id', v_product.source_document_version_id,
      'source_board_item_id', v_product.source_board_item_id,
      'source_publication_idea_id', v_product.source_publication_idea_id,
      'source_external_uri', v_product.source_external_uri,
      'target_instrument', v_product.target_instrument,
      'target_audience', v_product.target_audience,
      'target_language_policy', v_product.target_language_policy,
      'target_length_policy', v_product.target_length_policy,
      'review_mode', v_product.review_mode,
      'review_round', v_product.review_round,
      'status', v_product.status,
      'derived_group_id', v_product.derived_group_id,
      'initiative_id', v_product.initiative_id,
      'proposer_member_id', v_product.proposer_member_id,
      'publication_metadata', v_product.publication_metadata,
      'created_at', v_product.created_at,
      'updated_at', v_product.updated_at,
      'published_at', v_product.published_at,
      'archived_at', v_product.archived_at
    ),
    'source_summary', v_source_summary
  );
END;
$function$;

-- Reload PostgREST schema cache (RPC bodies changed).
NOTIFY pgrst, 'reload schema';
