-- Curation Review Audit Trail + SLA automation
-- Date: 2026-03-16
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. curation_review_log — audit trail for committee decisions
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.curation_review_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_item_id uuid NOT NULL REFERENCES public.board_items(id) ON DELETE CASCADE,
  curator_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  criteria_scores jsonb NOT NULL DEFAULT '{}'::jsonb,
  feedback_notes text,
  decision text NOT NULL CHECK (decision IN ('approved', 'returned_for_revision', 'rejected')),
  due_date timestamptz,
  completed_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_curation_review_log_item ON public.curation_review_log (board_item_id);
CREATE INDEX idx_curation_review_log_curator ON public.curation_review_log (curator_id);

ALTER TABLE public.curation_review_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY curation_review_log_read ON public.curation_review_log
  FOR SELECT TO authenticated USING (true);

CREATE POLICY curation_review_log_write ON public.curation_review_log
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.get_my_member_record() r
      WHERE r.is_superadmin IS true
        OR r.operational_role IN ('manager', 'deputy_manager')
        OR 'curator' = ANY(coalesce(r.designations, array[]::text[]))
        OR 'co_gp' = ANY(coalesce(r.designations, array[]::text[]))
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Add curation_due_at to board_items for SLA tracking
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.board_items
  ADD COLUMN IF NOT EXISTS curation_due_at timestamptz;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Trigger: auto-set curation_due_at = now() + 7 days on curation_pending
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_curation_due_date()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.curation_status = 'curation_pending'
     AND (OLD.curation_status IS DISTINCT FROM 'curation_pending') THEN
    NEW.curation_due_at := now() + interval '7 days';
  END IF;

  IF NEW.curation_status IN ('published', 'draft')
     AND OLD.curation_status = 'curation_pending' THEN
    NEW.curation_due_at := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_curation_due_date ON public.board_items;
CREATE TRIGGER trg_set_curation_due_date
  BEFORE UPDATE OF curation_status ON public.board_items
  FOR EACH ROW EXECUTE FUNCTION public.set_curation_due_date();

-- Backfill: set due_date for items already in curation_pending
UPDATE public.board_items
SET curation_due_at = updated_at + interval '7 days'
WHERE curation_status = 'curation_pending'
  AND curation_due_at IS NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RPC: submit_curation_review — the curador's single action
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.submit_curation_review(
  p_item_id        uuid,
  p_decision       text,
  p_criteria_scores jsonb DEFAULT '{}'::jsonb,
  p_feedback_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller   public.members%rowtype;
  v_item     public.board_items%rowtype;
  v_log_id   uuid;
  v_pub_id   uuid;
  v_origin_board uuid;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
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

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;
  IF v_item.curation_status <> 'curation_pending' THEN
    RAISE EXCEPTION 'Item is not in curation_pending status';
  END IF;

  INSERT INTO public.curation_review_log (
    board_item_id, curator_id, criteria_scores, feedback_notes,
    decision, due_date, completed_at
  ) VALUES (
    p_item_id, v_caller.id, p_criteria_scores, p_feedback_notes,
    p_decision, v_item.curation_due_at, now()
  )
  RETURNING id INTO v_log_id;

  IF p_decision = 'approved' THEN
    v_pub_id := public.publish_board_item_from_curation(p_item_id);
    RETURN v_log_id;
  END IF;

  IF p_decision = 'returned_for_revision' THEN
    v_origin_board := v_item.board_id;

    UPDATE public.board_items
    SET curation_status = 'draft',
        status = 'review',
        description = coalesce(description, '') ||
          E'\n\n---\n📋 **Feedback do Comitê de Curadoria** (' || to_char(now(), 'DD/MM/YYYY') || E'):\n' ||
          coalesce(p_feedback_notes, 'Sem observações específicas.'),
        updated_at = now()
    WHERE id = p_item_id;

    RETURN v_log_id;
  END IF;

  IF p_decision = 'rejected' THEN
    UPDATE public.board_items
    SET curation_status = 'draft',
        status = 'archived',
        description = coalesce(description, '') ||
          E'\n\n---\n❌ **Rejeitado pelo Comitê de Curadoria** (' || to_char(now(), 'DD/MM/YYYY') || E'):\n' ||
          coalesce(p_feedback_notes, 'Não atende aos critérios mínimos.'),
        updated_at = now()
    WHERE id = p_item_id;

    RETURN v_log_id;
  END IF;

  RETURN v_log_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_curation_review(uuid, text, jsonb, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Update list_curation_pending to include SLA fields + review history
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.list_curation_pending_board_items()
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.members%rowtype;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (
    v_caller.is_superadmin = true
    OR v_caller.operational_role IN ('manager','deputy_manager')
    OR 'curator' = ANY(coalesce(v_caller.designations, array[]::text[]))
    OR 'co_gp' = ANY(coalesce(v_caller.designations, array[]::text[]))
  ) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id,
      bi.title,
      bi.description,
      bi.status,
      bi.curation_status,
      bi.assignee_id,
      bi.reviewer_id,
      bi.due_date,
      bi.curation_due_at,
      bi.board_id,
      pb.tribe_id,
      t.name AS tribe_name,
      am.name AS assignee_name,
      rm.name AS reviewer_name,
      bi.created_at,
      bi.updated_at,
      bi.attachments,
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
    LEFT JOIN public.tribes t ON t.id = pb.tribe_id
    LEFT JOIN public.members am ON am.id = bi.assignee_id
    LEFT JOIN public.members rm ON rm.id = bi.reviewer_id
    WHERE bi.curation_status = 'curation_pending'
      AND bi.status <> 'archived'
      AND pb.is_active = true
    ORDER BY bi.curation_due_at ASC NULLS LAST, bi.updated_at DESC
  ) r;
END;
$$;
