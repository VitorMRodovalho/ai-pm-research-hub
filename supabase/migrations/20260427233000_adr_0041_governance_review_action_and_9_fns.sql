-- ============================================================
-- ADR-0041: participate_in_governance_review V4 action + 9 fn V3→V4 conversion
-- Section A: catalog seed (4 rows)
-- Section B: body changes for 9 fns (document_comments + curation/board)
-- Path Y additions: tribe_leader (assign/unassign/submit_for_curation),
--                   author (resolve_document_comment),
--                   self+author/board_admin/curator-special (assign_member_to_item)
-- Cross-references: ADR-0007, ADR-0011, ADR-0030, ADR-0037, ADR-0039
-- Rollback: revert this migration; re-apply older bodies from prior migrations
-- ============================================================

-- ── Section A: catalog seed ────────────────────────────────
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope) VALUES
  ('volunteer',     'manager',         'participate_in_governance_review', 'organization'),
  ('volunteer',     'deputy_manager',  'participate_in_governance_review', 'organization'),
  ('volunteer',     'co_gp',           'participate_in_governance_review', 'organization'),
  ('chapter_board', 'liaison',         'participate_in_governance_review', 'organization')
ON CONFLICT (kind, role, action) DO NOTHING;

-- ── Section B: 9 fn body changes ───────────────────────────

-- 1. create_document_comment ─────────────────
CREATE OR REPLACE FUNCTION public.create_document_comment(
  p_version_id uuid, p_clause_anchor text, p_body text, p_visibility text,
  p_parent_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_member record;
  v_comment_id uuid;
BEGIN
  SELECT m.id, m.name, m.operational_role, m.designations, m.is_active
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL OR v_member.is_active = false THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  IF p_visibility NOT IN ('curator_only','submitter_only','change_notes') THEN
    RETURN jsonb_build_object('error','invalid_visibility');
  END IF;

  -- ADR-0041: V4 catalog action `participate_in_governance_review` source-of-truth
  IF NOT public.can_by_member(v_member.id, 'participate_in_governance_review') THEN
    RETURN jsonb_build_object('error','not_authorized');
  END IF;

  IF length(COALESCE(p_body,'')) = 0 THEN
    RETURN jsonb_build_object('error','empty_body');
  END IF;

  INSERT INTO public.document_comments (document_version_id, author_id, clause_anchor, body, parent_id, visibility)
  VALUES (p_version_id, v_member.id, p_clause_anchor, p_body, p_parent_id, p_visibility)
  RETURNING id INTO v_comment_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'document_comment_created', 'document_comment', v_comment_id,
    jsonb_build_object('version_id', p_version_id, 'visibility', p_visibility, 'clause_anchor', p_clause_anchor));

  RETURN jsonb_build_object('success', true, 'comment_id', v_comment_id, 'created_at', now());
END;
$function$;

-- 2. list_document_comments ─────────────────
CREATE OR REPLACE FUNCTION public.list_document_comments(
  p_version_id uuid, p_include_resolved boolean DEFAULT false
) RETURNS TABLE(id uuid, clause_anchor text, body text, visibility text, parent_id uuid,
  author_id uuid, author_name text, author_role text, created_at timestamp with time zone,
  resolved_at timestamp with time zone, resolved_by_name text, resolution_note text)
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_member record;
  v_can_see_all boolean;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.is_active
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL OR v_member.is_active = false THEN RETURN; END IF;

  -- ADR-0041: V4 catalog. Author still sees own comments (preserved below).
  v_can_see_all := public.can_by_member(v_member.id, 'participate_in_governance_review');

  RETURN QUERY
  SELECT c.id, c.clause_anchor, c.body, c.visibility, c.parent_id,
    c.author_id, m.name AS author_name, m.operational_role AS author_role,
    c.created_at, c.resolved_at,
    (SELECT rm.name FROM public.members rm WHERE rm.id = c.resolved_by) AS resolved_by_name,
    c.resolution_note
  FROM public.document_comments c
  JOIN public.members m ON m.id = c.author_id
  WHERE c.document_version_id = p_version_id
    AND (p_include_resolved OR c.resolved_at IS NULL)
    AND (
      v_can_see_all
      OR c.author_id = v_member.id
    )
  ORDER BY c.clause_anchor NULLS LAST, c.created_at ASC;
