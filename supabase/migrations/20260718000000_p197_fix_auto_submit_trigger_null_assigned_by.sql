-- =====================================================================
-- p197 fix H5 — trigger guards NULL assigned_by in audit trail
-- =====================================================================
-- board_item_assignments.assigned_by is nullable (Trello sync / bulk
-- imports / migration backfills may insert without an actor). The
-- p196 trigger inserted NEW.assigned_by directly into
-- board_lifecycle_events.actor_member_id without checking — audit trail
-- gets NULL actor for valid system-triggered assignments.
--
-- Fix: COALESCE with card assignee_id (the next most relevant actor)
-- as fallback for system inserts.
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
  IF NEW.role IS DISTINCT FROM 'curation_reviewer' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = NEW.item_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF v_item.status = 'done' AND v_item.curation_status = 'draft' THEN
    UPDATE public.board_items
    SET curation_status = 'curation_pending',
        updated_at = now()
    WHERE id = NEW.item_id;

    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      NEW.item_id,
      'submitted_for_curation',
      'Auto-submit (trigger): curation_reviewer assigned to completed card. Distinct from manual submit_for_curation() RPC call.',
      -- p197 fix H5: NULL guard for bulk/system inserts (Trello sync, migration backfill)
      COALESCE(NEW.assigned_by, v_item.assignee_id)
    );
  END IF;

  RETURN NEW;
END;
$$;
