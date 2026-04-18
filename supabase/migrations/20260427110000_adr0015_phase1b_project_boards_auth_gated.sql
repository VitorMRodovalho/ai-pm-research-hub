-- ============================================================================
-- ADR-0015 Phase 1b — project_boards auth-gated readers cutover
--
-- Combines ADR-0015 JOIN cutover + ADR-0011 V4 auth refactor in 4 RPCs
-- that previously used inline operational_role/designations checks.
--
-- Scope: 4 RPCs
--   1. get_curation_dashboard             — auth gate + JOIN swap
--   2. list_curation_pending_board_items  — auth gate + JOIN swap
--   3. get_portfolio_timeline             — scope filter (not hard gate) + JOIN swap
--   4. list_legacy_board_items_for_tribe  — access check + JOIN swap
--
-- Auth mapping:
--   Curation-related:      can_by_member(m_id, 'write_board')
--     (covers curator, co_gp, manager, deputy_manager + leader roles per ADR-0007)
--   Management access:     can_by_member(m_id, 'manage_member')
--     (covers manager, deputy_manager, co_gp)
--
-- Completes project_boards Phase 1 (7/7 readers). Writers untouched
-- (dual-write triggers sync until Phase 2/3).
--
-- ADR: ADR-0015 Phase 1, ADR-0011 V4 Auth Pattern
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. get_curation_dashboard — JOIN initiatives + V4 auth (write_board)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_curation_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- ADR-0011 V4 auth: write_board covers curator + co_gp + manager + deputy
  IF NOT public.can_by_member(v_member_id, 'write_board') THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  SELECT jsonb_build_object(
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'description', bi.description,
        'status', bi.status,
        'curation_status', bi.curation_status,
        'curation_due_at', bi.curation_due_at,
        'board_id', bi.board_id,
        'board_name', pb.board_name,
        'tribe_id', pb.tribe_id,
        'tribe_name', i.title,
        'assignee_id', bi.assignee_id,
        'assignee_name', am.name,
        'reviewer_id', bi.reviewer_id,
        'reviewer_name', rm.name,
        'tags', bi.tags,
        'attachments', bi.attachments,
        'created_at', bi.created_at,
        'updated_at', bi.updated_at,
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
            'id', crl2.id,
            'curator_name', cm.name,
            'decision', crl2.decision,
            'feedback', crl2.feedback_notes,
            'scores', crl2.criteria_scores,
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
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. list_curation_pending_board_items — same auth + JOIN swap
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.list_curation_pending_board_items()
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- ADR-0011 V4 auth
  IF NOT public.can_by_member(v_member_id, 'write_board') THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.curation_status, bi.assignee_id, bi.reviewer_id,
      bi.due_date, bi.curation_due_at, bi.board_id,
      pb.tribe_id,
      i.title AS tribe_name,
      am.name AS assignee_name,
      rm.name AS reviewer_name,
      bi.created_at, bi.updated_at, bi.attachments,
      (SELECT count(*) FROM public.curation_review_log crl
       WHERE crl.board_item_id = bi.id) AS review_count,
      (SELECT json_agg(json_build_object(
        'id', crl2.id,
        'curator_name', cm.name,
        'decision', crl2.decision,
        'feedback', crl2.feedback_notes,
        'scores', crl2.criteria_scores,
        'completed_at', crl2.completed_at
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
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. get_portfolio_timeline — V4 auth gate + JOIN swap + scope filter
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_portfolio_timeline()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid;
  v_tribe_id integer;
  v_chapter text;
  v_is_admin boolean;
  v_result jsonb;
BEGIN
  SELECT id, tribe_id, chapter INTO v_member_id, v_tribe_id, v_chapter
    FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  -- ADR-0011 V4 gate: must be a member (readers get empty array otherwise)
  -- Scope determined by can_by_member; admins see all, scoped roles filtered below.
  v_is_admin := public.can_by_member(v_member_id, 'manage_member');

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', bi.id,
    'title', bi.title,
    'status', bi.status,
    'tribe_id', pb.tribe_id,
    'tribe_name', i.title,
    'baseline_date', bi.baseline_date,
    'forecast_date', bi.forecast_date,
    'actual_completion_date', bi.actual_completion_date,
    'is_portfolio_item', true,
    'assignee_name', m.name,
    'deviation_days', CASE
      WHEN bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
      THEN bi.forecast_date - bi.baseline_date ELSE 0 END
  ) ORDER BY pb.tribe_id, COALESCE(bi.baseline_date, bi.forecast_date, '2099-12-31'::date)), '[]'::jsonb)
  INTO v_result
  FROM board_items bi
  JOIN project_boards pb ON pb.id = bi.board_id AND pb.is_active = true
  LEFT JOIN initiatives i ON i.id = pb.initiative_id
  LEFT JOIN members m ON m.id = bi.assignee_id
  WHERE bi.status <> 'archived'
    AND bi.is_portfolio_item = true
    -- Preserve tribe active constraint via initiatives.legacy_tribe_id lookup
    AND (pb.initiative_id IS NULL OR EXISTS (
      SELECT 1 FROM tribes tr WHERE tr.id = i.legacy_tribe_id AND tr.is_active = true
    ));

  -- Scope filters for non-admins
  IF NOT v_is_admin AND v_tribe_id IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_result
    FROM jsonb_array_elements(v_result) elem
    WHERE (elem->>'tribe_id')::integer = v_tribe_id;
  END IF;

  -- Stakeholder chapter-based scope (when not admin)
  IF NOT v_is_admin AND public.can_by_member(v_member_id, 'manage_partner') AND v_chapter IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_result
    FROM jsonb_array_elements(v_result) elem
    WHERE (elem->>'tribe_id')::integer IN (
      SELECT pb2.tribe_id FROM project_boards pb2
      JOIN tribes t2 ON t2.id = pb2.tribe_id
      WHERE EXISTS (SELECT 1 FROM members m2 WHERE m2.tribe_id = t2.id AND m2.chapter = v_chapter)
    );
  END IF;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. list_legacy_board_items_for_tribe — V4 auth + JOIN swap
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.list_legacy_board_items_for_tribe(
  p_current_tribe_id integer
)
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
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

  -- ADR-0011 V4 auth: caller is the tribe leader OR has manage_member
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
      am.name AS assignee_name,
      am.photo_url AS assignee_photo,
      rm.name AS reviewer_name,
      pb.tribe_id AS origin_tribe_id,
      i.title AS origin_tribe_name
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    LEFT JOIN public.members am ON am.id = bi.assignee_id
    LEFT JOIN public.members rm ON rm.id = bi.reviewer_id
    WHERE pb.tribe_id <> p_current_tribe_id
      AND pb.is_active = true
      AND bi.status <> 'archived'
      AND (
        bi.assignee_id = v_leader_id
        OR pb.tribe_id IN (
          SELECT mch.tribe_id
          FROM public.member_cycle_history mch
          WHERE mch.member_id = v_leader_id
            AND mch.operational_role = 'tribe_leader'
            AND mch.tribe_id IS NOT NULL
        )
        OR pb.tribe_id IN (
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
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