END;
$function$;

-- 3. resolve_document_comment (V4 + author self-resolve preserved) ─────────────────
CREATE OR REPLACE FUNCTION public.resolve_document_comment(
  p_comment_id uuid, p_resolution_note text DEFAULT NULL::text
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_member record;
  v_comment record;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.is_active
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL OR v_member.is_active = false THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  SELECT c.id, c.author_id, c.resolved_at INTO v_comment
  FROM public.document_comments c WHERE c.id = p_comment_id;
  IF v_comment.id IS NULL THEN
    RETURN jsonb_build_object('error','not_found');
  END IF;
  IF v_comment.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('error','already_resolved');
  END IF;

  -- ADR-0041: V4 catalog OR Path Y (author self-resolve preserved)
  IF NOT (
    v_comment.author_id = v_member.id
    OR public.can_by_member(v_member.id, 'participate_in_governance_review')
  ) THEN
    RETURN jsonb_build_object('error','not_authorized');
  END IF;

  UPDATE public.document_comments
  SET resolved_at = now(), resolved_by = v_member.id, resolution_note = p_resolution_note, updated_at = now()
  WHERE id = p_comment_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'document_comment_resolved', 'document_comment', p_comment_id,
    jsonb_build_object('resolution_note', p_resolution_note));

  RETURN jsonb_build_object('success', true, 'resolved_at', now());
END;
$function$;

-- 4. assign_curation_reviewer (strict V4) ─────────────────
CREATE OR REPLACE FUNCTION public.assign_curation_reviewer(
  p_item_id uuid, p_reviewer_id uuid, p_round integer DEFAULT 1
) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller   members%rowtype;
  v_reviewer members%rowtype;
  v_item     board_items%rowtype;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- ADR-0041: strict V4 catalog (committee work)
  IF NOT public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review';
  END IF;

  SELECT * INTO v_reviewer FROM members WHERE id = p_reviewer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reviewer not found'; END IF;
  IF NOT (
    'curator' = ANY(coalesce(v_reviewer.designations, array[]::text[]))
    OR 'co_gp' = ANY(coalesce(v_reviewer.designations, array[]::text[]))
  ) THEN
    RAISE EXCEPTION 'Reviewer must have curator or co_gp designation';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;
  IF p_reviewer_id = v_item.assignee_id THEN
    IF NOT EXISTS (
      SELECT 1 FROM board_lifecycle_events
      WHERE item_id = p_item_id AND action = 'reviewer_assigned'
        AND review_round = p_round AND actor_member_id IS DISTINCT FROM p_reviewer_id
    ) THEN
      RAISE EXCEPTION 'Cannot designate item author as sole reviewer';
    END IF;
  END IF;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id, review_round)
  VALUES (v_item.board_id, p_item_id, 'reviewer_assigned',
    'Revisor designado: ' || v_reviewer.name, v_caller.id, p_round);
END;
$function$;

