-- =====================================================================
-- p196 Gap 2 — recalculate_card_dates: forecast follows actual on complete
-- =====================================================================
-- Bug observed (Débora, 2026-05-18): card "Artigo — Agentes Autônomos em GP"
-- completed 18-mai (all 4 checklists done), but forecast_date stayed at
-- 2026-04-30 (original baseline). UI showed "🔴 Desvio: Concluído 18d após
-- baseline" — confusing because forecast became implicit SLA reference.
--
-- Root cause: recalculate_card_dates only updates forecast_date when
-- v_has_dated_items=true (some checklist has target_date). When all
-- checklists have NULL target_date, forecast is never touched — stale
-- baseline value remains visible as "estimated completion".
--
-- Fix: when v_all_complete=true AND v_max_completed IS NOT NULL, set
-- forecast_date = v_max_completed::date. Forecast = best estimate of
-- completion; once complete, forecast = actual. This is correct
-- semantically regardless of whether checklists carry dates.
--
-- Backfill of Débora's card (forecast_date 2026-04-30 → 2026-05-18)
-- follows inline below.
--
-- Rollback: restore previous body of recalculate_card_dates from migration
-- 20260319100046_w141_board_engine_evolution.sql (or earlier capture).
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
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_board_item_id := OLD.board_item_id;
  ELSE
    v_board_item_id := NEW.board_item_id;
  END IF;

  -- Check if any checklist items have target_date
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

  -- Check if ALL checklist items are complete
  SELECT
    bool_and(is_completed),
    MAX(completed_at)
  INTO v_all_complete, v_max_completed
  FROM public.board_item_checklists
  WHERE board_item_id = v_board_item_id;

  IF v_all_complete = true AND v_max_completed IS NOT NULL THEN
    -- p196 Gap 2: forecast should reflect actual completion date once card is done,
    -- regardless of whether checklists carried target_dates. Forecast = best
    -- estimate of completion; once complete, forecast = actual.
    UPDATE public.board_items
    SET actual_completion_date = v_max_completed::date,
        forecast_date = v_max_completed::date
    WHERE id = v_board_item_id
      AND (actual_completion_date IS NULL
           OR forecast_date IS DISTINCT FROM v_max_completed::date);
  ELSE
    UPDATE public.board_items
    SET actual_completion_date = NULL
    WHERE id = v_board_item_id
      AND actual_completion_date IS NOT NULL;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;
