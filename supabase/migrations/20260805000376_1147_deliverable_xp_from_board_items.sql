-- #1147 (Fio 1/3, umbrella #1150): deliverable_completed XP never fired for the real flow.
-- The only XP trigger lived on tribe_deliverables (status='completed'), a dormant surface
-- (71 rows, 1 completed ever); real work completes as board_items.status='done'. Single-source
-- reconciliation (class #1032): XP now derives from card completion; the tribe_deliverables
-- XP trigger is retired so the same work can never be credited twice via two surfaces.
--
-- Scope (PM ratified 2026-07-08): only is_portfolio_item=true cards on tribe-scope boards
-- score (anti-inflation). Mirrors are projections of the work, not the work — excluded.
-- Idempotency (reopen→redone does not re-credit) lives in _grant_auto_xp's EXISTS guard
-- (ref_id + category + member_id).

-- 1) XP trigger on board_items (the authoritative deliverable surface)
CREATE OR REPLACE FUNCTION public.trg_board_item_deliverable_xp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_is_tribe boolean;
  v_deadline date;
  v_on_time boolean;
BEGIN
  -- fire when the card IS done and just became so (INSERT-already-done OR UPDATE-into-done)
  IF NEW.status = 'done'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'done')
     AND NEW.is_portfolio_item IS TRUE
     AND NEW.is_mirror IS NOT TRUE
     AND NEW.assignee_id IS NOT NULL THEN

    SELECT (pb.board_scope = 'tribe') INTO v_is_tribe
    FROM public.project_boards pb
    WHERE pb.id = NEW.board_id;

    IF v_is_tribe IS TRUE THEN
      -- deadline = committed date: due_date wins, baseline_date is the fallback commitment.
      -- No deadline → NULL → base only (no bonus, no penalty) — same policy as _grant_auto_xp.
      v_deadline := COALESCE(NEW.due_date, NEW.baseline_date);
      -- move_board_item sets actual_completion_date = CURRENT_DATE in the same UPDATE as
      -- status='done', so NEW carries it; direct UPDATEs without it fall back to today.
      v_on_time := CASE
        WHEN v_deadline IS NULL THEN NULL
        ELSE (COALESCE(NEW.actual_completion_date, CURRENT_DATE) <= v_deadline)
      END;

      PERFORM public._grant_auto_xp(
        'deliverable_completed',
        NEW.assignee_id,
        NEW.id,
        'Entregável concluído: ' || coalesce(substring(NEW.title FROM 1 FOR 80), '(sem título)'),
        v_on_time
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_board_item_deliverable_xp ON public.board_items;
CREATE TRIGGER trg_board_item_deliverable_xp
AFTER INSERT OR UPDATE OF status ON public.board_items
FOR EACH ROW EXECUTE FUNCTION public.trg_board_item_deliverable_xp();

COMMENT ON FUNCTION public.trg_board_item_deliverable_xp() IS
  '#1147: grants deliverable_completed XP when a tribe-board portfolio card reaches done. Idempotency in _grant_auto_xp (ref_id+category+member EXISTS) — reopen→redone does not re-credit.';

-- 2) Retire the XP grant on tribe_deliverables (single-source; prevents double credit).
DROP TRIGGER IF EXISTS tribe_deliverable_completed_xp ON public.tribe_deliverables;
DROP FUNCTION IF EXISTS public.trg_tribe_deliverable_completed_xp();

-- Keep the completed_at bookkeeping the old trigger provided, minus the XP grant and the
-- AFTER-trigger self-UPDATE (BEFORE trigger sets NEW directly).
CREATE OR REPLACE FUNCTION public.trg_tribe_deliverable_completed_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.status = 'completed'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed')
     AND NEW.completed_at IS NULL THEN
    NEW.completed_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tribe_deliverable_completed_at ON public.tribe_deliverables;
CREATE TRIGGER tribe_deliverable_completed_at
BEFORE INSERT OR UPDATE OF status ON public.tribe_deliverables
FOR EACH ROW EXECUTE FUNCTION public.trg_tribe_deliverable_completed_at();

COMMENT ON FUNCTION public.trg_tribe_deliverable_completed_at() IS
  '#1147: completed_at bookkeeping only. XP for deliverables moved to trg_board_item_deliverable_xp (board_items is the authoritative surface; tribe_deliverables is a dormant projection).';
