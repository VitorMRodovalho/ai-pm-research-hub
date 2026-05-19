-- =====================================================================
-- p197 fix H3 — recalculate_card_dates: don't clear actual_completion
--               for cards without any checklist items
-- =====================================================================
-- The previous fix (p196 Gap 2) set forecast_date=actual on completion.
-- But the ELSE branch unconditionally NULL'd actual_completion_date for
-- any v_all_complete=false case — INCLUDING cards with zero checklist
-- items (which is most cards, since checklist is optional).
--
-- bool_and(is_completed) on empty set returns NULL (not TRUE) so
-- v_all_complete=NULL → false → ELSE fired → cleared actual_completion
-- set by other paths (status='done' move, direct RPC, etc.).
--
-- Fix: in ELSE, only NULL out if the card actually HAS checklist items.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.recalculate_card_dates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_board_item_id uuid;
  v_max_target date;
  v_all_complete boolean;
  v_max_completed timestamptz;
  v_has_dated_items boolean;
  v_has_any_checklist boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_board_item_id := OLD.board_item_id;
  ELSE
    v_board_item_id := NEW.board_item_id;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.board_item_checklists
    WHERE board_item_id = v_board_item_id AND target_date IS NOT NULL
  ) INTO v_has_dated_items;

  IF v_has_dated_items THEN
    SELECT MAX(target_date) INTO v_max_target
    FROM public.board_item_checklists
    WHERE board_item_id = v_board_item_id
      AND target_date IS NOT NULL;

    UPDATE public.board_items
    SET forecast_date = v_max_target
    WHERE id = v_board_item_id;
  END IF;

  -- p197 fix H3: guard the ELSE branch against empty-checklist cards
  SELECT EXISTS(
    SELECT 1 FROM public.board_item_checklists
    WHERE board_item_id = v_board_item_id
  ) INTO v_has_any_checklist;

  SELECT
    bool_and(is_completed),
    MAX(completed_at)
  INTO v_all_complete, v_max_completed
  FROM public.board_item_checklists
  WHERE board_item_id = v_board_item_id;

  IF v_all_complete = true AND v_max_completed IS NOT NULL THEN
    -- p196 Gap 2: forecast follows actual once complete
    UPDATE public.board_items
    SET actual_completion_date = v_max_completed::date,
        forecast_date = v_max_completed::date
    WHERE id = v_board_item_id
      AND (actual_completion_date IS NULL
           OR forecast_date IS DISTINCT FROM v_max_completed::date);
  ELSIF v_has_any_checklist THEN
    -- Only clear if there ARE checklists and they're not all complete;
    -- empty-checklist cards have actual_completion set by other paths
    -- (status='done' move, direct RPC) and must not be reset here.
    UPDATE public.board_items
    SET actual_completion_date = NULL
    WHERE id = v_board_item_id
      AND actual_completion_date IS NOT NULL;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;
