-- ============================================================
-- W141: BoardEngine Evolution — PMBOK Dates, Checklist Table,
--       Mirror Cards, Roll-up Triggers, Assignment RPCs
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- PART A: PMBOK 3-date model on board_items
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.board_items
  ADD COLUMN IF NOT EXISTS baseline_date date,
  ADD COLUMN IF NOT EXISTS forecast_date date,
  ADD COLUMN IF NOT EXISTS actual_completion_date date;

-- Migrate existing due_date → baseline + forecast
UPDATE public.board_items
SET baseline_date = due_date::date,
    forecast_date = due_date::date
WHERE due_date IS NOT NULL
  AND baseline_date IS NULL;

-- For items already done, approximate actual_completion_date
UPDATE public.board_items bi
SET actual_completion_date = COALESCE(
  (SELECT MAX(ble.created_at)::date
   FROM public.board_lifecycle_events ble
   WHERE ble.item_id = bi.id
     AND ble.action = 'item_archived'
     AND ble.new_status IN ('done', 'concluido', 'Concluído')),
  bi.updated_at::date
)
WHERE bi.status IN ('done', 'concluido', 'Concluído')
  AND bi.actual_completion_date IS NULL;

COMMENT ON COLUMN public.board_items.baseline_date IS 'W141: Original agreed delivery date (PMBOK Baseline).';
COMMENT ON COLUMN public.board_items.forecast_date IS 'W141: Current projected delivery (PMBOK Forecast). Auto = MAX(checklist target_date).';
COMMENT ON COLUMN public.board_items.actual_completion_date IS 'W141: Real completion date (PMBOK Actual). Auto when ALL checklist items complete.';

-- ────────────────────────────────────────────────────────────
-- PART B: Mirror card columns on board_items
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.board_items
  ADD COLUMN IF NOT EXISTS mirror_source_id uuid REFERENCES public.board_items(id),
  ADD COLUMN IF NOT EXISTS mirror_target_id uuid REFERENCES public.board_items(id),
  ADD COLUMN IF NOT EXISTS is_mirror boolean DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_board_items_mirror_source ON public.board_items(mirror_source_id) WHERE mirror_source_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_board_items_mirror_target ON public.board_items(mirror_target_id) WHERE mirror_target_id IS NOT NULL;

COMMENT ON COLUMN public.board_items.mirror_source_id IS 'W141: If mirror card, points to original.';
COMMENT ON COLUMN public.board_items.mirror_target_id IS 'W141: If mirrored, points to the mirror card.';
COMMENT ON COLUMN public.board_items.is_mirror IS 'W141: True if card was created as a cross-board mirror.';