-- 5. assign_member_to_item (V4 + Path Y: tribe_leader, board_admin, self+author, curator+curation_reviewer) ─────────────────
CREATE OR REPLACE FUNCTION public.assign_member_to_item(
  p_item_id uuid, p_member_id uuid, p_role text DEFAULT 'author'::text
) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_board record;
  v_member members%rowtype;
  v_assignment_id uuid;
  v_is_board_admin boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;
  SELECT pb.* INTO v_board FROM project_boards pb WHERE pb.id = v_item.board_id;
  v_is_board_admin := EXISTS (
    SELECT 1 FROM board_members bm
    WHERE bm.board_id = v_board.id AND bm.member_id = v_caller.id AND bm.board_role = 'admin'
  );

  -- ADR-0041: V4 catalog OR Path Y (tribe_leader op-role / board_admin / self+author claim / curator+curation_reviewer)
  IF NOT (
    public.can_by_member(v_caller.id, 'participate_in_governance_review')
    OR v_caller.operational_role = 'tribe_leader'
    OR v_is_board_admin
    OR (p_role = 'curation_reviewer' AND 'curator' = ANY(coalesce(v_caller.designations, array[]::text[])))
    OR (v_caller.id = p_member_id AND p_role = 'author')
  ) THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review, tribe_leader, board admin, curator (for curation_reviewer), or self-claim (author)';
  END IF;

  IF p_role NOT IN ('author', 'reviewer', 'contributor', 'curation_reviewer') THEN
    RAISE EXCEPTION 'Invalid role: %. Must be author|reviewer|contributor|curation_reviewer', p_role;
  END IF;
  SELECT * INTO v_member FROM members WHERE id = p_member_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Member not found'; END IF;

  INSERT INTO board_item_assignments (item_id, member_id, role, assigned_by)
  VALUES (p_item_id, p_member_id, p_role, v_caller.id)
  ON CONFLICT (item_id, member_id, role) DO NOTHING
  RETURNING id INTO v_assignment_id;

  IF v_assignment_id IS NOT NULL THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_item.board_id, p_item_id, 'member_assigned',
      v_member.name || ' como ' || p_role, v_caller.id);
    PERFORM create_notification(
      p_member_id, 'card_assigned', 'board_item', p_item_id, v_item.title, v_caller.id,
      v_caller.name || ' atribuiu voce como ' || p_role
    );
  END IF;

  RETURN coalesce(v_assignment_id, (
    SELECT bia.id FROM board_item_assignments bia
    WHERE bia.item_id = p_item_id AND bia.member_id = p_member_id AND bia.role = p_role
  ));
END;
$function$;

-- 6. submit_curation_review (strict V4) ─────────────────
CREATE OR REPLACE FUNCTION public.submit_curation_review(
  p_item_id uuid, p_decision text,
  p_criteria_scores jsonb DEFAULT '{}'::jsonb,
  p_feedback_notes text DEFAULT NULL::text
) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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

  -- ADR-0041: strict V4 catalog (committee work)
  IF NOT public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review';
  END IF;

  IF p_decision NOT IN ('approved', 'returned_for_revision', 'rejected') THEN
    RAISE EXCEPTION 'Invalid decision: %', p_decision;
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Board item not found'; END IF;
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

  SELECT reviewers_required INTO v_required
  FROM board_sla_config WHERE board_id = v_item.board_id;
  v_required := coalesce(v_required, 2);

  INSERT INTO curation_review_log (
    board_item_id, curator_id, criteria_scores, feedback_notes,
    decision, due_date, completed_at
  ) VALUES (
    p_item_id, v_caller.id, p_criteria_scores, p_feedback_notes,
    p_decision, v_item.curation_due_at, now()
  ) RETURNING id INTO v_log_id;

  INSERT INTO board_lifecycle_events
    (board_id, item_id, action, reason, actor_member_id, review_score, review_round, sla_deadline)
  VALUES
    (v_item.board_id, p_item_id, 'curation_review',
     p_decision || ': ' || coalesce(p_feedback_notes, ''),
     v_caller.id, p_criteria_scores, v_current_round, v_item.curation_due_at);

  IF p_decision = 'approved' THEN
    SELECT count(*) INTO v_approved_count
    FROM curation_review_log
    WHERE board_item_id = p_item_id AND decision = 'approved';

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

