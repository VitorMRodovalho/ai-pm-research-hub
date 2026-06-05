-- #440 — keep board_items.assignee_id ("Responsável") consistent with the
-- board_item_assignments junction ("Participantes")
--
-- Bug: assignee_id (single "Responsável") and board_item_assignments (multi-role
-- junction: author/reviewer/contributor/curation_reviewer) were never synced.
-- create_board_item sets assignee_id = COALESCE(p_assignee_id, creator) while
-- only inserting the CREATOR as the junction author, and update_board_item can
-- set assignee_id with no junction row at all. Result (live): 132 of 593 items
-- have assignee_id pointing at a member absent from the junction entirely.
-- The Kanban DISPLAY symptom was already fixed in PR #442 (BoardKanban prefers
-- assignments[]); this migration fixes the underlying DATA divergence so every
-- non-display consumer that keys on assignee_id (move/update card-owner
-- permission, card_assigned notification, portfolio "owner" rollups) is honest.
--
-- Scope (PM-chosen "Option 2" — sync, lower blast radius): enforce the
-- invariant `assignee_id IS NULL OR assignee_id ∈ junction` from EVERY write
-- path via two triggers (no RPC body changes, so no permission/display/semantic
-- regression), plus a one-time backfill.
--   T1: when board_items.assignee_id is set (INSERT or UPDATE) to a member who
--       is not yet a participant, add them to the junction as 'author'.
--   T2: when a junction row is deleted and that member was the assignee and no
--       longer has any junction membership on the item, clear assignee_id.
--
-- Deferred (UX refinement, needs the author-vs-creator-vs-Responsável product
-- decision — NOT data integrity): (a) stop create_board_item defaulting the
-- assignee to the creator (leave NULL when no pick); (b) the Participantes
-- picker overwriting the Responsável when assigning a new 'author'. Tracked as a
-- #440 follow-up. The current triggers guarantee consistency regardless.
--
-- Rollback: DROP the two triggers + their functions. The backfill (added junction
-- 'author' rows) is not rolled back; it reconciles real data.

-- T1 — assignee is always a participant
CREATE OR REPLACE FUNCTION public.ensure_assignee_in_board_junction()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.assignee_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.board_item_assignments a
       WHERE a.item_id = NEW.id AND a.member_id = NEW.assignee_id
     ) THEN
    INSERT INTO public.board_item_assignments (item_id, member_id, role, assigned_by)
    VALUES (NEW.id, NEW.assignee_id, 'author', COALESCE(NEW.created_by, NEW.assignee_id))
    ON CONFLICT (item_id, member_id, role) DO NOTHING;
  END IF;
  RETURN NULL;
END;
$function$;
-- SECURITY DEFINER (not INVOKER): a direct low-privilege UPDATE of board_items
-- must still be able to write the junction row even when the session lacks
-- INSERT on board_item_assignments. RETURNS trigger => not directly callable.

DROP TRIGGER IF EXISTS trg_ensure_assignee_in_board_junction ON public.board_items;
CREATE TRIGGER trg_ensure_assignee_in_board_junction
  AFTER INSERT OR UPDATE OF assignee_id ON public.board_items
  FOR EACH ROW EXECUTE FUNCTION ensure_assignee_in_board_junction();

-- T2 — removing the assignee from the junction clears the Responsável.
-- AFTER DELETE timing: the deleted row is already gone, so the NOT EXISTS
-- correctly finds zero remaining junction rows for this member when it was their
-- last participation. Only clears assignee_id if the removed member WAS the assignee.
CREATE OR REPLACE FUNCTION public.clear_board_assignee_on_junction_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.board_items bi
  SET assignee_id = NULL
  WHERE bi.id = OLD.item_id
    AND bi.assignee_id = OLD.member_id
    AND NOT EXISTS (
      SELECT 1 FROM public.board_item_assignments a
      WHERE a.item_id = OLD.item_id AND a.member_id = OLD.member_id
    );
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_clear_board_assignee_on_junction_delete ON public.board_item_assignments;
CREATE TRIGGER trg_clear_board_assignee_on_junction_delete
  AFTER DELETE ON public.board_item_assignments
  FOR EACH ROW EXECUTE FUNCTION clear_board_assignee_on_junction_delete();

-- one-time backfill: add the assignee as a junction 'author' wherever the
-- assignee is currently absent from the junction entirely (132 items at migration time).
INSERT INTO public.board_item_assignments (item_id, member_id, role, assigned_by)
SELECT bi.id, bi.assignee_id, 'author', COALESCE(bi.created_by, bi.assignee_id)
FROM public.board_items bi
WHERE bi.assignee_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.board_item_assignments a
    WHERE a.item_id = bi.id AND a.member_id = bi.assignee_id
  )
ON CONFLICT (item_id, member_id, role) DO NOTHING;
