-- ============================================================================
-- W90: Curation Review Audit Trail
-- Expands board_lifecycle_events, adds board_sla_config, creates RPCs
-- for formal dual-reviewer curation with rubric scoring.
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Fix CHECK constraint on board_lifecycle_events.action
--    The original constraint only allowed 4 actions, but RPCs already
--    insert 'created', 'status_change', 'assigned', etc. — fix this.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE board_lifecycle_events
  DROP CONSTRAINT IF EXISTS board_lifecycle_events_action_check;

ALTER TABLE board_lifecycle_events
  ADD CONSTRAINT board_lifecycle_events_action_check
  CHECK (action IN (
    -- Original
    'board_archived', 'board_restored', 'item_archived', 'item_restored',
    -- BoardEngine RPCs (already in use)
    'created', 'status_change', 'assigned', 'archived', 'moved_out', 'moved_in',
    -- W90 curation actions
    'submitted_for_curation', 'reviewer_assigned', 'curation_review', 'curation_approved',
    -- W91 assignment actions (forward-compat)
    'member_assigned', 'member_unassigned'
  ));

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Add audit columns to board_lifecycle_events
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE board_lifecycle_events
  ADD COLUMN IF NOT EXISTS review_score jsonb DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS review_round int DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS sla_deadline timestamptz DEFAULT NULL;

COMMENT ON COLUMN board_lifecycle_events.review_score IS
  'Rubrica formal: {clarity: 1-5, originality: 1-5, adherence: 1-5, relevance: 1-5, ethics: 1-5, overall: text}';
COMMENT ON COLUMN board_lifecycle_events.review_round IS
  'Rodada de revisão (1 = primeira, 2 = segunda após correções)';
COMMENT ON COLUMN board_lifecycle_events.sla_deadline IS
  'Prazo para conclusão desta ação de curadoria';

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. board_sla_config — configurable SLA per board
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS board_sla_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_id uuid REFERENCES project_boards(id) NOT NULL,
  sla_days int NOT NULL DEFAULT 7,
  max_review_rounds int NOT NULL DEFAULT 2,
  reviewers_required int NOT NULL DEFAULT 2,
  rubric_criteria jsonb NOT NULL DEFAULT '["clarity","originality","adherence","relevance","ethics"]',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(board_id)
);

COMMENT ON TABLE board_sla_config IS 'SLA configuration per board — curadoria deadlines and review requirements';

ALTER TABLE board_sla_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read SLA config" ON board_sla_config
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Admins can manage SLA config" ON board_sla_config
  FOR ALL TO authenticated USING (
    EXISTS (
      SELECT 1 FROM members m
      WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager'))
    )
  );

-- Seed defaults for boards with curation items
INSERT INTO board_sla_config (board_id, sla_days, reviewers_required)
SELECT DISTINCT b.id, 7, 2
FROM project_boards b
JOIN board_items bi ON bi.board_id = b.id
WHERE bi.curation_status IS NOT NULL
  AND bi.curation_status <> 'draft'
  AND b.is_active = true