-- 7. submit_for_curation (V4 + Path Y: tribe_leader operational handoff) ─────────────────
CREATE OR REPLACE FUNCTION public.submit_for_curation(
  p_item_id uuid
) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_sla_days int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- ADR-0041: V4 catalog OR Path Y (tribe_leader operational handoff)
  IF NOT (
    public.can_by_member(v_caller.id, 'participate_in_governance_review')
    OR v_caller.operational_role = 'tribe_leader'
  ) THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review or tribe_leader';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;
  IF v_item.curation_status NOT IN ('leader_review', 'draft') THEN
    RAISE EXCEPTION 'Item must be in leader_review or draft status';
  END IF;

  SELECT sla_days INTO v_sla_days FROM board_sla_config WHERE board_id = v_item.board_id;

  UPDATE board_items
  SET curation_status = 'curation_pending',
      curation_due_at = now() + make_interval(days => coalesce(v_sla_days, 7)),
      updated_at = now()
  WHERE id = p_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, actor_member_id, sla_deadline)
  VALUES (v_item.board_id, p_item_id, 'submitted_for_curation', v_caller.id,
    now() + make_interval(days => coalesce(v_sla_days, 7)));
END;
$function$;

-- 8. unassign_member_from_item (V4 + Path Y: tribe_leader symmetric) ─────────────────
CREATE OR REPLACE FUNCTION public.unassign_member_from_item(
  p_item_id uuid, p_member_id uuid, p_role text
) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_member_name text;
  v_deleted int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- ADR-0041: V4 catalog OR Path Y (tribe_leader symmetric with assign_member_to_item)
  IF NOT (
    public.can_by_member(v_caller.id, 'participate_in_governance_review')
    OR v_caller.operational_role = 'tribe_leader'
  ) THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review or tribe_leader';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  SELECT name INTO v_member_name FROM members WHERE id = p_member_id;

  DELETE FROM board_item_assignments
  WHERE item_id = p_item_id AND member_id = p_member_id AND role = p_role;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  IF v_deleted > 0 THEN
    INSERT INTO board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES
      (v_item.board_id, p_item_id, 'member_unassigned',
       coalesce(v_member_name, 'membro') || ' removido de ' || p_role,
       v_caller.id);
  END IF;
END;
$function$;

-- 9. publish_board_item_from_curation (strict V4 — defense-in-depth, called internally only) ─────────────────
CREATE OR REPLACE FUNCTION public.publish_board_item_from_curation(
  p_item_id uuid
) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller     public.members%rowtype;
  v_item       public.board_items%rowtype;
  v_pub_board  uuid;
  v_new_id     uuid;
  v_pos        int;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- ADR-0041: strict V4 catalog (defense-in-depth; called internally by submit_curation_review)
  IF NOT public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review';
  END IF;

  SELECT bi.* INTO v_item
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;
  IF v_item.curation_status <> 'curation_pending' THEN
    RAISE EXCEPTION 'Only curation_pending items can be published';
  END IF;

  SELECT id INTO v_pub_board
  FROM public.project_boards
  WHERE coalesce(domain_key, '') = 'publications_submissions'
    AND is_active = true
  ORDER BY updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_pub_board IS NULL THEN
    RAISE EXCEPTION 'Publications board not found';
  END IF;

  SELECT coalesce(max(position), 0) + 1 INTO v_pos
  FROM public.board_items WHERE board_id = v_pub_board;

  INSERT INTO public.board_items (
    board_id, title, description, status, curation_status,
    assignee_id, due_date, position, created_at, updated_at,
    cycle, tags, labels, checklist, attachments, source_board, source_card_id
  ) VALUES (
    v_pub_board, v_item.title, v_item.description, 'done', 'published',
    v_item.assignee_id, v_item.due_date, v_pos, now(), now(),
    v_item.cycle, v_item.tags, v_item.labels, v_item.checklist, v_item.attachments,
    'tribe_curation', v_item.id::text
  )
  RETURNING id INTO v_new_id;

  UPDATE public.board_items
  SET curation_status = 'published', updated_at = now()
  WHERE id = p_item_id;

  RETURN v_new_id;
END;
$function$;

-- ── Cache reload ────────────────────────────
NOTIFY pgrst, 'reload schema';
