-- =====================================================================
-- p196 Gap 1 — Auto-submit FSM transition when curation_reviewer assigned
-- =====================================================================
-- Context: Tribe leaders intuitively "submit for curation" by assigning
-- 3 curators via UI ("+ Adicionar membro" with role=curation_reviewer).
-- This writes to board_item_assignments but does NOT fire the curation
-- FSM. As a result: 0 notifications, /admin/curatorship empty, 0 reviews
-- ever logged in curation_review_log (1.5 months of production silence).
--
-- Concrete case (Débora Moura, 2026-05-18 23:52):
--   1. Marked 4 checklist items as done
--   2. Moved card "Artigo — Agentes Autônomos em GP" backlog→done
--   3. Assigned Fabricio/Sarah/Roberto as curation_reviewer
--   4. Card stayed in curation_status='draft' (intent invisible to backend)
--
-- Fix: AFTER INSERT trigger on board_item_assignments that detects the
-- pattern (curation_reviewer + card status=done + curation_status=draft)
-- and transitions to 'curation_pending'. Existing triggers cascade:
--   - trg_set_curation_due_date (BEFORE UPDATE) sets curation_due_at
--   - trg_notify_curation_status (AFTER UPDATE) notifies assignees
--
-- DESIGN INTENT (PM clarification 2026-05-18): this trigger is a SAFETY
-- NET, not the canonical path. The canonical UX (planned, separate scope)
-- is a "Submeter para Curadoria" button that calls submit_for_curation()
-- without requiring the tribe leader to name curators. This trigger
-- catches the workaround pattern until that UI ships.
--
-- Rollback: DROP TRIGGER trg_auto_submit_curation_on_reviewer_assign
--           ON board_item_assignments;
--           DROP FUNCTION trg_auto_submit_curation_on_reviewer_assign();
-- =====================================================================

CREATE OR REPLACE FUNCTION public.trg_auto_submit_curation_on_reviewer_assign()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_item public.board_items%ROWTYPE;
BEGIN
  -- Fast exit: only react to curation_reviewer assignments
  IF NEW.role IS DISTINCT FROM 'curation_reviewer' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = NEW.item_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Auto-submit only when card is functionally complete AND not yet in curation FSM
  -- (status='done' = tribe finished work; curation_status='draft' = never submitted)
  IF v_item.status = 'done' AND v_item.curation_status = 'draft' THEN
    UPDATE public.board_items
    SET curation_status = 'curation_pending',
        updated_at = now()
    WHERE id = NEW.item_id;

    -- Audit trail: explicit lifecycle event distinguishes this auto-transition
    -- from manual calls to submit_for_curation() RPC.
    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      NEW.item_id,
      'submitted_for_curation',
      'Auto-submit (trigger): curation_reviewer assigned to completed card. Distinct from manual submit_for_curation() RPC call.',
      NEW.assigned_by
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_submit_curation_on_reviewer_assign
  ON public.board_item_assignments;

CREATE TRIGGER trg_auto_submit_curation_on_reviewer_assign
  AFTER INSERT ON public.board_item_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_auto_submit_curation_on_reviewer_assign();

COMMENT ON FUNCTION public.trg_auto_submit_curation_on_reviewer_assign()
IS 'p196 Gap 1: when tribe leader assigns curation_reviewer to a card with status=done and curation_status=draft, auto-transition curation_status to curation_pending. Existing BEFORE/AFTER triggers on board_items handle SLA + notifications.';