ON CONFLICT (board_id) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Update SLA trigger to use board_sla_config
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.set_curation_due_date()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_sla_days int;
BEGIN
  IF NEW.curation_status = 'curation_pending'
     AND (OLD.curation_status IS DISTINCT FROM 'curation_pending') THEN
    SELECT sla_days INTO v_sla_days
    FROM board_sla_config WHERE board_id = NEW.board_id;
    NEW.curation_due_at := now() + make_interval(days => coalesce(v_sla_days, 7));
  END IF;

  IF NEW.curation_status IN ('published', 'draft')
     AND OLD.curation_status = 'curation_pending' THEN
    NEW.curation_due_at := NULL;
  END IF;

  RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. RPC: submit_for_curation
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.submit_for_curation(p_item_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_sla_days int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT (
    v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')
  ) THEN
    RAISE EXCEPTION 'Requires tribe_leader or manager role';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  IF v_item.curation_status NOT IN ('leader_review', 'draft') THEN
    RAISE EXCEPTION 'Item must be in leader_review or draft status to submit for curation';
  END IF;

  SELECT sla_days INTO v_sla_days FROM board_sla_config WHERE board_id = v_item.board_id;

  UPDATE board_items SET
    curation_status = 'curation_pending',
    curation_due_at = now() + make_interval(days => coalesce(v_sla_days, 7)),
    updated_at = now()
  WHERE id = p_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, actor_member_id, sla_deadline)
  VALUES (v_item.board_id, p_item_id, 'submitted_for_curation', v_caller.id,
    now() + make_interval(days => coalesce(v_sla_days, 7)));
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_for_curation(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. RPC: assign_curation_reviewer
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.assign_curation_reviewer(
  p_item_id uuid,
  p_reviewer_id uuid,
  p_round int DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller members%rowtype;
  v_reviewer members%rowtype;
  v_item board_items%rowtype;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT (
    v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR 'curator' = ANY(coalesce(v_caller.designations, array[]::text[]))
    OR 'co_gp' = ANY(coalesce(v_caller.designations, array[]::text[]))
  ) THEN
    RAISE EXCEPTION 'Requires curator or manager role';
  END IF;

  SELECT * INTO v_reviewer FROM members WHERE id = p_reviewer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reviewer not found'; END IF;

  IF NOT ('curator' = ANY(coalesce(v_reviewer.designations, array[]::text[]))
       OR 'co_gp' = ANY(coalesce(v_reviewer.designations, array[]::text[]))) THEN
    RAISE EXCEPTION 'Reviewer must have curator or co_gp designation';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  -- Cannot be sole reviewer of own work
  IF p_reviewer_id = v_item.assignee_id THEN
    -- Allow if there's already another reviewer assigned for this round
    IF NOT EXISTS (
      SELECT 1 FROM board_lifecycle_events
      WHERE item_id = p_item_id AND action = 'reviewer_assigned'
        AND review_round = p_round AND actor_member_id IS DISTINCT FROM p_reviewer_id
    ) THEN
      RAISE EXCEPTION 'Cannot designate item author as sole reviewer (conflict of interest)';
    END IF;
  END IF;

  INSERT INTO board_lifecycle_events
    (board_id, item_id, action, reason, actor_member_id, review_round)
  VALUES
    (v_item.board_id, p_item_id, 'reviewer_assigned',
     'Revisor designado: ' || v_reviewer.name,
     v_caller.id, p_round);
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_curation_reviewer(uuid, uuid, int) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. Enhanced submit_curation_review — multi-reviewer consensus
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.submit_curation_review(
  p_item_id        uuid,
  p_decision       text,
  p_criteria_scores jsonb DEFAULT '{}'::jsonb,
  p_feedback_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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

  IF NOT (
    v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR 'curator' = ANY(coalesce(v_caller.designations, array[]::text[]))
    OR 'co_gp' = ANY(coalesce(v_caller.designations, array[]::text[]))
  ) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  IF p_decision NOT IN ('approved', 'returned_for_revision', 'rejected') THEN
    RAISE EXCEPTION 'Invalid decision: %', p_decision;
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Board item not found'; END IF;
  IF v_item.curation_status <> 'curation_pending' THEN
    RAISE EXCEPTION 'Item is not in curation_pending status';
  END IF;

  -- Validate rubric scores (5 criteria, each 1-5)
  IF p_criteria_scores IS NOT NULL AND p_criteria_scores <> '{}'::jsonb THEN
    FOR v_key IN SELECT unnest(ARRAY['clarity','originality','adherence','relevance','ethics'])
    LOOP
      v_score := (p_criteria_scores->>v_key)::int;
      IF v_score IS NULL OR v_score < 1 OR v_score > 5 THEN
        RAISE EXCEPTION 'Invalid score for %: must be 1-5', v_key;
      END IF;
    END LOOP;
  END IF;

  -- Determine current review round
  SELECT coalesce(max(review_round), 1) INTO v_current_round
  FROM board_lifecycle_events
  WHERE item_id = p_item_id AND action = 'reviewer_assigned';

  -- Get required reviewers from config (default 2)
  SELECT reviewers_required INTO v_required
  FROM board_sla_config WHERE board_id = v_item.board_id;
  v_required := coalesce(v_required, 2);

  -- Insert into curation_review_log (existing table)
  INSERT INTO curation_review_log (
    board_item_id, curator_id, criteria_scores, feedback_notes,
    decision, due_date, completed_at
  ) VALUES (
    p_item_id, v_caller.id, p_criteria_scores, p_feedback_notes,
    p_decision, v_item.curation_due_at, now()
  ) RETURNING id INTO v_log_id;

  -- Insert lifecycle event with score + round
  INSERT INTO board_lifecycle_events
    (board_id, item_id, action, reason, actor_member_id, review_score, review_round, sla_deadline)
  VALUES
    (v_item.board_id, p_item_id, 'curation_review',
     p_decision || ': ' || coalesce(p_feedback_notes, ''),
     v_caller.id, p_criteria_scores, v_current_round, v_item.curation_due_at);

  -- Check consensus
  IF p_decision = 'approved' THEN
    SELECT count(*) INTO v_approved_count
    FROM curation_review_log
    WHERE board_item_id = p_item_id
      AND decision = 'approved';

    IF v_approved_count >= v_required THEN
      -- All reviewers approved → publish
      v_pub_id := public.publish_board_item_from_curation(p_item_id);

      INSERT INTO board_lifecycle_events
        (board_id, item_id, action, reason, actor_member_id, review_round)
      VALUES
        (v_item.board_id, p_item_id, 'curation_approved',
         v_approved_count || '/' || v_required || ' revisores aprovaram',
         v_caller.id, v_current_round);
    END IF;
    -- Otherwise: still waiting for more reviewers

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
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. RPC: get_item_curation_history
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_item_curation_history(p_item_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result jsonb;
BEGIN
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
$$;

GRANT EXECUTE ON FUNCTION public.get_item_curation_history(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. RPC: get_curation_dashboard — replaces get_curation_cross_board
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_curation_dashboard()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller members%rowtype;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT (
    v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR 'curator' = ANY(coalesce(v_caller.designations, array[]::text[]))
    OR 'co_gp' = ANY(coalesce(v_caller.designations, array[]::text[]))
  ) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  SELECT jsonb_build_object(
    'items', coalesce((
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
        'tribe_name', t.name,
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
        'reviewers_required', coalesce(sc.reviewers_required, 2),
        'sla_status', CASE
          WHEN bi.curation_due_at IS NULL THEN 'no_sla'
          WHEN bi.curation_due_at < now() THEN 'overdue'
          WHEN bi.curation_due_at < now() + interval '2 days' THEN 'warning'
          ELSE 'on_time'
        END,
        'review_history', (
          SELECT coalesce(jsonb_agg(jsonb_build_object(
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
      LEFT JOIN tribes t ON t.id = pb.tribe_id
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

GRANT EXECUTE ON FUNCTION public.get_curation_dashboard() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 10. Enhanced get_card_timeline — include review fields
-- ═══════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.get_card_timeline(uuid);

CREATE OR REPLACE FUNCTION public.get_card_timeline(p_item_id uuid)
RETURNS TABLE(
  id bigint,
  action text,
  previous_status text,
  new_status text,
  reason text,
  actor_name text,
  created_at timestamptz,
  review_score jsonb,
  review_round int,
  sla_deadline timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
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
$$;