-- ────────────────────────────────────────────────────────────
-- PART C: board_item_checklists table (migrate from JSON)
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.board_item_checklists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_item_id uuid NOT NULL REFERENCES public.board_items(id) ON DELETE CASCADE,
  text text NOT NULL,
  is_completed boolean NOT NULL DEFAULT false,
  position smallint NOT NULL DEFAULT 0,
  assigned_to uuid REFERENCES public.members(id),
  target_date date,
  completed_at timestamptz,
  completed_by uuid REFERENCES public.members(id),
  assigned_at timestamptz,
  assigned_by uuid REFERENCES public.members(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_checklist_board_item ON public.board_item_checklists(board_item_id);
CREATE INDEX IF NOT EXISTS idx_checklist_assigned_to ON public.board_item_checklists(assigned_to) WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_checklist_target_date ON public.board_item_checklists(target_date) WHERE target_date IS NOT NULL;

-- RLS
ALTER TABLE public.board_item_checklists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read checklists"
  ON public.board_item_checklists FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can insert checklists"
  ON public.board_item_checklists FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated users can update checklists"
  ON public.board_item_checklists FOR UPDATE TO authenticated USING (true);

CREATE POLICY "Authenticated users can delete checklists"
  ON public.board_item_checklists FOR DELETE TO authenticated USING (true);

GRANT ALL ON public.board_item_checklists TO authenticated;

-- Migrate existing JSON checklist data into the new table
-- Use CTE to first filter to valid array rows, then expand
WITH valid_checklists AS (
  SELECT id, checklist::jsonb AS cl
  FROM public.board_items
  WHERE checklist IS NOT NULL
    AND checklist::text NOT IN ('null', '', '[]')
    AND jsonb_typeof(checklist::jsonb) = 'array'
)
INSERT INTO public.board_item_checklists (board_item_id, text, is_completed, position)
SELECT
  vc.id,
  (item->>'text')::text,
  COALESCE((item->>'done')::boolean, false),
  (row_number() OVER (PARTITION BY vc.id ORDER BY ordinality))::smallint - 1
FROM valid_checklists vc
CROSS JOIN LATERAL jsonb_array_elements(vc.cl) WITH ORDINALITY AS t(item, ordinality)
WHERE item->>'text' IS NOT NULL;

COMMENT ON TABLE public.board_item_checklists IS 'W141: Checklist items for board cards. Migrated from board_items.checklist JSON.';

-- ────────────────────────────────────────────────────────────
-- PART D: Expand board_lifecycle_events action CHECK constraint
-- ────────────────────────────────────────────────────────────

-- Drop old constraint, add expanded one
ALTER TABLE public.board_lifecycle_events
  DROP CONSTRAINT IF EXISTS board_lifecycle_events_action_check;

ALTER TABLE public.board_lifecycle_events
  ADD CONSTRAINT board_lifecycle_events_action_check
  CHECK (action IN (
    'board_archived', 'board_restored', 'item_archived', 'item_restored',
    'created', 'status_change',
    'forecast_update', 'actual_completion', 'mirror_created'
  ));

-- ────────────────────────────────────────────────────────────
-- PART E: Trigger — auto roll-up checklist dates to card
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.recalculate_card_dates()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $fn$
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
    UPDATE public.board_items
    SET actual_completion_date = v_max_completed::date
    WHERE id = v_board_item_id
      AND actual_completion_date IS NULL;
  ELSE
    UPDATE public.board_items
    SET actual_completion_date = NULL
    WHERE id = v_board_item_id
      AND actual_completion_date IS NOT NULL;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$fn$;

DROP TRIGGER IF EXISTS trg_checklist_date_rollup ON public.board_item_checklists;
CREATE TRIGGER trg_checklist_date_rollup
  AFTER INSERT OR UPDATE OR DELETE ON public.board_item_checklists
  FOR EACH ROW
  EXECUTE FUNCTION public.recalculate_card_dates();

COMMENT ON FUNCTION public.recalculate_card_dates IS 'W141: Auto roll-up checklist dates to card forecast/actual.';

-- ────────────────────────────────────────────────────────────
-- PART F: Trigger — log forecast/actual changes in lifecycle
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.log_forecast_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $fn$
BEGIN
  IF OLD.forecast_date IS DISTINCT FROM NEW.forecast_date THEN
    INSERT INTO public.board_lifecycle_events (
      item_id, board_id, action, previous_status, new_status, reason
    ) VALUES (
      NEW.id, NEW.board_id,
      'forecast_update',
      OLD.forecast_date::text,
      NEW.forecast_date::text,
      NULL
    );
  END IF;

  IF OLD.actual_completion_date IS DISTINCT FROM NEW.actual_completion_date THEN
    INSERT INTO public.board_lifecycle_events (
      item_id, board_id, action, previous_status, new_status, reason
    ) VALUES (
      NEW.id, NEW.board_id,
      'actual_completion',
      OLD.actual_completion_date::text,
      NEW.actual_completion_date::text,
      NULL
    );
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_board_item_date_log ON public.board_items;
CREATE TRIGGER trg_board_item_date_log
  AFTER UPDATE ON public.board_items
  FOR EACH ROW
  WHEN (OLD.forecast_date IS DISTINCT FROM NEW.forecast_date
     OR OLD.actual_completion_date IS DISTINCT FROM NEW.actual_completion_date)
  EXECUTE FUNCTION public.log_forecast_change();

-- ────────────────────────────────────────────────────────────
-- PART G: RPCs — Checklist assignment + completion
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.assign_checklist_item(
  p_checklist_item_id uuid,
  p_assigned_to uuid,
  p_target_date date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $fn$
DECLARE
  v_caller_id uuid;
  v_member_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  UPDATE public.board_item_checklists
  SET assigned_to = p_assigned_to,
      target_date = COALESCE(p_target_date, target_date),
      assigned_at = now(),
      assigned_by = v_member_id
  WHERE id = p_checklist_item_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.complete_checklist_item(
  p_checklist_item_id uuid,
  p_completed boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $fn$
DECLARE
  v_caller_id uuid;
  v_member_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  UPDATE public.board_item_checklists
  SET is_completed = p_completed,
      completed_at = CASE WHEN p_completed THEN now() ELSE NULL END,
      completed_by = CASE WHEN p_completed THEN v_member_id ELSE NULL END
  WHERE id = p_checklist_item_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.update_card_forecast(
  p_board_item_id uuid,
  p_new_forecast date,
  p_justification text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $fn$
DECLARE
  v_caller_id uuid;
  v_member_id uuid;
  v_old_forecast date;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  SELECT forecast_date INTO v_old_forecast FROM public.board_items WHERE id = p_board_item_id;

  UPDATE public.board_items
  SET forecast_date = p_new_forecast
  WHERE id = p_board_item_id;

  -- Log with justification (trigger also logs, but this adds the reason)
  INSERT INTO public.board_lifecycle_events (
    item_id, board_id, action, previous_status, new_status, reason, actor_member_id
  ) VALUES (
    p_board_item_id,
    (SELECT board_id FROM public.board_items WHERE id = p_board_item_id),
    'forecast_update',
    v_old_forecast::text,
    p_new_forecast::text,
    p_justification,
    v_member_id
  );
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.assign_checklist_item TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_checklist_item TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_card_forecast TO authenticated;

-- ────────────────────────────────────────────────────────────
-- PART H: RPCs — Mirror cards
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_mirror_card(
  p_source_item_id uuid,
  p_target_board_id uuid,
  p_target_status text DEFAULT 'backlog',
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $fn$
DECLARE
  v_caller_id uuid;
  v_member_id uuid;
  v_source record;
  v_mirror_id uuid;
  v_max_pos integer;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  SELECT * INTO v_source FROM public.board_items WHERE id = p_source_item_id;
  IF v_source IS NULL THEN RAISE EXCEPTION 'Source card not found'; END IF;

  -- Get next position in target column
  SELECT COALESCE(MAX(position), 0) + 1 INTO v_max_pos
  FROM public.board_items
  WHERE board_id = p_target_board_id AND status = p_target_status;

  INSERT INTO public.board_items (
    board_id, title, description, status, tags,
    mirror_source_id, is_mirror, position
  ) VALUES (
    p_target_board_id,
    v_source.title,
    COALESCE(p_notes, v_source.description),
    p_target_status,
    v_source.tags,
    p_source_item_id,
    true,
    v_max_pos
  )
  RETURNING id INTO v_mirror_id;

  -- Bidirectional link
  UPDATE public.board_items
  SET mirror_target_id = v_mirror_id
  WHERE id = p_source_item_id;

  -- Log lifecycle events on both cards
  INSERT INTO public.board_lifecycle_events (item_id, board_id, action, new_status, reason, actor_member_id)
  VALUES
    (p_source_item_id, v_source.board_id, 'mirror_created', v_mirror_id::text,
     'Card espelho criado no board ' || p_target_board_id::text, v_member_id),
    (v_mirror_id, p_target_board_id, 'mirror_created', p_source_item_id::text,
     'Espelho do card: ' || v_source.title, v_member_id);

  RETURN v_mirror_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.get_mirror_target_boards(
  p_source_board_id uuid
)
RETURNS TABLE (
  board_id uuid,
  board_name text,
  board_scope text,
  item_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER
AS $fn$
BEGIN
  RETURN QUERY
  SELECT
    pb.id,
    pb.board_name,
    pb.board_scope,
    (SELECT count(*) FROM public.board_items bi WHERE bi.board_id = pb.id AND bi.status != 'archived')
  FROM public.project_boards pb
  WHERE pb.id != p_source_board_id
    AND pb.is_active = true
  ORDER BY pb.board_scope, pb.board_name;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.create_mirror_card TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_mirror_target_boards TO authenticated;

-- ────────────────────────────────────────────────────────────
-- Done. W141 schema + RPCs + triggers complete.
-- ────────────────────────────────────────────────────────────
